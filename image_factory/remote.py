#!/usr/bin/env python3
"""Bounded RunPod deployment; credentials never leave Actions or enter logs."""
import base64,json,os,re,shlex,sys,time,uuid
from pathlib import Path
import requests,websocket
AUTH={'Authorization':'Bearer '+os.environ['RUNPOD_API_KEY']}
VOLUME='9wjb3sa5zm';ROOT='/workspace/ctnetwork-local/image-factory'
def api(method,path,**kw):
 r=requests.request(method,'https://rest.runpod.io/v1/'+path,headers=AUTH,timeout=45,**kw);r.raise_for_status();return r.json() if r.content else {}
def stop(p):
 api('POST',f'pods/{p}/stop')
 for _ in range(40):
  state=api('GET','pods/'+p)['desiredStatus']
  if state in ('EXITED','STOPPED'):print('IMAGE_GPU_STOP_CONFIRMED',p,state,flush=True);return
  time.sleep(3)
 raise RuntimeError('GPU shutdown could not be confirmed')
def select():
 pods=api('GET','pods'); candidates=['v92zliqqi85bwj','2tousj99hfcsm9','ugt1pe6ndmichc']
 for pid in candidates:
  p=next((p for p in pods if p['id']==pid),None)
  if not p or p.get('networkVolumeId')!=VOLUME or p.get('desiredStatus') not in ('EXITED','STOPPED'):continue
  if float(p.get('costPerHr') or 999)>.75:continue
  Path('image-factory-owned-pod.txt').write_text(pid)
  try:
   api('POST','pods/'+pid+'/start')
   print('IMAGE_POD_START',pid,p['name'],p.get('costPerHr'),flush=True)
   for _ in range(48):
    p=api('GET','pods/'+pid)
    if p['desiredStatus']=='RUNNING':return p
    time.sleep(5)
  except requests.HTTPError as e:print('EXISTING_POD_UNAVAILABLE',pid,e.response.status_code,flush=True)
  stop(pid);Path('image-factory-owned-pod.txt').unlink()
 raise RuntimeError('No existing stopped factory pod could resume within cost limit; no new pod created')
def main():
 pod=select();pid=pod['id'];password=pod['env']['JUPYTER_PASSWORD'];print('::add-mask::'+password,flush=True)
 base=f'https://{pid}-8888.proxy.runpod.net';s=requests.Session()
 for _ in range(60):
  try:
   r=s.get(base+'/login',timeout=10)
   if r.ok:break
  except requests.RequestException:pass
  time.sleep(3)
 else:raise RuntimeError('Jupyter unavailable on resumed pod')
 token=re.search(r'name="_xsrf" value="([^"]+)"',r.text).group(1)
 s.post(base+'/login',data={'_xsrf':token,'password':password,'next':'/'},timeout=30).raise_for_status()
 h={'X-XSRFToken':s.cookies.get('_xsrf')}
 def remote(code,timeout=180):
  r=s.post(base+'/api/terminals',headers=h,json={},timeout=30);r.raise_for_status();name=r.json()['name']
  ws=websocket.create_connection(f'wss://{pid}-8888.proxy.runpod.net/terminals/websocket/{name}',origin=base,cookie='; '.join(f'{c.name}={c.value}' for c in s.cookies),timeout=20)
  marker='CTN_DONE_'+uuid.uuid4().hex;out='';rc=None
  try:
   ws.send(json.dumps(['stdin','stty -echo\n']));time.sleep(1)
   wrapped='import subprocess,base64;rc=subprocess.call(["bash","-c",base64.b64decode('+repr(base64.b64encode(code.encode()).decode())+').decode()]);print('+repr(marker)+',rc,flush=True)'
   ws.send(json.dumps(['stdin','python3 -u -c '+shlex.quote(wrapped)+'\n']))
   until=time.time()+timeout
   while time.time()<until:
    try:d=json.loads(ws.recv())
    except websocket.WebSocketTimeoutException:continue
    if isinstance(d,list) and d[0]=='stdout':
     out+=d[1];print(d[1],end='',flush=True)
     m=re.search(re.escape(marker)+r' (\d+)',out)
     if m:rc=int(m.group(1));break
  finally:
   ws.close()
   try:s.delete(base+'/api/terminals/'+name,headers=h,timeout=10)
   except Exception:pass
  if rc!=0:raise RuntimeError('Remote execution failed or timed out; code='+str(rc))
  return out
 # Fingerprint CPU/GPU and production queues again on the selected existing machine.
 remote('nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader\npython3 -c "import torch;print(torch.__version__,torch.cuda.is_available())"\nls -ld /workspace/ComfyUI /workspace/ctnetwork-local\ndu -sx --block-size=1G /workspace/ctnetwork-local /workspace/ComfyUI',timeout=240)
 for file in ['install.py','studio.py']:
  blob=base64.b64encode((Path('image_factory')/file).read_bytes()).decode()
  # Versioned code directory, keep older successful versions available.
  dest=ROOT+'/releases/'+os.environ.get('GITHUB_SHA','manual')[:12]
  remote('mkdir -p '+shlex.quote(dest)+'\nprintf %s '+shlex.quote(blob)+' | base64 -d > '+shlex.quote(dest+'/'+file))
 code=f'''set -Eeuo pipefail
ROOT={ROOT}
RELEASE={dest}
python3 -u "$RELEASE/install.py"
PY="$ROOT/venv/bin/python"
# An independent service and separate input/output directories leave production intact.
"$PY" /workspace/ComfyUI/main.py --listen 127.0.0.1 --port 8191 --lowvram --disable-all-custom-nodes --extra-model-paths-config "$ROOT/model_paths.yaml" --input-directory "$ROOT/input" --output-directory "$ROOT/output/comfy" --user-directory "$ROOT/user" > "$ROOT/logs/comfy-image-factory.log" 2>&1 &
COMFY_PID=$!
trap 'kill "$COMFY_PID" 2>/dev/null || true' EXIT
for i in $(seq 1 120); do
 if curl --max-time 3 -fsS http://127.0.0.1:8191/system_stats > "$ROOT/status/system_stats.json"; then break; fi
 if ! kill -0 "$COMFY_PID" 2>/dev/null; then tail -70 "$ROOT/logs/comfy-image-factory.log"; exit 4; fi
 sleep 2
done
curl --max-time 5 -fsS http://127.0.0.1:8191/system_stats
"$PY" -u "$RELEASE/studio.py" certify
printf '%s' "$RELEASE" > "$ROOT/status/active_release.txt"
cd "$ROOT"
"$PY" - <<'PACK'
import json,zipfile,pathlib
root=pathlib.Path('/workspace/ctnetwork-local/image-factory')
r=json.loads((root/'status/latest.json').read_text())
with zipfile.ZipFile(root/'samples.zip','w',zipfile.ZIP_DEFLATED) as z:
 for p in pathlib.Path(r['output_folder']).rglob('*'):
  if p.is_file():z.write(p,p.relative_to(pathlib.Path(r['output_folder'])))
 z.write(root/'status/models.json','models.json')
PACK
'''
 remote(code,timeout=5400)
 for file in ['samples.zip','status/latest.json','status/models.json']:
  success=False
  for prefix in ['/files/workspace/ctnetwork-local/image-factory/','/files/ctnetwork-local/image-factory/']:
   r=s.get(base+prefix+file,headers=h,timeout=180)
   if r.ok:
    path=Path('image-factory-results')/Path(file).name;path.parent.mkdir(exist_ok=True);path.write_bytes(r.content);success=True;break
  if not success:raise RuntimeError('Unable to retrieve '+file)
 print('IMAGE_FACTORY_SAMPLES_RETRIEVED',flush=True)
if __name__=='__main__':
 if len(sys.argv)>1 and sys.argv[1]=='stop':
  p=Path('image-factory-owned-pod.txt')
  if p.exists():
   pid=p.read_text().strip();pod=api('GET','pods/'+pid)
   assert pod.get('networkVolumeId')==VOLUME and pod['name'].startswith('ctnetwork')
   stop(pid)
 else:main()
