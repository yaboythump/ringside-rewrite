#!/usr/bin/env python3
"""Compact before/after summary of a Project 003 server run (reads JSON only)."""
import json
import sys
from pathlib import Path

P = Path(sys.argv[1])


def load(p):
    p = P / p
    return json.loads(p.read_text()) if p.exists() else None


VKEYS = ['seconds_analyzed', 'holds', 'unique_visuals', 'repeats_total', 'repeats_within_window', 'min_repeat_gap_seconds',
         'max_appearances_one_visual', 'mean_hold_seconds', 'longest_hold_seconds', 'static_seconds_total',
         'static_fraction', 'longest_static_seconds', 'black_or_flat_runs', 'pillarbox_seconds', 'errors']


def vrow(r):
    return {k: r.get(k) for k in VKEYS} if r else None


out = {}
d = load('renders/raven-poc/delivery_report.json')
if d:
    for row in d['deliverables']:
        out['poc'] = {
            'file': row.get('video', {}).get('output'), 'render_seconds': row.get('video', {}).get('seconds_to_render'),
            'preflight': row.get('preflight'), 'plan': {k: v for k, v in (row.get('plan_report') or {}).items() if k != 'policy'},
            'delivery_qc': {k: row['video_qc'].get(k) for k in ['duration', 'integrated_lufs', 'true_peak_dbtp', 'errors', 'warnings', 'pass']} if row.get('video_qc') else None,
            'visual_qc': vrow(row.get('visual_qc')),
            'baselines_same_window': [vrow(b) | {'file': b['file']} for b in row.get('baseline_visual_qc', [])],
        }
    out['poc_pass'] = d.get('pass')
for name in ['raven-plan-approved', 'raven-plan-coverage']:
    r = load(f'renders/{name}/plan_report.json')
    if r:
        s = r['specs'][0]
        out[name] = {'preflight': s['preflight'], 'plan': {k: v for k, v in (s['plan_report'] or {}).items() if k != 'policy'}}
for name in ['published_raven_full', 'project002_raven_full', 'hip_hop_rewind_e001', 'published_raven_shorts']:
    r = load(f'qc/{name}.json')
    if r:
        out[name] = [vrow(i) for i in r['items']]
        if r.get('ledger'):
            out[name + '_ledger'] = {k: r['ledger'][k] for k in ['archive_rows', 'reused_seconds', 'photo_uses', 'pass']} | {'reused_ranges': r['ledger']['reused_ranges'][:12]}
print(json.dumps(out, indent=1, default=str))
