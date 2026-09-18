#!/usr/bin/env python3
from __future__ import annotations
import base64, io, json, os, re, sys, tarfile, time
from pathlib import Path
import requests, websocket

POD_ID=os.environ['POD_ID']
PASSWORD=Path(os.environ['JUPYTER_PASSWORD_FILE']).read_text().strip()
BASE=f'https://{POD_ID}-8888.proxy.runpod.net'
SESSION=requests.Session()
REPO=Path(__file__).resolve().parents[1]
CMD=REPO/'ctnetwork-tcwt-narration-command.json'

def payload():
    bio=io.BytesIO()
    with tarfile.open(fileobj=bio, mode='w:gz') as tf:
        tf.add(CMD, arcname='incoming/ctnetwork-tcwt-narration-command.json')
        tf.add(REPO/'runpod'/'ctnetwork_qwen_narrate.py', arcname='controller/ctnetwork_qwen_narrate.py')
    return base64.b64encode(bio.getvalue()).decode()

def login():
    for _ in range(120):
        try:
            r=SESSION.get(BASE+'/login',timeout=15)
            m=re.search(r'name="_xsrf" value="([^"]+)"',r.text) if r.ok else None
            if not m:
                time.sleep(4); continue
            rr=SESSION.post(BASE+'/login',data={'_xsrf':m.group(1),'password':PASSWORD,'next':'/'},timeout=20,allow_redirects=False)
            if rr.status_code not in (200,302,303):
                time.sleep(4); continue
            xc=SESSION.cookies.get('_xsrf'); headers={'X-XSRFToken':xc} if xc else {}
            if SESSION.get(BASE+'/api/status',headers=headers,timeout=20).status_code==200:
                return headers
        except Exception:
            time.sleep(4)
    raise RuntimeError('Jupyter authentication unavailable')

def run_remote(headers):
    r=SESSION.post(BASE+'/api/terminals',headers=headers,json={},timeout=30); r.raise_for_status()
    term=r.json()['name']
    cookie='; '.join(f'{c.name}={c.value}' for c in SESSION.cookies)
    ws=websocket.create_connection(f'wss://{POD_ID}-8888.proxy.runpod.net/terminals/websocket/{term}',cookie=cookie,origin=BASE,timeout=60)

    shell=r'''set -Eeuo pipefail
ROOT=/workspace/ctnetwork-local
mkdir -p "$ROOT/controller" "$ROOT/incoming" "$ROOT/status"
echo __PAYLOAD__ | base64 -d >/tmp/tcwt-narration.tgz
tar --no-same-owner -xzf /tmp/tcwt-narration.tgz -C "$ROOT"
chmod +x "$ROOT/controller/ctnetwork_qwen_narrate.py"

python3 - <<'PY'
import json, pathlib, urllib.request, shutil, subprocess, os
root=pathlib.Path('/workspace/ctnetwork-local')
cmd=json.load(open(root/'incoming/ctnetwork-tcwt-narration-command.json'))
job=cmd['job_id']
outdir=root/'ready_for_approval'/job
audiodir=outdir/'audio'
audiodir.mkdir(parents=True,exist_ok=True)
ref=audiodir/'onyx-reference.mp3'
script_file=audiodir/'script.txt'
ref_text_file=audiodir/'voice-reference.txt'
out=audiodir/'narration.wav'

req=urllib.request.Request(cmd['voice_reference_url'],headers={'User-Agent':'CTNETWORK-Production/1.0'})
with urllib.request.urlopen(req,timeout=240) as r, open(ref,'wb') as f:
    shutil.copyfileobj(r,f,4*1024*1024)
script_file.write_text(cmd['script'].strip()+'\n',encoding='utf-8')
ref_text_file.write_text(cmd['voice_reference_text'].strip()+'\n',encoding='utf-8')

qpy=root/'envs/qwen3-tts/bin/python'
helper=root/'controller/ctnetwork_qwen_narrate.py'
if not qpy.exists():
    raise SystemExit('Qwen runtime missing')
subprocess.run([
    str(qpy),str(helper),
    '--text-file',str(script_file),
    '--ref-audio',str(ref),
    '--ref-text-file',str(ref_text_file),
    '--output',str(out),
    '--language','English'
],check=True)

dur=float(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-of','default=nw=1:nk=1',str(out)],text=True).strip())
streams=int(subprocess.check_output(['bash','-lc',f"ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 '{out}' | wc -l"],text=True).strip())
if streams < 1 or dur < 180:
    raise SystemExit(f'narration QC failed streams={streams} duration={dur}')
checkpoint={
    'job_id':job,
    'show':'True Crime With Thump',
    'title':cmd['title'],
    'stage':'NARRATION_COMPLETE',
    'narration':str(out),
    'duration_seconds':round(dur,2),
    'audio_streams':streams,
    'voice_reference':'TCWT locked Onyx-style reference',
    'publish_allowed':False
}
(outdir/'checkpoint.json').write_text(json.dumps(checkpoint,indent=2)+'\n')
prod=pathlib.Path('/workspace/ctnetwork-production/episodes')/job/'audio'
prod.mkdir(parents=True,exist_ok=True)
shutil.copy2(out,prod/'narration.wav')
shutil.copy2(outdir/'checkpoint.json',prod.parent/'checkpoint.json')
(root/'status/tcwt_narration_latest.status').write_text('PASS\n')
print(json.dumps(checkpoint,indent=2))
PY

echo TCWT_NARRATION_CHECKPOINT_READY
'''
    shell=shell.replace('__PAYLOAD__',payload())
    marker=f'__TCWT_NARR_{int(time.time()*1000)}__'
    enc=base64.b64encode(shell.encode()).decode()
    ws.send(json.dumps(['stdin',f'echo {enc} | base64 -d >/tmp/tcwt-narration.sh; bash /tmp/tcwt-narration.sh; rc=$?; echo {marker}:$rc\n']))
    deadline=time.time()+10800; output=''; rc=None
    try:
        while time.time()<deadline:
            try: msg=ws.recv()
            except Exception: continue
            try: data=json.loads(msg)
            except Exception: continue
            if isinstance(data,list) and len(data)>=2 and data[0]=='stdout':
                text=data[1]; output+=text; sys.stdout.write(text); sys.stdout.flush()
                mm=re.search(re.escape(marker)+r':(\d+)',output)
                if mm:
                    rc=int(mm.group(1)); break
    finally:
        ws.close()
        try: SESSION.delete(BASE+f'/api/terminals/{term}',headers=headers,timeout=10)
        except Exception: pass
    if rc != 0:
        raise RuntimeError(f'narration remote failed rc={rc}')

def download(headers):
    job=json.loads(CMD.read_text())['job_id']
    rel=f'ctnetwork-local/ready_for_approval/{job}/audio/narration.wav'
    for url in [BASE+'/files/'+rel, BASE+'/files/workspace/'+rel]:
        try:
            r=SESSION.get(url,headers=headers,timeout=300)
            if r.ok and len(r.content)>100000:
                Path('/tmp/tcwt-motel-narration.wav').write_bytes(r.content)
                print('DOWNLOADED_NARRATION',len(r.content))
                return
        except Exception as e:
            print('download failed',e)
    raise RuntimeError('could not download narration artifact')

def main():
    h=login()
    run_remote(h)
    download(h)

if __name__=='__main__':
    main()
