#!/usr/bin/env python3
from __future__ import annotations

import base64
import io
import json
import os
import re
import sys
import tarfile
import time
from pathlib import Path

import requests
import websocket

POD_ID = os.environ['POD_ID']
PASSWORD = Path(os.environ['JUPYTER_PASSWORD_FILE']).read_text().strip()
BASE = f'https://{POD_ID}-8888.proxy.runpod.net'
SESSION = requests.Session()
REPO = Path(__file__).resolve().parents[1]
MANIFEST = REPO / 'ctnetwork-production-manifest.json'


def build_payload() -> str:
    bio = io.BytesIO()
    with tarfile.open(fileobj=bio, mode='w:gz') as tf:
        tf.add(REPO / 'runpod' / 'ctnetwork_factory_v2.py', arcname='controller/ctnetwork_factory_v2.py')
        tf.add(REPO / 'runpod' / 'ctnetwork_qwen_narrate.py', arcname='controller/ctnetwork_qwen_narrate.py')
        tf.add(REPO / 'runpod' / 'ctnetwork_ltx_generate.py', arcname='controller/ctnetwork_ltx_generate.py')
        tf.add(MANIFEST, arcname='incoming/ctnetwork-production-manifest.json')
        # Authorized CTNETWORK show reference used by the final local-factory proof job.
        # It remains inside the production payload and is never published as a standalone asset.
        malik_ref = REPO / 'published-assets' / 'the-case-against' / 'narrator-audition' / 'malik_am_onyx_raw.wav'
        if malik_ref.exists():
            tf.add(malik_ref, arcname='incoming/voice_refs/the_case_against_malik.wav')
        for p in sorted((REPO / 'ctnetwork' / 'shows').glob('*.yaml')):
            tf.add(p, arcname=f'recipes/{p.name}')
    return base64.b64encode(bio.getvalue()).decode()


def login():
    r = None
    for _ in range(30):
        try:
            r = SESSION.get(BASE + '/login', timeout=12)
            if r.ok:
                break
        except Exception:
            pass
        time.sleep(4)
    if r is None or not r.ok:
        raise RuntimeError(f'Jupyter not reachable; last={getattr(r, "status_code", None)}')
    m = re.search(r'name="_xsrf" value="([^"]+)"', r.text)
    if not m:
        raise RuntimeError('Could not find Jupyter XSRF token')
    xsrf = m.group(1)
    rr = SESSION.post(BASE + '/login', data={'_xsrf': xsrf, 'password': PASSWORD, 'next': '/'}, timeout=30, allow_redirects=False)
    if rr.status_code not in (200, 302, 303):
        rr.raise_for_status()
    cx = SESSION.cookies.get('_xsrf')
    headers = {'X-XSRFToken': cx} if cx else {}
    SESSION.get(BASE + '/api/status', headers=headers, timeout=30).raise_for_status()
    return headers


def run_remote(headers):
    r = SESSION.post(BASE + '/api/terminals', headers=headers, json={}, timeout=30)
    r.raise_for_status()
    term = r.json()['name']
    cookie = '; '.join(f'{c.name}={c.value}' for c in SESSION.cookies)
    ws = websocket.create_connection(f'wss://{POD_ID}-8888.proxy.runpod.net/terminals/websocket/{term}', cookie=cookie, origin=BASE, timeout=60)
    payload = build_payload()
    shell = f'''set -Eeuo pipefail
ROOT=/workspace/ctnetwork-local
BATCH="$ROOT/batches/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$ROOT/controller" "$ROOT/recipes" "$ROOT/incoming" "$ROOT/batches" "$ROOT/ready_for_approval" "$ROOT/status"
echo {payload} | base64 -d >/tmp/ctnetwork-production-payload.tar.gz
tar -xzf /tmp/ctnetwork-production-payload.tar.gz -C "$ROOT"
chmod +x "$ROOT/controller/ctnetwork_factory_v2.py" "$ROOT/controller/ctnetwork_qwen_narrate.py" "$ROOT/controller/ctnetwork_ltx_generate.py"

# Hard safety gate: a production batch cannot run before the local engine factory has passed.
for s in lipsync_smoke qwen_smoke ltx25_smoke ltx25_dfr factory_acceptance; do
  test "$(cat "$ROOT/status/${{s}}.status" 2>/dev/null || true)" = PASS || {{ echo "FACTORY_GATE_BLOCKED:${{s}}"; exit 71; }}
done

MAN="$ROOT/incoming/ctnetwork-production-manifest.json"
rm -rf "$ROOT/incoming/jobs"
set +e
python3 - <<'PY'
import json, pathlib
p=pathlib.Path('/workspace/ctnetwork-local/incoming/ctnetwork-production-manifest.json')
m=json.load(open(p))
assert m.get('manual_gate_required') is True, 'manual gate flag missing'
assert m.get('publish_allowed') is False, 'publish must default false'
jobs=m.get('jobs') or []
if not jobs:
    print('NO_JOBS_DUE')
    raise SystemExit(20)
out=pathlib.Path('/workspace/ctnetwork-local/incoming/jobs')
out.mkdir(parents=True, exist_ok=True)
for i,j in enumerate(jobs,1):
    if j.get('publish') is True:
        raise AssertionError('job requests publishing inside production gate')
    jid=j.get('job_id')
    if not jid:
        raise AssertionError(f'job {i} missing stable job_id')
    (out/f'{i:02d}-{jid}.json').write_text(json.dumps(j, indent=2)+'\n')
print('JOBS_DUE', len(jobs))
PY
split_rc=$?
set -e
if [ "$split_rc" -eq 20 ]; then
  echo NO_PRODUCTION_REQUIRED
  echo PASS > "$ROOT/status/production_batch.status"
  exit 0
fi
test "$split_rc" -eq 0 || exit "$split_rc"

mkdir -p "$BATCH"
failed=0
for job in "$ROOT"/incoming/jobs/*.json; do
  echo "=== CTNETWORK JOB $(basename "$job") ==="
  if "$ROOT/envs/core/bin/python" "$ROOT/controller/ctnetwork_factory_v2.py" run-manifest "$job"; then
    echo "PASS $(basename "$job")" >> "$BATCH/results.txt"
  else
    echo "FAIL $(basename "$job")" >> "$BATCH/results.txt"
    failed=1
  fi
done

python3 - <<'PY'
import json, pathlib
root=pathlib.Path('/workspace/ctnetwork-local')
manifest=json.load(open(root/'incoming/ctnetwork-production-manifest.json'))
summary={'production_date':manifest.get('production_date'),'manual_gate_required':True,'publish_allowed':False,'jobs':[]}
for j in manifest.get('jobs',[]):
    jid=j['job_id']
    sp=root/'jobs'/jid/'state.json'
    state=json.load(open(sp)) if sp.exists() else {'job_id':jid,'state':'UNKNOWN'}
    ap=root/'ready_for_approval'/jid/'approval.json'
    if ap.exists():
        a=json.load(open(ap))
        assert a.get('publish_allowed') is False
        assert a.get('approved') is False
        state['approval_gate_verified']=True
    summary['jobs'].append(state)
path=root/'status'/'production_batch_latest.json'
path.write_text(json.dumps(summary,indent=2)+'\n')
print(path)
PY

test "$failed" -eq 0 || {{ echo BATCH_HAS_BLOCKED_JOBS; exit 72; }}
echo PASS > "$ROOT/status/production_batch.status"
echo CTNETWORK_PRODUCTION_BATCH_READY_FOR_APPROVAL
'''
    enc = base64.b64encode(shell.encode()).decode()
    ws.send(json.dumps(['stdin', f'echo {enc} | base64 -d >/tmp/ctnetwork-run-production.sh; bash /tmp/ctnetwork-run-production.sh; rc=$?; echo __CTN_PRODUCTION_DONE__:$rc\n']))
    deadline = time.time() + 21600
    output = ''
    rc = None
    try:
        while time.time() < deadline:
            try:
                msg = ws.recv()
            except Exception as exc:
                print('websocket:', exc, flush=True)
                continue
            if not msg:
                continue
            try:
                data = json.loads(msg)
            except Exception:
                continue
            if isinstance(data, list) and len(data) >= 2 and data[0] == 'stdout':
                text = data[1]
                output += text
                sys.stdout.write(text)
                sys.stdout.flush()
                m = re.search(r'__CTN_PRODUCTION_DONE__:(\d+)', output)
                if m:
                    rc = int(m.group(1))
                    break
    finally:
        ws.close()
        try:
            SESSION.delete(BASE + f'/api/terminals/{term}', headers=headers, timeout=10)
        except Exception:
            pass
    if rc is None:
        raise RuntimeError('production batch timed out')
    if rc != 0:
        raise RuntimeError(f'production batch failed rc={rc}')


def main():
    data = json.loads(MANIFEST.read_text())
    print(f"production_date={data.get('production_date')} jobs={len(data.get('jobs') or [])}")
    headers = login()
    run_remote(headers)


if __name__ == '__main__':
    main()
