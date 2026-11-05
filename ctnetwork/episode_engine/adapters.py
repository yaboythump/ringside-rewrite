#!/usr/bin/env python3
"""Build render specs from existing CTNETWORK job folders (read-only).

Ringside Rewrite jobs (Raven 20261104 / ECW 20261030 layout):
  production_plan_v2.json        outputs[0].scenes[].{text,image,audio}
  work/edit/timeline.json        approved picture edit (optional; else 1 image/segment)
  inputs/shorts_plan.json        [{n, headline, text, shots:[[scene, focus]...]}]
  work/audio/short_{n}.wav       Short narration
  graphics/thumbnail.jpg         chat-made thumbnail

HHWI adds a locked intro (profile key intro.video_asset) that is prepended
once with its baked audio.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent


def load_formula(show):
    return json.loads((HERE / 'formulas' / f'{show}.json').read_text())


def _sfx(formula, cues):
    out = []
    for c in cues:
        a = formula['sfx_assets'][c['sfx']]
        out.append({'file': a['file'], 'db': a.get('db', -25.0), 'fade': a.get('fade', 0.0), 'at': c['at']})
    return out


def rewrite_episode(job: Path, formula: dict, *, cues=None, music_bed=None, intro=None):
    job = Path(job)
    plan = json.loads((job / 'production_plan_v2.json').read_text())
    out = plan['outputs'][0]
    segments = [{'audio': str(job / s['audio']), 'speech_db': formula['narrator']['speech_db']} for s in out['scenes']]
    ep = formula['episode']
    tl_file = job / 'work/edit/timeline.json'
    if tl_file.exists():  # preserve the approved edit exactly: same images, same order, same cut points
        timeline = [{'image': t['image'], 'duration': float(t['duration'])} for t in json.loads(tl_file.read_text())]
        if timeline and timeline[-1]['duration'] > 0:
            # the approved timeline already contains the outro hold item
            outro_hold = timeline[-1]['duration']
        else:
            outro_hold = ep['outro_hold']
    else:
        import subprocess
        timeline = []
        for s in out['scenes']:
            d = float(subprocess.check_output(['ffprobe', '-v', 'error', '-show_entries', 'format=duration',
                                               '-of', 'csv=p=0', str(job / s['audio'])]).decode())
            timeline.append({'image': str(job / s['image']), 'duration': d})
        outro_hold = ep['outro_hold']
        timeline.append({'image': str(job / 'graphics/thumbnail.jpg'), 'duration': outro_hold, 'move': 'push_in', 'zoom': 0.03})
    music = dict(formula['music'])
    if music_bed:
        music['bed'] = music_bed
    spec = {
        'id': 'episode', 'job_dir': str(job), 'show': formula['show_slug'],
        'output': Path(out['file']).name,
        'width': ep['width'], 'height': ep['height'], 'fps': ep['fps'],
        'segments': segments, 'timeline': timeline, 'outro_hold': outro_hold,
        'music': music, 'sfx': _sfx(formula, cues or formula['sfx_cues_default']),
        'overlays': ep['overlays'], 'motion': ep['motion'], 'encode': ep['encode'],
        'loudness': formula['loudness'], 'thumbnail': str(job / 'graphics/thumbnail.jpg'),
        'qc': {'width': ep['width'], 'height': ep['height'], 'min_seconds': ep['min_seconds'],
               'max_seconds': ep['max_seconds']},
    }
    if intro:
        spec['intro'] = {'video': intro}
    return spec


def rewrite_shorts(job: Path, formula: dict, *, covers_dir=None, subject='', music_bed=None):
    import subprocess
    job = Path(job)
    plans = json.loads((job / 'inputs/shorts_plan.json').read_text())
    sh = formula['shorts']
    music = dict(formula['music'])
    if music_bed:
        music['bed'] = music_bed
    specs = []
    for s in plans:
        n = s['n']
        audio = job / f'work/audio/short_{n}.wav'
        narr = float(subprocess.check_output(['ffprobe', '-v', 'error', '-show_entries', 'format=duration',
                                              '-of', 'csv=p=0', str(audio)]).decode())
        # Approved renders padded short narration with silence to reach 45 s.
        # Here the gap becomes a music-up outro on the final shot instead of dead air.
        tail = max(0.6, sh['min_seconds'] + 0.3 - narr)
        total = narr + tail
        if total > sh['max_seconds']:
            raise ValueError(f'short {n} narration {narr:.1f}s exceeds {sh["max_seconds"]}s')
        cover = Path(covers_dir) / f'thumbnail_short_{n}.jpg' if covers_dir else job / 'graphics/thumbnail.jpg'
        cover_s = sh['cover_seconds']
        shot_len = (total - cover_s) / len(s['shots'])
        timeline = [{'image': str(cover), 'duration': cover_s, 'move': 'static'}]
        for k, (idx, focus) in enumerate(s['shots']):
            timeline.append({'image': str(job / f'graphics/scene_{int(idx):02}.jpg'), 'duration': shot_len,
                             'focus': float(focus), 'move': ['push_in', 'pull_out'][k % 2]})
        overlays = []
        for o in sh['overlays']:
            o = dict(o)
            o['text'] = o['text'].replace('{SUBJECT}', subject.upper() or s.get('subject', '').upper()).rstrip(' /')
            o['enable'] = f'gte(t,{cover_s})'  # the cover is the published opening frame: keep it clean
            overlays.append(o)
        specs.append({
            'id': f'short_{n}', 'job_dir': str(job), 'show': formula['show_slug'],
            'output': f'Short_{n}.mp4', 'width': sh['width'], 'height': sh['height'], 'fps': sh['fps'],
            'segments': [{'audio': str(audio), 'speech_db': formula['narrator']['speech_db']}],
            'timeline': timeline, 'outro_hold': tail,
            'music': {**music, 'fade_in': 0.3, 'fade_out': 1.0}, 'sfx': [],
            'overlays': overlays, 'motion': sh['motion'], 'encode': sh['encode'],
            'loudness': formula['loudness'], 'thumbnail': str(cover),
            'qc': {'width': sh['width'], 'height': sh['height'], 'min_seconds': sh['min_seconds'],
                   'max_seconds': sh['max_seconds']},
        })
    return specs


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('job')
    ap.add_argument('--show', default='ringside_rewrite')
    ap.add_argument('--covers-dir')
    ap.add_argument('--subject', default='')
    ap.add_argument('--cues', help='JSON file with job-specific SFX cues')
    ap.add_argument('--intro')
    ap.add_argument('--episode-only', action='store_true')
    ap.add_argument('--out', required=True)
    a = ap.parse_args()
    f = load_formula(a.show)
    cues = json.loads(Path(a.cues).read_text()) if a.cues else None
    specs = [rewrite_episode(Path(a.job), f, cues=cues, intro=a.intro)]
    if not a.episode_only and (Path(a.job) / 'inputs/shorts_plan.json').exists():
        specs += rewrite_shorts(Path(a.job), f, covers_dir=a.covers_dir, subject=a.subject)
    Path(a.out).write_text(json.dumps(specs, indent=2))
    print(a.out, len(specs), 'specs')


if __name__ == '__main__':
    main()
