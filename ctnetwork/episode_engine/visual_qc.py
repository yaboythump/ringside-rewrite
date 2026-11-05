#!/usr/bin/env python3
"""Automated *visual* QC for CTNETWORK masters and Shorts (read-only).

`qc.py` covers delivery spec: codecs, loudness, black frames, freezedetect.
This module looks at the picture the way a viewer does:

* **Repetition.** Every sampled frame gets a 64-bit DCT perceptual hash.
  Consecutive frames that look alike form a *hold*, meaning one visual on
  screen. A gentle Ken Burns move stays inside one hold, while a cut or a
  clearly different framing starts a new one. Each hold is compared with all
  earlier holds. A match means the viewer is shown the same image again, and
  the report says when, how often, and how soon after the last time.
* **Static sequences.** Runs where the picture does not move at all (no camera
  motion, no cut) longer than the show allows.
* **Pacing.** Holds longer than the show's maximum read as a slideshow even
  with motion.
* **Missing media.** Black or flat (placeholder) frames, and large black
  pillar/letter bars that mean a still was not fitted.
* **Asset preflight** (before rendering): every still and narration file
  exists and decodes, meets the resolution floor, and is not a byte-identical
  or near-identical duplicate of another still under a different name.
* **Archive ledger reuse** (footage shows such as Hip Hop Rewind): the same
  source range used more than once.

Outputs a JSON report and a contact sheet (one tile per hold, with repeats
outlined in red) for human review. Thresholds come from the show formula's
`visual_qc` block.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

DEFAULTS = {
    'sample_fps': 4.0,
    'hold_distance': 14,          # pHash bits: frames within this of the hold's anchor are the same visual
    'repeat_distance': 22,        # pHash pre-filter for "same image again" candidates
    'repeat_correlation': 0.95,   # ...confirmed by alignment-tolerant correlation
    'min_hold_seconds': 1.0,      # ignore dissolve transients
    'repeat_window_seconds': 90,  # repeats closer than this are "excessive"
    'max_repeats_in_window': 0,
    'max_appearances_per_visual': 3,
    'max_static_seconds': 6.0,
    'static_epsilon': 0.0012,     # mean abs frame difference (0-1) below which the picture is frozen
    'max_hold_seconds': 14.0,
    'black_luma': 0.035,
    'flat_std': 0.012,
    'max_black_seconds': 0.3,
    'bar_fraction': 0.04,
}
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'


# ----------------------------------------------------------------- hashing
def _dct_matrix(n=32):
    k = np.arange(n)
    m = np.cos(np.pi * (2 * k[None, :] + 1) * k[:, None] / (2 * n))
    m[0] /= np.sqrt(2)
    return m * np.sqrt(2 / n)


_D = _dct_matrix()


def phash(gray: np.ndarray) -> int:
    """64-bit DCT perceptual hash of a grayscale frame (any size)."""
    im = Image.fromarray(np.clip(gray * 255, 0, 255).astype(np.uint8)).resize((32, 32), Image.Resampling.BILINEAR)
    a = np.asarray(im, np.float32)
    c = _D @ a @ _D.T
    low = c[:8, :8].flatten()[1:]
    bits = low > np.median(low)
    return int(''.join('1' if b else '0' for b in bits), 2)


def hamming(a: int, b: int) -> int:
    return bin(a ^ b).count('1')


def _prep(gray: np.ndarray, w=64, h=36) -> np.ndarray:
    im = Image.fromarray(np.clip(gray * 255, 0, 255).astype(np.uint8)).resize((w, h), Image.Resampling.BILINEAR)
    return np.asarray(im, np.float32) / 255.0


def same_picture(a: np.ndarray, b: np.ndarray, scales=(0.88, 0.94, 1.0, 1.06, 1.13), shift=3) -> float:
    """Alignment-tolerant normalised correlation of two 64x36 frames (max over small zooms/shifts).

    Ken Burns moves of the same still stay above ~0.9; different title cards that
    share a background pattern (which fool a perceptual hash) fall well below it.
    """
    h, w = a.shape
    m = shift + 4
    A = a[m:h - m, m:w - m]
    A = (A - A.mean()) / (A.std() + 1e-6)
    best = -1.0
    for s in scales:
        if s == 1.0:
            B0 = b
        else:
            cw, ch = int(round(w / s)), int(round(h / s))
            im = Image.fromarray(np.clip(b * 255, 0, 255).astype(np.uint8))
            if s > 1:   # b is a tighter view: zoom a into b's scale instead by cropping b's canvas larger
                x0, y0 = (w - cw) // 2, (h - ch) // 2
                B0 = np.asarray(im.crop((x0, y0, x0 + cw, y0 + ch)).resize((w, h), Image.Resampling.BILINEAR), np.float32) / 255
            else:
                pad = Image.new('L', (cw, ch), 0)
                pad.paste(im, ((cw - w) // 2, (ch - h) // 2))
                B0 = np.asarray(pad.resize((w, h), Image.Resampling.BILINEAR), np.float32) / 255
        for dy in range(-shift, shift + 1):
            for dx in range(-shift, shift + 1):
                B = B0[m + dy:h - m + dy, m + dx:w - m + dx]
                B = (B - B.mean()) / (B.std() + 1e-6)
                best = max(best, float((A * B).mean()))
    return best


# ---------------------------------------------------------------- decoding
def sample_frames(path: Path, fps: float, w=96, h=54, start=None, seconds=None):
    win = (['-ss', f'{start:.3f}'] if start else []) + (['-t', f'{seconds:.3f}'] if seconds else [])
    raw = subprocess.check_output(['ffmpeg', '-v', 'error', *win, '-i', str(path), '-vf',
                                   f'fps={fps},scale={w}:{h}:flags=area,format=gray', '-f', 'rawvideo', '-'])
    n = len(raw) // (w * h)
    return np.frombuffer(raw[:n * w * h], np.uint8).reshape(n, h, w).astype(np.float32) / 255.0


# ---------------------------------------------------------------- analysis
def analyze_video(path, limits=None, contact_sheet=None, start=None, seconds=None):
    """Analyse a whole file, or the window [start, start+seconds] of it (for like-for-like comparisons)."""
    L = {**DEFAULTS, **(limits or {})}
    path = Path(path)
    fps = float(L['sample_fps'])
    window_start = float(start or 0.0)
    frames = sample_frames(path, fps, start=start, seconds=seconds)
    n = len(frames)
    dt = 1.0 / fps
    errors, warnings = [], []
    if n == 0:
        return {'file': str(path), 'pass': False, 'errors': ['no_decodable_video_frames']}
    hashes = [phash(f) for f in frames]
    diffs = np.concatenate([[1.0], np.mean(np.abs(np.diff(frames, axis=0)), axis=(1, 2))])
    luma = frames.mean(axis=(1, 2))
    std = frames.std(axis=(1, 2))

    # holds: consecutive frames within hold_distance of the hold's anchor (first) frame
    holds, h0 = [], 0
    for i in range(1, n + 1):
        if i == n or hamming(hashes[i], hashes[h0]) > L['hold_distance'] or diffs[i] > 0.12:
            holds.append((h0, i))
            h0 = i
    hold_rows = []
    for a, b in holds:
        mid = (a + b - 1) // 2
        hold_rows.append({'start': round(a * dt, 2), 'end': round(b * dt, 2), 'seconds': round((b - a) * dt, 2),
                          'hash': hashes[mid], 'mid_index': mid})
    real = [h for h in hold_rows if h['seconds'] >= L['min_hold_seconds']
            and std[h['mid_index']] > L['flat_std'] and luma[h['mid_index']] > L['black_luma']]

    # repetition: assign each real hold to a visual id
    visuals: list[dict] = []
    repeats = []
    small = {}
    prev_visual = None
    for h in real:
        small[h['mid_index']] = _prep(frames[h['mid_index']])
    for h in real:
        match = None
        for v in visuals:
            cands = [m for x, m in zip(v['hashes'], v['mids']) if hamming(h['hash'], x) <= L['repeat_distance']]
            if any(same_picture(small[h['mid_index']], small[m]) >= L['repeat_correlation'] for m in cands):
                match = v
                break
        if match is not None and visuals and match is prev_visual and h['start'] - match['last_end'] <= 0.6:
            # same visual continuing across a hold split (e.g. a long pan): one appearance, not a repeat
            h['visual'] = match['id']
            match['last_end'] = h['end']
            continue
        if match is None:
            visuals.append({'id': len(visuals), 'hashes': [h['hash']], 'mids': [h['mid_index']], 'appearances': [h['start']]})
            h['visual'] = len(visuals) - 1
        else:
            gap = h['start'] - match['last_end']
            repeats.append({'at': h['start'], 'visual': match['id'], 'first_seen': match['appearances'][0],
                            'gap_seconds': round(gap, 2), 'appearance': len(match['appearances']) + 1})
            match['hashes'].append(h['hash'])
            match['mids'].append(h['mid_index'])
            match['appearances'].append(h['start'])
            h['visual'] = match['id']
            h['repeat'] = True
        (match or visuals[-1])['last_end'] = h['end']
        prev_visual = match or visuals[-1]
    close = [r for r in repeats if r['gap_seconds'] < L['repeat_window_seconds']]
    most = max((len(v['appearances']) for v in visuals), default=0)

    # static runs: picture identical frame to frame
    static_runs, s0 = [], None
    for i in range(1, n + 1):
        still = i < n and diffs[i] < L['static_epsilon']
        if still and s0 is None:
            s0 = i - 1
        if not still and s0 is not None:
            static_runs.append((round(s0 * dt, 2), round(i * dt, 2)))
            s0 = None
    long_static = [r for r in static_runs if r[1] - r[0] > L['max_static_seconds']]
    static_total = sum(b - a for a, b in static_runs if b - a > 1.0)
    long_holds = [h for h in real if h['seconds'] > L['max_hold_seconds']]

    # missing media
    blackish = (luma < L['black_luma']) | (std < L['flat_std'])
    black_runs, b0 = [], None
    for i in range(n + 1):
        if i < n and blackish[i] and b0 is None:
            b0 = i
        if (i == n or not blackish[i]) and b0 is not None:
            if (i - b0) * dt > L['max_black_seconds']:
                black_runs.append((round(b0 * dt, 2), round(i * dt, 2)))
            b0 = None
    W = frames.shape[2]
    bw = max(1, int(L['bar_fraction'] * W))
    bars = (frames[:, :, :bw].mean(axis=(1, 2)) < 0.02) & (frames[:, :, -bw:].mean(axis=(1, 2)) < 0.02) & (luma > 0.08)
    bar_seconds = float(bars.sum() * dt)

    if len(close) > L['max_repeats_in_window']:
        errors.append(f'excessive_repetition_{len(close)}_repeats_within_{L["repeat_window_seconds"]}s')
    if most > L['max_appearances_per_visual']:
        errors.append(f'one_visual_shown_{most}_times_max_{L["max_appearances_per_visual"]}')
    if long_static:
        errors.append(f'static_sequences_{len(long_static)}_over_{L["max_static_seconds"]}s')
    if long_holds:
        errors.append(f'long_holds_{len(long_holds)}_over_{L["max_hold_seconds"]}s')
    if black_runs:
        errors.append(f'missing_media_black_or_flat_{len(black_runs)}')
    if bar_seconds > 1.0:
        warnings.append(f'pillarbox_bars_{bar_seconds:.1f}s_unfitted_media')
    dur = n * dt
    report = {
        'file': str(path), 'seconds_analyzed': round(dur, 2), 'sample_fps': fps,
        'holds': len(real), 'unique_visuals': len(visuals),
        'unique_visual_ratio': round(len(visuals) / max(len(real), 1), 3),
        'repeats_total': len(repeats), 'repeats_within_window': len(close),
        'min_repeat_gap_seconds': min((r['gap_seconds'] for r in repeats), default=None),
        'max_appearances_one_visual': most,
        'mean_hold_seconds': round(float(np.mean([h['seconds'] for h in real])), 2) if real else 0,
        'longest_hold_seconds': max((h['seconds'] for h in real), default=0),
        'static_seconds_total': round(static_total, 1), 'static_fraction': round(static_total / max(dur, 1e-9), 3),
        'longest_static_seconds': max((b - a for a, b in static_runs), default=0),
        'black_or_flat_runs': black_runs, 'pillarbox_seconds': round(bar_seconds, 1),
        'repeats': repeats[:200], 'long_holds': [[h['start'], h['end']] for h in long_holds][:50],
        'limits': L, 'errors': errors, 'warnings': warnings, 'pass': not errors,
    }
    if contact_sheet:
        _contact_sheet(path, real, Path(contact_sheet), offset=window_start)
        report['contact_sheet'] = str(contact_sheet)
    return report


def _contact_sheet(path: Path, holds, out: Path, cols=8, tw=240, th=135, limit=96, offset=0.0):
    rows = []
    for h in holds[:limit]:
        t = offset + (h['start'] + h['end']) / 2
        raw = subprocess.check_output(['ffmpeg', '-v', 'error', '-ss', f'{t:.2f}', '-i', str(path), '-frames:v', '1',
                                       '-vf', f'scale={tw}:{th}', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'])
        if len(raw) < tw * th * 3:
            continue
        rows.append((h, Image.frombytes('RGB', (tw, th), raw[:tw * th * 3])))
    if not rows:
        return
    r = (len(rows) + cols - 1) // cols
    sheet = Image.new('RGB', (cols * (tw + 6) + 6, r * (th + 28) + 6), (12, 12, 14))
    d = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype(FONT, 14)
    except OSError:
        font = ImageFont.load_default()
    for k, (h, im) in enumerate(rows):
        x, y = 6 + (k % cols) * (tw + 6), 6 + (k // cols) * (th + 28)
        sheet.paste(im, (x, y))
        col = (230, 40, 50) if h.get('repeat') else (60, 180, 90)
        d.rectangle([x - 2, y - 2, x + tw + 1, y + th + 1], outline=col, width=3 if h.get('repeat') else 1)
        mm, ss = divmod(int(h['start']), 60)
        d.text((x + 2, y + th + 4), f"{mm}:{ss:02d} V{h.get('visual', '?')} {h['seconds']:.1f}s"
               + ('  REPEAT' if h.get('repeat') else ''), fill=col, font=font)
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out, quality=88)


# --------------------------------------------------------------- preflight
def _image_hash(p: Path) -> int:
    with Image.open(p) as im:
        g = np.asarray(im.convert('L').resize((96, 54)), np.float32) / 255
    return phash(g)


def preflight(spec: dict, min_width=1280, min_height=720, dup_distance=4) -> dict:
    """Missing-media and duplicate-asset checks on a render spec, before any render time is spent."""
    errors, warnings = [], []
    images = list(dict.fromkeys(t['image'] for t in spec.get('timeline', [])))
    hashes, shas = {}, {}
    for p in images:
        P = Path(p)
        if not P.is_file():
            errors.append(f'missing_image:{p}')
            continue
        try:
            with Image.open(P) as im:
                im.load()
                w, h = im.size
        except Exception as exc:  # noqa: BLE001
            errors.append(f'undecodable_image:{p}:{exc}')
            continue
        if w < min_width or h < min_height:
            errors.append(f'image_below_floor_{w}x{h}:{p}')
        shas.setdefault(hashlib.sha256(P.read_bytes()).hexdigest(), []).append(p)
        hashes[p] = _image_hash(P)
    for _, names in shas.items():
        if len(names) > 1:
            errors.append('byte_identical_stills:' + ','.join(Path(n).name for n in names))
    keys = list(hashes)
    for i in range(len(keys)):
        for j in range(i + 1, len(keys)):
            if hamming(hashes[keys[i]], hashes[keys[j]]) <= dup_distance:
                warnings.append(f'near_duplicate_stills:{Path(keys[i]).name}~{Path(keys[j]).name}')
    for s in spec.get('segments', []):
        P = Path(s['audio'])
        if not P.is_file():
            errors.append(f'missing_narration:{P}')
            continue
        try:
            raw = subprocess.check_output(['ffmpeg', '-v', 'error', '-i', str(P), '-ac', '1', '-ar', '8000', '-f', 'f32le', '-'])
            x = np.frombuffer(raw, np.float32)
            if len(x) < 8000 * 0.5:
                errors.append(f'narration_too_short:{P.name}')
            elif float(np.sqrt(np.mean(x * x))) < 1e-3:
                errors.append(f'narration_silent:{P.name}')
        except subprocess.CalledProcessError:
            errors.append(f'undecodable_narration:{P.name}')
    for key in ['bed']:
        b = (spec.get('music') or {}).get(key)
        if b and not Path(b).is_file():
            errors.append(f'missing_music:{b}')
    for c in spec.get('sfx', []):
        if not Path(c['file']).is_file():
            errors.append(f"missing_sfx:{c['file']}")
    if spec.get('intro') and not Path(spec['intro']['video']).is_file():
        errors.append(f"missing_intro:{spec['intro']['video']}")
    return {'images': len(images), 'errors': errors, 'warnings': warnings, 'pass': not errors}


# ------------------------------------------------------- archive (footage)
def ledger_reuse(rows: list[dict], min_overlap=0.5) -> dict:
    """Overlapping source ranges in a footage edit (kind=archive, source, source_in, duration)."""
    arch = [r for r in rows if r.get('kind') == 'archive']
    hits = []
    for i in range(len(arch)):
        a = arch[i]
        a0, a1 = float(a['source_in']), float(a['source_in']) + float(a['duration'])
        for j in range(i + 1, len(arch)):
            b = arch[j]
            if b['source'] != a['source']:
                continue
            b0, b1 = float(b['source_in']), float(b['source_in']) + float(b['duration'])
            ov = min(a1, b1) - max(a0, b0)
            if ov >= min_overlap:
                hits.append({'source': a['source'], 'first': [a0, a1], 'again': [b0, b1], 'overlap_seconds': round(ov, 2),
                             'first_at': a.get('sequence_start'), 'again_at': b.get('sequence_start')})
    photos = {}
    for r in rows:
        if r.get('kind') == 'photo':
            photos[r['photo']] = photos.get(r['photo'], 0) + 1
    return {'archive_rows': len(arch), 'reused_ranges': hits, 'reused_seconds': round(sum(h['overlap_seconds'] for h in hits), 2),
            'photo_uses': photos, 'pass': not hits}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('files', nargs='*')
    ap.add_argument('--formula', help='show formula JSON with a visual_qc block')
    ap.add_argument('--shorts', action='store_true', help='use the formula visual_qc_shorts block')
    ap.add_argument('--contact-dir')
    ap.add_argument('--ledger', help='footage edit JSON (Hip Hop Rewind episode_edit.json) to check for reused ranges')
    ap.add_argument('--out')
    a = ap.parse_args()
    limits = {}
    if a.formula:
        f = json.loads(Path(a.formula).read_text())
        limits = f.get('visual_qc_shorts' if a.shorts else 'visual_qc', {})
    rows = []
    for f in a.files:
        sheet = Path(a.contact_dir) / (Path(f).stem + '_contact.jpg') if a.contact_dir else None
        rows.append(analyze_video(f, limits, contact_sheet=sheet))
        print('VISUAL_QC', 'PASS' if rows[-1]['pass'] else 'FAIL', f, rows[-1]['errors'], flush=True)
    report = {'items': rows}
    if a.ledger:
        report['ledger'] = ledger_reuse(json.loads(Path(a.ledger).read_text()))
    report['pass'] = all(r['pass'] for r in rows) and report.get('ledger', {}).get('pass', True)
    txt = json.dumps(report, indent=2)
    if a.out:
        Path(a.out).write_text(txt)
    else:
        print(txt)
    raise SystemExit(0 if report['pass'] else 1)


if __name__ == '__main__':
    main()
