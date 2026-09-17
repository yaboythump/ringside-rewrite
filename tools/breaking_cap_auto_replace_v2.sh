#!/usr/bin/env bash
set -Eeuo pipefail
WORK=/workspace/ctnetwork/breaking-cap/sports-parodies/2026-09-17-auto-character-replace
COMFY=/workspace/ComfyUI
VENV=/workspace/ctnetwork-local/envs/wan-animate
PY=$VENV/bin/python
mkdir -p "$WORK" "$COMFY/input" "$COMFY/output" "$COMFY/models/detection" "$COMFY/custom_nodes"
command -v ffmpeg >/dev/null || { apt-get update -qq; apt-get install -y -qq ffmpeg fonts-dejavu-core git; }
test -x "$PY"; test -f "$COMFY/main.py"
test -f "$COMFY/models/diffusion_models/Wan2_2-Animate-14B_fp8_e4m3fn_scaled_KJ.safetensors"

DRIVER='https://cdn.creativeclaw.co/u/6d1d5f99/videos/5e75207c-49e6-4b54-acea-8469be5aa737.mp4'
REF='https://cdn.creativeclaw.co/u/6d1d5f99/images/568bb85d-2474-42dd-a5cf-50df0e5b3aa4.jpg'
LOGO='https://cdn.creativeclaw.co/u/6d1d5f99/images/d9c58993-5aa6-4e56-93a8-c114273e92b9.jpg'
curl -L --fail --retry 5 "$DRIVER" -o "$WORK/source.mp4"
curl -L --fail --retry 5 "$REF" -o "$WORK/reference.jpg"
curl -L --fail --retry 5 "$LOGO" -o "$WORK/logo.jpg"
cp "$WORK/reference.jpg" "$COMFY/input/breaking_cap_reference.jpg"

cd "$COMFY/custom_nodes"
[[ -d ComfyUI-WanAnimatePreprocess ]] || git clone --depth 1 https://github.com/kijai/ComfyUI-WanAnimatePreprocess.git
[[ -d ComfyUI-segment-anything-2 ]] || git clone --depth 1 https://github.com/kijai/ComfyUI-segment-anything-2.git
[[ -d ComfyUI-KJNodes ]] || git clone --depth 1 https://github.com/kijai/ComfyUI-KJNodes.git
for R in ComfyUI-WanAnimatePreprocess ComfyUI-segment-anything-2 ComfyUI-KJNodes; do
  [[ -f "$R/requirements.txt" ]] && "$PY" -m pip install -q -r "$R/requirements.txt" || true
done

[[ -s "$COMFY/models/detection/yolov10m.onnx" ]] || curl -L --fail --retry 5 'https://huggingface.co/Wan-AI/Wan2.2-Animate-14B/resolve/main/process_checkpoint/det/yolov10m.onnx?download=true' -o "$COMFY/models/detection/yolov10m.onnx"
[[ -s "$COMFY/models/detection/vitpose-l-wholebody.onnx" ]] || curl -L --fail --retry 5 'https://huggingface.co/JunkyByte/easy_ViTPose/resolve/main/onnx/wholebody/vitpose-l-wholebody.onnx?download=true' -o "$COMFY/models/detection/vitpose-l-wholebody.onnx"

WF0="$WORK/wan_auto_replace.json"
curl -L --fail --retry 5 'https://raw.githubusercontent.com/Comfy-Org/workflow_templates/main/templates/template_purz_wan22_animate_auto_character_replace.json' -o "$WF0"

pkill -f "$COMFY/main.py" >/dev/null 2>&1 || true
nohup "$PY" "$COMFY/main.py" --listen 127.0.0.1 --port 8188 --lowvram >"$WORK/comfy.log" 2>&1 &
for i in $(seq 1 180); do curl -fsS --max-time 3 http://127.0.0.1:8188/system_stats >/dev/null 2>&1 && break; sleep 2; done
curl -fsS http://127.0.0.1:8188/system_stats >/dev/null || { tail -180 "$WORK/comfy.log"; exit 70; }

rm -f "$WORK"/concat.txt "$WORK"/gen_*.mp4
N=0
for SPEC in 0:4 4:4 8:4 12:4 16:4.408345; do
  ST=${SPEC%%:*}; LN=${SPEC##*:}; N=$((N+1)); P=$(printf '%02d' $N); IN="bc_driver_$P.mp4"
  ffmpeg -y -ss "$ST" -t "$LN" -i "$WORK/source.mp4" -vf 'fps=16,scale=576:320:force_original_aspect_ratio=increase,crop=576:320' -an -c:v libx264 -preset veryfast -crf 18 "$COMFY/input/$IN" >/dev/null 2>&1
  WF="$WORK/wf_$P.json"; cp "$WF0" "$WF"
  "$PY" - "$WF" "$IN" "$P" <<'PATCH'
import json,sys
p,inp,pad=sys.argv[1:]; w=json.load(open(p))
prompt=("Transfer the driving performer's facial expression, head movement, shoulder movement and arm gestures onto only "
        "the seated basketball player in the reference image. Preserve the reference subject's appearance and seated position. "
        "Keep the locker-room background, microphone, interviewer hand, lower-third graphic, chair, walls and every non-target "
        "object stable. Photorealistic sports interview, natural anatomy, stable face and hands, no extra people, no scene changes.")
for n in w.get('nodes',[]):
    if n.get('id')==10: n['widgets_values'][0]='breaking_cap_reference.jpg'
    elif n.get('id')==301:
        v=n.get('widgets_values',{})
        if isinstance(v,dict):
            v['video']=inp; v['force_rate']=16; v['frame_load_cap']=0; v['skip_first_frames']=0; v['select_every_nth']=1
            if isinstance(v.get('videopreview'),dict):
                v['videopreview'].setdefault('params',{})['filename']=inp
                v['videopreview']['params']['force_rate']=16
    elif n.get('id')==159: n['widgets_values'][0]=576
    elif n.get('id')==160: n['widgets_values'][0]=320
    elif n.get('id')==19: n['widgets_values'][0]=f'breaking_cap/auto_replace_{pad}'
def patch(c):
    for n in c.get('nodes',[]) if isinstance(c,dict) else []:
        props=n.get('properties',{}) or {}
        vals=n.get('widgets_values')
        if props.get('Node name for S&R')=='CLIPTextEncode' and isinstance(vals,list) and vals and vals[0]=='the person is dancing':
            vals[0]=prompt
    for sg in (c.get('definitions',{}) or {}).get('subgraphs',[]) if isinstance(c,dict) else []: patch(sg)
patch(w); json.dump(w,open(p,'w'),ensure_ascii=False)
PATCH
  BEFORE=$(date +%s); cd "$COMFY"; export COMFYUI_HOST=http://127.0.0.1:8188
  "$VENV/bin/comfy" --json run --workflow "$WF" --wait --timeout 3600 >"$WORK/run_$P.json" 2>"$WORK/run_$P.err" || { cat "$WORK/run_$P.err"; tail -260 "$WORK/comfy.log"; exit 71; }
  GEN=$(find "$COMFY/output" -type f -name '*.mp4' -newermt "@$BEFORE" -printf '%T@ %p\n' | sort -nr | head -1 | cut -d' ' -f2-)
  test -s "$GEN" || exit 72
  ffmpeg -y -i "$GEN" -vf 'fps=16,scale=576:320:force_original_aspect_ratio=increase,crop=576:320' -t "$LN" -an -c:v libx264 -preset medium -crf 17 -pix_fmt yuv420p "$WORK/gen_$P.mp4" >/dev/null 2>&1
  echo "file '$WORK/gen_$P.mp4'" >>"$WORK/concat.txt"
done

ffmpeg -y -f concat -safe 0 -i "$WORK/concat.txt" -an -c:v libx264 -preset medium -crf 17 -pix_fmt yuv420p "$WORK/visual.mp4" >/dev/null 2>&1
FONT=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf
FINAL=/workspace/breaking_cap_photo_lock_FINAL.mp4
ffmpeg -y -i "$WORK/visual.mp4" -i "$WORK/source.mp4" -i "$WORK/logo.jpg" -filter_complex \
"[0:v]split=2[b][f];[b]scale=576:1024:force_original_aspect_ratio=increase,crop=576:1024,gblur=sigma=26[blur];[f]scale=576:-2[front];[blur][front]overlay=(W-w)/2:(H-h)/2[base];[2:v]scale=74:74:force_original_aspect_ratio=decrease,format=rgba,colorchannelmixer=aa=.92[lg];[base]drawbox=x=0:y=0:w=576:h=176:color=black@.84:t=fill,drawtext=fontfile=$FONT:text='SHE ASKED HIM HOW HE FELT':x=(w-text_w)/2:y=32:fontsize=31:fontcolor=white:borderw=2:bordercolor=black,drawtext=fontfile=$FONT:text='ABOUT THE GAME TONIGHT':x=(w-text_w)/2:y=80:fontsize=34:fontcolor=white:borderw=2:bordercolor=black,drawtext=fontfile=$FONT:text='AI PARODY':x=18:y=136:fontsize=19:fontcolor=white:box=1:boxcolor=red@.8:boxborderw=7[t];[t][lg]overlay=W-w-16:H-h-18[v]" \
-map '[v]' -map 1:a:0 -t 20.408345 -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p -c:a copy -movflags +faststart "$FINAL" >/dev/null 2>&1
ffprobe -v error -show_entries format=duration -show_entries stream=codec_type,width,height -of json "$FINAL" | tee "$WORK/qc.json"
test -s "$FINAL"; echo AUTO_REPLACE_FINAL_READY
