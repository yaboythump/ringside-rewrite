#!/usr/bin/env python3
from __future__ import annotations

import base64, json, os, re, time
from pathlib import Path
import requests, websocket

REPO = Path(__file__).resolve().parents[1]
CMD = json.loads((REPO / "clutch-replay-parody-command.json").read_text())
POD_ID = os.environ["POD_ID"]
PASSWORD = Path(os.environ["JUPYTER_PASSWORD_FILE"]).read_text().strip()
BASE = f"https://{POD_ID}-8888.proxy.runpod.net"
S = requests.Session()

def login():
    for attempt in range(1, 121):
        try:
            S.cookies.clear()
            r = S.get(BASE + "/login", timeout=15)
            if r.status_code != 200:
                time.sleep(3); continue
            m = re.search(r'name="_xsrf" value="([^"]+)"', r.text)
            if not m:
                time.sleep(3); continue
            rr = S.post(BASE + "/login", data={"_xsrf": m.group(1), "password": PASSWORD, "next": "/"}, timeout=20, allow_redirects=False)
            if rr.status_code not in (200, 302, 303):
                time.sleep(3); continue
            xsrf = S.cookies.get("_xsrf")
            headers = {"X-XSRFToken": xsrf} if xsrf else {}
            if S.get(BASE + "/api/status", headers=headers, timeout=20).status_code == 200:
                print(f"JUPYTER_AUTH_READY attempt={attempt}", flush=True)
                return headers
        except Exception as exc:
            print("auth retry", attempt, repr(exc), flush=True)
        time.sleep(3)
    raise RuntimeError("Jupyter authentication unavailable")

def terminal(headers):
    r = S.post(BASE + "/api/terminals", headers=headers, json={}, timeout=30)
    r.raise_for_status()
    name = r.json()["name"]
    cookie = "; ".join(f"{c.name}={c.value}" for c in S.cookies)
    ws = websocket.create_connection(f"wss://{POD_ID}-8888.proxy.runpod.net/terminals/websocket/{name}", cookie=cookie, origin=BASE, timeout=60)
    return name, ws

def build_remote() -> str:
    cfg = base64.b64encode(json.dumps(CMD).encode()).decode()
    shell = r'''set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
ROOT=/workspace/ctnetwork/breaking-cap/sports-parodies
CFG=/tmp/breaking-cap-parody.json
mkdir -p "$ROOT"
echo __CFG__ | base64 -d > "$CFG"
PY0=$(command -v python3 || command -v python || true)
if [ -z "$PY0" ]; then apt-get update -qq; apt-get install -y -qq python3 python3-pip python3-venv; PY0=$(command -v python3); fi
SLUG=$($PY0 -c 'import json;print(json.load(open("/tmp/breaking-cap-parody.json"))["slug"])')
WORK="$ROOT/$SLUG"; mkdir -p "$WORK"
echo "WORK=$WORK"
nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader || true
command -v ffmpeg >/dev/null || { apt-get update -qq; apt-get install -y -qq ffmpeg git curl fonts-dejavu-core python3-venv; }
command -v git >/dev/null || { apt-get update -qq; apt-get install -y -qq git; }
VENV=/workspace/ctnetwork-local/envs/wan-animate
if [ ! -x "$VENV/bin/python" ]; then $PY0 -m venv --system-site-packages "$VENV" || { apt-get update -qq; apt-get install -y -qq python3-venv; $PY0 -m venv --system-site-packages "$VENV"; }; fi
PY="$VENV/bin/python"; PIP="$PY -m pip"
$PIP install -q --upgrade pip setuptools wheel
$PIP install -q comfy-cli requests websocket-client
COMFY=/workspace/ComfyUI
if [ ! -f "$COMFY/main.py" ]; then git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git "$COMFY"; fi
$PIP install -q -r "$COMFY/requirements.txt"
mkdir -p "$COMFY/custom_nodes" "$COMFY/input" "$COMFY/output" "$COMFY/models/diffusion_models" "$COMFY/models/loras" "$COMFY/models/clip_vision" "$COMFY/models/vae" "$COMFY/models/text_encoders"
clone_node(){ url="$1"; name="$2"; if [ ! -d "$COMFY/custom_nodes/$name/.git" ]; then rm -rf "$COMFY/custom_nodes/$name"; git clone --depth 1 "$url" "$COMFY/custom_nodes/$name"; fi; if [ -f "$COMFY/custom_nodes/$name/requirements.txt" ]; then $PIP install -q -r "$COMFY/custom_nodes/$name/requirements.txt"; fi; }
clone_node https://github.com/kijai/ComfyUI-KJNodes.git ComfyUI-KJNodes
clone_node https://github.com/Fannovel16/comfyui_controlnet_aux.git comfyui_controlnet_aux
get(){ url="$1"; out="$2"; if [ ! -s "$out" ]; then echo "DOWNLOADING $(basename "$out")"; curl -L --fail --retry 4 --retry-delay 3 -C - "$url" -o "$out"; fi; }
get 'https://huggingface.co/Kijai/WanVideo_comfy_fp8_scaled/resolve/main/Wan22Animate/Wan2_2-Animate-14B_fp8_e4m3fn_scaled_KJ.safetensors' "$COMFY/models/diffusion_models/Wan2_2-Animate-14B_fp8_e4m3fn_scaled_KJ.safetensors"
get 'https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Lightx2v/lightx2v_I2V_14B_480p_cfg_step_distill_rank64_bf16.safetensors' "$COMFY/models/loras/lightx2v_I2V_14B_480p_cfg_step_distill_rank64_bf16.safetensors"
get 'https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors' "$COMFY/models/clip_vision/clip_vision_h.safetensors"
get 'https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors' "$COMFY/models/vae/wan_2.1_vae.safetensors"
get 'https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors' "$COMFY/models/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"
get 'https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/LoRAs/Wan22_relight/WanAnimate_relight_lora_fp16.safetensors' "$COMFY/models/loras/WanAnimate_relight_lora_fp16.safetensors"
DRIVER_URL=$($PY -c 'import json;print(json.load(open("/tmp/breaking-cap-parody.json"))["driver_url"])')
REF_URL=$($PY -c 'import json;print(json.load(open("/tmp/breaking-cap-parody.json"))["reference_image_url"])')
LOGO_URL=$($PY -c 'import json;print(json.load(open("/tmp/breaking-cap-parody.json"))["logo_url"])')
DUR=$($PY -c 'import json;print(json.load(open("/tmp/breaking-cap-parody.json"))["driver_duration_seconds"])')
echo "Downloading exact uploaded motion/audio master"
curl -L --fail --retry 4 "$DRIVER_URL" -o "$WORK/source.mp4"
curl -L --fail --retry 4 "$REF_URL" -o "$WORK/reference.jpg"
curl -L --fail --retry 4 "$LOGO_URL" -o "$WORK/breaking_cap_logo.webp"
ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$WORK/source.mp4" | tee "$WORK/source-duration.txt"
cp "$WORK/reference.jpg" "$COMFY/input/breaking_cap_reference.jpg"
WF_BASE="$WORK/wan22_move_base.json"
curl -L --fail --retry 4 'https://raw.githubusercontent.com/Comfy-Org/workflow_templates/main/templates/video_wan2_2_14B_animate.json' -o "$WF_BASE"
pkill -f "$COMFY/main.py" >/dev/null 2>&1 || true
nohup "$PY" "$COMFY/main.py" --listen 127.0.0.1 --port 8188 --lowvram > "$WORK/comfy.log" 2>&1 &
for i in $(seq 1 120); do curl -fsS --max-time 3 http://127.0.0.1:8188/system_stats >/dev/null 2>&1 && break; sleep 2; done
curl -fsS http://127.0.0.1:8188/system_stats | head -c 2000 || { tail -100 "$WORK/comfy.log"; exit 80; }
SEGMENTS="0:4 4:4 8:4 12:4 16:4.408345"
rm -f "$WORK"/render_*.mp4 "$WORK"/concat.txt
IDX=0
for SPEC in $SEGMENTS; do
  START="${SPEC%%:*}"; LEN="${SPEC##*:}"; IDX=$((IDX+1)); PAD=$(printf '%02d' "$IDX")
  INPUT_NAME="breaking_driver_${PAD}.mp4"; INPUT_PATH="$COMFY/input/$INPUT_NAME"
  echo "=== SEGMENT $PAD start=$START len=$LEN ==="
  ffmpeg -y -ss "$START" -t "$LEN" -i "$WORK/source.mp4" -vf "fps=16,scale=384:672:force_original_aspect_ratio=increase,crop=384:672" -an -c:v libx264 -preset veryfast -crf 20 "$INPUT_PATH"
  WF="$WORK/wan22_move_${PAD}.json"; cp "$WF_BASE" "$WF"
  "$PY" - "$WF" "$INPUT_NAME" "$PAD" <<'PYPATCH'
import json, sys
p, input_name, pad = sys.argv[1:4]
w = json.load(open(p))
for n in w.get("nodes", []):
    if n.get("id") == 145: n["widgets_values"][0] = input_name
    elif n.get("id") == 10: n["widgets_values"][0] = "breaking_cap_reference.jpg"
    elif n.get("id") == 21:
        n["widgets_values"][0] = ("Photorealistic professional basketball postgame courtside interview. Animate the basketball player and nearby reporter from the reference image using the natural full-body gestures, facial expressions, head movement, timing and energy from the driving video. Preserve the arena interview setting, uniform, microphone, body proportions and recognizable appearance from the reference image. Natural hands, eyes, mouth and anatomy. No kitchen background.")
    elif n.get("id") == 232:
        for x in n.get("inputs", []):
            if x.get("name") in ("background_video", "character_mask"): x["link"] = None
    elif n.get("id") == 19:
        n["widgets_values"][0] = f"breaking_cap/phx_{pad}"; n["mode"] = 0
    elif n.get("id") in (243, 277): n["mode"] = 4
kill = {676, 692}
w["links"] = [l for l in w.get("links", []) if not (isinstance(l, list) and l and l[0] in kill)]
for n in w.get("nodes", []):
    for o in n.get("outputs", []) or []:
        if isinstance(o.get("links"), list):
            kept = [x for x in o["links"] if x not in kill]; o["links"] = kept or None
json.dump(w, open(p, "w"), ensure_ascii=False)
PYPATCH
  BEFORE=$(date +%s)
  cd "$COMFY"; export COMFYUI_HOST=http://127.0.0.1:8188
  set +e
  "$VENV/bin/comfy" --json run --workflow "$WF" --wait --timeout 3600 > "$WORK/comfy-run-${PAD}.json" 2> "$WORK/comfy-run-${PAD}.err"
  RRC=$?; set -e
  if [ "$RRC" -ne 0 ]; then echo "COMFY RUN FAILED segment=$PAD"; cat "$WORK/comfy-run-${PAD}.json" || true; cat "$WORK/comfy-run-${PAD}.err" || true; tail -200 "$WORK/comfy.log" || true; exit "$RRC"; fi
  GEN=$(find "$COMFY/output" -type f -name '*.mp4' -newermt "@$BEFORE" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
  [ -n "$GEN" ] && [ -s "$GEN" ] || { echo "NO_GENERATED_VIDEO segment=$PAD"; find "$COMFY/output" -maxdepth 3 -type f | tail -50; exit 81; }
  OUT="$WORK/render_${PAD}.mp4"
  ffmpeg -y -i "$GEN" -t "$LEN" -an -c:v libx264 -preset medium -crf 18 "$OUT"
  echo "file '$OUT'" >> "$WORK/concat.txt"
done
ffmpeg -y -f concat -safe 0 -i "$WORK/concat.txt" -an -c:v libx264 -preset medium -crf 18 "$WORK/visual_master.mp4"
FONT=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf
FINAL="$WORK/breaking_cap_phx_parody_FINAL.mp4"
ffmpeg -y -i "$WORK/visual_master.mp4" -i "$WORK/source.mp4" -i "$WORK/breaking_cap_logo.webp" -filter_complex "[0:v]split=2[bg][fg];[bg]scale=576:1024:force_original_aspect_ratio=increase,crop=576:1024,gblur=sigma=24[blur];[fg]scale=576:1024:force_original_aspect_ratio=decrease[front];[blur][front]overlay=(W-w)/2:(H-h)/2[base];[2:v]scale=92:92:force_original_aspect_ratio=decrease,format=rgba,colorchannelmixer=aa=0.90[logo];[base]drawbox=x=0:y=0:w=576:h=178:color=black@0.82:t=fill,drawtext=fontfile=$FONT:text='SHE ASKED HIM HOW HE FELT':x=(w-text_w)/2:y=34:fontsize=31:fontcolor=white:borderw=2:bordercolor=black,drawtext=fontfile=$FONT:text='ABOUT THE GAME TONIGHT':x=(w-text_w)/2:y=82:fontsize=34:fontcolor=white:borderw=2:bordercolor=black,drawtext=fontfile=$FONT:text='AI PARODY':x=18:y=137:fontsize=19:fontcolor=white:box=1:boxcolor=red@0.78:boxborderw=7[tmp];[tmp][logo]overlay=W-w-16:H-h-20[v]" -map "[v]" -map 1:a:0 -t "$DUR" -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p -c:a copy -movflags +faststart "$FINAL"
ffprobe -v error -show_entries format=duration -show_entries stream=codec_name,codec_type,width,height -of json "$FINAL" | tee "$WORK/qc.json"
"$PY" - "$WORK/qc.json" <<'PYQC'
import json, sys
j=json.load(open(sys.argv[1])); s=j["streams"]
assert any(x["codec_type"]=="video" and x.get("width")==576 and x.get("height")==1024 for x in s)
assert any(x["codec_type"]=="audio" for x in s)
d=float(j["format"]["duration"]); assert 20.0 <= d <= 20.6, d
PYQC
cp "$FINAL" /workspace/breaking_cap_phx_parody_FINAL.mp4
echo "FINAL_READY=/workspace/breaking_cap_phx_parody_FINAL.mp4"
'''
    return shell.replace("__CFG__", cfg)

def run_remote(headers):
    _, ws = terminal(headers)
    shell = build_remote()
    marker = f"__BREAKING_CAP_DONE_{int(time.time()*1000)}__"
    enc = base64.b64encode(shell.encode()).decode()
    command = f"echo {enc} | base64 -d > /tmp/breaking-cap-render.sh; bash /tmp/breaking-cap-render.sh; rc=$?; echo {marker}:$rc\n"
    ws.send(json.dumps(["stdin", command]))
    started = time.time(); rc = None
    while time.time() - started < 6 * 3600:
        try: raw = ws.recv()
        except Exception: continue
        try: msg = json.loads(raw)
        except Exception: continue
        if isinstance(msg, list) and len(msg) >= 2 and msg[0] == "stdout":
            text = str(msg[1]); print(text, end="", flush=True)
            m = re.search(re.escape(marker) + r":(\d+)", text)
            if m: rc = int(m.group(1)); break
    ws.close()
    if rc is None: raise RuntimeError("remote render timed out")
    if rc != 0: raise RuntimeError(f"remote render failed rc={rc}")

def download_final(headers):
    url = BASE + "/files/breaking_cap_phx_parody_FINAL.mp4"
    with S.get(url, headers=headers, stream=True, timeout=600) as r:
        r.raise_for_status()
        out = REPO / "breaking_cap_phx_parody_FINAL.mp4"
        with out.open("wb") as f:
            for chunk in r.iter_content(1024 * 1024):
                if chunk: f.write(chunk)
    print(f"DOWNLOADED={out} bytes={out.stat().st_size}", flush=True)

if __name__ == "__main__":
    headers = login()
    run_remote(headers)
    download_final(headers)
