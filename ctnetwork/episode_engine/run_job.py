#!/usr/bin/env python3
"""One command: existing job -> finished, QC'd, review-ready deliverables in a sandbox.

    python run_job.py /srv/ctnetwork/jobs/<job> --out /srv/ctnetwork-dev/renders/<job> \
        [--planner coverage] [--excerpt 60-90 | --segments 1-2] [--act-breaks 2] \
        [--covers-dir DIR] [--subject RAVEN] [--episode-only] [--compare BASELINE.mp4 ...]

--planner approved  (default) the approved edit exactly, with Project 002 motion/crossfades
--planner coverage  Project 003 virtual-coverage shot plan over the same approved stills
--excerpt LO-HI     render only a contiguous run of segments (cold open first) lasting LO-HI s
--compare FILE      also visual-QC the same time window of an existing master (read-only)

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
import visual_qc  # noqa: E402


def planned_dips(spec) -> list[list[float]]:
    """Time windows of the plan's intentional dip-to-black transitions (QC must not call them missing media)."""
    out, t = [], 0.0
    if spec.get('intro'):
        t += render.duration(Path(spec['intro']['video']))
    for i, it in enumerate(spec['timeline']):
        tr = it.get('transition_in') or {}
        if i and tr.get('type') == 'fadeblack':
            out.append([round(t - 0.1, 3), round(t + float(tr.get('seconds', 1.0)) + 0.1, 3)])
        t += float(it['duration'])
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('job')
    ap.add_argument('--out', required=True)
    ap.add_argument('--show', default='ringside_rewrite')
    ap.add_argument('--planner', choices=['approved', 'coverage'], default='approved')
    ap.add_argument('--excerpt', help='LO-HI seconds; renders a segment excerpt (implies --episode-only)')
    ap.add_argument('--segments', help='FIRST-LAST segment numbers (implies --episode-only)')
    ap.add_argument('--act-breaks', help='comma-separated segment numbers that open a new act')
    ap.add_argument('--output-name')
    ap.add_argument('--compare', nargs='*', default=[], help='existing masters to visual-QC over the same window')
    ap.add_argument('--covers-dir')
    ap.add_argument('--subject', default='')
    ap.add_argument('--cues')
    ap.add_argument('--intro')
    ap.add_argument('--episode-only', action='store_true')
    ap.add_argument('--plan-only', action='store_true', help='write plan + preflight report, render nothing')
    ap.add_argument('--threads', type=int, default=4)
    a = ap.parse_args()
    job, out = Path(a.job).resolve(), Path(a.out).resolve()
    if out.is_relative_to(job):
        raise SystemExit('output must be outside the production job')
    out.mkdir(parents=True, exist_ok=True)
    f = adapters.load_formula(a.show)
    cues = json.loads(Path(a.cues).read_text()) if a.cues else None
    act_breaks = [int(x) for x in a.act_breaks.split(',')] if a.act_breaks else None
    seg_range = None
    if a.segments:
        seg_range = tuple(int(x) for x in a.segments.split('-'))
    elif a.excerpt:
        lo, hi = (float(x) for x in a.excerpt.split('-'))
        f.setdefault('excerpt', {}).update(min_seconds=lo, max_seconds=hi)
        seg_range = adapters.choose_excerpt(adapters.segment_durations(job), lo, hi, f['episode']['outro_hold'])
        print('EXCERPT segments', seg_range, flush=True)
    if seg_range and a.planner != 'coverage':
        raise SystemExit('--excerpt/--segments need --planner coverage')
    specs = [adapters.rewrite_episode(job, f, cues=cues, intro=a.intro, planner=a.planner,
                                      segment_range=seg_range, act_breaks=act_breaks, output_name=a.output_name)]
    if not (a.episode_only or seg_range) and (job / 'inputs/shorts_plan.json').exists():
        specs += adapters.rewrite_shorts(job, f, covers_dir=a.covers_dir, subject=a.subject)
    (out / 'specs.json').write_text(json.dumps(specs, indent=2))
    if a.plan_only:
        rows = []
        for spec in specs:
            pre = visual_qc.preflight(spec)
            rows.append({'id': spec['id'], 'preflight': pre, 'plan_report': spec.get('plan_report')})
            print('PLAN', spec['id'], json.dumps({k: v for k, v in (spec.get('plan_report') or {}).items() if k != 'policy'}), flush=True)
        (out / 'plan_report.json').write_text(json.dumps({'planner': a.planner, 'specs': rows}, indent=2))
        raise SystemExit(0 if all(r['preflight']['pass'] for r in rows) else 1)

    t0 = time.monotonic()
    report = {'job': str(job), 'engine': render.ENGINE_VERSION, 'planner': a.planner, 'generation_credits_spent': 0,
              'publishing_authorized': False, 'deliverables': []}
    for spec in specs:
        pre = visual_qc.preflight(spec)
        print('PREFLIGHT', spec['id'], 'PASS' if pre['pass'] else 'FAIL', pre['errors'], pre['warnings'], flush=True)
        if not pre['pass']:
            report['deliverables'].append({'id': spec['id'], 'preflight': pre})
            continue
        if spec.get('plan_report'):
            print('PLAN', spec['id'], json.dumps({k: v for k, v in spec['plan_report'].items() if k != 'policy'}), flush=True)
        print('RENDER', spec['id'], flush=True)
        rec = render.render(spec, out, threads=a.threads)
        q = spec['qc']
        vqc = qc.video_qc(rec['output'], width=q['width'], height=q['height'], min_seconds=q['min_seconds'],
                          max_seconds=q['max_seconds'], lufs=spec['loudness']['I'],
                          true_peak_max=spec['loudness']['TP'] + 0.5, allowed_black=planned_dips(spec))
        is_short = spec['height'] > spec['width']
        limits = f.get('visual_qc_shorts' if is_short else 'visual_qc', {})
        vis = visual_qc.analyze_video(rec['output'], limits, contact_sheet=out / f"{spec['id']}_contact.jpg")
        tw, th = (1280, 720) if spec['width'] > spec['height'] else (1080, 1920)
        thumb_out = out / f"{spec['id']}_thumbnail.jpg"
        thumb = thumbnail.prepare(spec['thumbnail'], thumb_out, tw, th)
        tqc = qc.thumbnail_qc(thumb_out, tw, th)
        row = {'id': spec['id'], 'preflight': pre, 'plan_report': spec.get('plan_report'), 'video': rec,
               'video_qc': vqc, 'visual_qc': vis, 'thumbnail': thumb, 'thumbnail_qc': tqc}
        if a.compare and not is_short:
            row['baseline_visual_qc'] = []
            for b in a.compare:
                bq = visual_qc.analyze_video(b, limits, contact_sheet=out / f"baseline_{Path(b).parent.name}_contact.jpg",
                                             start=0.0, seconds=vqc['duration'] if seg_range else None)
                row['baseline_visual_qc'].append(bq)
                print('BASELINE_VISUAL_QC', b, 'PASS' if bq['pass'] else 'FAIL', bq['errors'], flush=True)
        report['deliverables'].append(row)
        print('QC', spec['id'], 'PASS' if vqc['pass'] and tqc['pass'] else 'FAIL', vqc['errors'], flush=True)
        print('VISUAL_QC', spec['id'], 'PASS' if vis['pass'] else 'FAIL', vis['errors'], flush=True)
        (out / 'delivery_report.json').write_text(json.dumps(report, indent=2))
    report['pass'] = all(d.get('preflight', {}).get('pass') and d.get('video_qc', {}).get('pass')
                         and d.get('visual_qc', {}).get('pass') and d.get('thumbnail_qc', {}).get('pass')
                         for d in report['deliverables'])
    report['wall_seconds'] = round(time.monotonic() - t0, 1)
    (out / 'delivery_report.json').write_text(json.dumps(report, indent=2))
    print('DELIVERY', 'PASS' if report['pass'] else 'FAIL', out / 'delivery_report.json', flush=True)
    raise SystemExit(0 if report['pass'] else 1)


if __name__ == '__main__':
    main()
