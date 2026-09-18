#!/usr/bin/env python3
from __future__ import annotations
import os
from pathlib import Path
from ringside_wcw_full_episode import resolve_running_pod, wait_jupyter, login, terminal_run, download, stop_pod, JOB_ID

OUT = Path("ringside-wcw-review")
OUT.mkdir(parents=True, exist_ok=True)

def main():
    pod_id, password, created_pod = resolve_running_pod()
    print("USING_PRODUCTION_POD", pod_id, "created_fresh=", created_pod, flush=True)
    base = f"https://{pod_id}-8888.proxy.runpod.net"
    try:
        wait_jupyter(base)
        s, headers = login(base, password)
        shell = f"""set -Eeuo pipefail
ROOT=/workspace/ctnetwork-local
JOB=$ROOT/{JOB_ID}
mkdir -p "$JOB"/{{clips_stable,output,sfx}}
test -s "$JOB/audio/section_15.wav"
test -s "$JOB/visuals/scene_15.jpg"

# Rebuild normalized narration only if needed.
if [ ! -s "$JOB/audio/narration.wav" ]; then
  : > "$JOB/audio/concat.txt"
  for I in $(seq -w 1 15); do
    if [ ! -s "$JOB/audio/norm_${{I}}.wav" ]; then
      ffmpeg -y -loglevel error -i "$JOB/audio/section_${{I}}.wav" -ar 48000 -ac 1 -af "loudnorm=I=-16:TP=-1.5:LRA=11" "$JOB/audio/norm_${{I}}.wav"
    fi
    echo "file '$JOB/audio/norm_${{I}}.wav'" >> "$JOB/audio/concat.txt"
  done
  ffmpeg -y -loglevel error -f concat -safe 0 -i "$JOB/audio/concat.txt" -c:a pcm_s16le "$JOB/audio/narration.wav"
fi

python3 - <<'PY'
import json, pathlib, subprocess
job=pathlib.Path("/workspace/ctnetwork-local/{JOB_ID}")
durs=[]
for i in range(1,16):
    p=job/"audio"/f"norm_{{i:02d}}.wav"
    sec=float(subprocess.check_output([
        "ffprobe","-v","error","-show_entries","format=duration",
        "-of","default=nw=1:nk=1",str(p)
    ],text=True).strip())
    durs.append(max(2.0,sec))

concat=[]
for i,dur in enumerate(durs,1):
    img=job/"visuals"/f"scene_{{i:02d}}.jpg"
    out=job/"clips_stable"/f"scene_{{i:02d}}.mp4"
    vf="scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,format=yuv420p"
    subprocess.run([
        "ffmpeg","-y","-loglevel","error","-loop","1","-framerate","30",
        "-i",str(img),"-t",f"{{dur:.3f}}","-vf",vf,"-an",
        "-c:v","libx264","-preset","veryfast","-crf","19","-r","30",
        "-movflags","+faststart",str(out)
    ],check=True)
    concat.append(f"file '{{out}}'\\n")
(job/"clips_stable"/"concat.txt").write_text("".join(concat))
(job/"text"/"stable_durations.json").write_text(json.dumps(durs))
print("STABLE_SCENES_READY", len(durs), sum(durs), flush=True)
PY

ffmpeg -y -loglevel error -f concat -safe 0 -i "$JOB/clips_stable/concat.txt" -c copy "$JOB/visual_master_stable.mp4"

DUR=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$JOB/audio/narration.wav")
ENDFADE=$(awk -v d="$DUR" 'BEGIN{{e=d-2;if(e<0)e=0;printf "%.3f",e}}')

# Simple wrestling-style rhythmic bed: low pulse + filtered noise. Stable lavfi only.
ffmpeg -y -loglevel error \
  -f lavfi -i "sine=frequency=55:sample_rate=48000:duration=$DUR" \
  -f lavfi -i "sine=frequency=110:sample_rate=48000:duration=$DUR" \
  -f lavfi -i "anoisesrc=color=pink:amplitude=0.02:sample_rate=48000:duration=$DUR" \
  -filter_complex "[0:a]volume=0.10,tremolo=f=2:d=0.8[a0];[1:a]volume=0.035,tremolo=f=4:d=0.7[a1];[2:a]highpass=f=500,lowpass=f=5000,volume=0.14[a2];[a0][a1][a2]amix=inputs=3:duration=longest,afade=t=in:st=0:d=1.5,afade=t=out:st=$ENDFADE:d=2[bed]" \
  -map "[bed]" -c:a pcm_s16le "$JOB/sfx/music_bed_stable.wav"

ffmpeg -y -loglevel error \
  -f lavfi -i "sine=frequency=880:sample_rate=48000:duration=1.1" \
  -f lavfi -i "sine=frequency=1320:sample_rate=48000:duration=1.1" \
  -filter_complex "[0:a]volume=.24,afade=t=out:st=.12:d=.9[a];[1:a]volume=.14,afade=t=out:st=.08:d=.9[b];[a][b]amix=inputs=2" \
  "$JOB/sfx/bell_stable.wav"

ffmpeg -y -loglevel error \
  -f lavfi -i "anoisesrc=color=pink:amplitude=0.08:sample_rate=48000:duration=3" \
  -af "highpass=f=250,lowpass=f=5000,afade=t=in:d=.15,afade=t=out:st=1.8:d=1.2,volume=.16" \
  "$JOB/sfx/crowd_stable.wav"

ffmpeg -y -loglevel error \
  -i "$JOB/audio/narration.wav" \
  -stream_loop -1 -i "$JOB/sfx/music_bed_stable.wav" \
  -i "$JOB/sfx/bell_stable.wav" \
  -i "$JOB/sfx/crowd_stable.wav" \
  -filter_complex "[1:a]atrim=0:$DUR,volume=0.28[bed];[2:a]adelay=0|0[bell0];[2:a]adelay=180000|180000[bell1];[3:a]adelay=18000|18000[c1];[3:a]adelay=95000|95000[c2];[0:a][bed][bell0][bell1][c1][c2]amix=inputs=6:duration=first:dropout_transition=1,loudnorm=I=-15:TP=-1.0:LRA=9[a]" \
  -map "[a]" -c:a pcm_s16le "$JOB/audio/final_mix_stable.wav"

ffmpeg -y -loglevel error \
  -i "$JOB/visual_master_stable.mp4" -i "$JOB/audio/final_mix_stable.wav" \
  -map 0:v:0 -map 1:a:0 -c:v copy -c:a aac -b:a 192k -ar 48000 -shortest -movflags +faststart \
  "$JOB/output/RINGSIDE_REWRITE_WCW_WON_REVIEW_MASTER.mp4"

ffprobe -v error -show_entries format=duration,size -show_entries stream=codec_name,width,height -of json \
  "$JOB/output/RINGSIDE_REWRITE_WCW_WON_REVIEW_MASTER.mp4" > "$JOB/output/qc.json"

python3 - <<'PY'
import json, pathlib
p=pathlib.Path("/workspace/ctnetwork-local/{JOB_ID}/output/RINGSIDE_REWRITE_WCW_WON_REVIEW_MASTER.mp4")
q=json.load(open(p.parent/"qc.json"))
fmt=q.get("format",{{}})
streams=q.get("streams",[])
assert p.exists() and p.stat().st_size > 1_000_000
assert float(fmt.get("duration") or 0) > 120
assert any(s.get("codec_name")=="h264" and int(s.get("width") or 0)==1920 and int(s.get("height") or 0)==1080 for s in streams)
assert any(s.get("codec_name")=="aac" for s in streams)
(p.parent/"READY_FOR_APPROVAL.txt").write_text("READY_FOR_APPROVAL\npublish_allowed=false\n")
print("WCW_STABLE_MASTER_QC_PASS", p.stat().st_size, fmt.get("duration"), flush=True)
PY

cd "$ROOT"
tar -czf ringside-wcw-review.tar.gz \
  {JOB_ID}/output/RINGSIDE_REWRITE_WCW_WON_REVIEW_MASTER.mp4 \
  {JOB_ID}/output/qc.json \
  {JOB_ID}/output/READY_FOR_APPROVAL.txt
ls -lh ringside-wcw-review.tar.gz
"""
        terminal_run(base, pod_id, s, headers, shell, timeout=7200)
        download(base, s, headers, "ctnetwork-local/ringside-wcw-review.tar.gz", OUT/"ringside-wcw-review.tar.gz")
    finally:
        stop_pod(pod_id)

if __name__ == "__main__":
    main()
