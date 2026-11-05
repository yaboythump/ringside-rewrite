#!/usr/bin/env python3
"""One command: existing job -> finished, QC'd, review-ready deliverables in a sandbox.

    python run_job.py /srv/ctnetwork/jobs/<job> --out /srv/ctnetwork-dev/renders/<job> \
        [--covers-dir DIR] [--subject RAVEN] [--episode-only]

Zero generation credits: narration, stills and covers must already exist.
Never publishes, never writes to the job, the DB, or the review web root.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import adapters  # noqa: E402
import qc  # noqa: E402
import render  # noqa: E402
import thumbnail  # noqa: E402


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('job')
    ap.add_argument('--out', required=True)
    ap.add_argument('--show', default='ringside_rewrite')
    ap.add_argument('--covers-dir')
    ap.add_argument('--subject', default='')
    ap.add_argument('--cues')
    ap.add_argument('--intro')
    ap.add_argument('--episode-only', action='store_true')
    ap.add_argument('--threads', type=int, default=4)
    a = ap.parse_args()
    job, out = Path(a.job).resolve(), Path(a.out).resolve()
    if out.is_relative_to(job):
        raise SystemExit('output must be outside the production job')
    out.mkdir(parents=True, exist_ok=True)
    f = adapters.load_formula(a.show)
    cues = json.loads(Path(a.cues).read_text()) if a.cues else None
    specs = [adapters.rewrite_episode(job, f, cues=cues, intro=a.intro)]
    if not a.episode_only and (job / 'inputs/shorts_plan.json').exists():
        specs += adapters.rewrite_shorts(job, f, covers_dir=a.covers_dir, subject=a.subject)
    (out / 'specs.json').write_text(json.dumps(specs, indent=2))

    t0 = time.monotonic()
    report = {'job': str(job), 'engine': render.ENGINE_VERSION, 'generation_credits_spent': 0,
              'publishing_authorized': False, 'deliverables': []}
    for spec in specs:
        print('RENDER', spec['id'], flush=True)
        rec = render.render(spec, out, threads=a.threads)
        q = spec['qc']
        vqc = qc.video_qc(rec['output'], width=q['width'], height=q['height'], min_seconds=q['min_seconds'],
                          max_seconds=q['max_seconds'], lufs=spec['loudness']['I'],
                          true_peak_max=spec['loudness']['TP'] + 0.5)
        tw, th = (1280, 720) if spec['width'] > spec['height'] else (1080, 1920)
        thumb_out = out / f"{spec['id']}_thumbnail.jpg"
        thumb = thumbnail.prepare(spec['thumbnail'], thumb_out, tw, th)
        tqc = qc.thumbnail_qc(thumb_out, tw, th)
        report['deliverables'].append({'id': spec['id'], 'video': rec, 'video_qc': vqc, 'thumbnail': thumb,
                                       'thumbnail_qc': tqc})
        print('QC', spec['id'], 'PASS' if vqc['pass'] and tqc['pass'] else 'FAIL', vqc['errors'], flush=True)
        (out / 'delivery_report.json').write_text(json.dumps(report, indent=2))
    report['pass'] = all(d['video_qc']['pass'] and d['thumbnail_qc']['pass'] for d in report['deliverables'])
    report['wall_seconds'] = round(time.monotonic() - t0, 1)
    (out / 'delivery_report.json').write_text(json.dumps(report, indent=2))
    print('DELIVERY', 'PASS' if report['pass'] else 'FAIL', out / 'delivery_report.json', flush=True)
    raise SystemExit(0 if report['pass'] else 1)


if __name__ == '__main__':
    main()
