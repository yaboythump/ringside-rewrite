#!/usr/bin/env python3
"""Automated delivery QC for CTNETWORK masters, Shorts and thumbnails.

One decode pass measures: container/stream spec, full decode errors, black
frames, frozen picture (static slideshow holds), dead air, integrated loudness
and true peak, and audio/video length agreement. Thumbnails are checked
against YouTube upload limits. Read-only: it never modifies the file.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path

DEFAULTS = {
    'width': 1920, 'height': 1080, 'fps': 30, 'sample_rate': 48000, 'channels': 2,
    'min_seconds': 0, 'max_seconds': 1e9,
    'lufs': -14.0, 'lufs_tolerance': 1.0, 'true_peak_max': -1.0,
    'max_freeze_seconds': 6.0, 'freeze_noise': 0.0015,
    'max_black_seconds': 0.2, 'silence_db': -50, 'max_silence_seconds': 2.0,
    'av_tolerance': 0.15,
    'allowed_black': [],   # [start, end] windows of intentional dips to black (from the shot plan)
}


def _probe(p):
    return json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-show_streams', '-show_format',
                                               '-of', 'json', str(p)]))


def _intervals(text, start_key, end_key):
    starts = [float(x) for x in re.findall(start_key + r'[:=]\s*([0-9.]+)', text)]
    ends = [float(x) for x in re.findall(end_key + r'[:=]\s*([0-9.]+)', text)]
    out = []
    for i, s in enumerate(starts):
        e = ends[i] if i < len(ends) else None
        out.append([round(s, 2), round(e, 2) if e is not None else None])
    return out


def video_qc(path, **limits):
    L = {**DEFAULTS, **{k: v for k, v in limits.items() if v is not None}}
    path = Path(path)
    d = _probe(path)
    v = next((s for s in d['streams'] if s['codec_type'] == 'video'), None)
    a = next((s for s in d['streams'] if s['codec_type'] == 'audio'), None)
    dur = float(d['format'].get('duration', 0))
    errors, warnings = [], []
    if not v:
        errors.append('no_video_stream')
    else:
        if (v['width'], v['height']) != (L['width'], L['height']):
            errors.append(f"dimensions_{v['width']}x{v['height']}_expected_{L['width']}x{L['height']}")
        num, den = (int(x) for x in v['r_frame_rate'].split('/'))
        if abs(num / den - L['fps']) > 0.01:
            errors.append(f'fps_{num / den:.3f}_expected_{L["fps"]}')
        if v.get('codec_name') != 'h264' or v.get('pix_fmt') != 'yuv420p':
            errors.append(f"video_codec_{v.get('codec_name')}_{v.get('pix_fmt')}")
    if not a:
        errors.append('no_audio_stream')
    else:
        if int(a.get('sample_rate', 0)) != L['sample_rate']:
            errors.append(f"audio_rate_{a.get('sample_rate')}")
        if int(a.get('channels', 0)) != L['channels']:
            errors.append(f"audio_channels_{a.get('channels')}")
    if v and a:
        dv, da = float(v.get('duration', dur)), float(a.get('duration', dur))
        if abs(dv - da) > L['av_tolerance']:
            errors.append(f'av_length_mismatch_{dv - da:+.2f}s')
    if not L['min_seconds'] <= dur <= L['max_seconds']:
        errors.append(f'runtime_{dur:.1f}s_outside_{L["min_seconds"]}-{L["max_seconds"]}')

    vf = (f"blackdetect=d={L['max_black_seconds']}:pix_th=0.08:pic_th=0.98,"
          f"freezedetect=n={L['freeze_noise']}:d={L['max_freeze_seconds']}")
    af = f"silencedetect=n={L['silence_db']}dB:d={L['max_silence_seconds']},ebur128=peak=true"
    p = subprocess.run(['ffmpeg', '-hide_banner', '-nostats', '-v', 'info', '-xerror', '-i', str(path),
                        '-vf', vf, '-af', af, '-f', 'null', '-'], capture_output=True, text=True)
    log = p.stderr
    if p.returncode:
        errors.append('decode_failed')
    black = _intervals(log, 'black_start', 'black_end')
    freeze = _intervals(log, r'lavfi\.freezedetect\.freeze_start', r'lavfi\.freezedetect\.freeze_end')
    silence = _intervals(log, 'silence_start', 'silence_end')
    lufs = re.findall(r'I:\s*([-0-9.]+) LUFS', log)
    peak = re.findall(r'Peak:\s*([-0-9.]+) dBFS', log)
    lufs = float(lufs[-1]) if lufs else None
    peak = float(peak[-1]) if peak else None
    allowed = L.get('allowed_black') or []
    planned = [b for b in black if any(a0 <= b[0] and (b[1] if b[1] is not None else dur) <= a1 for a0, a1 in allowed)]
    unplanned = [b for b in black if b not in planned]
    if unplanned:
        errors.append(f'black_frames_{len(unplanned)}')
    if planned:
        warnings.append(f'planned_dip_to_black_{len(planned)}')
    if freeze:
        held = sum(((e if e is not None else dur) - s) for s, e in freeze)
        errors.append(f'static_holds_{len(freeze)}_totalling_{held:.0f}s_slideshow_feel')
    if silence:
        errors.append(f'dead_air_{len(silence)}')
    if lufs is None or abs(lufs - L['lufs']) > L['lufs_tolerance']:
        errors.append(f'loudness_{lufs}_LUFS_target_{L["lufs"]}')
    if peak is None or peak > L['true_peak_max']:
        errors.append(f'true_peak_{peak}_dBTP_over_{L["true_peak_max"]}')
    elif peak < L['true_peak_max'] - 4:
        warnings.append(f'true_peak_{peak}_dBTP_headroom_unused')
    return {'file': str(path), 'duration': round(dur, 3), 'width': v and v['width'], 'height': v and v['height'],
            'integrated_lufs': lufs, 'true_peak_dbtp': peak, 'black': black, 'freeze': freeze,
            'silence': silence, 'errors': errors, 'warnings': warnings, 'pass': not errors}


def thumbnail_qc(path, width=1280, height=720, max_bytes=2 * 1024 * 1024):
    from PIL import Image
    path = Path(path)
    errors = []
    with Image.open(path) as im:
        im.load()
        w, h, fmt = im.size[0], im.size[1], im.format
    if (w, h) != (width, height):
        errors.append(f'dimensions_{w}x{h}_expected_{width}x{height}')
    if fmt not in ('JPEG', 'PNG'):
        errors.append(f'format_{fmt}')
    if path.stat().st_size > max_bytes:
        errors.append(f'bytes_{path.stat().st_size}_over_youtube_2MB_limit')
    return {'file': str(path), 'width': w, 'height': h, 'format': fmt, 'bytes': path.stat().st_size,
            'errors': errors, 'pass': not errors}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('files', nargs='+')
    ap.add_argument('--width', type=int)
    ap.add_argument('--height', type=int)
    ap.add_argument('--min-seconds', type=float)
    ap.add_argument('--max-seconds', type=float)
    ap.add_argument('--out')
    a = ap.parse_args()
    rows = []
    for f in a.files:
        if f.lower().endswith(('.jpg', '.jpeg', '.png')):
            rows.append(thumbnail_qc(f, a.width or 1280, a.height or 720))
        else:
            rows.append(video_qc(f, width=a.width, height=a.height, min_seconds=a.min_seconds,
                                 max_seconds=a.max_seconds))
    report = {'pass': all(r['pass'] for r in rows), 'items': rows}
    txt = json.dumps(report, indent=2)
    if a.out:
        Path(a.out).write_text(txt)
    print(txt)
    raise SystemExit(0 if report['pass'] else 1)


if __name__ == '__main__':
    main()
