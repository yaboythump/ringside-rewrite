#!/usr/bin/env python3
from __future__ import annotations
import json, os, pathlib, subprocess, sys, time, requests, re, hashlib

ROOT=pathlib.Path(__file__).resolve().parents[1]
CMD=ROOT/"ctnetwork-shorts-control.json"
API="https://api.upload-post.com/api"

def run(args):
    print("+"," ".join(map(str,args)),flush=True)
    subprocess.run([str(x) for x in args],check=True)

def probe(path):
    out=subprocess.check_output(["ffprobe","-v","error","-show_entries","format=duration","-of","default=nw=1:nk=1",str(path)],text=True).strip()
    return float(out)

def download(url,dest):
    dest.parent.mkdir(parents=True,exist_ok=True)
    if dest.exists() and dest.stat().st_size>4096:
        return
    with requests.get(url,stream=True,timeout=900) as r:
        r.raise_for_status()
        with open(dest,"wb") as f:
            for b in r.iter_content(4*1024*1024):
                if b:f.write(b)
    if dest.stat().st_size<4096: raise RuntimeError(f"download failed: {dest}")

def auth():
    key=os.getenv("UPLOAD_POST_API_KEY","").strip()
    if not key: raise RuntimeError("UPLOAD_POST_API_KEY missing")
    return {"Authorization":f"Apikey {key}"}

def response_json(r):
    try:p=r.json()
    except Exception:p={"raw":r.text}
    if not r.ok or p.get("success") is False:
        raise RuntimeError(f"Upload-Post HTTP {r.status_code}: {p}")
    return p

def result_for(payload,platform):
    res=payload.get("results",{})
    if isinstance(res,list):
        return next((x for x in res if x.get("platform")==platform),{})
    return res.get(platform,{}) if isinstance(res,dict) else {}

def poll(request_id,platform,timeout=1800):
    h=auth(); end=time.time()+timeout; last={}
    while time.time()<end:
        last=response_json(requests.get(API+"/uploadposts/status",headers=h,params={"request_id":request_id},timeout=60))
        r=result_for(last,platform)
        status=str(r.get("status") or last.get("status") or "").lower()
        if r.get("success") is True or status in {"completed","success","done"}: return r or last
        if r.get("skipped") or status in {"failed","error","skipped"}: raise RuntimeError(f"{platform} failed: {last}")
        time.sleep(10)
    raise TimeoutError(f"{platform} timed out: {last}")

def youtube_id(result):
    for k in ("video_id","post_id","publish_id","id"):
        v=result.get(k)
        if isinstance(v,str) and v.strip():return v.strip()
    u=str(result.get("url") or result.get("post_url") or "")
    m=re.search(r"(?:v=|youtu\.be/|shorts/)([A-Za-z0-9_-]{6,})",u)
    return m.group(1) if m else None

def render_short(master,out,spec):
    start=float(spec["start"]); dur=float(spec["duration"])
    # 9:16 premium layout: blurred full-frame background + clean center image, no burned captions.
    fc=(
      "[0:v]scale=720:1280:force_original_aspect_ratio=increase,crop=720:1280,"
      "boxblur=18:1[bg];"
      "[0:v]scale=720:1280:force_original_aspect_ratio=decrease[fg];"
      "[bg][fg]overlay=(W-w)/2:(H-h)/2,format=yuv420p[v]"
    )
    run(["ffmpeg","-y","-ss",f"{start:.3f}","-t",f"{dur:.3f}","-i",master,
         "-filter_complex",fc,"-map","[v]","-map","0:a:0","-r","30",
         "-c:v","libx264","-preset","veryfast","-crf","20",
         "-c:a","aac","-b:a","160k","-ar","48000","-movflags","+faststart",out])
    actual=probe(out)
    if actual < 20 or actual > 61.5: raise RuntimeError(f"Short duration invalid: {actual}")

def upload_youtube(profile,video,cover,spec,identity):
    h=auth(); data={
      "user":profile,"platform[]":"youtube","title":spec["title"],
      "description":spec["description"],"privacyStatus":spec.get("privacy","public"),
      "async_upload":"true","selfDeclaredMadeForKids":"false","external_id":identity
    }
    with video.open("rb") as vf:
        p=response_json(requests.post(API+"/upload",headers={**h,"Idempotency-Key":identity},
             data=data,files={"video":(video.name,vf,"video/mp4")},timeout=900))
    req=p.get("request_id") or p.get("job_id")
    result=poll(str(req),"youtube") if req else result_for(p,"youtube")
    vid=youtube_id(result)
    if not vid: raise RuntimeError(f"Could not resolve YouTube id: {result}")
    with cover.open("rb") as cf:
        patch=response_json(requests.post(API+"/uploadposts/youtube/thumbnail",headers=h,
             data={"user":profile,"video_id":vid},
             files={"thumbnail":(cover.name,cf,"image/jpeg")},timeout=180))
    if patch.get("success") is not True: raise RuntimeError(f"thumbnail patch failed: {patch}")
    return {"video_id":vid,"result":result,"thumbnail":patch}

def upload_platform(profile,platform,video,cover,spec,identity,facebook_page_id=None):
    h=auth()
    data=[
      ("user",profile),("platform[]",platform),("title",spec["title"]),
      ("description",spec["description"]),("async_upload","true"),("external_id",identity)
    ]
    if platform=="facebook":
        if facebook_page_id:data += [("facebook_page_id",facebook_page_id)]
        data += [("facebook_media_type","REELS"),("facebook_title",spec["title"]),("facebook_description",spec["description"])]
    if platform=="tiktok":
        data += [("privacy","PUBLIC_TO_EVERYONE")]
    files={}
    with video.open("rb") as vf, cover.open("rb") as cf:
        files["video"]=(video.name,vf,"video/mp4")
        if platform=="tiktok":
            files["cover"]=(cover.name,cf,"image/jpeg")
        p=response_json(requests.post(API+"/upload",headers={**h,"Idempotency-Key":identity},data=data,files=files,timeout=900))
    req=p.get("request_id") or p.get("job_id")
    return poll(str(req),platform) if req else result_for(p,platform)

def main():
    cfg=json.loads(CMD.read_text())
    if not cfg.get("approved"): raise RuntimeError("approved=true required")
    if not cfg.get("master_url"): raise RuntimeError("master_url required")
    shorts=cfg.get("shorts") or []
    if len(shorts)!=3: raise RuntimeError("HHWI requires exactly 3 Shorts")
    for s in shorts:
        if not s.get("thumbnail_url"):
            raise RuntimeError("Each short requires thumbnail_url from ChatGPT. Main Higgsfield image credits are never used.")
    work=ROOT/"ctnetwork-shorts-work"/cfg.get("slug","episode")
    work.mkdir(parents=True,exist_ok=True)
    master=work/"master.mp4"; download(cfg["master_url"],master)
    if probe(master)<120: raise RuntimeError("master unexpectedly short")
    receipts={"slug":cfg.get("slug"),"show":cfg.get("show"),"profile":cfg["profile"],"shorts":[]}
    for i,s in enumerate(shorts,1):
        out=work/f"short_{i:02d}.mp4"
        cover=work/f"short_{i:02d}_cover.jpg"
        download(s["thumbnail_url"],cover)
        render_short(master,out,s)
        item={"n":i,"title":s["title"],"duration":probe(out),"file":out.name}
        if cfg.get("publish",False):
            base=f"{cfg.get('slug','episode')}-short-{i:02d}"
            platforms=cfg.get("platforms",["youtube"])
            if "youtube" in platforms:
                item["youtube"]=upload_youtube(cfg["profile"],out,cover,s,base+"-youtube")
            if "facebook" in platforms:
                item["facebook"]=upload_platform(cfg["profile"],"facebook",out,cover,s,base+"-facebook",cfg.get("facebook_page_id"))
            if "tiktok" in platforms:
                item["tiktok"]=upload_platform(cfg["profile"],"tiktok",out,cover,s,base+"-tiktok")
        receipts["shorts"].append(item)
    (work/"receipt.json").write_text(json.dumps(receipts,indent=2,ensure_ascii=False)+"\n")
    print("SHORTS_CONTROL_COMPLETE",json.dumps(receipts),flush=True)

if __name__=="__main__":
    main()
