#!/usr/bin/env python3
"""Certify CTNETWORK's supplied-assets lane on the real RunPod factory."""
from __future__ import annotations
import base64, json, os, re, sys, time
from pathlib import Path
import requests, websocket

POD_ID=os.environ['POD_ID']; PASSWORD=Path(os.environ['JUPYTER_PASSWORD_FILE']).read_text().strip()
BASE=f'https://{POD_ID}-8888.proxy.runpod.net'; S=requests.Session(); REPO=Path(__file__).resolve().parents[1]

def login():
    last='not-started'
    for attempt in range(1,121):
        try:
            # RunPod's HTTP proxy can briefly return 200 for /login before the
            # authenticated Jupyter routes are fully ready. Treat the complete
            # GET -> POST -> /api/status sequence as the readiness check.
            S.cookies.clear()
            r=S.get(BASE+'/login',timeout=15)
            last=f'GET {r.status_code}'
            if r.status_code != 200:
                if attempt % 10 == 0: print(f'jupyter login wait attempt={attempt} {last}',flush=True)
                time.sleep(4); continue
            m=re.search(r'name="_xsrf" value="([^"]+)"',r.text)
            if not m:
                last='GET 200 without xsrf'; time.sleep(4); continue
            rr=S.post(BASE+'/login',data={'_xsrf':m.group(1),'password':PASSWORD,'next':'/'},timeout=20,allow_redirects=False)
            last=f'POST {rr.status_code}'
            if rr.status_code not in (200,302,303):
                if attempt % 5 == 0 or rr.status_code != 404: print(f'jupyter auth wait attempt={attempt} {last}',flush=True)
                time.sleep(4); continue
            xs=S.cookies.get('_xsrf'); h={'X-XSRFToken':xs} if xs else {}
            sr=S.get(BASE+'/api/status',headers=h,timeout=20)
            last=f'STATUS {sr.status_code}'
            if sr.status_code != 200:
                if attempt % 5 == 0: print(f'jupyter api wait attempt={attempt} {last}',flush=True)
                time.sleep(4); continue
            print(f'JUPYTER_AUTH_READY attempt={attempt}',flush=True)
            return h
        except Exception as e:
            last=repr(e)
            if attempt % 10 == 0: print(f'jupyter auth wait attempt={attempt} {last}',flush=True)
            time.sleep(4)
    raise RuntimeError(f'Jupyter authentication unavailable after retries: {last}')

def terminal(h):
    last=None
    for attempt in range(1,61):
        name=None
        try:
            r=S.post(BASE+'/api/terminals',headers=h,json={},timeout=30); r.raise_for_status(); name=r.json()['name']
            cookie='; '.join(f'{c.name}={c.value}' for c in S.cookies)
            ws=websocket.create_connection(f'wss://{POD_ID}-8888.proxy.runpod.net/terminals/websocket/{name}',cookie=cookie,origin=BASE,timeout=30)
            print(f'TERMINAL_READY attempt={attempt}',flush=True); return name,ws
        except Exception as e:
            last=e
            if name:
                try:S.delete(BASE+f'/api/terminals/{name}',headers=h,timeout=10)
                except Exception:pass
            if attempt % 10 == 0: print(f'terminal wait attempt={attempt} {last!r}',flush=True)
            time.sleep(3)
    raise RuntimeError(f'terminal unavailable {last!r}')

def run(h,cmd,timeout=3600):
    name,ws=terminal(h); marker=f'__CTN_CERT_{int(time.time()*1000)}__'; out=''; rc=None
    ws.send(json.dumps(['stdin',f'set +e\n{cmd}\nrc=$?\necho {marker}:$rc\n']))
    deadline=time.time()+timeout
    try:
        while time.time()<deadline:
            try: msg=ws.recv()
            except Exception: continue
            try:d=json.loads(msg)
            except Exception:continue
            if isinstance(d,list) and len(d)>=2 and d[0]=='stdout':
                t=d[1]; out+=t; sys.stdout.write(t); sys.stdout.flush(); m=re.search(re.escape(marker)+r':(\d+)',out)
                if m: rc=int(m.group(1)); break
    finally:
        ws.close()
        try:S.delete(BASE+f'/api/terminals/{name}',headers=h,timeout=10)
        except Exception:pass
    if rc is None: raise RuntimeError('certification timeout')
    if rc: raise RuntimeError(f'certification failed rc={rc}\n{out[-12000:]}')
    return out

def main():
    h=login(); src=(REPO/'runpod/ctnetwork_factory_v2.py').read_bytes(); enc=base64.b64encode(src).decode()
    run(h,f"mkdir -p /workspace/ctnetwork-local/controller; echo {enc} | base64 -d > /workspace/ctnetwork-local/controller/ctnetwork_factory_v2.py; chmod +x /workspace/ctnetwork-local/controller/ctnetwork_factory_v2.py",180)
    cmd=r'''set -Eeuo pipefail
ROOT=/workspace/ctnetwork-local; CERT="$ROOT/certification/asset-pipeline"; JOB=ctn-asset-pipeline-cert
rm -rf "$CERT" "$ROOT/jobs/$JOB" "$ROOT/ready_for_approval/$JOB"; mkdir -p "$CERT" "$ROOT/status" "$ROOT/jobs" "$ROOT/ready_for_approval"
command -v ffmpeg >/dev/null; command -v ffprobe >/dev/null
PY=python3; [ -x "$ROOT/envs/core/bin/python" ] && PY="$ROOT/envs/core/bin/python"; "$PY" --version
ffmpeg -y -f lavfi -i 'testsrc2=size=1280x720:rate=30' -t 18 -pix_fmt yuv420p -c:v libx264 -preset fast -crf 20 "$CERT/visual.mp4" >/tmp/ctn-cert-video.log 2>&1
ffmpeg -y -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=18' -af 'volume=0.08' -c:a pcm_s16le "$CERT/narration.wav" >/tmp/ctn-cert-audio.log 2>&1
ffmpeg -y -ss 1 -i "$CERT/visual.mp4" -frames:v 1 -q:v 2 "$CERT/thumbnail.jpg" >/tmp/ctn-cert-thumb.log 2>&1
cat > "$CERT/manifest.json" <<JSON
{"job_id":"$JOB","show":"CTNETWORK Certification","title":"Supplied Asset Production Pipeline Certification","description":"Internal readiness proof.","inputs":{"narration":"$CERT/narration.wav","visual":"$CERT/visual.mp4","thumbnail":"$CERT/thumbnail.jpg"},"shorts":{"count":2,"seconds":8},"publish":false}
JSON
"$PY" "$ROOT/controller/ctnetwork_factory_v2.py" run-manifest "$CERT/manifest.json"
OUT="$ROOT/ready_for_approval/$JOB"
for f in master.mp4 short_01_9x16.mp4 short_02_9x16.mp4 thumbnail.jpg qc.json approval.json checksums.json; do test -s "$OUT/$f"; done
python3 - <<'PY'
import json,pathlib,subprocess
root=pathlib.Path('/workspace/ctnetwork-local'); out=root/'ready_for_approval/ctn-asset-pipeline-cert'
qc=json.load(open(out/'qc.json')); ap=json.load(open(out/'approval.json')); st=json.load(open(root/'jobs/ctn-asset-pipeline-cert/state.json'))
assert qc.get('pass') is True,qc; assert ap.get('requires_manual_approval') is True,ap; assert ap.get('approved') is False,ap; assert ap.get('publish_allowed') is False,ap; assert st.get('state')=='READY_FOR_APPROVAL',st
for name in ['master.mp4','short_01_9x16.mp4','short_02_9x16.mp4']:
 d=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(out/name)],text=True)); s=d.get('streams',[]); assert any(x.get('codec_type')=='video' for x in s),name; assert any(x.get('codec_type')=='audio' for x in s),name
report={'mode':'supplied_assets','status':'PASS','job_id':'ctn-asset-pipeline-cert','master':str(out/'master.mp4'),'shorts':2,'qc_pass':True,'manual_approval_verified':True,'publish_locked':True,'ltx_generation_required':False,'narrator_generation_required':False}
(root/'status/asset_pipeline.json').write_text(json.dumps(report,indent=2)+'\n'); (root/'status/asset_pipeline.status').write_text('PASS\n'); (root/'status/production_ready.status').write_text('PASS\n'); print(json.dumps(report,indent=2))
PY
sha256sum "$OUT/master.mp4" "$OUT/short_01_9x16.mp4" "$OUT/short_02_9x16.mp4"
echo CTNETWORK_ASSET_PIPELINE_CERTIFICATION_PASS'''
    out=run(h,cmd); Path('/tmp/ctnetwork-asset-pipeline-certification.txt').write_text(out)
if __name__=='__main__': main()
