#!/usr/bin/env python3
from __future__ import annotations

import base64, json, os, re, sys, time
from pathlib import Path
import requests, websocket

REPO = Path(__file__).resolve().parents[1]
CMD = json.loads((REPO / 'clutch-replay-parody-command.json').read_text())
POD_ID = os.environ['POD_ID']
PASSWORD = Path(os.environ['JUPYTER_PASSWORD_FILE']).read_text().strip()
BASE = f'https://{POD_ID}-8888.proxy.runpod.net'
S = requests.Session()


def login():
    for attempt in range(1, 121):
        try:
            S.cookies.clear()
            r = S.get(BASE + '/login', timeout=15)
            if r.status_code != 200:
                time.sleep(3); continue
            m = re.search(r'name="_xsrf" value="([^"]+)"', r.text)
            if not m:
                time.sleep(3); continue
            rr = S.post(BASE + '/login', data={'_xsrf': m.group(1), 'password': PASSWORD, 'next': '/'}, timeout=20, allow_redirects=False)
            if rr.status_code not in (200, 302, 303):
                time.sleep(3); continue
            xsrf = S.cookies.get('_xsrf')
            headers = {'X-XSRFToken': xsrf} if xsrf else {}
            if S.get(BASE + '/api/status', headers=headers, timeout=20).status_code == 200:
                print(f'JUPYTER_AUTH_READY attempt={attempt}', flush=True)
                return headers
        except Exception as exc:
            print('auth retry', attempt, repr(exc), flush=True)
        time.sleep(3)
    raise RuntimeError('Jupyter authentication unavailable')


def terminal(headers):
    r = S.post(BASE + '/api/terminals', headers=headers, json={}, timeout=30); r.raise_for_status()
    name = r.json()['name']
    cookie = '; '.join(f'{c.name}={c.value}' for c in S.cookies)
    ws = websocket.create_connection(f'wss://{POD_ID}-8888.proxy.runpod.net/terminals/websocket/{name}', cookie=cookie, origin=BASE, timeout=60)
    return name, ws


def build_remote() -> str:
    cfg = base64.b64encode(json.dumps(CMD).encode()).decode()
    return r'''set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
ROOT=/workspace/ctnetwork/clutch-replay/sports-parodies
CFG=/tmp/clutch-parody.json
mkdir -p "$ROOT"
echo __CFG__ | base64 -d > "$CFG"
SLUG=$(python3 -c 'import json;print(json.load(open("/tmp/clutch-parody.json"))["slug"])' 2>/dev/null || true)
if [ -z "$SLUG" ]; then
  PY0=$(command -v python3 || command -v python || true)
  [ -n "$PY0" ] || { apt-get update -qq && apt-get install -y -qq python3 python3-pip python3-venv; PY0=$(command -v python3); }
  SLUG=$($PY0 -c 'import json;print(json.load(open("/tmp/clutch-parody.json"))["slug"])')
fi
WORK="$ROOT/$SLUG"; mkdir -p "$WORK"
PY0=$(command -v python3 || command -v python)
echo "SYSTEM_PY=$PY0"
echo '=== GPU ==='; nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader || true
command -v ffmpeg >/dev/null || { apt-get update -qq; apt-get install -y -qq ffmpeg git curl fonts-dejavu-core python3-venv; }
command -v git >/dev/null || { apt-get update -qq; apt-get install -y -qq git; }

VENV=/workspace/ctnetwork-local/envs/wan-animate
if [ ! -x "$VENV/bin/python" ]; then
  $PY0 -m venv --system-site-packages "$VENV" || { apt-get update -qq; apt-get install -y -qq python3-venv; $PY0 -m venv --system-site-packages "$VENV"; }
fi
PY="$VENV/bin/python"; PIP="$PY -m pip"
$PIP install -q --upgrade pip setuptools wheel
$PIP install -q comfy-cli yt-dlp requests websocket-client

COMFY=/workspace/ComfyUI
if [ ! -f "$COMFY/main.py" ]; then git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git "$COMFY"; fi
$PIP install -q -r "$COMFY/requirements.txt"
mkdir -p "$COMFY/custom_nodes" "$COMFY/input" "$COMFY/output" "$COMFY/models/diffusion_models" "$COMFY/models/loras" "$COMFY/models/clip_vision" "$COMFY/models/vae" "$COMFY/models/text_encoders"

clone_node(){ url="$1"; name="$2"; if [ ! -d "$COMFY/custom_nodes/$name/.git" ]; then rm -rf "$COMFY/custom_nodes/$name"; git clone --depth 1 "$url" "$COMFY/custom_nodes/$name"; fi; if [ -f "$COMFY/custom_nodes/$name/requirements.txt" ]; then $PIP install -q -r "$COMFY/custom_nodes/$name/requirements.txt"; fi; }
clone_node https://github.com/kijai/ComfyUI-KJNodes.git ComfyUI-KJNodes
clone_node https://github.com/Fannovel16/comfyui_controlnet_aux.git comfyui_controlnet_aux
clone_node https://github.com/kijai/ComfyUI-segment-anything-2.git ComfyUI-segment-anything-2

get(){ url="$1"; out="$2"; if [ ! -s "$out" ]; then echo "DOWNLOADING $(basename "$out")"; curl -L --fail --retry 4 --retry-delay 3 -C - "$url" -o "$out"; fi; }
get 'https://huggingface.co/Kijai/WanVideo_comfy_fp8_scaled/resolve/main/Wan22Animate/Wan2_2-Animate-14B_fp8_e4m3fn_scaled_KJ.safetensors' "$COMFY/models/diffusion_models/Wan2_2-Animate-14B_fp8_e4m3fn_scaled_KJ.safetensors"
get 'https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Lightx2v/lightx2v_I2V_14B_480p_cfg_step_distill_rank64_bf16.safetensors' "$COMFY/models/loras/lightx2v_I2V_14B_480p_cfg_step_distill_rank64_bf16.safetensors"
get 'https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors' "$COMFY/models/clip_vision/clip_vision_h.safetensors"
get 'https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors' "$COMFY/models/vae/wan_2.1_vae.safetensors"
get 'https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors' "$COMFY/models/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"
get 'https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/LoRAs/Wan22_relight/WanAnimate_relight_lora_fp16.safetensors' "$COMFY/models/loras/WanAnimate_relight_lora_fp16.safetensors"

DRIVER_URL=$($PY -c 'import json;print(json.load(open("/tmp/clutch-parody.json"))["driver_url"])')
FALLBACK_URL=$($PY -c 'import json;print(json.load(open("/tmp/clutch-parody.json"))["driver_fallback_url"])')
START=$($PY -c 'import json;print(json.load(open("/tmp/clutch-parody.json"))["driver_start_seconds"])')
DUR=$($PY -c 'import json;print(json.load(open("/tmp/clutch-parody.json"))["driver_duration_seconds"])')
REF_URL=$($PY -c 'import json;print(json.load(open("/tmp/clutch-parody.json"))["reference_image_url"])')
HEADLINE=$($PY -c 'import json;print(json.load(open("/tmp/clutch-parody.json"))["headline"])')

rm -f "$WORK"/source.*
set +e
"$VENV/bin/yt-dlp" --no-playlist --merge-output-format mp4 -f 'bv*+ba/b' -o "$WORK/source.%(ext)s" "$DRIVER_URL"
ytdlp_rc=$?
set -e
SRC=$(find "$WORK" -maxdepth 1 -type f -name 'source.*' | head -1 || true)
if [ "$ytdlp_rc" -ne 0 ] || [ -z "$SRC" ]; then
  rm -f "$WORK"/source.*
  "$VENV/bin/yt-dlp" --no-playlist --merge-output-format mp4 -f 'bv*+ba/b' -o "$WORK/source.%(ext)s" "$FALLBACK_URL"
  SRC=$(find "$WORK" -maxdepth 1 -type f -name 'source.*' | head -1)
  START=0
fi
curl -L --fail --retry 4 "$REF_URL" -o "$WORK/tommy_pham.jpg"
ffmpeg -y -ss "$START" -t "$DUR" -i "$SRC" -vf 'fps=16,scale=512:512:force_original_aspect_ratio=decrease,pad=512:512:(ow-iw)/2:(oh-ih)/2:black' -an -c:v libx264 -preset veryfast -crf 18 "$WORK/driver_16fps.mp4"
ffmpeg -y -ss "$START" -t "$DUR" -i "$SRC" -vn -c:a aac -b:a 192k "$WORK/driver_audio.m4a"
cp "$WORK/driver_16fps.mp4" "$COMFY/input/clutch_driver.mp4"
cp "$WORK/tommy_pham.jpg" "$COMFY/input/tommy_pham.jpg"

WF="$WORK/wan22_animate_ui.json"
curl -L --fail --retry 4 'https://raw.githubusercontent.com/Comfy-Org/workflow_templates/main/templates/video_wan2_2_14B_animate.json' -o "$WF"
$PY - "$WF" <<'PYPATCH'
import json,sys
p=sys.argv[1]; w=json.load(open(p))
for n in w.get('nodes',[]):
    if n.get('id')==145:
        n['widgets_values'][0]='clutch_driver.mp4'
    elif n.get('id')==10:
        n['widgets_values'][0]='tommy_pham.jpg'
    elif n.get('id')==21:
        n['widgets_values'][0]='Tommy Pham, professional baseball player in a Chicago White Sox uniform, emotional frustrated crying rant, photorealistic sports interview, realistic face, natural hands, accurate human anatomy.'
    elif n.get('id')==232:
        for x in n.get('inputs',[]):
            if x.get('name') in ('background_video','character_mask'): x['link']=None
    elif n.get('id')==19:
        n['widgets_values'][0]='clutch_replay/tommy_pham'
        n['mode']=0
    elif n.get('id') in (243,277):
        n['mode']=4
# remove the two Mix-mode links and dangling link refs
kill={676,692}
w['links']=[l for l in w.get('links',[]) if not (isinstance(l,list) and l and l[0] in kill)]
for n in w.get('nodes',[]):
    for o in n.get('outputs',[]) or []:
        if isinstance(o.get('links'),list): o['links']=[x for x in o['links'] if x not in kill] or None
json.dump(w,open(p,'w'),ensure_ascii=False)
PYPATCH

# Launch local ComfyUI. FP8 model + lowvram/offload is intentional for 24GB-class GPUs.
pkill -f "$COMFY/main.py" >/dev/null 2>&1 || true
nohup "$PY" "$COMFY/main.py" --listen 127.0.0.1 --port 8188 --lowvram > "$WORK/comfy.log" 2>&1 &
CPID=$!
for i in $(seq 1 120); do curl -fsS --max-time 3 http://127.0.0.1:8188/system_stats >/dev/null 2>&1 && break; sleep 2; done
curl -fsS http://127.0.0.1:8188/system_stats | head -c 2000 || { tail -100 "$WORK/comfy.log"; exit 80; }

cd "$COMFY"
export COMFYUI_HOST=http://127.0.0.1:8188
set +e
"$VENV/bin/comfy" --json run --workflow "$WF" --wait --timeout 3600 > "$WORK/comfy-run.json" 2> "$WORK/comfy-run.err"
RRC=$?
set -e
if [ "$RRC" -ne 0 ]; then
  echo 'COMFY RUN FAILED'; cat "$WORK/comfy-run.json" || true; cat "$WORK/comfy-run.err" || true; tail -200 "$WORK/comfy.log" || true; exit "$RRC"
fi
sleep 2
GEN=$(find "$COMFY/output/clutch_replay" "$COMFY/output" -type f \( -name '*.mp4' -o -name '*.webm' \) -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
[ -n "$GEN" ] && [ -s "$GEN" ] || { echo 'NO_GENERATED_VIDEO'; find "$COMFY/output" -maxdepth 3 -type f | tail -50; exit 81; }

echo "GENERATED=$GEN"
FINAL="$WORK/clutch_replay_tommy_pham_parody.mp4"
FONT=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf
# Build vertical social master: blurred fill, centered generated subject, dedicated title safe-zone, original meme audio, parody label.
ffmpeg -y -i "$GEN" -i "$WORK/driver_audio.m4a" -filter_complex "[0:v]split=2[bg][fg];[bg]scale=576:1024:force_original_aspect_ratio=increase,crop=576:1024,gblur=sigma=28[blur];[fg]scale=576:760:force_original_aspect_ratio=decrease[front];[blur][front]overlay=(W-w)/2:210[tmp];[tmp]drawbox=x=0:y=0:w=576:h=190:color=black@0.88:t=fill,drawtext=fontfile=$FONT:text='TOMMY PHAM AFTER BEGGING TO PLAY...':x=(w-text_w)/2:y=36:fontsize=32:fontcolor=white:borderw=2:bordercolor=black,drawtext=fontfile=$FONT:text='THEN DOING THIS':x=(w-text_w)/2:y=86:fontsize=38:fontcolor=white:borderw=2:bordercolor=black,drawtext=fontfile=$FONT:text='AI PARODY':x=18:y=148:fontsize=20:fontcolor=white:box=1:boxcolor=black@0.7:boxborderw=8[v]" -map '[v]' -map 1:a:0 -c:v libx264 -preset medium -crf 18 -c:a aac -b:a 192k -shortest -movflags +faststart "$FINAL"
ffprobe -v error -show_entries format=duration -show_entries stream=codec_type,width,height -of json "$FINAL" | tee "$WORK/qc.json"
$PY - "$WORK/qc.json" <<'PYQC'
import json,sys
j=json.load(open(sys.argv[1])); s=j['streams']; assert any(x['codec_type']=='video' and x.get('width',0)<x.get('height',0) for x in s); assert any(x['codec_type']=='audio' for x in s); assert float(j['format']['duration'])>3
PYQC
cp "$FINAL" /workspace/clutch_replay_tommy_pham_parody.mp4
printf 'PASS\n' > "$WORK/status.txt"
echo "FINAL_READY=$FINAL"
'''.replace('__CFG__', cfg)


def run_remote(headers):
    name, ws = terminal(headers)
    shell = build_remote()
    marker = f'__CLUTCH_DONE_{int(time.time()*1000)}__'
    enc = base64.b64encode(shell.encode()).decode()
    ws.send(json.dumps(['stdin', f'echo {enc} | base64 -d >/tmp/clutch-parody.sh; bash /tmp/clutch-parody.sh; rc=$?; echo {marker}:$rc\n']))
    deadline=time.time()+21600; output=''; rc=None
    try:
        while time.time()<deadline:
            try: msg=ws.recv()
            except Exception as exc:
                print('websocket',repr(exc),flush=True); continue
            try: data=json.loads(msg)
            except Exception: continue
            if isinstance(data,list) and len(data)>=2 and data[0]=='stdout':
                text=data[1]; output+=text; sys.stdout.write(text); sys.stdout.flush()
                m=re.search(re.escape(marker)+r':(\d+)',output)
                if m: rc=int(m.group(1)); break
    finally:
        ws.close()
        try:S.delete(BASE+f'/api/terminals/{name}',headers=headers,timeout=10)
        except Exception:pass
    if rc is None: raise RuntimeError('remote parody render timed out')
    if rc != 0: raise RuntimeError(f'remote parody render failed rc={rc}')


def download_final(headers):
    out=REPO/'clutch_replay_tommy_pham_parody.mp4'
    for path in ('/files/workspace/clutch_replay_tommy_pham_parody.mp4','/files/clutch_replay_tommy_pham_parody.mp4'):
        r=S.get(BASE+path,headers=headers,timeout=180,stream=True)
        if r.status_code==200:
            with out.open('wb') as f:
                for chunk in r.iter_content(1024*1024):
                    if chunk:f.write(chunk)
            if out.stat().st_size>100000:
                print(f'DOWNLOADED_FINAL {out} {out.stat().st_size}',flush=True); return out
    raise RuntimeError('final file exists remotely but Jupyter file download failed')


def main():
    assert CMD.get('publish_allowed') is False
    headers=login(); run_remote(headers); download_final(headers)

if __name__=='__main__': main()
