from __future__ import annotations
import json, mimetypes, os, re, sys, time
from pathlib import Path
from typing import Any
import requests

API_BASE='https://api.upload-post.com/api'
UPLOAD_URL=f'{API_BASE}/upload'
STATUS_URL=f'{API_BASE}/uploadposts/status'


def headers(key=None):
    key=key or os.environ.get('UPLOAD_POST_API_KEY','').strip()
    if not key: raise RuntimeError('UPLOAD_POST_API_KEY missing')
    return {'Authorization':f'Apikey {key}'}


def extract_yt(payload:dict[str,Any]):
    r=payload.get('results')
    if isinstance(r,dict) and isinstance(r.get('youtube'),dict): return r['youtube']
    if isinstance(r,list):
        for x in r:
            if isinstance(x,dict) and x.get('platform')=='youtube': return x
    if payload.get('platform')=='youtube': return payload
    return None


def video_id(result):
    if not result:return None
    for k in ('video_id','publish_id','post_id','id'):
        v=result.get(k)
        if isinstance(v,str) and v.strip(): return v.strip()
    u=result.get('url')
    if isinstance(u,str):
        for pat in (r'[?&]v=([\w-]{6,})',r'youtu\.be/([\w-]{6,})',r'youtube\.com/shorts/([\w-]{6,})'):
            m=re.search(pat,u)
            if m:return m.group(1)
    return None


def poll(req_id, timeout=1800):
    end=time.time()+timeout; last={}
    while time.time()<end:
        r=requests.get(STATUS_URL,headers=headers(),params={'request_id':req_id},timeout=60); r.raise_for_status(); last=r.json()
        st=str(last.get('status','')).lower(); yt=extract_yt(last); yst=str((yt or {}).get('status','')).lower()
        if st in ('success','completed','done') or (yt or {}).get('success') is True or yst in ('success','completed','done'): return last
        if st in ('failed','error') or yst in ('failed','error'): raise RuntimeError(json.dumps(last))
        time.sleep(10)
    raise TimeoutError(json.dumps(last))


def upload(path:Path, *, user:str, platforms:list[str], title:str, description:str, scheduled=None, thumb:Path|None=None, fb_page=None, fb_reel=False, idem=''):
    if not path.exists() or path.stat().st_size<1024: raise RuntimeError(f'Missing media {path}')
    hs=headers();
    if idem: hs['Idempotency-Key']=idem
    handles=[]; files={}
    try:
        vh=path.open('rb'); handles.append(vh); files['video']=(path.name,vh,'video/mp4')
        if thumb:
            th=thumb.open('rb'); handles.append(th); files['thumbnail']=(thumb.name,th,mimetypes.guess_type(thumb.name)[0] or 'image/jpeg')
        data=[('user',user),('title',title),('description',description),('async_upload','true')]
        for p in platforms:data.append(('platform[]',p))
        if 'youtube' in platforms:
            data += [('privacyStatus','public'),('selfDeclaredMadeForKids','false')]
        if 'facebook' in platforms and fb_page:
            data += [('facebook_page_id',fb_page),('facebook_media_type','REELS' if fb_reel else 'VIDEO')]
        if scheduled:data.append(('scheduled_date',scheduled))
        r=requests.post(UPLOAD_URL,headers=hs,data=data,files=files,timeout=900)
        try: payload=r.json()
        except Exception: payload={'raw':r.text}
        if r.status_code>=400 or payload.get('success') is False: raise RuntimeError(f'Upload failed {r.status_code}: {json.dumps(payload)}')
        if payload.get('job_id'): return {'mode':'scheduled','job_id':payload['job_id'],'raw':payload}
        req=payload.get('request_id')
        if req and not scheduled:
            final=poll(str(req)); yt=extract_yt(final) or extract_yt(payload)
            return {'mode':'published','request_id':req,'video_id':video_id(yt),'url':(yt or {}).get('url'),'raw':final}
        return {'mode':'queued','request_id':req,'raw':payload}
    finally:
        for h in handles:
            try:h.close()
            except:pass


def main():
    job_path=Path(sys.argv[1] if len(sys.argv)>1 else 'hiphop_whatif/current/job.json')
    job=json.loads(job_path.read_text(encoding='utf-8')); root=job_path.parent; out=root/'output'; profile=job.get('profile','HipHopWhatIf'); fb=job.get('facebook_page_id')
    full=job['full']; desc=full['description']
    print('Publishing full YouTube episode...')
    yt=upload(out/'full.mp4',user=profile,platforms=['youtube'],title=full['title'],description=desc,thumb=out/'thumbnail.jpg',idem=f"hhwi-{job['slug']}-full-youtube")
    print('Publishing full Facebook video...')
    fbfull=upload(out/'full.mp4',user=profile,platforms=['facebook'],title=full['title'],description=desc,fb_page=fb,fb_reel=False,idem=f"hhwi-{job['slug']}-full-facebook")
    receipts={'profile':profile,'slug':job['slug'],'full':{'youtube':yt,'facebook':fbfull},'shorts':[]}
    for i,s in enumerate(job['shorts'],1):
        path=out/f'short_{i:02d}.mp4'; sched=s['scheduled_date']
        y=upload(path,user=profile,platforms=['youtube'],title=s['title'],description=s['description'],scheduled=sched,idem=f"hhwi-{job['slug']}-short-{i}-yt")
        f=upload(path,user=profile,platforms=['facebook'],title=s['title'],description=s['description'],scheduled=sched,fb_page=fb,fb_reel=True,idem=f"hhwi-{job['slug']}-short-{i}-fb")
        receipts['shorts'].append({'youtube':y,'facebook':f,'scheduled_date':sched})
    (out/'publish-receipt.json').write_text(json.dumps(receipts,indent=2),encoding='utf-8')
    print(json.dumps(receipts,indent=2))
    if not yt.get('video_id'): raise RuntimeError('YouTube video_id unresolved; thumbnail gate cannot continue')

if __name__=='__main__':main()
