#!/usr/bin/env python3
from __future__ import annotations
import requests, time
from pathlib import Path
from ringside_recap_aew_0916_narration import create_pod, wait_running, login, terminal_run, AUTH

OUT=Path("ringside-recap-aew-0916-render")
OUT.mkdir(exist_ok=True)

def main():
    pid,pw=create_pod()
    print("RENDER_POD",pid,flush=True)
    try:
        wait_running(pid)
        base=f"https://{pid}-8888.proxy.runpod.net"
        for _ in range(120):
            try:
                if requests.get(base+"/login",timeout=15).status_code==200:
                    break
            except Exception:
                pass
            time.sleep(5)
        s,h=login(base,pw)
        shell=r'''set -Eeuo pipefail
ROOT=/workspace/ctnetwork-local
JOB=$ROOT/ringside-recap-aew-0916
ASSETS=$ROOT/staged-assets/ringside-recap-aew-0916
OUT=$JOB/final
mkdir -p "$OUT" "$JOB/clips" "$JOB/audio/final" "$JOB/shorts"

if ! command -v ffmpeg >/dev/null; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y --no-install-recommends ffmpeg
fi

echo "WAITING_FOR_NARRATION_AND_APPROVED_ASSETS"
for I in $(seq 1 240); do
  if [ -s "$JOB/output/narration.wav" ] && [ -s "$JOB/output/durations.json" ] && [ -s "$ASSETS/ASSETS_READY.status" ]; then
    echo "INPUTS_READY attempt=$I"
    break
  fi
  if [ "$I" -eq 240 ]; then
    echo "INPUT_TIMEOUT"
    ls -lah "$JOB/output" 2>/dev/null || true
    ls -lah "$ASSETS" 2>/dev/null || true
    exit 41
  fi
  sleep 15
done

python3 - <<'PY'
import json, pathlib
job=pathlib.Path('/workspace/ctnetwork-local/ringside-recap-aew-0916')
assets=pathlib.Path('/workspace/ctnetwork-local/staged-assets/ringside-recap-aew-0916')
d=json.load(open(job/'output/durations.json'))
assert len(d)==12, len(d)
for i in range(1,13):
    p=assets/f'scene_{i:02d}.jpg'
    assert p.exists() and p.stat().st_size>10000, p
assert (assets/'thumbnail.jpg').exists()
print('INPUT_QC_PASS',sum(d),len(d))
PY

python3 - <<'PY'
import json, pathlib, subprocess
job=pathlib.Path('/workspace/ctnetwork-local/ringside-recap-aew-0916')
assets=pathlib.Path('/workspace/ctnetwork-local/staged-assets/ringside-recap-aew-0916')
durs=json.load(open(job/'output/durations.json'))
clips=job/'clips'
clips.mkdir(exist_ok=True)
concat=[]
for i,dur in enumerate(durs,1):
    src=assets/f'scene_{i:02d}.jpg'
    out=clips/f'scene_{i:02d}.mp4'
    fadeout=max(0.0,float(dur)-0.22)
    vf=(
      "scale=1920:1080:force_original_aspect_ratio=decrease:flags=lanczos,"
      "pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=black,"
      "setsar=1,fps=30,format=yuv420p,"
      f"fade=t=in:st=0:d=0.18,fade=t=out:st={fadeout:.3f}:d=0.18"
    )
    subprocess.run([
      'ffmpeg','-y','-loglevel','error','-loop','1','-framerate','30','-i',str(src),
      '-t',f'{float(dur):.3f}','-vf',vf,'-an',
      '-c:v','libx264','-preset','veryfast','-crf','18','-r','30','-movflags','+faststart',str(out)
    ],check=True)
    concat.append(f"file '{out}'\n")
(clips/'concat.txt').write_text(''.join(concat))
print('FULL_FRAME_SCENES_READY',len(durs),sum(durs))
PY

ffmpeg -y -loglevel error -f concat -safe 0 -i "$JOB/clips/concat.txt" -c copy "$OUT/visual_master.mp4"

DUR=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$JOB/output/narration.wav")
FADEOUT=$(python3 - <<PY
d=float("$DUR")
print(max(0,d-2))
PY
)

ffmpeg -y -loglevel error   -f lavfi -i "sine=frequency=55:sample_rate=48000:duration=$DUR"   -f lavfi -i "anoisesrc=color=pink:amplitude=0.012:sample_rate=48000:duration=$DUR"   -filter_complex "[0:a]volume=0.035,tremolo=f=1.5:d=0.55[a0];[1:a]highpass=f=180,lowpass=f=2800,volume=0.035[a1];[a0][a1]amix=inputs=2:duration=longest,afade=t=in:st=0:d=1.2,afade=t=out:st=$FADEOUT:d=2[bed]"   -map "[bed]" -c:a pcm_s16le "$JOB/audio/final/music_bed.wav"

ffmpeg -y -loglevel error   -f lavfi -i "sine=frequency=880:sample_rate=48000:duration=0.75"   -f lavfi -i "sine=frequency=1320:sample_rate=48000:duration=0.75"   -filter_complex "[0:a]volume=0.20,afade=t=out:st=0.25:d=0.5[a];[1:a]volume=0.10,afade=t=out:st=0.25:d=0.5[b];[a][b]amix=inputs=2"   -c:a pcm_s16le "$JOB/audio/final/bell.wav"

ENDMS=$(python3 - <<PY
d=float("$DUR")
print(max(0,int((d-1.0)*1000)))
PY
)

ffmpeg -y -loglevel error   -i "$JOB/output/narration.wav"   -i "$JOB/audio/final/music_bed.wav"   -i "$JOB/audio/final/bell.wav"   -filter_complex "[1:a]volume=0.25[bed];[2:a]adelay=0|0[b0];[2:a]adelay=$ENDMS|$ENDMS[b1];[0:a][bed][b0][b1]amix=inputs=4:duration=first:dropout_transition=1,loudnorm=I=-15:TP=-1.0:LRA=9[a]"   -map "[a]" -c:a pcm_s16le "$JOB/audio/final/final_mix.wav"

ffmpeg -y -loglevel error   -i "$OUT/visual_master.mp4" -i "$JOB/audio/final/final_mix.wav"   -map 0:v:0 -map 1:a:0 -c:v copy -c:a aac -b:a 192k -ar 48000 -shortest -movflags +faststart   "$OUT/RINGSIDE_RECAP_AEW_DYNAMITE_0916_REVIEW_MASTER.mp4"

ffmpeg -y -loglevel error -i "$ASSETS/thumbnail.jpg" -frames:v 1   -vf "scale=1280:720:force_original_aspect_ratio=decrease:flags=lanczos,pad=1280:720:(ow-iw)/2:(oh-ih)/2:color=black"   -q:v 2 "$OUT/thumbnail.jpg"

python3 - <<'PY' > "$JOB/shorts/starts.env"
import json
d=json.load(open('/workspace/ctnetwork-local/ringside-recap-aew-0916/output/durations.json'))
def start(n): return sum(d[:n-1])
total=sum(d)
for k,n in [('S1',3),('S2',7),('S3',8)]:
    s=start(n)
    ln=min(55.0,max(12.0,total-s-0.5))
    print(f'{k}_START={s:.3f}')
    print(f'{k}_LEN={ln:.3f}')
PY
source "$JOB/shorts/starts.env"

for N in 1 2 3; do
  eval START=\$S${N}_START
  eval LEN=\$S${N}_LEN
  ffmpeg -y -loglevel error -ss "$START" -i "$OUT/RINGSIDE_RECAP_AEW_DYNAMITE_0916_REVIEW_MASTER.mp4" -t "$LEN"     -vf "scale=1080:1920:force_original_aspect_ratio=decrease:flags=lanczos,pad=1080:1920:(ow-iw)/2:(oh-ih)/2:color=0x101014,setsar=1,format=yuv420p"     -c:v libx264 -preset veryfast -crf 19 -c:a aac -b:a 160k -ar 48000 -movflags +faststart     "$OUT/short_0${N}_9x16.mp4"
done

cat > "$OUT/metadata.json" <<'JSON'
{
  "show": "Ringside Recap",
  "channel": "Ringside Wrestling Network TV",
  "title": "AEW Dynamite Recap 9/16: Ospreay & Moxley Bring Chaos Before All Out",
  "description": "Ringside Recap breaks down the biggest developments from AEW Dynamite on September 16, including the Ospreay-Moxley main-event fallout, Hangman Page and Brodido earning a Trios title opportunity, the Willow Nightingale-Thekla All Out setup, the Mercedes Mone status update, Ciampa-Okada, and the Darby/Borden/Fletcher/Knight build.",
  "hashtags": ["#AEW","#AEWDynamite","#AEWAllOut","#Wrestling","#ProWrestling"],
  "burned_in_captions": false,
  "visual_rule": "FULL_IMAGE_NO_CROP",
  "publish_allowed": false
}
JSON

python3 - <<'PY'
import json, pathlib, subprocess
out=pathlib.Path('/workspace/ctnetwork-local/ringside-recap-aew-0916/final')
def probe(p):
    raw=subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(p)],text=True)
    j=json.loads(raw)
    v=[x for x in j['streams'] if x.get('codec_type')=='video'][0]
    a=[x for x in j['streams'] if x.get('codec_type')=='audio'][0]
    return {'file':p.name,'duration':float(j['format']['duration']),'size':p.stat().st_size,'width':v['width'],'height':v['height'],'vcodec':v['codec_name'],'acodec':a['codec_name']}
m=probe(out/'RINGSIDE_RECAP_AEW_DYNAMITE_0916_REVIEW_MASTER.mp4')
assert m['width']==1920 and m['height']==1080 and m['duration']>240 and m['vcodec']=='h264' and m['acodec']=='aac'
shorts=[]
for i in range(1,4):
    s=probe(out/f'short_0{i}_9x16.mp4')
    assert s['width']==1080 and s['height']==1920 and s['duration']>10
    shorts.append(s)
thumb=out/'thumbnail.jpg'
assert thumb.exists() and thumb.stat().st_size>10000
qc={'pass':True,'master':m,'shorts':shorts,'thumbnail_bytes':thumb.stat().st_size,'full_image_no_crop':True,'burned_in_captions':False,'publish_allowed':False}
(out/'qc.json').write_text(json.dumps(qc,indent=2)+'\n')
(out/'READY_FOR_APPROVAL.txt').write_text('READY_FOR_APPROVAL\nFULL_IMAGE_NO_CROP=true\npublish_allowed=false\n')
print('FINAL_QC_PASS',json.dumps(qc))
PY

cd "$ROOT"
tar -czf ringside-recap-aew-0916-package.tar.gz   ringside-recap-aew-0916/final/RINGSIDE_RECAP_AEW_DYNAMITE_0916_REVIEW_MASTER.mp4   ringside-recap-aew-0916/final/short_01_9x16.mp4   ringside-recap-aew-0916/final/short_02_9x16.mp4   ringside-recap-aew-0916/final/short_03_9x16.mp4   ringside-recap-aew-0916/final/thumbnail.jpg   ringside-recap-aew-0916/final/metadata.json   ringside-recap-aew-0916/final/qc.json   ringside-recap-aew-0916/final/READY_FOR_APPROVAL.txt
ls -lh ringside-recap-aew-0916-package.tar.gz
echo RINGSIDE_RECAP_AEW_0916_READY_FOR_APPROVAL
'''
        terminal_run(base,pid,s,h,shell)
        target=OUT/"ringside-recap-aew-0916-package.tar.gz"
        ok=False
        for remote in ["ctnetwork-local/ringside-recap-aew-0916-package.tar.gz","workspace/ctnetwork-local/ringside-recap-aew-0916-package.tar.gz"]:
            try:
                rr=s.get(base+"/files/"+remote,headers=h,timeout=900)
                if rr.ok and len(rr.content)>100000:
                    target.write_bytes(rr.content)
                    print("PACKAGE_DOWNLOADED",target,len(rr.content),flush=True)
                    ok=True
                    break
            except Exception as exc:
                print("PACKAGE_DOWNLOAD_RETRY",remote,repr(exc),flush=True)
        if not ok:
            raise RuntimeError("render package download failed")
    finally:
        try:
            requests.post(f"https://rest.runpod.io/v1/pods/{pid}/stop",headers=AUTH,timeout=30)
        except Exception:
            pass

if __name__=="__main__":
    main()
