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
        shows = REPO / 'ctnetwork' / 'shows'
        if shows.exists():
            for p in sorted(shows.glob('*.yaml')):
                tf.add(p, arcname=f'recipes/{p.name}')
    return base64.b64encode(bio.getvalue()).decode()


def login() -> dict[str, str]:
    last = 'not-started'
    for attempt in range(1, 121):
        try:
            SESSION.cookies.clear()
            r = SESSION.get(BASE + '/login', timeout=15)
            last = f'GET {r.status_code}'
            if r.status_code != 200:
                time.sleep(4)
                continue
            m = re.search(r'name="_xsrf" value="([^"]+)"', r.text)
            if not m:
                last = 'GET 200 without xsrf'
                time.sleep(4)
                continue
            rr = SESSION.post(
                BASE + '/login',
                data={'_xsrf': m.group(1), 'password': PASSWORD, 'next': '/'},
                timeout=20,
                allow_redirects=False,
            )
            last = f'POST {rr.status_code}'
            if rr.status_code not in (200, 302, 303):
                time.sleep(4)
                continue
            cx = SESSION.cookies.get('_xsrf')
            headers = {'X-XSRFToken': cx} if cx else {}
            sr = SESSION.get(BASE + '/api/status', headers=headers, timeout=20)
            last = f'STATUS {sr.status_code}'
            if sr.status_code != 200:
                time.sleep(4)
                continue
            print(f'JUPYTER_AUTH_READY attempt={attempt}', flush=True)
            return headers
        except Exception as exc:
            last = repr(exc)
            time.sleep(4)
    raise RuntimeError(f'Jupyter authentication unavailable: {last}')


def terminal(headers: dict[str, str]):
    last = None
    for attempt in range(1, 61):
        name = None
        try:
            r = SESSION.post(BASE + '/api/terminals', headers=headers, json={}, timeout=30)
            r.raise_for_status()
            name = r.json()['name']
            cookie = '; '.join(f'{c.name}={c.value}' for c in SESSION.cookies)
            ws = websocket.create_connection(
                f'wss://{POD_ID}-8888.proxy.runpod.net/terminals/websocket/{name}',
                cookie=cookie,
                origin=BASE,
                timeout=60,
            )
            print(f'TERMINAL_READY attempt={attempt}', flush=True)
            return name, ws
        except Exception as exc:
            last = exc
            if name:
                try:
                    SESSION.delete(BASE + f'/api/terminals/{name}', headers=headers, timeout=10)
                except Exception:
                    pass
            time.sleep(3)
    raise RuntimeError(f'Jupyter terminal unavailable: {last!r}')


def run_remote(headers: dict[str, str]):
    term, ws = terminal(headers)
    cookie_payload = build_payload()
    shell = f'''set -Eeuo pipefail
ROOT=/workspace/ctnetwork-local
BATCH="$ROOT/batches/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$ROOT/controller" "$ROOT/recipes" "$ROOT/incoming" "$ROOT/batches" "$ROOT/ready_for_approval" "$ROOT/status"
echo {cookie_payload} | base64 -d >/tmp/ctnetwork-production-payload.tar.gz
tar --no-same-owner -xzf /tmp/ctnetwork-production-payload.tar.gz -C "$ROOT"
chmod +x "$ROOT/controller/ctnetwork_factory_v2.py" "$ROOT/controller/ctnetwork_qwen_narrate.py" "$ROOT/controller/ctnetwork_ltx_generate.py"
command -v ffmpeg >/dev/null || {{ echo FFMPEG_MISSING; exit 70; }}
command -v ffprobe >/dev/null || {{ echo FFPROBE_MISSING; exit 70; }}
test "$(cat "$ROOT/status/production_ready.status" 2>/dev/null || true)" = PASS || {{ echo FACTORY_NOT_CERTIFIED_FOR_PRODUCTION; exit 71; }}
PY=python3
[ -x "$ROOT/envs/core/bin/python" ] && PY="$ROOT/envs/core/bin/python"
"$PY" --version

MAN="$ROOT/incoming/ctnetwork-production-manifest.json"
rm -rf "$ROOT/incoming/jobs" "$ROOT/incoming/remote-assets"

set +e
python3 - <<'PY'
import json, pathlib, subprocess, urllib.parse, urllib.request
root=pathlib.Path('/workspace/ctnetwork-local')
m=json.load(open(root/'incoming/ctnetwork-production-manifest.json'))
assert m.get('manual_gate_required') is True, 'manual gate flag missing'
assert m.get('publish_allowed') is False, 'publish must default false'
jobs=m.get('jobs') or []
if not jobs:
    print('NO_JOBS_DUE')
    raise SystemExit(20)
out=root/'incoming/jobs'; out.mkdir(parents=True,exist_ok=True)
assets=root/'incoming/remote-assets'; assets.mkdir(parents=True,exist_ok=True)
needs_qwen=False; needs_ltx=False; needs_dfr=False

def suffix(url,fallback):
    s=pathlib.Path(urllib.parse.urlparse(url).path).suffix.lower()
    return s if s and len(s)<=8 else fallback

def download(url,dest):
    dest.parent.mkdir(parents=True,exist_ok=True)
    req=urllib.request.Request(url,headers={{'User-Agent':'CTNETWORK-Production/1.0'}})
    with urllib.request.urlopen(req,timeout=180) as r, open(dest,'wb') as f:
        while True:
            b=r.read(4*1024*1024)
            if not b: break
            f.write(b)
    if dest.stat().st_size<1024: raise RuntimeError(f'downloaded asset empty: {{url}}')
    print('ASSET_DOWNLOADED',dest,dest.stat().st_size,flush=True)

def duration(path):
    x=subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-of','default=nw=1:nk=1',str(path)],text=True).strip()
    return max(1.0,float(x))

def slideshow(images,narration,dest):
    total=duration(narration); each=max(1.5,total/max(1,len(images)))
    clips=[]; clipdir=dest.parent/'clips'; clipdir.mkdir(parents=True,exist_ok=True)
    for n,img in enumerate(images,1):
        clip=clipdir/f'{{n:03d}}.mp4'
        vf="scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,zoompan=z='min(zoom+0.0008,1.07)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=1:s=1920x1080:fps=30,format=yuv420p"
        subprocess.run(['ffmpeg','-y','-loop','1','-t',f'{{each:.3f}}','-i',str(img),'-vf',vf,'-an','-c:v','libx264','-preset','veryfast','-crf','19','-movflags','+faststart',str(clip)],check=True)
        clips.append(clip)
    concat=clipdir/'concat.txt'; concat.write_text(''.join("file '%s'\\n"%str(c).replace("'","'\\\\''") for c in clips))
    subprocess.run(['ffmpeg','-y','-f','concat','-safe','0','-i',str(concat),'-c','copy',str(dest)],check=True)
    print('SLIDESHOW_READY',dest,dest.stat().st_size,flush=True)

for i,j in enumerate(jobs,1):
    assert j.get('publish') is not True, 'publishing requested inside production gate'
    jid=j.get('job_id'); assert jid, f'job {{i}} missing job_id'
    a=assets/jid; a.mkdir(parents=True,exist_ok=True)
    inputs=j.setdefault('inputs',{{}})
    for kind,fallback in [('narration','.wav'),('visual','.mp4'),('thumbnail','.jpg')]:
        url=inputs.pop(kind+'_url',None)
        if url:
            dest=a/(kind+suffix(url,fallback)); download(url,dest); inputs[kind]=str(dest)
    urls=inputs.pop('visual_urls',None) or []
    if urls:
        imgs=[]
        for k,url in enumerate(urls,1):
            dest=a/f'image_{{k:03d}}'+suffix(url,'.jpg'); download(url,dest); imgs.append(dest)
        narration=inputs.get('narration'); assert narration, f'{{jid}}: visual_urls needs narration'
        visual=a/'visual-slideshow.mp4'; slideshow(imgs,pathlib.Path(narration),visual); inputs['visual']=str(visual)
    if not inputs.get('narration'):
        engine=str((j.get('narration') or {{}}).get('engine') or '').lower()
        if engine not in {{'qwen','qwen3-tts','local_qwen'}}: raise AssertionError(f'{{jid}}: approved narrator input required; no automatic substitution')
        needs_qwen=True
    if not inputs.get('visual'):
        v=j.get('visuals') or {{}}
        if not v.get('prompt'): raise AssertionError(f'{{jid}}: approved visual input or explicit visual prompt required')
        needs_ltx=True
        if str(v.get('quality','dfr')).lower()=='dfr': needs_dfr=True
    (out/f'{{i:02d}}-{{jid}}.json').write_text(json.dumps(j,indent=2)+'\n')
(root/'incoming/engine-requirements.env').write_text(f'NEEDS_QWEN={{int(needs_qwen)}}\nNEEDS_LTX={{int(needs_ltx)}}\nNEEDS_DFR={{int(needs_dfr)}}\n')
print('JOBS_DUE',len(jobs),'needs_qwen',needs_qwen,'needs_ltx',needs_ltx,'needs_dfr',needs_dfr,flush=True)
PY
split_rc=$?
set -e
if [ "$split_rc" -eq 20 ]; then echo NO_PRODUCTION_REQUIRED; echo PASS > "$ROOT/status/production_batch.status"; exit 0; fi
test "$split_rc" -eq 0 || exit "$split_rc"

source "$ROOT/incoming/engine-requirements.env"
if [ "$NEEDS_QWEN" = 1 ]; then test "$(cat "$ROOT/status/qwen_smoke.status" 2>/dev/null || true)" = PASS || {{ echo QWEN_REQUIRED_BUT_NOT_CERTIFIED; exit 73; }}; fi
if [ "$NEEDS_LTX" = 1 ]; then test "$(cat "$ROOT/status/ltx25_smoke.status" 2>/dev/null || true)" = PASS || {{ echo LTX_REQUIRED_BUT_NOT_CERTIFIED; exit 74; }}; fi
if [ "$NEEDS_DFR" = 1 ]; then test "$(cat "$ROOT/status/ltx25_dfr.status" 2>/dev/null || true)" = PASS || {{ echo LTX_DFR_REQUIRED_BUT_NOT_CERTIFIED; exit 75; }}; fi
echo "ENGINE_GATE_PASS qwen=$NEEDS_QWEN ltx=$NEEDS_LTX dfr=$NEEDS_DFR"

mkdir -p "$BATCH"; failed=0
for job in "$ROOT"/incoming/jobs/*.json; do
  echo "=== CTNETWORK JOB $(basename "$job") ==="
  if "$PY" "$ROOT/controller/ctnetwork_factory_v2.py" run-manifest "$job"; then echo "PASS $(basename "$job")" >> "$BATCH/results.txt"; else echo "FAIL $(basename "$job")" >> "$BATCH/results.txt"; failed=1; fi
done

python3 - <<'PY'
import json,pathlib
root=pathlib.Path('/workspace/ctnetwork-local'); manifest=json.load(open(root/'incoming/ctnetwork-production-manifest.json'))
summary={{'production_date':manifest.get('production_date'),'manual_gate_required':True,'publish_allowed':False,'jobs':[]}}
for j in manifest.get('jobs',[]):
    jid=j['job_id']; sp=root/'jobs'/jid/'state.json'; state=json.load(open(sp)) if sp.exists() else {{'job_id':jid,'state':'UNKNOWN'}}
    ap=root/'ready_for_approval'/jid/'approval.json'
    if ap.exists():
        a=json.load(open(ap)); assert a.get('publish_allowed') is False; assert a.get('approved') is False; state['approval_gate_verified']=True
        qp=root/'ready_for_approval'/jid/'qc.json'
        if qp.exists(): state['qc']=json.load(open(qp))
    summary['jobs'].append(state)
path=root/'status'/'production_batch_latest.json'; path.write_text(json.dumps(summary,indent=2)+'\n'); print(json.dumps(summary,indent=2))
PY

test "$failed" -eq 0 || {{ echo BATCH_HAS_BLOCKED_JOBS; exit 72; }}
echo PASS > "$ROOT/status/production_batch.status"
echo CTNETWORK_PRODUCTION_BATCH_READY_FOR_APPROVAL
'''
    marker = f'__CTN_PRODUCTION_{int(time.time()*1000)}__'
    enc = base64.b64encode(shell.encode()).decode()
    ws.send(json.dumps(['stdin', f'echo {enc} | base64 -d >/tmp/ctnetwork-run-production.sh; bash /tmp/ctnetwork-run-production.sh; rc=$?; echo {marker}:$rc\n']))
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
            try:
                data = json.loads(msg)
            except Exception:
                continue
            if isinstance(data, list) and len(data) >= 2 and data[0] == 'stdout':
                text = data[1]; output += text; sys.stdout.write(text); sys.stdout.flush()
                m = re.search(re.escape(marker) + r':(\d+)', output)
                if m:
                    rc = int(m.group(1)); break
    finally:
        ws.close()
        try: SESSION.delete(BASE + f'/api/terminals/{term}', headers=headers, timeout=10)
        except Exception: pass
    if rc is None: raise RuntimeError('production batch timed out')
    if rc != 0: raise RuntimeError(f'production batch failed rc={rc}')


def main():
    data = json.loads(MANIFEST.read_text())
    print(f"production_date={data.get('production_date')} jobs={len(data.get('jobs') or [])}")
    run_remote(login())


if __name__ == '__main__':
    main()
