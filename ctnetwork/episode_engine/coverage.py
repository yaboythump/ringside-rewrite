#!/usr/bin/env python3
"""Cinematic shot planner: "virtual coverage" from the approved stills.

Why this exists
---------------
Every CTNETWORK long-form episode is built from a fixed set of approved
chat-made stills (about 15 for Ringside Rewrite) that has to cover 9-10 minutes
of narration. The approved Raven edit (2026-11-04) put 61 picture slots on
16 images by interleaving them A-B-A-C: the same still came back after one
or two shots, and scene_07 appeared 7 times. Project 002 added Ken Burns motion,
but it kept that edit, so the repetition stayed.

What it does
------------
Real documentary editors cover a long VO passage from one photograph by
shooting it several ways: a wide, a medium on the subject, a close-up on a
detail. This planner does the same with the approved images. It never
generates, recolours or invents imagery:

* **Framings.** It finds each still's points of interest with spectral-residual
  saliency plus a centre prior, then derives up to four framings per still
  (wide / medium / close / alternate close). Each one keeps a minimum source-pixel
  floor, so nothing is upscaled into mush.
* **Shot selection.** Each segment uses only the stills the approved edit gave
  that segment (the storyboard stays the source of truth). Within that pool it
  orders shots so the same still never comes back-to-back. A reused still is
  a clearly different framing (at least a 1.25x size change or a different
  region). An identical framing may return only after 90 s (the visual-QC window), at most
  twice, and always with a different camera move.
* **Pacing.** Cuts land on the narrator's natural pauses, which are detected
  from the narration audio (no transcription and no API calls). Dynamic
  programming picks the shot lengths within the show's min/max hold, so the
  rhythm varies the way a real edit does instead of using equal slices.
* **Camera.** Each shot gets a move suited to its framing: push into the
  subject, lateral drift, tilt reveal, or settle. Speed is capped in
  output-pixels per second, and the planner avoids repeating the same move or
  reversing direction on consecutive shots.
* **Transitions.** Hard cuts on pauses inside a segment, dissolves between
  segments, dip-to-black at act breaks, and a dissolve into the outro hold.

The output is an ordinary engine timeline (`image`, `duration`, `rect0`,
`rect1`, `transition`), and `render.py` renders it frame-accurately.
"""
from __future__ import annotations

import hashlib
import json
import math
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
from PIL import Image

PLANNER_VERSION = 'ctn-coverage-planner-2026-11-05'

DEFAULT_POLICY = {
    'shot_min': 4.0,            # seconds; shortest hold the show allows
    'shot_target': 6.5,         # preferred hold
    'shot_max': 9.5,            # longest hold before it reads as a slideshow
    'min_source_px': 1040,      # crop width in source pixels must be >= this (quality floor)
    'framings': ['wide', 'medium', 'close', 'close_alt'],
    'max_uses_per_still': 10,   # across the whole programme
    'framing_reuse_after_seconds': 90.0,   # an identical framing may return only after this long...
    'max_uses_per_framing': 3,             # ...and at most this many times (= visual QC appearance limit)
    'cut_on_pauses': True,
    'pause_min_seconds': 0.22,
    'segment_transition': {'type': 'fade', 'seconds': 0.6},
    'act_break_transition': {'type': 'fadeblack', 'seconds': 1.0},
    'outro_transition': {'type': 'fade', 'seconds': 0.8},
    'act_breaks': [],           # 1-based segment numbers that START a new act
    'move_speed_px_s': 22.0,    # max camera travel in output px/s (calm, premium)
    'zoom_rate': 0.012,         # max fractional size change per second
}

ASPECT_CACHE: dict = {}


# --------------------------------------------------------------- saliency
def _gray(path: Path, w=192) -> tuple[np.ndarray, tuple[int, int]]:
    with Image.open(path) as im:
        size = im.size
        g = im.convert('L').resize((w, max(1, round(w * im.size[1] / im.size[0]))), Image.Resampling.BILINEAR)
    return np.asarray(g, np.float32) / 255.0, size


def _box_blur(a: np.ndarray, r: int) -> np.ndarray:
    if r <= 0:
        return a
    k = 2 * r + 1
    p = np.pad(a, r, mode='edge')
    c = p.cumsum(0).cumsum(1)
    c = np.pad(c, ((1, 0), (1, 0)))
    return (c[k:, k:] - c[:-k, k:] - c[k:, :-k] + c[:-k, :-k]) / (k * k)


def saliency_map(path: Path) -> np.ndarray:
    """Spectral-residual saliency (Hou & Zhang 2007) blended with local contrast and a centre prior."""
    g, _ = _gray(path)
    F = np.fft.fft2(g)
    logamp = np.log(np.abs(F) + 1e-6)
    phase = np.angle(F)
    resid = logamp - _box_blur(logamp, 1)
    sr = np.abs(np.fft.ifft2(np.exp(resid + 1j * phase))) ** 2
    sr = _box_blur(sr, 3)
    gy, gx = np.gradient(g)
    contrast = _box_blur(np.hypot(gx, gy), 4)
    h, w = g.shape
    yy, xx = np.mgrid[0:h, 0:w]
    centre = np.exp(-(((xx / w - 0.5) / 0.38) ** 2 + ((yy / h - 0.45) / 0.42) ** 2))

    def norm(a):
        a = a - a.min()
        return a / (a.max() + 1e-9)
    return norm(0.55 * norm(sr) + 0.45 * norm(contrast)) * (0.35 + 0.65 * centre)


def interest_points(path: Path, k=3) -> list[tuple[float, float, float]]:
    """Top-k salient points (x, y, weight) in normalised coords, with non-max suppression."""
    s = saliency_map(path).copy()
    h, w = s.shape
    pts = []
    for _ in range(k):
        i = int(np.argmax(s))
        y, x = divmod(i, w)
        val = float(s[y, x])
        if val <= 1e-6:
            break
        pts.append(((x + 0.5) / w, (y + 0.5) / h, val))
        r = int(0.22 * w)
        s[max(0, y - r):y + r + 1, max(0, x - r):x + r + 1] = 0
    if not pts:
        pts = [(0.5, 0.45, 1.0)]
    return pts


# ---------------------------------------------------------------- framings
@dataclass
class Framing:
    image: str
    name: str
    rect: tuple[float, float, float]   # (x, y, w) top-left + width, normalised to the cover-fit canvas
    focus: tuple[float, float]

    def key(self):
        return (self.image, self.name)


def _rect_around(cx, cy, w, out_aspect, canvas_aspect):
    # width fraction w on a canvas already cover-fitted to the output aspect -> height fraction == w
    h = w
    x = min(max(cx - w / 2, 0.0), 1.0 - w)
    y = min(max(cy - h / 2, 0.0), 1.0 - h)
    return (round(x, 4), round(y, 4), round(w, 4))


def framings_for(path: Path, out_w: int, out_h: int, policy: dict) -> list[Framing]:
    with Image.open(path) as im:
        sw, sh = im.size
    # Width of the cover-fit canvas in source pixels (the approved scale/crop the engine already uses).
    canvas_src_w = min(sw, sh * out_w / out_h)
    w_floor = min(1.0, policy['min_source_px'] / canvas_src_w)
    pts = interest_points(Path(path))
    # Map interest points from source coordinates to the cover-fit canvas.
    src_aspect, out_aspect = sw / sh, out_w / out_h
    def to_canvas(x, y):
        if src_aspect > out_aspect:   # source wider: canvas crops left/right
            frac = out_aspect / src_aspect
            return (min(max((x - (1 - frac) / 2) / frac, 0), 1), y)
        frac = src_aspect / out_aspect
        return (x, min(max((y - (1 - frac) / 2) / frac, 0), 1))
    pts = [(*to_canvas(x, y), v) for x, y, v in pts]
    primary = pts[0]
    alt = pts[1] if len(pts) > 1 else (1 - primary[0], primary[1], 0.5)
    wanted = {
        'wide': (0.5, 0.5, 1.0),
        'medium': (primary[0], primary[1], max(w_floor, 0.80)),
        'close': (primary[0], primary[1], max(w_floor, 0.62)),
        'close_alt': (alt[0], alt[1], max(w_floor, 0.62)),
    }
    out, seen = [], []
    for name in policy['framings']:
        cx, cy, w = wanted[name]
        r = _rect_around(cx, cy, w, out_aspect, out_aspect)
        # A framing must be clearly different from every framing already kept for this still.
        if any(_too_similar(r, s) for s in seen):
            continue
        seen.append(r)
        out.append(Framing(str(path), name, r, (round(cx, 3), round(cy, 3))))
    return out


def _too_similar(a, b):
    size_ratio = max(a[2], b[2]) / min(a[2], b[2])
    acx, acy = a[0] + a[2] / 2, a[1] + a[2] / 2
    bcx, bcy = b[0] + b[2] / 2, b[1] + b[2] / 2
    shift = math.hypot(acx - bcx, acy - bcy) / min(a[2], b[2])
    return size_ratio < 1.25 and shift < 0.30


# ------------------------------------------------------------ pause / pacing
def speech_pauses(x: np.ndarray, sr: int, min_pause=0.22, win=0.02) -> list[float]:
    """Mid-points (s) of the narrator's natural pauses, from the narration waveform."""
    hop = max(1, int(win * sr))
    n = len(x) // hop
    if n < 3:
        return []
    e = np.sqrt(np.mean(x[:n * hop].reshape(n, hop) ** 2, axis=1) + 1e-12)
    db = 20 * np.log10(e)
    voiced = db[db > -70]
    if not len(voiced):
        return []
    thresh = max(np.percentile(voiced, 60) - 22.0, -55.0)
    quiet = db < thresh
    out, i = [], 0
    while i < n:
        if quiet[i]:
            j = i
            while j < n and quiet[j]:
                j += 1
            if (j - i) * win >= min_pause and i > 0 and j < n:
                out.append(round((i + j) / 2 * win, 3))
            i = j
        else:
            i += 1
    return out


def choose_cuts(total: float, pauses: list[float], n_min: int, policy: dict) -> list[float]:
    """Pick cut times (excluding 0 and total) from pause candidates via DP.

    Minimises squared deviation from the target hold, keeps each shot within
    [shot_min, shot_max] where possible, and requires at least n_min shots so
    the segment's approved pool is shown. Falls back to evenly spaced cuts
    when the narration has no usable pauses.
    """
    lo, tgt, hi = policy['shot_min'], policy['shot_target'], policy['shot_max']
    n_ideal = max(n_min, round(total / tgt), 1)
    if total < lo * 1.6:
        return []
    cands = [p for p in pauses if lo * 0.75 <= p <= total - lo * 0.75] if policy.get('cut_on_pauses', True) else []
    pts = [0.0] + sorted(set(cands)) + [total]
    INF = float('inf')
    # best[i] = (cost, prev_index, shots) ending at pts[i]
    best = [(INF, -1, 0)] * len(pts)
    best[0] = (0.0, -1, 0)
    for i in range(1, len(pts)):
        for j in range(i):
            if best[j][0] == INF:
                continue
            d = pts[i] - pts[j]
            if d < lo * 0.75 or d > hi * 1.35:
                continue
            pen = (d - tgt) ** 2 + (25.0 if d < lo else 0) + (25.0 * (d - hi) if d > hi else 0)
            c = best[j][0] + pen
            if c < best[i][0]:
                best[i] = (c, j, best[j][2] + 1)
    if best[-1][0] == INF or best[-1][2] < min(n_min, n_ideal):
        n = max(n_ideal, 1)
        even = [round(total * k / n, 3) for k in range(1, n)]
        if pauses:  # snap even cuts to the nearest pause within 1.2 s
            even = [min(pauses, key=lambda p: abs(p - c)) if min(abs(p - c) for p in pauses) < 1.2 else c for c in even]
        return sorted(set(c for c in even if 0 < c < total))
    cuts, i = [], len(pts) - 1
    while best[i][1] >= 0:
        cuts.append(pts[i])
        i = best[i][1]
    return sorted(c for c in cuts if 0 < c < total)


# ------------------------------------------------------------------ moves
MOVE_KINDS = ['push_in', 'drift_right', 'pull_out', 'drift_left', 'tilt_up', 'tilt_down', 'settle']


def _clamp_rect(x, y, w):
    w = min(max(w, 0.05), 1.0)
    return (round(min(max(x, 0.0), 1 - w), 4), round(min(max(y, 0.0), 1 - w), 4), round(w, 4))


def plan_move(fr: Framing, seconds: float, prev_move: str | None, out_w: int, policy: dict,
              rng: np.random.Generator, avoid=()) -> tuple[str, tuple, tuple]:
    """Start/end rects for a framing. Travel is capped by pixel speed and zoom rate."""
    x, y, w = fr.rect
    max_travel = policy['move_speed_px_s'] * seconds / out_w     # in canvas widths
    dz = min(policy['zoom_rate'] * seconds, 0.10)
    room_x, room_y = 1 - w, 1 - w
    options = []
    if w > 0.70:
        options += ['push_in', 'pull_out', 'drift_right', 'drift_left']
    else:
        options += ['push_in', 'settle', 'drift_right', 'drift_left', 'tilt_up', 'tilt_down']
    # Moves that need headroom only when there is room to travel.
    def feasible(m):
        if m in ('drift_right', 'drift_left'):
            return room_x > 0.02 or w > 0.9
        if m in ('tilt_up', 'tilt_down'):
            return room_y > 0.04
        return True
    options = [m for m in options if feasible(m)]
    opposite = {'drift_right': 'drift_left', 'drift_left': 'drift_right', 'push_in': 'pull_out',
                'pull_out': 'push_in', 'tilt_up': 'tilt_down', 'tilt_down': 'tilt_up'}
    ranked = [m for m in options if m != prev_move and m != opposite.get(prev_move)] or options
    ranked = [m for m in ranked if m not in avoid] or ranked   # a returning framing never moves the same way
    move = ranked[int(rng.integers(0, len(ranked)))]
    fx, fy = fr.focus
    cx0, cy0 = x + w / 2, y + w / 2
    tcx, tcy = cx0 + (fx - cx0) * 0.25, cy0 + (fy - cy0) * 0.25   # drift a quarter of the way to the subject
    if move == 'push_in':        # end tighter, centred toward the subject
        w1 = w * (1 - dz)
        r0, r1 = (x, y, w), _clamp_rect(tcx - w1 / 2, tcy - w1 / 2, w1)
    elif move == 'pull_out':
        w0 = w * (1 - dz)
        r0, r1 = _clamp_rect(tcx - w0 / 2, tcy - w0 / 2, w0), (x, y, w)
    elif move in ('drift_right', 'drift_left'):
        ww = w if w < 0.99 else 1 - dz * 0.8     # a wide needs a hair of zoom to have room to pan
        t = min(max_travel, (1 - ww) if w >= 0.99 else room_x, 0.12)
        base_x = x if w < 0.99 else (1 - ww) / 2
        base_y = y if w < 0.99 else (1 - ww) / 2
        a, b = base_x - t / 2, base_x + t / 2
        if move == 'drift_left':
            a, b = b, a
        r0, r1 = _clamp_rect(a, base_y, ww), _clamp_rect(b, base_y, ww)
    elif move in ('tilt_up', 'tilt_down'):
        t = min(max_travel, room_y, 0.10)
        a, b = y + t / 2, y - t / 2
        if move == 'tilt_down':
            a, b = b, a
        r0, r1 = _clamp_rect(x, a, w), _clamp_rect(x, b, w)
    else:  # settle: very slow push, reads as a held, living frame
        w1 = w * (1 - dz * 0.4)
        r0, r1 = (x, y, w), _clamp_rect(x + (w - w1) / 2, y + (w - w1) / 2, w1)
    return move, tuple(r0), tuple(r1)


# ---------------------------------------------------------------- planner
@dataclass
class Segment:
    duration: float
    pool: list[str]                       # approved stills for this segment, in approved order
    pauses: list[float] = field(default_factory=list)


def plan_timeline(segments: list[Segment], out_w: int, out_h: int, policy: dict | None = None,
                  outro: dict | None = None, seed: int = 7) -> dict:
    """Return {'timeline': [...], 'report': {...}} for the engine renderer."""
    P = {**DEFAULT_POLICY, **(policy or {})}
    rng = np.random.default_rng(seed)
    frames_cache: dict[str, list[Framing]] = {}
    used: dict = {}            # framing key -> {'count', 'last_t', 'moves'}
    clock = 0.0
    uses: dict[str, int] = {}
    last_seen: dict[str, int] = {}
    timeline, warnings, asset_requests = [], [], []
    shot_idx = 0
    prev_move = None
    act_breaks = set(int(a) for a in P.get('act_breaks', []))
    seg_start = np.concatenate([[0.0], np.cumsum([sg.duration for sg in segments])])
    for si, seg in enumerate(segments, 1):
        pool = list(dict.fromkeys(seg.pool))
        # Lookahead: a still that later segments also need (within the reuse window) is shared fairly,
        # so one segment cannot burn every framing of it and starve the next one.
        horizon = seg_start[si] + P['framing_reuse_after_seconds']
        cap = {}
        for p in pool:
            k = 1 + sum(1 for j in range(si, len(segments)) if seg_start[j] < horizon and p in segments[j].pool)
            cap[p] = max(1, math.ceil(len(P['framings']) / k))
        seg_uses: dict[str, int] = {}
        for p in pool:
            if p not in frames_cache:
                frames_cache[p] = framings_for(Path(p), out_w, out_h, P)
        cuts = choose_cuts(seg.duration, seg.pauses, n_min=min(len(pool), max(1, int(seg.duration // P['shot_min']))), policy=P)
        bounds = [0.0] + cuts + [seg.duration]
        # Never ask for more shots than distinct framings we can still supply: lengthen holds instead.
        left = [len([f for f in frames_cache[p] if _framing_free(f, used, clock, P)]) for p in pool]
        available = _max_alternating(left, prev_in_pool=(timeline[-1]['image'] in pool) if timeline else False,
                                     prev_count=left[pool.index(timeline[-1]['image'])] if timeline and timeline[-1]['image'] in pool else 0)
        floor_shots = math.ceil(seg.duration / (P['shot_max'] * 1.35))
        if available < floor_shots:
            warnings.append(f'segment_{si}_framings_short_{available}_of_{floor_shots}: early reuse instead of an over-long hold')
            available = floor_shots
        if len(bounds) - 1 > max(available, 1) and available > 1:
            # Fewer framings than the ideal shot count: re-solve the cuts for that count so holds stay even.
            P2 = {**P, 'shot_target': seg.duration / available,
                  'shot_max': max(P['shot_max'], seg.duration / available * 1.25),
                  'shot_min': min(P['shot_min'], seg.duration / available * 0.7)}
            bounds = [0.0] + choose_cuts(seg.duration, seg.pauses, n_min=available, policy=P2) + [seg.duration]
        while len(bounds) - 1 > max(available, 1) and len(bounds) > 2:
            # drop the cut that makes the shortest resulting shot
            lens = [bounds[i + 1] - bounds[i] for i in range(len(bounds) - 1)]
            k = int(np.argmin([lens[i] + lens[i + 1] for i in range(len(lens) - 1)])) + 1
            del bounds[k]
        wanted = max(1, round(seg.duration / P['shot_target']))
        if wanted > len(bounds) - 1:
            per_still = max(1, len(P['framings']))
            asset_requests.append({'segment': si, 'seconds': round(seg.duration, 1), 'approved_stills': len(pool),
                                   'shots_planned': len(bounds) - 1, 'shots_for_target_pacing': wanted,
                                   'additional_stills_recommended': math.ceil((wanted - (len(bounds) - 1)) / per_still) or 1})
        prev_image = timeline[-1]['image'] if timeline else None
        for k in range(len(bounds) - 1):
            d = bounds[k + 1] - bounds[k]
            fr = _pick_framing(pool, frames_cache, used, uses, last_seen, shot_idx, prev_image, P, warnings, clock,
                               over_cap={q for q in pool if seg_uses.get(q, 0) >= cap[q]})
            seg_uses[fr.image] = seg_uses.get(fr.image, 0) + 1
            u = used.setdefault(fr.key(), {'count': 0, 'last_t': -1e9, 'moves': []})
            uses[fr.image] = uses.get(fr.image, 0) + 1
            last_seen[fr.image] = shot_idx
            move, r0, r1 = plan_move(fr, d, prev_move, out_w, P, rng, avoid=u['moves'])
            u['count'] += 1
            u['last_t'] = clock + d
            u['moves'].append(move)
            prev_move = move
            if k == 0 and si > 1:
                tr = P['act_break_transition'] if si in act_breaks else P['segment_transition']
            elif k == 0:
                tr = {'type': 'cut', 'seconds': 0}
            else:
                tr = {'type': 'cut', 'seconds': 0}
            timeline.append({'image': fr.image, 'duration': round(d, 4), 'segment': si, 'framing': fr.name,
                             'move': move, 'rect0': list(r0), 'rect1': list(r1),
                             'transition_in': dict(tr)})
            prev_image = fr.image
            shot_idx += 1
            clock += d
    if outro:
        img = outro['image']
        timeline.append({'image': img, 'duration': float(outro['duration']), 'segment': 'outro', 'framing': 'wide',
                         'move': 'settle', 'rect0': [0, 0, 1], 'rect1': [0.012, 0.012, 0.976],
                         'transition_in': dict(P['outro_transition'])})
    report = plan_report(timeline)
    report['warnings'] = warnings
    report['asset_requests'] = asset_requests
    report['planner'] = PLANNER_VERSION
    report['policy'] = P
    return {'timeline': timeline, 'report': report}


def _max_alternating(counts, prev_in_pool=False, prev_count=0) -> int:
    """Longest shot sequence these per-still framing counts can fill with no still twice in a row."""
    total = sum(counts)
    if not total:
        return 0
    if len([c for c in counts if c]) == 1:
        return total  # single-still segment: consecutive shots are reframed cut-ins (wide -> close)
    m = max(counts)
    n = total if m <= total - m + 1 else 2 * (total - m) + 1
    if prev_in_pool and prev_count == m and m > total - m:
        n -= 1  # the segment cannot open on the still the previous segment ended on
    return max(n, 1)


def _framing_free(fr, used, now, P) -> bool:
    u = used.get(fr.key())
    if u is None:
        return True
    return u['count'] < P['max_uses_per_framing'] and now - u['last_t'] >= P['framing_reuse_after_seconds']


def _pick_framing(pool, frames_cache, used, uses, last_seen, shot_idx, prev_image, P, warnings, now,
                  over_cap=frozenset()) -> Framing:
    best, best_score = None, None
    order = {p: i for i, p in enumerate(pool)}
    for p in pool:
        for rank, fr in enumerate(frames_cache[p]):
            if not _framing_free(fr, used, now, P):
                continue
            gap = shot_idx - last_seen.get(p, -10 ** 6)
            score = 0.0
            if p == prev_image:
                score -= 1000                       # never the same still back-to-back
            if fr.key() in used:
                score -= 40                         # fresh framings first; a returning one is a last resort
            score += min(gap, 8) * 10               # prefer stills not seen recently
            score -= uses.get(p, 0) * 6             # spread usage across the pool
            score -= rank * 4                       # wide before medium before close for a first look
            score -= order[p] * 1.5                 # keep the storyboard's order when otherwise equal
            if uses.get(p, 0) >= P['max_uses_per_still']:
                score -= 500
            if p in over_cap:
                score -= 200                        # leave this still's other framings for a later segment
            if best_score is None or score > best_score:
                best, best_score = fr, score
    if best is None:
        warnings.append(f'framing_pool_exhausted_at_shot_{shot_idx}: add approved stills to this segment')
        cands = [f for p in pool for f in frames_cache[p] if p != prev_image] or [f for p in pool for f in frames_cache[p]]
        best = min(cands, key=lambda f: (used.get(f.key(), {}).get('last_t', -1e9)))
    elif best.image == prev_image:
        warnings.append(f'single_still_segment_at_shot_{shot_idx}: back-to-back still is a reframed cut-in')
    return best


# ------------------------------------------------------------ plan metrics
def plan_report(timeline: list[dict]) -> dict:
    """Repetition metrics for any engine timeline (approved edit or planned)."""
    imgs = [Path(t['image']).name for t in timeline]
    shots = [(Path(t['image']).name, t.get('framing', 'wide')) for t in timeline]
    counts: dict[str, int] = {}
    for i in imgs:
        counts[i] = counts.get(i, 0) + 1
    gaps, last = [], {}
    for i, s in enumerate(imgs):
        if s in last:
            gaps.append(i - last[s])
        last[s] = i
    exact_last, exact_repeats, exact_close = {}, 0, 0
    t = 0.0
    for i, s in enumerate(shots):
        if s in exact_last:
            exact_repeats += 1
            if t - exact_last[s] < 90:
                exact_close += 1
        t += float(timeline[i]['duration'])
        exact_last[s] = t
    durs = [float(t['duration']) for t in timeline]
    trans = {}
    for t in timeline:
        k = (t.get('transition_in') or {'type': 'fade'})['type']
        trans[k] = trans.get(k, 0) + 1
    return {
        'shots': len(timeline), 'unique_stills': len(counts), 'max_uses_one_still': max(counts.values()) if counts else 0,
        'most_used': sorted(counts.items(), key=lambda kv: -kv[1])[:5],
        'back_to_back_same_still': sum(1 for g in gaps if g == 1),
        'reuse_within_2_shots': sum(1 for g in gaps if g <= 2),
        'min_reuse_gap_shots': min(gaps) if gaps else None,
        'identical_shot_repeats': exact_repeats,
        'identical_repeats_within_90s': exact_close,
        'mean_shot_seconds': round(float(np.mean(durs)), 2) if durs else 0,
        'shot_seconds_range': [round(min(durs), 2), round(max(durs), 2)] if durs else [0, 0],
        'transitions': trans,
    }


def fingerprint(timeline) -> str:
    return hashlib.sha256(json.dumps(timeline, sort_keys=True).encode()).hexdigest()[:16]
