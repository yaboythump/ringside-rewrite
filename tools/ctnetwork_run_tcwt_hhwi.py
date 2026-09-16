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
MANIFEST=REPO/'ctnetwork-production-manifest.json'

def build_payload():
    bio=io.BytesIO()
    with tarfile.open(fileobj=bio,mode='w:gz') as tf:
        tf.add(REPO/'runpod'/'ctnetwork_factory_v2.py',arcname='controller/ctnetwork_factory_v2.py')
        tf.add(REPO/'runpod'/'ctnetwork_qwen_narrate.py',arcname='controller/ctnetwork_qwen_narrate.py')
        tf.add(MANIFEST,arcname='incoming/ctnetwork-production-manifest.json')
    return base64.b64encode(bio.getvalue()).decode()

def login():
    for attempt in range(1,121):
        try:
            SESSION.cookies.clear(); r=SESSION.get(BASE+'/login',timeout=15)
            m=re.search(r'name="_xsrf" value="([^"]+)"',r.text) if r.status_code==200 else None
            if not m: time.sleep(4); continue
            rr=SESSION.post(BASE+'/login',data={'_xsrf':m.group(1),'password':PASSWORD,'next':'/'},timeout=20,allow_redirects=False)
            if rr.status_code not in (200,302,303): time.sleep(4); continue
            cx=SESSION.cookies.get('_xsrf'); headers={'X-XSRFToken':cx} if cx else {}
            if SESSION.get(BASE+'/api/status',headers=headers,timeout=20).status_code==200:
                print('JUPYTER_AUTH_READY',flush=True); return headers
        except Exception: time.sleep(4)
    raise RuntimeError('Jupyter authentication unavailable')

def terminal(headers):
    for attempt in range(1,61):
        name=None
        try:
            r=SESSION.post(BASE+'/api/terminals',headers=headers,json={},timeout=30); r.raise_for_status(); name=r.json()['name']
            cookie='; '.join(f'{c.name}={c.value}' for c in SESSION.cookies)
            ws=websocket.create_connection(f'wss://{POD_ID}-8888.proxy.runpod.net/terminals/websocket/{name}',cookie=cookie,origin=BASE,timeout=60)
            return name,ws
        except Exception:
            if name:
                try: SESSION.delete(BASE+f'/api/terminals/{name}',headers=headers,timeout=10)
                except Exception: pass
            time.sleep(3)
    raise RuntimeError('Jupyter terminal unavailable')

def run_remote(headers):
    term,ws=terminal(headers); payload=build_payload()
    shell='''set -Eeuo pipefail
ROOT=/workspace/ctnetwork-local
mkdir -p "$ROOT/controller" "$ROOT/incoming" "$ROOT/incoming/jobs" "$ROOT/incoming/remote-assets" "$ROOT/ready_for_approval" "$ROOT/status"
echo __PAYLOAD__ | base64 -d >/tmp/tcwt-payload.tgz
tar --no-same-owner -xzf /tmp/tcwt-payload.tgz -C "$ROOT"
chmod +x "$ROOT/controller/ctnetwork_factory_v2.py" "$ROOT/controller/ctnetwork_qwen_narrate.py"
command -v ffmpeg >/dev/null
command -v ffprobe >/dev/null
test "$(cat "$ROOT/status/production_ready.status" 2>/dev/null || true)" = PASS
python3 - <<'PY'
import json,pathlib,subprocess,urllib.parse,urllib.request,shutil
root=pathlib.Path('/workspace/ctnetwork-local'); m=json.load(open(root/'incoming/ctnetwork-production-manifest.json'))
assert m.get('manual_gate_required') is True and m.get('publish_allowed') is False
jobs=m.get('jobs') or []; assert jobs
out=root/'incoming/jobs'; out.mkdir(parents=True,exist_ok=True)
assets=root/'incoming/remote-assets'; assets.mkdir(parents=True,exist_ok=True)

def suffix(url,fallback):
    s=pathlib.Path(urllib.parse.urlparse(url).path).suffix.lower(); return s if s and len(s)<=8 else fallback

def download(url,dest):
    req=urllib.request.Request(url,headers={'User-Agent':'CTNETWORK-Production/1.0'})
    with urllib.request.urlopen(req,timeout=240) as r, open(dest,'wb') as f:
        shutil.copyfileobj(r,f,4*1024*1024)
    if dest.stat().st_size<1024: raise RuntimeError(f'asset empty: {url}')
    print('ASSET_DOWNLOADED',dest,dest.stat().st_size,flush=True)

def duration(path):
    return max(1.0,float(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-of','default=nw=1:nk=1',str(path)],text=True).strip()))

def make_slideshow(images,narration,dest):
    total=duration(narration); each=max(2.0,total/max(1,len(images)))
    clips=[]; cdir=dest.parent/'clips'; cdir.mkdir(parents=True,exist_ok=True)
    for n,img in enumerate(images,1):
        clip=cdir/f'{n:03d}.mp4'
        zoom="min(zoom+0.0007,1.08)" if n%2 else "max(1.08-0.0007*on,1.0)"
        x="iw/2-(iw/zoom/2)"; y="ih/2-(ih/zoom/2)"
        vf=f"scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,zoompan=z='{zoom}':x='{x}':y='{y}':d=1:s=1920x1080:fps=30,format=yuv420p"
        subprocess.run(['ffmpeg','-y','-loop','1','-t',f'{each:.3f}','-i',str(img),'-vf',vf,'-an','-c:v','libx264','-preset','veryfast','-crf','19','-movflags','+faststart',str(clip)],check=True)
        clips.append(clip)
    concat=cdir/'concat.txt'; concat.write_text(''.join("file '"+str(c).replace("'","'\\''")+"'"+chr(10) for c in clips))
    subprocess.run(['ffmpeg','-y','-f','concat','-safe','0','-i',str(concat),'-c','copy',str(dest)],check=True)
    print('HHWI_STYLE_VISUAL_MASTER_READY',dest,flush=True)

for i,j in enumerate(jobs,1):
    assert j.get('publish') is not True
    jid=j['job_id']; a=assets/jid; a.mkdir(parents=True,exist_ok=True); inputs=j.setdefault('inputs',{})
    thumb_url=inputs.pop('thumbnail_url',None)
    if thumb_url:
        p=a/('thumbnail'+suffix(thumb_url,'.jpg')); download(thumb_url,p); inputs['thumbnail']=str(p)
    n=j.get('narration') or {}; engine=str(n.get('engine') or '').lower()
    if not inputs.get('narration'):
        assert engine in {'qwen','qwen3-tts','local_qwen'}
        assert (root/'status/qwen_smoke.status').read_text().strip()=='PASS'
        ref_url=n.get('voice_reference_url'); ref_text=n.get('voice_reference_text'); script=n.get('text') or j.get('script')
        assert ref_url and ref_text and script
        ref=a/('voice-reference'+suffix(ref_url,'.mp3')); download(ref_url,ref)
        script_file=a/'script.txt'; script_file.write_text(script+chr(10))
        ref_text_file=a/'voice-reference.txt'; ref_text_file.write_text(ref_text+chr(10))
        narration=a/'narration-onyx-reference.wav'
        qpy=root/'envs/qwen3-tts/bin/python'; helper=root/'controller/ctnetwork_qwen_narrate.py'
        cmd=[str(qpy),str(helper),'--text-file',str(script_file),'--ref-audio',str(ref),'--ref-text-file',str(ref_text_file),'--output',str(narration),'--language','English']
        subprocess.run(cmd,check=True); inputs['narration']=str(narration); print('ONYX_REFERENCE_NARRATION_READY',flush=True)
    urls=inputs.pop('visual_urls',None) or []
    assert urls, f'{jid}: storyboard visual_urls required'
    imgs=[]
    for k,url in enumerate(urls,1):
        p=a/f'image_{k:03d}'+suffix(url,'.png'); download(url,p); imgs.append(p)
    visual=a/'hhwi-style-storyboard-master.mp4'; make_slideshow(imgs,pathlib.Path(inputs['narration']),visual); inputs['visual']=str(visual)
    (out/f'{i:02d}-{jid}.json').write_text(json.dumps(j,indent=2)+chr(10))
PY
PY=python3; [ -x "$ROOT/envs/core/bin/python" ] && PY="$ROOT/envs/core/bin/python"
failed=0
for job in "$ROOT"/incoming/jobs/*.json; do
  if "$PY" "$ROOT/controller/ctnetwork_factory_v2.py" run-manifest "$job"; then echo PASS; else failed=1; fi
done
python3 - <<'PY'
import json,pathlib
root=pathlib.Path('/workspace/ctnetwork-local'); m=json.load(open(root/'incoming/ctnetwork-production-manifest.json'))
summary={'production_date':m.get('production_date'),'manual_gate_required':True,'publish_allowed':False,'jobs':[]}
for j in m['jobs']:
 p=root/'jobs'/j['job_id']/'state.json'; s=json.load(open(p)) if p.exists() else {'job_id':j['job_id'],'state':'UNKNOWN'}
 ap=root/'ready_for_approval'/j['job_id']/'approval.json'
 if ap.exists():
  a=json.load(open(ap)); assert a.get('publish_allowed') is False and a.get('approved') is False; s['approval_gate_verified']=True
 summary['jobs'].append(s)
path=root/'status'/'production_batch_latest.json'; path.write_text(json.dumps(summary,indent=2)+chr(10)); print(json.dumps(summary,indent=2))
PY
test "$failed" -eq 0
echo PASS > "$ROOT/status/production_batch.status"
echo CTNETWORK_TCWT_HHWI_READY_FOR_APPROVAL
'''
    shell=shell.replace('__PAYLOAD__',payload)
    marker=f'__TCWT_{int(time.time()*1000)}__'; enc=base64.b64encode(shell.encode()).decode()
    ws.send(json.dumps(['stdin',f'echo {enc} | base64 -d >/tmp/tcwt-run.sh; bash /tmp/tcwt-run.sh; rc=$?; echo {marker}:$rc\n']))
    deadline=time.time()+21600; output=''; rc=None
    try:
        while time.time()<deadline:
            try: msg=ws.recv()
            except Exception: continue
            try: data=json.loads(msg)
            except Exception: continue
            if isinstance(data,list) and len(data)>=2 and data[0]=='stdout':
                text=data[1]; output+=text; sys.stdout.write(text); sys.stdout.flush()
                mm=re.search(re.escape(marker)+r':(\d+)',output)
                if mm: rc=int(mm.group(1)); break
    finally:
        ws.close()
        try: SESSION.delete(BASE+f'/api/terminals/{term}',headers=headers,timeout=10)
        except Exception: pass
    if rc is None or rc!=0: raise RuntimeError(f'TCWT production failed rc={rc}')

def main(): run_remote(login())
if __name__=='__main__': main()
