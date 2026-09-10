"""Explicit release only: revalidate media, preserve cadence, persist each receipt."""
from __future__ import annotations
import argparse
import json
import os
import re
import sys
import time
from contextlib import ExitStack
from datetime import datetime, timedelta, timezone
from pathlib import Path
import requests
from qc import package

ROOT=Path(__file__).resolve().parent
API='https://api.upload-post.com/api'
PROFILE='HipHopWhatIf'
PAGE='1305726102625399'

def release_time(value):
    when=datetime.fromisoformat(value.replace('Z','+00:00'))
    if when.tzinfo is None or when < datetime.now(timezone.utc)+timedelta(hours=2):
        raise ValueError('Release time must include timezone and be at least two hours ahead')
    return when

def result_for(payload,platform):
    results=payload.get('results',{})
    if isinstance(results,list):
        return next((r for r in results if r.get('platform')==platform),{})
    return results.get(platform,{}) if isinstance(results,dict) else {}

def confirmed(result):
    return (not result.get('skipped') and result.get('status') not in
            {'failed','skipped','retryable','queued','processing'} and
            (result.get('success') is True or result.get('status')=='completed'))

def response_json(response):
    response.raise_for_status()
    payload=response.json()
    if payload.get('success') is False:
        raise RuntimeError(f'Upload service rejected request: {payload}')
    return payload

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--release-at',required=True,type=release_time)
    parser.add_argument('--execute',action='store_true')
    args=parser.parse_args()
    if not args.execute:
        raise RuntimeError('Explicit --execute is required; nothing uploaded')
    job=json.loads((ROOT/'job.json').read_text())
    assert job['profile']==PROFILE and job['facebook_page_id']==PAGE
    assert len(job['short_titles'])==5
    out=ROOT/'output'
    package(out)
    description=job['full']['description']+'\n\n'+(out/'visual-credits.md').read_text()
    assert len(description)<=5000, 'YouTube description too long'
    key=os.environ.get('UPLOAD_POST_API_KEY','').strip()
    if not key: raise RuntimeError('UPLOAD_POST_API_KEY missing')
    headers={'Authorization':f'Apikey {key}'}
    response_json(requests.get(API+'/uploadposts/me',headers=headers,timeout=60))
    receipt_path=out/'publish-receipt.json'
    receipts=json.loads(receipt_path.read_text()) if receipt_path.exists() else {}
    def save(): receipt_path.write_text(json.dumps(receipts,indent=2)+'\n')
    for index in range(6):
        name='full.mp4' if index==0 else f'short_{index:02d}.mp4'
        title=job['full']['title'] if index==0 else job['short_titles'][index-1]
        scheduled=(args.release_at+timedelta(hours=index)).isoformat()
        for platform in ('youtube','facebook'):
            identity=f'{job["slug"]}-{name}-{platform}'
            data={'user':PROFILE,'platform[]':platform,'title':title,'description':description,
                  'async_upload':'true','external_id':identity}
            if platform=='youtube':
                data.update(privacyStatus='private',youtube_publish_at=scheduled,
                            selfDeclaredMadeForKids='false')
            else:
                data.update(scheduled_date=scheduled,facebook_page_id=PAGE,
                            facebook_media_type='VIDEO' if index==0 else 'REELS',
                            facebook_title=title,facebook_description=description)
            # Stable across runner retries and rerenders: never silently duplicate an episode.
            upload_headers={**headers,'Idempotency-Key':identity}
            entry=receipts.setdefault(identity,{})
            if 'accepted' not in entry:
                with ExitStack() as stack:
                    files={'video':(name,stack.enter_context((out/name).open('rb')),'video/mp4')}
                    if index==0 and platform=='youtube':
                        files['thumbnail']=('thumbnail.jpg',stack.enter_context((out/'thumbnail.jpg').open('rb')),'image/jpeg')
                    entry['accepted']=response_json(requests.post(API+'/upload',headers=upload_headers,
                                                                data=data,files=files,timeout=900))
                    entry['requested_release_at']=scheduled
                    save()
            payload=entry['accepted']
            if platform=='facebook':
                if not payload.get('job_id'): raise RuntimeError('Facebook schedule missing job_id')
                entry['state']='scheduled'; save(); continue
            if not entry.get('video_id'):
                deadline=time.monotonic()+1800
                while True:
                    result=result_for(payload,platform)
                    if confirmed(result): break
                    if payload.get('status') in {'completed','failed'} or result.get('skipped'):
                        raise RuntimeError(f'YouTube did not confirm success: {payload}')
                    if time.monotonic()>deadline: raise TimeoutError('YouTube upload timed out; receipts saved')
                    request_id=entry['accepted'].get('request_id')
                    if not request_id: raise RuntimeError('Missing upload request_id')
                    time.sleep(10)
                    payload=response_json(requests.get(API+'/uploadposts/status',headers=headers,
                                                       params={'request_id':request_id},timeout=60))
                video_id=result.get('video_id') or result.get('post_id')
                if not video_id:
                    match=re.search(r'(?:v=|youtu.be/|shorts/)([A-Za-z0-9_-]{11})',result.get('url',result.get('post_url','')))
                    video_id=match.group(1) if match else None
                if not video_id: raise RuntimeError('Missing YouTube video ID')
                entry.update(video_id=video_id,result=result,state='uploaded_for_scheduled_release'); save()
            if index==0:
                with (out/'thumbnail.jpg').open('rb') as image:
                    patch=response_json(requests.post(API+'/uploadposts/youtube/thumbnail',headers=headers,
                        data={'user':PROFILE,'video_id':entry['video_id']},
                        files={'thumbnail':('thumbnail.jpg',image,'image/jpeg')},timeout=120))
                assert patch.get('success') is True and patch.get('video_id')==entry['video_id']
                sys.path.insert(0,str(ROOT.parents[1]))
                from scripts.verify_youtube_thumbnail import verify
                verify(entry['video_id'],out/'thumbnail.jpg')
                entry['thumbnail_verified']=True; save()
    print('RELEASE_SUBMITTED: YouTube uploads confirmed; Facebook jobs scheduled; see receipts')

if __name__=='__main__': main()
