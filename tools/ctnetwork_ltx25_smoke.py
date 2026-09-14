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
PASSWORD_FILE = Path(os.environ["JUPYTER_PASSWORD_FILE"])
PASSWORD = PASSWORD_FILE.read_text().strip()
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
    r = SESSION.post(
        BASE + "/login",
        data={"_xsrf": xsrf, "password": PASSWORD, "next": "/"},
        timeout=30,
        allow_redirects=False,
    )
    if r.status_code not in (200, 302, 303):
        r.raise_for_status()
    cookie_xsrf = SESSION.cookies.get("_xsrf")
    headers = {"X-XSRFToken": cookie_xsrf} if cookie_xsrf else {}
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
OUT="$ROOT/ready_for_approval/ltx25-official-smoke.mp4"
PY="$SRC/.venv/bin/python"
mkdir -p "$ROOT/ready_for_approval" "$STATUS"
export HF_HUB_ENABLE_HF_TRANSFER=0
export HF_HOME="$ROOT/cache/huggingface"
export TRANSFORMERS_CACHE="$ROOT/cache/huggingface/transformers"

# Mechanical certification uses the fast distilled pipeline. Production recipes
# can promote selected shots to the DFR detailing tier after this base engine passes.
test "$(cat "$STATUS/ltx25_models.status" 2>/dev/null || true)" = PASS || { echo LTX25_MODELS_NOT_READY; exit 41; }
test -x "$PY" || { echo LTX25_PYTHON_MISSING; exit 42; }
TRANS="$MODELS/diffusion_models/ltx-2.5-22b-distilled-transformer-bf16.safetensors"
TEXT="$MODELS/text_encoders/gemma4-12b-with-proj-ltx-2.5-bf16.safetensors"
VVIDEO="$MODELS/vae/ltx-2.5-video-vae-bf16.safetensors"
VAUDIO="$MODELS/vae/ltx-2.5-audio-vae-bf16.safetensors"
UPSCALE="$MODELS/latent_upscale_models/ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors"
for f in "$TRANS" "$TEXT" "$VVIDEO" "$VAUDIO" "$UPSCALE"; do test -s "$f" || { echo "LTX25_MODEL_FILE_MISSING:$f"; exit 43; }; done

"$PY" - <<'PY'
import torch
print('ltx25 torch', torch.__version__, 'cuda', torch.version.cuda, 'available', torch.cuda.is_available())
if not torch.cuda.is_available(): raise SystemExit(44)
print('gpu', torch.cuda.get_device_name(0), torch.cuda.get_device_capability(0))
PY

rm -f "$OUT"
cd "$SRC"
"$PY" -m ltx_pipelines.distilled \
  --transformer-path "$TRANS" \
  --text-encoder-path "$TEXT" \
  --video-vae-path "$VVIDEO" \
  --audio-vae-path "$VAUDIO" \
  --spatial-upsampler-path "$UPSCALE" \
  --num-frames 65 \
  --seed 42 \
  --quantization fp8-cast \
  --offload cpu \
  --output-path "$OUT" \
  --prompt "A premium cinematic CTNETWORK studio ident: dark modern production room, polished metal CTNETWORK emblem, subtle camera push-in, realistic reflections, controlled dramatic lighting, professional broadcast quality. No captions, no extra text."

test -s "$OUT" || { echo LTX25_OUTPUT_MISSING; exit 45; }
VIDEO_STREAMS=$(ffprobe -v error -select_streams v -show_entries stream=index -of csv=p=0 "$OUT" | wc -l)
DURATION=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$OUT")
WIDTH=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 "$OUT")
HEIGHT=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 "$OUT")
python3 -c "v=int('$VIDEO_STREAMS'); d=float('$DURATION'); w=int('$WIDTH'); h=int('$HEIGHT'); assert v>=1; assert d>0.5; assert w>=256 and h>=256; print(f'QC PASS video_streams={v} duration={d:.2f}s resolution={w}x{h}')"
ffprobe -v error -show_streams -show_format -of json "$OUT" > "${OUT%.mp4}.ffprobe.json"
echo PASS > "$STATUS/ltx25_smoke.status"
echo "OUTPUT=$OUT"
'''

    encoded = base64.b64encode(shell.encode()).decode()
    command = (
        f"echo {encoded} | base64 -d >/tmp/ctn-ltx25-smoke.sh; "
        "bash /tmp/ctn-ltx25-smoke.sh; rc=$?; "
        "echo __CTN_LTX25_SMOKE_DONE__:$rc\n"
    )
    ws.send(json.dumps(["stdin", command]))
    deadline = time.time() + 7200
    rc = None
    output = ""
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
                m = re.search(r"__CTN_LTX25_SMOKE_DONE__:(\d+)", output)
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
        raise RuntimeError("LTX 2.5 smoke test timed out before completion marker")
    if rc != 0:
        raise RuntimeError(f"LTX 2.5 smoke test failed rc={rc}")


def download_result():
    for rel in (
        "/files/ctnetwork-local/ready_for_approval/ltx25-official-smoke.mp4",
        "/files/workspace/ctnetwork-local/ready_for_approval/ltx25-official-smoke.mp4",
    ):
        try:
            r = SESSION.get(BASE + rel, timeout=300)
            if r.ok and len(r.content) > 4096:
                Path("/tmp/ltx25-official-smoke.mp4").write_bytes(r.content)
                print(f"downloaded ltx25 output bytes={len(r.content)}", flush=True)
                return
        except Exception as exc:
            print(f"download attempt failed: {exc}", flush=True)
    print("warning: LTX artifact download failed; persistent server copy still exists", flush=True)


def main():
    headers = login()
    run_remote(headers)
    download_result()


if __name__ == "__main__":
    main()
