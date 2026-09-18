#!/usr/bin/env python3
from __future__ import annotations
import base64, json
from pathlib import Path
from ringside_wcw_full_episode import resolve_running_pod, wait_jupyter, login, terminal_run, stop_pod, JOB_ID

OUT=Path("ringside-wcw-reframed")
OUT.mkdir(parents=True,exist_ok=True)
CROPS=[
[0,205,318,160],[318,205,329,160],[647,205,316,160],[963,205,349,160],
[0,455,318,145],[318,455,329,145],[647,455,316,145],[963,455,349,145],
[0,705,318,125],[318,705,329,125],[647,705,316,125],[963,705,349,125],
[0,930,620,140],[620,930,341,140],[961,930,351,140]
]

def main():
    pod_id,password,created=resolve_running_pod()
    print("USING_PRODUCTION_POD",pod_id,"created_fresh=",created,flush=True)
    base=f"https://{pod_id}-8888.proxy.runpod.net"
    try:
        wait_jupyter(base); s,headers=login(base,password)
        crops_b64=base64.b64encode(json.dumps(CROPS).encode()).decode()
        shell=f"""set -Eeuo pipefail
ROOT=/workspace/ctnetwork-local
JOB=$ROOT/{JOB_ID}
mkdir -p "$JOB"/{{visuals_full,clips_full,output}}
test -s "$JOB/raw/storyboard.jpg"
test -s "$JOB/audio/final_mix_stable.wav"
echo {crops_b64} | base64 -d > "$JOB/text/crops_full.json"

python3 - <<'PY'
import json,pathlib,subprocess
job=pathlib.Path("/workspace/ctnetwork-local/{JOB_ID}")
crops=json.load(open(job/"text"/"crops_full.json"))
durs=[]
for i in range(1,16):
    p=job/"audio"/f"norm_{{i:02d}}.wav"
    sec=float(subprocess.check_output(["ffprobe","-v","error","-show_entries","format=duration","-of","default=nw=1:nk=1",str(p)],text=True).strip())
    durs.append(max(2.0,sec))

concat=[]
for i,((x,y,w,h),dur) in enumerate(zip(crops,durs),1):
    still=job/"visuals_full"/f"scene_{{i:02d}}.jpg"
    clip=job/"clips_full"/f"scene_{{i:02d}}.mp4"
    filt=(
        f"crop={{w}}:{{h}}:{{x}}:{{y}},split=2[bg][fg];"
        "[bg]scale=1920:1080:force_original_aspect_ratio=increase,"
        "crop=1920:1080,boxblur=24:2[bg2];"
        "[fg]scale=1760:990:force_original_aspect_ratio=decrease[fg2];"
        "[bg2][fg2]overlay=(W-w)/2:(H-h)/2,format=yuv420p"
    )
    subprocess.run(["ffmpeg","-y","-loglevel","error","-i",str(job/"raw"/"storyboard.jpg"),"-filter_complex",filt,"-frames:v","1","-q:v","2",str(still)],check=True)
    subprocess.run([
        "ffmpeg","-y","-loglevel","error","-loop","1","-framerate","30","-i",str(still),
        "-t",f"{{dur:.3f}}","-vf","format=yuv420p","-an","-c:v","libx264","-preset","veryfast","-crf","18",
        "-r","30","-movflags","+faststart",str(clip)
    ],check=True)
    concat.append(f"file '{{clip}}'\\n")
(job/"clips_full"/"concat.txt").write_text("".join(concat))
print("FULL_FRAME_SCENES_READY",len(concat),sum(durs),flush=True)
PY

ffmpeg -y -loglevel error -f concat -safe 0 -i "$JOB/clips_full/concat.txt" -c copy "$JOB/visual_master_fullframe.mp4"

ffmpeg -y -loglevel error \
  -i "$JOB/visual_master_fullframe.mp4" -i "$JOB/audio/final_mix_stable.wav" \
  -map 0:v:0 -map 1:a:0 -c:v copy -c:a aac -b:a 192k -ar 48000 -shortest -movflags +faststart \
  "$JOB/output/RINGSIDE_REWRITE_WCW_WON_FULLFRAME_REVIEW.mp4"

ffprobe -v error -show_entries format=duration,size -show_entries stream=codec_name,width,height -of json \
 "$JOB/output/RINGSIDE_REWRITE_WCW_WON_FULLFRAME_REVIEW.mp4" > "$JOB/output/qc_fullframe.json"

python3 - <<'PY'
import json,pathlib
p=pathlib.Path("/workspace/ctnetwork-local/{JOB_ID}/output/RINGSIDE_REWRITE_WCW_WON_FULLFRAME_REVIEW.mp4")
q=json.load(open(p.parent/"qc_fullframe.json")); fmt=q.get("format",{{}}); streams=q.get("streams",[])
assert p.exists() and p.stat().st_size>1_000_000
assert 210<float(fmt.get("duration") or 0)<230
assert any(s.get("codec_name")=="h264" and int(s.get("width") or 0)==1920 and int(s.get("height") or 0)==1080 for s in streams)
assert any(s.get("codec_name")=="aac" for s in streams)
(p.parent/"READY_FOR_APPROVAL_FULLFRAME.txt").write_text("READY_FOR_APPROVAL\\npublish_allowed=false\\nformula=locked\\nframing_fix=full_image_visible\\n")
print("WCW_FULLFRAME_QC_PASS",p.stat().st_size,fmt.get("duration"),flush=True)
PY

cd "$ROOT"
tar -czf ringside-wcw-fullframe-review.tar.gz \
 {JOB_ID}/output/RINGSIDE_REWRITE_WCW_WON_FULLFRAME_REVIEW.mp4 \
 {JOB_ID}/output/qc_fullframe.json \
 {JOB_ID}/output/READY_FOR_APPROVAL_FULLFRAME.txt

python3 - <<'PY'
import base64, pathlib, json
p=pathlib.Path("/workspace/ctnetwork-local/ringside-wcw-fullframe-review.tar.gz")
print("PACKAGE_BYTES",p.stat().st_size,flush=True)
PY
"""
        terminal_run(base,pod_id,s,headers,shell,timeout=3600)

        dest=OUT/"ringside-wcw-fullframe-review.tar.gz"
        ok=False
        for rel in ["ctnetwork-local/ringside-wcw-fullframe-review.tar.gz","workspace/ctnetwork-local/ringside-wcw-fullframe-review.tar.gz"]:
            rr=s.get(base+"/api/contents/"+rel,headers=headers,timeout=1200)
            if rr.ok:
                model=rr.json()
                if model.get("type")=="file" and model.get("content"):
                    dest.write_bytes(base64.b64decode(model["content"]))
                    print("DOWNLOADED",rel,dest.stat().st_size,flush=True)
                    ok=True; break
        if not ok: raise RuntimeError("FULLFRAME_PACKAGE_DOWNLOAD_FAILED")
    finally:
        stop_pod(pod_id)

if __name__=="__main__":
    main()
