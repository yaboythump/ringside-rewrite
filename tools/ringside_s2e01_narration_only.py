#!/usr/bin/env python3
import base64, json, os, re, secrets, sys, time
from pathlib import Path
import requests, websocket
import ringside_s2e01_server_assets as src

KEY=os.environ['RUNPOD_API_KEY']; AUTH={'Authorization':f'Bearer {KEY}'}
VOL=src.VOLUME; DC=src.DC; REPO=os.environ.get('GITHUB_REPOSITORY','yaboythump/ringside-rewrite')
OUT=Path('narration-only'); OUT.mkdir(exist_ok=True)
REF_URL='https://raw.githubusercontent.com/yaboythump/ringside-rewrite/main/server_refs/kevin_ref_short.b64'
BATCH_URL='https://raw.githubusercontent.com/yaboythump/ringside-rewrite/main/runpod/ctnetwork_qwen_narrate_batch.py'
REF_TEXT='One bell changed professional wrestling'

def create_pod():
    p={"name":f"rr-s2e01-narr-{int(time.time())}","imageName":"runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404","cloudType":"SECURE","computeType":"GPU","gpuTypeIds":["NVIDIA RTX PRO 4500 Blackwell","NVIDIA GeForce RTX 5090","NVIDIA RTX PRO 6000 Blackwell Server Edition","NVIDIA A100 80GB PCIe"],"gpuTypePriority":"availability","gpuCount":1,"dataCenterIds":[DC],"dataCenterPriority":"availability","containerDiskInGb":40,"networkVolumeId":VOL,"volumeMountPath":"/workspace","ports":["8888/http","22/tcp"],"env":{"JUPYTER_PASSWORD":secrets.token_hex(24)}}
    last=None
    for i in range(1,7):
        try:
            r=requests.post('https://rest.runpod.io/v1/pods',headers={**AUTH,'Content-Type':'application/json'},json=p,timeout=60); r.raise_for_status(); j=r.json(); return j['id'],p['env']['JUPYTER_PASSWORD']
        except Exception as e: last=e; print('CREATE_RETRY',i,repr(e),flush=True); time.sleep(min(20,i*4))
    raise last

def wait_run(pid):
    for i in range(120):
        r=requests.get(f'https://rest.runpod.io/v1/pods/{pid}',headers=AUTH,timeout=30); r.raise_for_status()
        if r.json().get('desiredStatus')=='RUNNING': return
        time.sleep(5)
    raise RuntimeError('pod not running')

def login(base,password):
    for i in range(1,21):
        try:
            s=requests.Session(); r=s.get(base+'/login',timeout=30)
            if r.status_code!=200: raise RuntimeError(r.status_code)
            m=re.search(r'name="_xsrf" value="([^"]+)"',r.text)
            if not m: raise RuntimeError('no xsrf')
            rr=s.post(base+'/login',data={'_xsrf':m.group(1),'password':password,'next':'/'},timeout=30,allow_redirects=False)
            if rr.status_code not in (200,302,303): raise RuntimeError(rr.status_code)
            x=s.cookies.get('_xsrf'); return s,({'X-XSRFToken':x} if x else {})
        except Exception as e: print('LOGIN_RETRY',i,repr(e),flush=True); time.sleep(min(12,i*2))
    raise RuntimeError('login failed')

def term(base,pid,s,h,shell):
    for attempt in range(1,9):
        try:
            r=s.post(base+'/api/terminals',headers=h,json={},timeout=30); r.raise_for_status(); name=r.json()['name']
            ck='; '.join(f'{c.name}={c.value}' for c in s.cookies)
            ws=websocket.create_connection(f'wss://{pid}-8888.proxy.runpod.net/terminals/websocket/{name}',cookie=ck,origin=base,timeout=90)
            marker='__DONE__'+str(int(time.time()*1000)); enc=base64.b64encode(shell.encode()).decode(); ws.send(json.dumps(['stdin',f'echo {enc} | base64 -d >/tmp/run.sh; bash /tmp/run.sh; rc=$?; echo {marker}:$rc\n']))
            buf=''; deadline=time.time()+7200
            while time.time()<deadline:
                msg=ws.recv(); data=json.loads(msg)
                if isinstance(data,list) and len(data)>1 and data[0]=='stdout':
                    t=data[1]; sys.stdout.write(t); sys.stdout.flush(); buf+=t
                    mm=re.search(re.escape(marker)+r':(\d+)',buf)
                    if mm:
                        ws.close(); rc=int(mm.group(1))
                        if rc: raise RuntimeError(f'remote rc {rc}')
                        return
            raise RuntimeError('remote timeout')
        except Exception as e:
            print('TERM_RETRY',attempt,repr(e),flush=True); time.sleep(min(15,attempt*3))
    raise RuntimeError('terminal failed')

def main():
    pid,pw=create_pod()
    try:
        wait_run(pid); base=f'https://{pid}-8888.proxy.runpod.net'
        for i in range(120):
            try:
                if requests.get(base+'/login',timeout=15).status_code==200: break
            except: pass
            time.sleep(5)
        s,h=login(base,pw)
        sec=base64.b64encode(json.dumps(src.SECTIONS).encode()).decode(); ref=base64.b64encode(REF_TEXT.encode()).decode()
        shell=f'''set -Eeuo pipefail
if ! command -v ffmpeg >/dev/null; then export DEBIAN_FRONTEND=noninteractive; apt-get update -y; apt-get install -y --no-install-recommends ffmpeg curl ca-certificates; fi
ROOT=/workspace/ctnetwork-local; JOB=$ROOT/ringside-s2e01-narration-only; rm -rf "$JOB"; mkdir -p "$JOB"/{{text,audio,raw}}
QPY="$ROOT/envs/qwen3-tts/bin/python"; QBATCH="$ROOT/controller/ctnetwork_qwen_narrate_batch.py"; test -x "$QPY"
curl -L --fail --retry 5 "{BATCH_URL}" -o "$QBATCH"; chmod +x "$QBATCH"; test -s "$QBATCH"
curl -L --fail --retry 5 "{REF_URL}" | tr -d '\\r\\n ' | base64 -d > "$JOB/raw/kevin.mp3"; ffprobe -v error "$JOB/raw/kevin.mp3"
ffmpeg -y -loglevel error -i "$JOB/raw/kevin.mp3" -t 3.4 -ar 24000 -ac 1 "$JOB/raw/kevin_ref.wav"
echo {ref} | base64 -d > "$JOB/text/ref.txt"; echo {sec} | base64 -d > "$JOB/text/sections.json"
"$QPY" "$QBATCH" --sections-json "$JOB/text/sections.json" --ref-audio "$JOB/raw/kevin_ref.wav" --ref-text-file "$JOB/text/ref.txt" --output-dir "$JOB/audio" --language English
: > "$JOB/audio/concat.txt"; for I in 01 02 03 04 05; do test -s "$JOB/audio/section_${{I}}.wav"; echo "file '$JOB/audio/section_${{I}}.wav'" >> "$JOB/audio/concat.txt"; done
ffmpeg -y -loglevel error -f concat -safe 0 -i "$JOB/audio/concat.txt" -ar 48000 -ac 1 -c:a pcm_s16le "$JOB/narration.wav"
ffprobe -v error -show_entries format=duration,size -of json "$JOB/narration.wav" > "$JOB/qc.json"
cd "$ROOT"; tar -czf ringside-s2e01-narration-only.tar.gz ringside-s2e01-narration-only/narration.wav ringside-s2e01-narration-only/qc.json
echo NARRATION_ONLY_READY
'''
        term(base,pid,s,h,shell)
        r=s.get(base+'/files/ctnetwork-local/ringside-s2e01-narration-only.tar.gz',headers=h,timeout=600); r.raise_for_status(); (OUT/'ringside-s2e01-narration-only.tar.gz').write_bytes(r.content)
    finally:
        try: requests.post(f'https://rest.runpod.io/v1/pods/{pid}/stop',headers=AUTH,timeout=30)
        except: pass
main()
