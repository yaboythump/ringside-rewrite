#!/usr/bin/env python3
import base64
import json
import os
import re
import sys
import time
from pathlib import Path

import requests
import websocket

POD_ID = os.environ["POD_ID"]
PASSWORD = Path(os.environ["JUPYTER_PASSWORD_FILE"]).read_text().strip()
BASE = f"https://{POD_ID}-8888.proxy.runpod.net"
SESSION = requests.Session()


def login():
    last = None
    for _ in range(60):
        try:
            last = SESSION.get(BASE + "/login", timeout=15)
            if last.ok:
                break
        except Exception:
            pass
        time.sleep(5)
    else:
        raise RuntimeError(f"Jupyter not reachable; last={getattr(last, 'status_code', None)}")
    m = re.search(r'name="_xsrf" value="([^"]+)"', last.text)
    if not m:
        raise RuntimeError("Could not find Jupyter XSRF token")
    xsrf = m.group(1)
    r = SESSION.post(BASE + "/login", data={"_xsrf": xsrf, "password": PASSWORD, "next": "/"}, timeout=30, allow_redirects=False)
    if r.status_code not in (200, 302, 303):
        r.raise_for_status()
    cx = SESSION.cookies.get("_xsrf")
    headers = {"X-XSRFToken": cx} if cx else {}
    SESSION.get(BASE + "/api/status", headers=headers, timeout=30).raise_for_status()
    return headers


def run_remote(headers):
    r = SESSION.post(BASE + "/api/terminals", headers=headers, json={}, timeout=30)
    r.raise_for_status()
    terminal = r.json()["name"]
    cookie = "; ".join(f"{c.name}={c.value}" for c in SESSION.cookies)
    ws = websocket.create_connection(
        f"wss://{POD_ID}-8888.proxy.runpod.net/terminals/websocket/{terminal}",
        cookie=cookie,
        origin=BASE,
        timeout=60,
    )

    shell = r'''set -Eeuo pipefail
ROOT=/workspace/ctnetwork-local
SRC="$ROOT/src/LTX-2"
MODELS="$ROOT/models/ltx-2.5"
STATUS="$ROOT/status"
OUT="$ROOT/ready_for_approval/ltx25-dfr-smoke.mp4"
PY="$SRC/.venv/bin/python"
LORA_DIR="$MODELS/loras"
LORA="$LORA_DIR/ltx-2.5-22b-ic-lora-pixel-spatial-upscaler-x2-1.0.safetensors"
mkdir -p "$ROOT/ready_for_approval" "$STATUS" "$LORA_DIR" "$ROOT/cache/huggingface"
export HF_HUB_ENABLE_HF_TRANSFER=0
export HF_HOME="$ROOT/cache/huggingface"
export HF_HUB_CACHE="$HF_HOME/hub"
export TRANSFORMERS_CACHE="$HF_HOME/transformers"

test "$(cat "$STATUS/ltx25_smoke.status" 2>/dev/null || true)" = PASS || { echo LTX25_BASE_SMOKE_NOT_CERTIFIED; exit 51; }
test -x "$PY" || { echo LTX25_PYTHON_MISSING; exit 52; }

if [ ! -s "$LORA" ]; then
  echo CACHE_PERSISTENT_LTX25_DETAILING_LORA
  "$PY" -m pip install --quiet --upgrade huggingface-hub hf_xet
  "$PY" - <<'PY'
from huggingface_hub import hf_hub_download
p = hf_hub_download(
    repo_id='Lightricks/LTX-2.5-22b-IC-LoRA-Pixel-Spatial-Upscaler',
    filename='ltx-2.5-22b-ic-lora-pixel-spatial-upscaler-x2-1.0.safetensors',
    local_dir='/workspace/ctnetwork-local/models/ltx-2.5/loras',
)
print('DETAILING_LORA_CACHE', p)
PY
fi
test -s "$LORA" || { echo DETAILING_LORA_MISSING; exit 53; }

TRANS="$MODELS/diffusion_models/ltx-2.5-22b-distilled-transformer-bf16.safetensors"
TEXT="$MODELS/text_encoders/gemma4-12b-with-proj-ltx-2.5-bf16.safetensors"
VVIDEO="$MODELS/vae/ltx-2.5-video-vae-bf16.safetensors"
VAUDIO="$MODELS/vae/ltx-2.5-audio-vae-bf16.safetensors"
UPSCALE="$MODELS/latent_upscale_models/ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors"
for f in "$TRANS" "$TEXT" "$VVIDEO" "$VAUDIO" "$UPSCALE" "$LORA"; do test -s "$f" || { echo "DFR_MODEL_FILE_MISSING:$f"; exit 54; }; done

"$PY" - <<'PY'
import torch
print('dfr torch', torch.__version__, 'cuda', torch.version.cuda, 'available', torch.cuda.is_available())
if not torch.cuda.is_available(): raise SystemExit(55)
print('gpu', torch.cuda.get_device_name(0), torch.cuda.get_device_capability(0))
PY

rm -f "$OUT"
cd "$SRC"
set +e
"$PY" -m ltx_pipelines.dfr_pipeline \
  --transformer-path "$TRANS" \
  --text-encoder-path "$TEXT" \
  --video-vae-path "$VVIDEO" \
  --audio-vae-path "$VAUDIO" \
  --detailing-lora "$LORA" \
  --spatial-upsampler-path "$UPSCALE" \
  --width 768 \
  --height 512 \
  --num-frames 33 \
  --seed 43 \
  --quantization fp8-cast \
  --offload cpu \
  --output-path "$OUT" \
  --prompt "Premium cinematic CTNETWORK production room. A polished metallic network emblem in a dark professional studio, fine texture detail, realistic reflections, controlled broadcast lighting, subtle camera movement, premium commercial finish. No captions, no extra text."
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  echo "DFR_PRIMARY_COMMAND_FAILED rc=$rc; inspecting CLI and retrying without optional memory flags."
  "$PY" -m ltx_pipelines.dfr_pipeline --help > "$STATUS/ltx25-dfr-help.txt" 2>&1 || true
  "$PY" -m ltx_pipelines.dfr_pipeline \
    --transformer-path "$TRANS" \
    --text-encoder-path "$TEXT" \
    --video-vae-path "$VVIDEO" \
    --audio-vae-path "$VAUDIO" \
    --detailing-lora "$LORA" \
    --spatial-upsampler-path "$UPSCALE" \
    --width 768 \
    --height 512 \
    --num-frames 33 \
    --seed 43 \
    --output-path "$OUT" \
    --prompt "Premium cinematic CTNETWORK production room. A polished metallic network emblem in a dark professional studio, fine texture detail, realistic reflections, controlled broadcast lighting, subtle camera movement, premium commercial finish. No captions, no extra text."
fi

test -s "$OUT" || { echo DFR_OUTPUT_MISSING; exit 56; }
VIDEO_STREAMS=$(ffprobe -v error -select_streams v -show_entries stream=index -of csv=p=0 "$OUT" | wc -l)
DURATION=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$OUT")
WIDTH=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 "$OUT")
HEIGHT=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 "$OUT")
python3 -c "v=int('$VIDEO_STREAMS'); d=float('$DURATION'); w=int('$WIDTH'); h=int('$HEIGHT'); assert v>=1; assert d>0.5; assert w>=512 and h>=512; print(f'DFR QC PASS streams={v} duration={d:.2f}s resolution={w}x{h}')"
ffprobe -v error -show_streams -show_format -of json "$OUT" > "${OUT%.mp4}.ffprobe.json"
echo PASS > "$STATUS/ltx25_dfr.status"
echo "OUTPUT=$OUT"
'''
    encoded = base64.b64encode(shell.encode()).decode()
    command = f"echo {encoded} | base64 -d >/tmp/ctn-ltx25-dfr-smoke.sh; bash /tmp/ctn-ltx25-dfr-smoke.sh; rc=$?; echo __CTN_LTX25_DFR_DONE__:$rc\n"
    ws.send(json.dumps(["stdin", command]))
    deadline = time.time() + 9000
    output = ""
    rc = None
    try:
        while time.time() < deadline:
            try:
                msg = ws.recv()
            except Exception as exc:
                print("websocket:", exc, flush=True)
                continue
            if not msg:
                continue
            try:
                data = json.loads(msg)
            except Exception:
                continue
            if isinstance(data, list) and len(data) >= 2 and data[0] == "stdout":
                text = data[1]
                output += text
                sys.stdout.write(text)
                sys.stdout.flush()
                m = re.search(r"__CTN_LTX25_DFR_DONE__:(\d+)", output)
                if m:
                    rc = int(m.group(1))
                    break
    finally:
        ws.close()
        try:
            SESSION.delete(BASE + f"/api/terminals/{terminal}", headers=headers, timeout=10)
        except Exception:
            pass
    if rc is None:
        raise RuntimeError("LTX 2.5 DFR smoke timed out")
    if rc != 0:
        raise RuntimeError(f"LTX 2.5 DFR smoke failed rc={rc}")


def download():
    for rel in (
        "/files/ctnetwork-local/ready_for_approval/ltx25-dfr-smoke.mp4",
        "/files/workspace/ctnetwork-local/ready_for_approval/ltx25-dfr-smoke.mp4",
    ):
        try:
            r = SESSION.get(BASE + rel, timeout=300)
            if r.ok and len(r.content) > 4096:
                Path("/tmp/ltx25-dfr-smoke.mp4").write_bytes(r.content)
                print(f"downloaded DFR output bytes={len(r.content)}")
                return
        except Exception as exc:
            print("download attempt failed", exc)
    print("warning: DFR artifact download failed; persistent server copy remains")


def main():
    headers = login()
    run_remote(headers)
    download()


if __name__ == "__main__":
    main()
