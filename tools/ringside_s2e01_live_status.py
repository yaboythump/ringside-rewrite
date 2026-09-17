#!/usr/bin/env python3
import os,re,time,requests,json
KEY=os.environ['RUNPOD_API_KEY']; AUTH={'Authorization':f'Bearer {KEY}'}
PID='ugt1pe6ndmichc'
r=requests.get(f'https://rest.runpod.io/v1/pods/{PID}',headers=AUTH,timeout=30); r.raise_for_status(); pod=r.json()
pw=(pod.get('env') or {}).get('JUPYTER_PASSWORD'); print('POD_STATUS',pod.get('desiredStatus'),'HAS_PASSWORD',bool(pw),flush=True)
if not pw: raise SystemExit('no Jupyter password')
base=f'https://{PID}-8888.proxy.runpod.net'
s=requests.Session()
for i in range(1,10):
    try:
        rr=s.get(base+'/login',timeout=20)
        if rr.status_code!=200: raise RuntimeError(rr.status_code)
        m=re.search(r'name="_xsrf" value="([^"]+)"',rr.text)
        if not m: raise RuntimeError('no xsrf')
        p=s.post(base+'/login',data={'_xsrf':m.group(1),'password':pw,'next':'/'},timeout=20,allow_redirects=False)
        if p.status_code not in (200,302,303): raise RuntimeError(p.status_code)
        break
    except Exception as e:
        print('LOGIN_RETRY',i,repr(e),flush=True); time.sleep(3)
else: raise SystemExit('login failed')
h={}; x=s.cookies.get('_xsrf');
if x: h['X-XSRFToken']=x
paths=['ctnetwork-local/ringside-s2e01-attitude-era/audio','ctnetwork-local/ringside-s2e01-attitude-era/motion','ctnetwork-local/ringside-s2e01-attitude-era']
for path in paths:
    q=s.get(base+'/api/contents/'+path,headers=h,params={'content':1},timeout=30)
    print('PATH',path,'HTTP',q.status_code,flush=True)
    if q.ok:
        j=q.json(); items=j.get('content') if isinstance(j,dict) else None
        if isinstance(items,list):
            for item in items: print('ITEM',item.get('name'),item.get('size'),item.get('type'),flush=True)
