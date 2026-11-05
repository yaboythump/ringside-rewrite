#!/usr/bin/env python3
"""CTNETWORK cinematic episode finisher (development build).

Takes an existing job's approved assets (chat-made stills, narration that has
already been synthesized, the approved music bed and SFX) and renders a
finished master with:

  * slow Ken Burns motion on every still (no static slideshow holds)
  * frame-accurate crossfades that keep narration sync exactly
  * music ducked under narration, with seamless crossfaded loops
  * the show's established SFX cues, branding and outro hold
  * optional locked intro (HHWI) prepended with its baked audio untouched
  * two-pass EBU R128 loudness normalisation to the show profile target

It never calls TTS, image or video generation APIs, never writes inside the
source job directory, and never publishes. Everything lands in --out.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

import numpy as np
import soundfile as sf

SR = 48000
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
ENGINE_VERSION = 'ctn-episode-engine-dev-2026-11-05b'
# Broadcast-range BT.709 tags. ffmpeg 8 decodes JPEG stills as full-range (yuvj420p) and
# would otherwise flag the master full-range, which some players render with crushed blacks.
BT709 = ['-color_range', 'tv', '-colorspace', 'bt709', '-color_primaries', 'bt709', '-color_trc', 'bt709']


# --------------------------------------------------------------------- utils
def sha256(p: Path) -> str:
    h = hashlib.sha256()
    with Path(p).open('rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


def run(cmd, log: Path, timeout=None):
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open('w') as f:
        f.write(' '.join(str(c) for c in cmd) + '\n\n')
        f.flush()
        p = subprocess.run([str(c) for c in cmd], stdout=f, stderr=subprocess.STDOUT, timeout=timeout)
    if p.returncode:
        tail = log.read_text()[-1500:]
        raise RuntimeError(f'command failed ({p.returncode}); log {log}\n{tail}')


def duration(p: Path) -> float:
    out = subprocess.check_output(['ffprobe', '-v', 'error', '-show_entries', 'format=duration',
                                   '-of', 'csv=p=0', str(p)])
    return float(out.decode().strip())


def load_audio(p: Path) -> np.ndarray:
    raw = subprocess.check_output(['ffmpeg', '-v', 'error', '-i', str(p), '-ar', str(SR), '-ac', '1',
                                   '-f', 'f32le', '-'])
    return np.frombuffer(raw, dtype=np.float32).copy()


def rms_gain(x: np.ndarray, db: float) -> np.ndarray:
    """Same RMS normalisation the approved Ringside Rewrite renders use."""
    rms = float(np.sqrt(np.mean(x * x) + 1e-12))
    return x * (10 ** (db / 20) / max(rms, 1e-5))


def db_to_lin(db):
    return 10 ** (np.asarray(db) / 20)


# ---------------------------------------------------------------------- audio
def build_speech(segments, fades=240):
    """Concatenate narration segments using the approved per-segment levelling."""
    waves, offsets, durs, clock = [], [], [], 0.0
    for seg in segments:
        x = rms_gain(load_audio(Path(seg['audio'])), seg.get('speech_db', -20.0))
        x = np.clip(x, -0.85, 0.85)
        n = min(fades, len(x) // 2)
        if n:
            x[:n] *= np.linspace(0, 1, n)
            x[-n:] *= np.linspace(1, 0, n)
        gap = int(round(seg.get('gap_after', 0.0) * SR))
        offsets.append(clock)
        durs.append(len(x) / SR)
        waves.append(x)
        if gap:
            waves.append(np.zeros(gap, np.float32))
        clock += (len(x) + gap) / SR
    return np.concatenate(waves).astype(np.float32), offsets, durs


def seamless_loop(music: np.ndarray, n: int, xfade_s=2.0) -> np.ndarray:
    """Loop a bed to n samples with equal-power crossfades instead of hard seams."""
    if len(music) >= n:
        return music[:n].copy()
    xf = int(min(xfade_s * SR, len(music) // 4))
    out = np.zeros(n + len(music), np.float32)
    t = np.linspace(0, 1, xf, dtype=np.float32) if xf else np.zeros(0, np.float32)
    fade_in, fade_out = np.sin(t * np.pi / 2), np.cos(t * np.pi / 2)
    pos = 0
    first = True
    while pos < n:
        chunk = music.copy()
        if xf:
            if not first:
                chunk[:xf] *= fade_in
            chunk[-xf:] *= fade_out
        out[pos:pos + len(chunk)] += chunk
        pos += len(chunk) - xf
        first = False
    return out[:n]


def duck_curve(speech: np.ndarray, under_db: float, gap_db: float, *, win=0.05,
               threshold_db=-42.0, attack=0.12, release=0.9, hold=0.35) -> np.ndarray:
    """Per-sample gain (linear) for the bed: under_db while narrating, gap_db in pauses."""
    hop = int(win * SR)
    frames = max(1, math.ceil(len(speech) / hop))
    pad = np.zeros(frames * hop, np.float32)
    pad[:len(speech)] = speech
    env = np.sqrt(np.mean(pad.reshape(frames, hop) ** 2, axis=1) + 1e-12)
    active = 20 * np.log10(env) > threshold_db
    hold_n = int(hold / win)
    if hold_n:  # bridge short breaths so the bed doesn't pump between words
        idx = np.where(active)[0]
        held = active.copy()
        for i in idx:
            held[i:i + hold_n] = True
        active = held
    target = np.where(active, under_db, gap_db).astype(np.float64)
    g = np.empty_like(target)
    cur = gap_db
    a_coef = math.exp(-win / attack)
    r_coef = math.exp(-win / release)
    for i, tg in enumerate(target):
        c = a_coef if tg < cur else r_coef
        cur = tg + (cur - tg) * c
        g[i] = cur
    per_sample = np.repeat(g, hop)[:len(speech)]
    return db_to_lin(per_sample).astype(np.float32)


def place(mix: np.ndarray, clip: np.ndarray, t: float, fade=0.0):
    k = int(round(t * SR))
    if k >= len(mix):
        return
    end = min(k + len(clip), len(mix))
    c = clip[:end - k].copy()
    f = int(min(fade * SR, len(c) // 2))
    if f:
        c[:f] *= np.linspace(0, 1, f)
        c[-f:] *= np.linspace(1, 0, f)
    mix[k:end] += c


def resolve_cue_time(cue, offsets):
    at = cue['at']
    if 'segment' in at:
        return offsets[int(at['segment']) - 1] + float(at.get('plus', 0.0))
    return float(at['t'])


def build_mix(spec, work: Path):
    speech, offsets, durs = build_speech(spec['segments'])
    tail = float(spec.get('outro_hold', 0.0))
    lead = float(spec.get('lead_in', 0.0))
    if lead:
        speech = np.concatenate([np.zeros(int(lead * SR), np.float32), speech])
        offsets = [o + lead for o in offsets]
    n = len(speech) + int(round(tail * SR))
    sp = np.zeros(n, np.float32)
    sp[:len(speech)] = speech

    m = spec['music']
    bed = rms_gain(load_audio(Path(m['bed'])), 0.0)  # unity RMS; levels applied by curve
    bed = seamless_loop(bed, n, m.get('loop_crossfade', 2.0))
    if m.get('duck', True):
        gain = duck_curve(sp, m.get('under_db', -32.0), m.get('gap_db', -26.0))
    else:
        gain = np.full(n, db_to_lin(m.get('under_db', -32.0)), np.float32)
    mix_bed = bed * gain
    fi, fo = int(m.get('fade_in', 1.0) * SR), int(m.get('fade_out', 2.0) * SR)
    if fi:
        mix_bed[:fi] *= np.linspace(0, 1, fi)
    if fo:
        mix_bed[-fo:] *= np.linspace(1, 0, fo)
    mix = sp + mix_bed

    for cue in spec.get('sfx', []):
        clip = rms_gain(load_audio(Path(cue['file'])), cue.get('db', -25.0))
        place(mix, clip, resolve_cue_time(cue, offsets), cue.get('fade', 0.0))

    pre = work / 'mix_pre.wav'
    sf.write(pre, np.clip(mix, -0.98, 0.98), SR, subtype='PCM_24')
    sf.write(work / 'speech_track.wav', sp, SR, subtype='PCM_16')
    final = work / 'mix.wav'
    loudnorm_two_pass(pre, final, spec.get('loudness', {}), work)
    return final, offsets, durs, n / SR


def _measure(src: Path, I, TP, LRA):
    flt = f'loudnorm=I={I}:TP={TP}:LRA={LRA}:print_format=json'
    p = subprocess.run(['ffmpeg', '-hide_banner', '-nostats', '-i', str(src), '-af', flt, '-f', 'null', '-'],
                       capture_output=True, text=True, check=True)
    txt = p.stderr
    return json.loads(txt[txt.rindex('{'):txt.rindex('}') + 1])


def loudnorm_two_pass(src: Path, dst: Path, target, work: Path):
    """Measure -> (limit if needed) -> linear loudnorm. Linear mode never pumps the mix.

    If reaching the target integrated loudness would push true peak over the
    ceiling, linear loudnorm silently undershoots (the Raven master measured
    -14.4 LUFS / -4.0 dBTP). A transparent look-ahead limiter on the gained
    signal first lets the linear pass land on target.
    """
    I, TP, LRA = target.get('I', -14.0), target.get('TP', -1.5), target.get('LRA', 11)
    orig = src
    meas = _measure(src, I, TP, LRA)
    gain = I - float(meas['input_i'])
    for k in range(4):
        if float(meas['input_tp']) + (I - float(meas['input_i'])) <= TP - 0.1:
            break
        limited = work / f'mix_limited_{k}.wav'
        ceiling = 10 ** ((TP - 1.0) / 20)  # 4x oversampled; 1 dB margin absorbs inter-sample overshoot
        run(['ffmpeg', '-y', '-v', 'error', '-i', orig, '-af',
             f'aresample=192000,volume={gain:.3f}dB,alimiter=limit={ceiling:.4f}:attack=5:release=80:level=disabled,aresample={SR}',
             '-c:a', 'pcm_s24le', limited], work / f'limiter_{k}.log')
        src = limited
        meas = _measure(src, I, TP, LRA)
        gain += I - float(meas['input_i'])  # limiting ate some loudness: push the pre-gain and retry
    (work / 'loudnorm_pass1.json').write_text(json.dumps(meas, indent=2))
    flt2 = (f"loudnorm=I={I}:TP={TP}:LRA={LRA}:measured_I={meas['input_i']}:measured_TP={meas['input_tp']}"
            f":measured_LRA={meas['input_lra']}:measured_thresh={meas['input_thresh']}"
            f":offset={meas['target_offset']}:linear=true")
    run(['ffmpeg', '-y', '-v', 'error', '-i', src, '-af', flt2, '-ar', SR, '-ac', 2, dst], work / 'loudnorm_pass2.log')


# --------------------------------------------------------------------- video
MOVES = ['push_in', 'pan_right', 'pull_out', 'pan_left']


def zoompan_expr(move: str, frames: int, zoom: float):
    last = max(frames - 1, 1)
    p = f'(on/{last})'
    e = f'({p}*{p}*(3-2*{p}))'  # smoothstep easing: no abrupt starts/stops
    cx, cy = 'iw/2-(iw/zoom/2)', 'ih/2-(ih/zoom/2)'
    if move == 'push_in':
        return f'1+{zoom}*{e}', cx, cy
    if move == 'pull_out':
        return f'1+{zoom}-{zoom}*{e}', cx, cy
    if move == 'pan_right':
        return f'1+{zoom}', f'(iw-iw/zoom)*{e}', cy
    if move == 'pan_left':
        return f'1+{zoom}', f'(iw-iw/zoom)*(1-{e})', cy
    if move == 'static':
        return '1', '0', '0'
    raise ValueError(move)


def render_clip(item, frames, W, H, fps, out: Path, log: Path, threads=2):
    move = item.get('move', 'push_in')
    zoom = float(item.get('zoom', 0.07))
    sw, sh = 2 * W, 2 * H  # oversample so zoompan's integer crop steps are sub-pixel in the output
    focus = item.get('focus')
    if focus is None:
        pre = f'scale={sw}:{sh}:force_original_aspect_ratio=increase:out_range=tv,crop={sw}:{sh}'
    else:  # vertical reframing of a 16:9 still, centred on the approved focus point
        pre = f'scale=-2:{sh}:out_range=tv,crop={sw}:{sh}:x=(iw-ow)*{float(focus)}:y=0'
    z, x, y = zoompan_expr(move, frames, zoom)
    vf = f"{pre},setsar=1,zoompan=z='{z}':x='{x}':y='{y}':d={frames}:s={W}x{H}:fps={fps},format=yuv420p"
    run(['ffmpeg', '-y', '-v', 'error', '-i', item['image'], '-vf', vf, '-frames:v', frames, '-an',
         '-c:v', 'libx264', '-preset', 'veryfast', '-crf', 10, '-threads', threads, '-pix_fmt', 'yuv420p', *BT709, out], log)


def frame_plan(timeline, fps, total_seconds, xfade_s):
    """Frame-exact boundaries: cumulative rounding so 60+ cuts never drift off narration."""
    starts = [0.0]
    for it in timeline[:-1]:
        starts.append(starts[-1] + float(it['duration']))
    total_frames = int(round(total_seconds * fps))
    F = [int(round(s * fps)) for s in starts] + [total_frames]
    nominal = [F[i + 1] - F[i] for i in range(len(timeline))]
    if min(nominal) <= 0:
        raise ValueError('timeline shorter than audio or zero-length shot')
    T = int(round(xfade_s * fps))
    T = max(0, min(T, min(nominal) // 3))
    return nominal, T


def xfade_graph(n_inputs, nominal, T, fps, transition):
    """filter_complex chaining inputs with xfade at frame-exact offsets.

    Input i (except the last) is rendered T frames longer than its nominal slot,
    so each crossfade starts exactly on the shot's original cut time and the
    picture never drifts against the narration.
    """
    if n_inputs == 1 or T == 0:
        if n_inputs == 1:
            return '[0:v]null[vout]', '[vout]'
        ins = ''.join(f'[{i}:v]' for i in range(n_inputs))
        return f'{ins}concat=n={n_inputs}:v=1:a=0[vout]', '[vout]'
        return '[0:v]null[vout]', '[vout]'
    parts, prev, acc = [], '[0:v]', 0
    for i in range(1, n_inputs):
        acc += nominal[i - 1]
        lab = f'[x{i}]'
        parts.append(f'{prev}[{i}:v]xfade=transition={transition}:duration={T / fps:.6f}:offset={acc / fps:.6f}{lab}')
        prev = lab
    return ';'.join(parts), prev


def drawtext_chain(overlays):
    out = []
    for o in overlays:
        txt = o['text'].replace(':', r'\:').replace("'", r"\'")
        out.append(f"drawtext=fontfile={o.get('font', FONT)}:text='{txt}':fontsize={o.get('size', 24)}"
                   f":fontcolor=white@{o.get('alpha', 0.85)}:x={o['x']}:y={o['y']}"
                   f":shadowcolor=black:shadowx=2:shadowy=2"
                   + (f":enable='{o['enable']}'" if o.get('enable') else ''))
    return ','.join(out)


def render_video(spec, mix: Path, total_s: float, work: Path, out: Path, threads=4, chunk=10):
    W, H, fps = spec['width'], spec['height'], spec.get('fps', 30)
    motion = spec.get('motion', {})
    timeline = spec['timeline']
    nominal, T = frame_plan(timeline, fps, total_s, motion.get('transition_seconds', 0.6) if motion.get('enabled', True) else 0)
    if not motion.get('enabled', True):
        T = 0
    clips_dir = work / 'clips'
    clips_dir.mkdir(exist_ok=True)
    clip_paths, lengths = [], []
    for i, it in enumerate(timeline):
        it = dict(it)
        if not motion.get('enabled', True):
            it['move'] = 'static'
        it.setdefault('move', MOVES[i % len(MOVES)])
        it.setdefault('zoom', motion.get('zoom', 0.07))
        frames = nominal[i] + (T if i < len(timeline) - 1 else 0)
        key = hashlib.sha256(json.dumps([sha256(Path(it['image'])), it['move'], it['zoom'], it.get('focus'),
                                         frames, W, H, fps, ENGINE_VERSION]).encode()).hexdigest()[:16]
        p = clips_dir / f'{i:03}_{key}.mp4'
        if not p.exists():  # resume-safe: identical inputs are never re-rendered
            tmp = p.with_suffix('.part.mp4')
            render_clip(it, frames, W, H, fps, tmp, clips_dir / f'{i:03}.log', threads=threads)
            tmp.replace(p)
        clip_paths.append(p)
        lengths.append(frames)
        print(f'CLIP {i + 1}/{len(timeline)} {it["move"]} {frames}f', flush=True)

    transition = motion.get('transition', 'fade')
    # level 1: chunks of clips joined with xfade
    chunk_paths, chunk_nominal = [], []
    for c0 in range(0, len(clip_paths), chunk):
        idx = list(range(c0, min(c0 + chunk, len(clip_paths))))
        nom = [nominal[i] for i in idx]
        is_last_chunk = idx[-1] == len(clip_paths) - 1
        p = work / f'chunk_{c0 // chunk:02}.mp4'
        if len(idx) == 1:
            shutil.copyfile(clip_paths[idx[0]], p)
        else:
            graph, last = xfade_graph(len(idx), nom, T, fps, transition)
            cmd = ['ffmpeg', '-y', '-v', 'error']
            for i in idx:
                cmd += ['-i', clip_paths[i]]
            cmd += ['-filter_complex', graph, '-map', last, '-an', '-c:v', 'libx264', '-preset', 'veryfast',
                    '-crf', 10, '-threads', threads, '-pix_fmt', 'yuv420p', *BT709, p]
            run(cmd, work / f'chunk_{c0 // chunk:02}.log')
        expected = sum(nom) + (0 if is_last_chunk else T)
        got = int(round(duration(p) * fps))
        if abs(got - expected) > 1:
            raise RuntimeError(f'chunk {p.name} length {got}f != expected {expected}f')
        chunk_paths.append(p)
        chunk_nominal.append(sum(nom))

    # level 2: chain chunks, add branding, mux audio, final encode at show profile settings
    graph, last = xfade_graph(len(chunk_paths), chunk_nominal, T, fps, transition)
    ov = drawtext_chain(spec.get('overlays', []))
    graph += f';{last}{ov or "null"},scale=out_range=tv,format=yuv420p[body]'
    cmd = ['ffmpeg', '-y', '-v', 'warning']
    for p in chunk_paths:
        cmd += ['-i', p]
    cmd += ['-i', mix]
    a_idx = len(chunk_paths)
    intro = spec.get('intro')
    if intro:
        cmd += ['-i', intro['video']]
        i_idx = a_idx + 1
        graph += (f';[{i_idx}:v]scale={W}:{H}:force_original_aspect_ratio=decrease:out_range=tv,pad={W}:{H}:(ow-iw)/2:(oh-ih)/2,'
                  f'setsar=1,fps={fps},format=yuv420p[iv]'
                  f';[{i_idx}:a]aresample={SR},aformat=sample_fmts=fltp:channel_layouts=stereo[ia]'
                  f';[{a_idx}:a]aformat=sample_fmts=fltp:channel_layouts=stereo[ba]'
                  f';[iv][ia][body][ba]concat=n=2:v=1:a=1[vfinal][afinal]')
        vmap, amap = '[vfinal]', '[afinal]'
        total_out = duration(Path(intro['video'])) + total_s
    else:
        vmap, amap = '[body]', f'{a_idx}:a'
        total_out = total_s
    enc = spec.get('encode', {})
    cmd += ['-filter_complex', graph, '-map', vmap, '-map', amap, '-r', fps,
            '-c:v', 'libx264', '-preset', enc.get('preset', 'slow'), '-crf', enc.get('crf', 18),
            '-tune', enc.get('tune', 'film'), '-threads', threads, '-pix_fmt', 'yuv420p', *BT709,
            '-c:a', 'aac', '-b:a', '192k', '-ar', SR, '-ac', 2, '-t', f'{total_out:.3f}',
            '-movflags', '+faststart', out]
    run(cmd, work / 'final_encode.log')
    return out


# ------------------------------------------------------------------- driver
def render(spec: dict, out_dir: Path, threads=4):
    out_dir = Path(out_dir)
    work = out_dir / 'work' / spec['id']
    work.mkdir(parents=True, exist_ok=True)
    src_job = Path(spec['job_dir']).resolve() if spec.get('job_dir') else None
    if src_job and out_dir.resolve().is_relative_to(src_job):
        raise RuntimeError('refusing to write inside the source production job')
    for it in spec['timeline']:
        if not Path(it['image']).is_file():
            raise FileNotFoundError(it['image'])
    for s in spec['segments']:
        if not Path(s['audio']).is_file():
            raise FileNotFoundError(f"narration missing (engine never synthesizes): {s['audio']}")
    t0 = time.monotonic()
    mix, offsets, durs, total = build_mix(spec, work)
    tl_total = sum(float(i['duration']) for i in spec['timeline'])
    if abs(tl_total - total) > 0.5:
        # timeline is authoritative for picture order; stretch the final shot to the audio length
        spec['timeline'][-1]['duration'] = float(spec['timeline'][-1]['duration']) + (total - tl_total)
    target = out_dir / spec['output']
    render_video(spec, mix, total, work, target, threads=threads)
    receipt = {
        'engine': ENGINE_VERSION, 'id': spec['id'], 'output': str(target), 'sha256': sha256(target),
        'seconds_to_render': round(time.monotonic() - t0, 1), 'audio_seconds': total,
        'narration_offsets': offsets, 'inputs': {
            'images': {it['image']: sha256(Path(it['image'])) for it in spec['timeline']},
            'narration': {s['audio']: sha256(Path(s['audio'])) for s in spec['segments']},
            'music': {spec['music']['bed']: sha256(Path(spec['music']['bed']))}},
        'generation_credits_spent': 0, 'publishing_authorized': False}
    (out_dir / f"{spec['id']}.render.json").write_text(json.dumps(receipt, indent=2))
    return receipt


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('spec', help='render spec JSON (see adapters.py)')
    ap.add_argument('--out', required=True)
    ap.add_argument('--threads', type=int, default=4)
    a = ap.parse_args()
    specs = json.loads(Path(a.spec).read_text())
    for spec in specs if isinstance(specs, list) else [specs]:
        print(json.dumps(render(spec, Path(a.out), a.threads), indent=2), flush=True)


if __name__ == '__main__':
    main()
