#!/usr/bin/env python3
from __future__ import annotations
import json, os, re, secrets, subprocess, tarfile, time
from pathlib import Path
import requests, websocket

KEY=os.environ["RUNPOD_API_KEY"]
AUTH={"Authorization":f"Bearer {KEY}"}
VOL="9wjb3sa5zm"
DC="EU-RO-1"
ROOT=Path("aew0916-cpu-finish")
ROOT.mkdir(exist_ok=True)
BUNDLE=ROOT/"inputs.tar.gz"

def create_pod():
    payload={
      "name":f"rwn-aew0916-transfer-{int(time.time())}",
      "imageName":"runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404",
      "cloudType":"SECURE","computeType":"GPU",
      "gpuTypeIds":["NVIDIA RTX PRO 4500 Blackwell","NVIDIA GeForce RTX 5090","NVIDIA RTX PRO 6000 Blackwell Server Edition","NVIDIA A100 80GB PCIe"],
      "gpuTypePriority":"availability","gpuCount":1,
      "dataCenterIds":[DC],"dataCenterPriority":"availability",
      "containerDiskInGb":20,"networkVolumeId":VOL,"volumeMountPath":"/workspace",
      "ports":["8888/http"],"env":{"JUPYTER_PASSWORD":secrets.token_hex(24)}
    }
    r=requests.post("https://rest.runpod.io/v1/pods",headers={**AUTH,"Content-Type":"application/json"},json=payload,timeout=60)
    r.raise_for_status()
    return r.json()["id"],payload["env"]["JUPYTER_PASSWORD"]

def wait_running(pid):
    for i in range(90):
        r=requests.get(f"https://rest.runpod.io/v1/pods/{pid}",headers=AUTH,timeout=30); r.raise_for_status()
        if r.json().get("desiredStatus")=="RUNNING": return
        time.sleep(3)
    raise RuntimeError("pod start timeout")

def login(base,pw):
    for i in range(30):
        try:
            s=requests.Session()
            r=s.get(base+"/login",timeout=20)
            m=re.search(r'name="_xsrf" value="([^"]+)"',r.text)
            if not m: raise RuntimeError("no xsrf")
            rr=s.post(base+"/login",data={"_xsrf":m.group(1),"password":pw,"next":"/"},timeout=20,allow_redirects=False)
            if rr.status_code not in (200,302,303): raise RuntimeError(rr.status_code)
            x=s.cookies.get("_xsrf")
            h={"X-XSRFToken":x} if x else {}
            s.get(base+"/api/status",headers=h,timeout=20).raise_for_status()
            return s,h
        except Exception:
            time.sleep(2)
    raise RuntimeError("jupyter login failed")

def terminal(base,pid,s,h,cmd):
    r=s.post(base+"/api/terminals",headers=h,json={},timeout=30); r.raise_for_status()
    name=r.json()["name"]
    ck="; ".join(f"{c.name}={c.value}" for c in s.cookies)
    ws=websocket.create_connection(f"wss://{pid}-8888.proxy.runpod.net/terminals/websocket/{name}",cookie=ck,origin=base,timeout=90)
    marker="__DONE__"+str(int(time.time()*1000))
    import base64
    enc=base64.b64encode(cmd.encode()).decode()
    ws.send(json.dumps(["stdin",f"echo {enc} | base64 -d >/tmp/x.sh; bash /tmp/x.sh; rc=$?; echo {marker}:$rc\n"]))
    buf=""
    end=time.time()+900
    while time.time()<end:
        data=json.loads(ws.recv())
        if isinstance(data,list) and len(data)>1 and data[0]=="stdout":
            t=data[1]; print(t,end="",flush=True); buf+=t
            m=re.search(re.escape(marker)+r":(\d+)",buf)
            if m:
                ws.close()
                rc=int(m.group(1))
                if rc: raise RuntimeError(f"remote rc {rc}")
                return
    raise RuntimeError("terminal timeout")

def download_bundle(base,s,h):
    candidates=[
      "workspace/ctnetwork-local/aew0916-inputs.tar.gz",
      "ctnetwork-local/aew0916-inputs.tar.gz",
      "aew0916-inputs.tar.gz"
    ]
    for p in candidates:
        try:
            r=s.get(base+"/files/"+p,headers=h,timeout=600)
            print("DOWNLOAD_TRY",p,r.status_code,len(r.content),flush=True)
            if r.ok and len(r.content)>100000:
                BUNDLE.write_bytes(r.content); return
        except Exception as e:
            print("DOWNLOAD_ERR",p,repr(e),flush=True)
    raise RuntimeError("input bundle download failed")

def probe(p):
    raw=subprocess.check_output(["ffprobe","-v","error","-show_streams","-show_format","-of","json",str(p)],text=True)
    j=json.loads(raw)
    v=next(x for x in j["streams"] if x.get("codec_type")=="video")
    a=next(x for x in j["streams"] if x.get("codec_type")=="audio")
    return {"file":p.name,"duration":float(j["format"]["duration"]),"size":p.stat().st_size,"width":v["width"],"height":v["height"],"vcodec":v["codec_name"],"acodec":a["codec_name"]}

def run(cmd):
    subprocess.run(cmd,check=True)

def main():
    pid,pw=create_pod()
    print("TRANSFER_POD",pid,flush=True)
    try:
        wait_running(pid)
        base=f"https://{pid}-8888.proxy.runpod.net"
        for _ in range(60):
            try:
                if requests.get(base+"/login",timeout=10).status_code==200: break
            except Exception: pass
            time.sleep(2)
        s,h=login(base,pw)
        remote=r'''set -Eeuo pipefail
ROOT=/workspace/ctnetwork-local
JOB=$ROOT/ringside-recap-aew-0916
ASSETS=$ROOT/staged-assets/ringside-recap-aew-0916
test -s "$JOB/output/narration.wav"
test -s "$JOB/output/durations.json"
test -s "$ASSETS/ASSETS_READY.status"
for I in $(seq -w 1 12); do test -s "$ASSETS/scene_$I.jpg"; done
test -s "$ASSETS/thumbnail.jpg"
cd "$ROOT"
tar -czf aew0916-inputs.tar.gz   ringside-recap-aew-0916/output/narration.wav   ringside-recap-aew-0916/output/durations.json   staged-assets/ringside-recap-aew-0916/scene_01.jpg   staged-assets/ringside-recap-aew-0916/scene_02.jpg   staged-assets/ringside-recap-aew-0916/scene_03.jpg   staged-assets/ringside-recap-aew-0916/scene_04.jpg   staged-assets/ringside-recap-aew-0916/scene_05.jpg   staged-assets/ringside-recap-aew-0916/scene_06.jpg   staged-assets/ringside-recap-aew-0916/scene_07.jpg   staged-assets/ringside-recap-aew-0916/scene_08.jpg   staged-assets/ringside-recap-aew-0916/scene_09.jpg   staged-assets/ringside-recap-aew-0916/scene_10.jpg   staged-assets/ringside-recap-aew-0916/scene_11.jpg   staged-assets/ringside-recap-aew-0916/scene_12.jpg   staged-assets/ringside-recap-aew-0916/thumbnail.jpg
ls -lh aew0916-inputs.tar.gz
'''
        terminal(base,pid,s,h,remote)
        download_bundle(base,s,h)
    finally:
        try:
            requests.post(f"https://rest.runpod.io/v1/pods/{pid}/stop",headers=AUTH,timeout=30)
            print("TRANSFER_POD_STOPPED",pid,flush=True)
        except Exception as e:
            print("STOP_WARN",repr(e),flush=True)

    work=ROOT/"work"; work.mkdir(exist_ok=True)
    with tarfile.open(BUNDLE,"r:gz") as tf: tf.extractall(work)
    job=work/"ringside-recap-aew-0916"
    assets=work/"staged-assets"/"ringside-recap-aew-0916"
    out=ROOT/"final"; clips=ROOT/"clips"
    out.mkdir(exist_ok=True); clips.mkdir(exist_ok=True)
    durs=json.loads((job/"output"/"durations.json").read_text())
    assert len(durs)==12

    concat=[]
    for i,dur in enumerate(durs,1):
        src=assets/f"scene_{i:02d}.jpg"
        dst=clips/f"scene_{i:02d}.mp4"
        fade=max(0,float(dur)-0.22)
        vf=f"scale=1920:1080:force_original_aspect_ratio=decrease:flags=lanczos,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1,fps=30,format=yuv420p,fade=t=in:st=0:d=0.18,fade=t=out:st={fade:.3f}:d=0.18"
        run(["ffmpeg","-y","-loglevel","error","-loop","1","-framerate","30","-i",str(src),"-t",f"{float(dur):.3f}","-vf",vf,"-an","-c:v","libx264","-preset","veryfast","-crf","18","-r","30","-movflags","+faststart",str(dst)])
        concat.append(f"file '{dst.resolve()}'\n")
    (clips/"concat.txt").write_text("".join(concat))
    visual=out/"visual_master.mp4"
    run(["ffmpeg","-y","-loglevel","error","-f","concat","-safe","0","-i",str(clips/"concat.txt"),"-c","copy",str(visual)])

    narr=job/"output"/"narration.wav"
    dur=float(subprocess.check_output(["ffprobe","-v","error","-show_entries","format=duration","-of","default=nw=1:nk=1",str(narr)],text=True).strip())
    bed=ROOT/"bed.wav"; bell=ROOT/"bell.wav"; mix=ROOT/"mix.wav"
    fade=max(0,dur-2)
    run(["ffmpeg","-y","-loglevel","error","-f","lavfi","-i",f"sine=frequency=55:sample_rate=48000:duration={dur}","-f","lavfi","-i",f"anoisesrc=color=pink:amplitude=0.012:sample_rate=48000:duration={dur}","-filter_complex",f"[0:a]volume=0.035,tremolo=f=1.5:d=0.55[a0];[1:a]highpass=f=180,lowpass=f=2800,volume=0.035[a1];[a0][a1]amix=inputs=2:duration=longest,afade=t=in:st=0:d=1.2,afade=t=out:st={fade}:d=2[bed]","-map","[bed]","-c:a","pcm_s16le",str(bed)])
    run(["ffmpeg","-y","-loglevel","error","-f","lavfi","-i","sine=frequency=880:sample_rate=48000:duration=0.75","-f","lavfi","-i","sine=frequency=1320:sample_rate=48000:duration=0.75","-filter_complex","[0:a]volume=0.20,afade=t=out:st=0.25:d=0.5[a];[1:a]volume=0.10,afade=t=out:st=0.25:d=0.5[b];[a][b]amix=inputs=2","-c:a","pcm_s16le",str(bell)])
    endms=max(0,int((dur-1)*1000))
    run(["ffmpeg","-y","-loglevel","error","-i",str(narr),"-i",str(bed),"-i",str(bell),"-filter_complex",f"[1:a]volume=0.25[bed];[2:a]adelay=0|0[b0];[2:a]adelay={endms}|{endms}[b1];[0:a][bed][b0][b1]amix=inputs=4:duration=first:dropout_transition=1,loudnorm=I=-15:TP=-1.0:LRA=9[a]","-map","[a]","-c:a","pcm_s16le",str(mix)])

    master=out/"RINGSIDE_RECAP_AEW_DYNAMITE_0916_REVIEW_MASTER.mp4"
    run(["ffmpeg","-y","-loglevel","error","-i",str(visual),"-i",str(mix),"-map","0:v:0","-map","1:a:0","-c:v","copy","-c:a","aac","-b:a","192k","-ar","48000","-shortest","-movflags","+faststart",str(master)])
    thumb=out/"thumbnail.jpg"
    run(["ffmpeg","-y","-loglevel","error","-i",str(assets/"thumbnail.jpg"),"-frames:v","1","-vf","scale=1280:720:force_original_aspect_ratio=decrease:flags=lanczos,pad=1280:720:(ow-iw)/2:(oh-ih)/2:color=black","-q:v","2",str(thumb)])

    starts=[sum(durs[:2]),sum(durs[:6]),sum(durs[:7])]
    shorts=[]
    for i,start in enumerate(starts,1):
        length=min(55,max(12,dur-start-0.5))
        sp=out/f"short_0{i}_9x16.mp4"
        run(["ffmpeg","-y","-loglevel","error","-ss",f"{start:.3f}","-i",str(master),"-t",f"{length:.3f}","-vf","scale=1080:1920:force_original_aspect_ratio=decrease:flags=lanczos,pad=1080:1920:(ow-iw)/2:(oh-ih)/2:color=0x101014,setsar=1,format=yuv420p","-c:v","libx264","-preset","veryfast","-crf","19","-c:a","aac","-b:a","160k","-ar","48000","-movflags","+faststart",str(sp)])
        shorts.append(probe(sp))

    q={"pass":True,"master":probe(master),"shorts":shorts,"full_image_no_crop":True,"burned_in_captions":False,"publish_allowed":False}
    (out/"qc.json").write_text(json.dumps(q,indent=2)+"\n")
    (out/"metadata.json").write_text(json.dumps({
      "show":"Ringside Recap","channel":"Ringside Wrestling Network TV",
      "title":"AEW Dynamite Recap 9/16: Ospreay & Moxley Bring Chaos Before All Out",
      "hashtags":["#AEW","#AEWDynamite","#AEWAllOut","#Wrestling","#ProWrestling"],
      "visual_rule":"FULL_IMAGE_NO_CROP","publish_allowed":False
    },indent=2)+"\n")
    print("CPU_FINISH_QC",json.dumps(q),flush=True)

if __name__=="__main__": main()
