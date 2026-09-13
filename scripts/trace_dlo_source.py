#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import urllib.request
from datetime import datetime
from pathlib import Path

API = os.environ.get('GITHUB_API_URL', 'https://api.github.com')
REPO = os.environ['GITHUB_REPOSITORY']
TOKEN = os.environ['GH_TOKEN']
START = datetime.fromisoformat('2026-09-06T00:00:00+00:00')
END = datetime.fromisoformat('2026-09-10T23:59:59+00:00')


def get(url: str):
    req = urllib.request.Request(url, headers={
        'Authorization': f'Bearer {TOKEN}',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
    })
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode('utf-8'))


def dt(s: str | None):
    if not s:
        return None
    return datetime.fromisoformat(s.replace('Z', '+00:00'))


def in_window(s: str | None) -> bool:
    d = dt(s)
    return bool(d and START <= d <= END)


def main():
    report = {'artifacts': [], 'runs': []}

    for page in range(1, 40):
        data = get(f'{API}/repos/{REPO}/actions/artifacts?per_page=100&page={page}')
        arts = data.get('artifacts', [])
        if not arts:
            break
        stop = False
        for a in arts:
            created = a.get('created_at')
            if in_window(created):
                report['artifacts'].append({
                    'id': a.get('id'), 'name': a.get('name'), 'size': a.get('size_in_bytes'),
                    'expired': a.get('expired'), 'created_at': created,
                    'expires_at': a.get('expires_at'),
                    'run_id': (a.get('workflow_run') or {}).get('id'),
                    'run_branch': (a.get('workflow_run') or {}).get('head_branch'),
                    'run_sha': (a.get('workflow_run') or {}).get('head_sha'),
                })
            d = dt(created)
            if d and d < START:
                stop = True
        if stop:
            break

    for page in range(1, 30):
        data = get(f'{API}/repos/{REPO}/actions/runs?per_page=100&page={page}')
        runs = data.get('workflow_runs', [])
        if not runs:
            break
        stop = False
        for r in runs:
            created = r.get('created_at')
            if in_window(created):
                hay = ' '.join([
                    str(r.get('name') or ''), str(r.get('display_title') or ''),
                    str(r.get('path') or ''), str((r.get('head_commit') or {}).get('message') or ''),
                ]).casefold()
                if any(k in hay for k in ['ringside', 'droz', "d'lo", 'dlo', 'produce', 'retry', 'upload']):
                    report['runs'].append({
                        'id': r.get('id'), 'name': r.get('name'), 'display_title': r.get('display_title'),
                        'path': r.get('path'), 'event': r.get('event'), 'status': r.get('status'),
                        'conclusion': r.get('conclusion'), 'created_at': created,
                        'updated_at': r.get('updated_at'), 'sha': r.get('head_sha'),
                        'message': (r.get('head_commit') or {}).get('message'),
                    })
            d = dt(created)
            if d and d < START:
                stop = True
        if stop:
            break

    run_ids = sorted({a['run_id'] for a in report['artifacts'] if a.get('run_id')})
    enrich = []
    for rid in run_ids:
        try:
            r = get(f'{API}/repos/{REPO}/actions/runs/{rid}')
            enrich.append({
                'id': rid, 'name': r.get('name'), 'display_title': r.get('display_title'),
                'path': r.get('path'), 'event': r.get('event'), 'conclusion': r.get('conclusion'),
                'created_at': r.get('created_at'), 'sha': r.get('head_sha'),
                'message': (r.get('head_commit') or {}).get('message'),
            })
        except Exception as e:
            enrich.append({'id': rid, 'error': str(e)})
    report['artifact_runs'] = enrich

    Path('dlo-source-trace.json').write_text(json.dumps(report, indent=2), encoding='utf-8')

    print('=== ARTIFACTS IN WINDOW ===')
    for x in report['artifacts']:
        print(json.dumps(x))
    print('=== PRODUCTION-LIKE RUNS ===')
    for x in report['runs']:
        print(json.dumps(x))
    print('=== ARTIFACT RUN METADATA ===')
    for x in enrich:
        print(json.dumps(x))


if __name__ == '__main__':
    main()
