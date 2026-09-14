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


def wait_for_jupyter():
    last = None
    for _ in range(120):
        try:
            r = SESSION.get(BASE + "/login", timeout=15)
            last = r
            if r.ok:
                return r
        except Exception:
            pass
        time.sleep(5)
    raise RuntimeError(f"Jupyter not reachable; last={getattr(last, 'status_code', None)}")


def login():
    r = wait_for_jupyter()
    m = re.search(r'name="_xsrf" value="([^"]+)"', r.text)
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
    probe = SESSION.get(BASE + "/api/status", headers=headers, timeout=30)
    probe.raise_for_status()
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
STATUS="$ROOT/status"
OUT="$ROOT/ready_for_approval/latentsync-official-smoke.mp4"
WRAPPER="$ROOT/bin/ctn-lipsync-test"
PY="$ROOT/envs/latentsync/bin/python"
UV="$ROOT/bin/uv"
export UV_INSTALL_DIR="$ROOT/bin"
export UV_PYTHON_INSTALL_DIR="$ROOT/python"
export UV_CACHE_DIR="$ROOT/cache/uv"
export HF_HOME="$ROOT/cache/huggingface"
export HF_HUB_CACHE="$HF_HOME/hub"
export TRANSFORMERS_CACHE="$HF_HOME/transformers"
export HF_HUB_ENABLE_HF_TRANSFER=0
export PATH="$ROOT/bin:$PATH"

test "$(cat "$STATUS/latentsync.status" 2>/dev/null || true)" = PASS || { echo LATENTSYNC_NOT_READY; exit 21; }
test -s "$ROOT/src/LatentSync/checkpoints/whisper/tiny.pt" || { echo WHISPER_CHECKPOINT_MISSING; exit 23; }
test -s "$ROOT/src/LatentSync/checkpoints/latentsync_unet.pt" || { echo LATENTSYNC_UNET_MISSING; exit 24; }
test -s "$ROOT/src/LatentSync/assets/demo1_video.mp4" || { echo DEMO_VIDEO_MISSING; exit 25; }
test -s "$ROOT/src/LatentSync/assets/demo1_audio.wav" || { echo DEMO_AUDIO_MISSING; exit 26; }
mkdir -p "$ROOT/bin" "$ROOT/python" "$ROOT/cache/uv" "$HF_HUB_CACHE" "$TRANSFORMERS_CACHE" "$ROOT/envs" "$ROOT/ready_for_approval"

if [ ! -x "$UV" ]; then
  echo REPAIR_PERSISTENT_UV
  curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="$ROOT/bin" sh
fi

if ! "$PY" -V >/dev/null 2>&1; then
  echo REPAIR_PERSISTENT_LATENTSYNC_RUNTIME
  rm -rf "$ROOT/envs/latentsync"
  "$UV" python install 3.10
  "$UV" venv --python 3.10 "$ROOT/envs/latentsync"
  "$UV" pip install --python "$PY" torch torchvision --index-url https://download.pytorch.org/whl/cu128
  awk '!/^torch==/ && !/^torchvision==/ && !/^--extra-index-url/' \
    "$ROOT/src/LatentSync/requirements.txt" > "$STATUS/latentsync-requirements-blackwell.txt"
  "$UV" pip install --python "$PY" -r "$STATUS/latentsync-requirements-blackwell.txt"
  "$UV" pip install --python "$PY" huggingface-hub hf_xet
  "$PY" - <<'PYCHK'
import torch
print('cold-start latentsync torch', torch.__version__, 'cuda', torch.version.cuda, 'available', torch.cuda.is_available())
if not torch.cuda.is_available(): raise SystemExit(2)
print(torch.cuda.get_device_name(0), torch.cuda.get_device_capability(0))
PYCHK
  echo PASS > "$STATUS/latentsync_runtime_persistent.status"
fi

if [ "$(cat "$STATUS/latentsync_vae_persistent.status" 2>/dev/null || true)" != PASS ]; then
  echo CACHE_PERSISTENT_LATENTSYNC_VAE
  "$PY" - <<'PYVAE'
from huggingface_hub import snapshot_download
p = snapshot_download(
    repo_id="stabilityai/sd-vae-ft-mse",
    cache_dir="/workspace/ctnetwork-local/cache/huggingface/hub",
)
print("VAE_CACHE", p)
PYVAE
  find "$HF_HUB_CACHE" -type f \( -name 'diffusion_pytorch_model.safetensors' -o -name 'diffusion_pytorch_model.bin' \) -print -quit | grep -q . || { echo VAE_MODEL_FILE_MISSING; exit 28; }
  echo PASS > "$STATUS/latentsync_vae_persistent.status"
fi

if [ ! -x "$WRAPPER" ]; then
  cat > "$WRAPPER" <<'WRAP'
#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=/workspace/ctnetwork-local
VIDEO=${1:?usage: ctn-lipsync-test input_video input_audio [output]}
AUDIO=${2:?usage: ctn-lipsync-test input_video input_audio [output]}
OUT=${3:-$ROOT/ready_for_approval/lipsync-test.mp4}
export HF_HOME="$ROOT/cache/huggingface"
export HF_HUB_CACHE="$HF_HOME/hub"
export TRANSFORMERS_CACHE="$HF_HOME/transformers"
export HF_HUB_ENABLE_HF_TRANSFER=0
cd "$ROOT/src/LatentSync"
"$ROOT/envs/latentsync/bin/python" -m scripts.inference \
  --unet_config_path configs/unet/stage2_512.yaml \
  --inference_ckpt_path checkpoints/latentsync_unet.pt \
  --inference_steps 20 \
  --guidance_scale 1.5 \
  --enable_deepcache \
  --video_path "$VIDEO" \
  --audio_path "$AUDIO" \
  --video_out_path "$OUT"
ffprobe -v error -show_entries format=duration -show_streams -of json "$OUT" > "${OUT%.mp4}.ffprobe.json"
echo "$OUT"
WRAP
  chmod +x "$WRAPPER"
  echo SELF_HEALED_LIPSYNC_WRAPPER
else
  if ! grep -q 'HF_HUB_CACHE' "$WRAPPER" || ! grep -q 'HF_HUB_ENABLE_HF_TRANSFER=0' "$WRAPPER"; then
    rm -f "$WRAPPER"
    cat > "$WRAPPER" <<'WRAP'
#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=/workspace/ctnetwork-local
VIDEO=${1:?usage: ctn-lipsync-test input_video input_audio [output]}
AUDIO=${2:?usage: ctn-lipsync-test input_video input_audio [output]}
OUT=${3:-$ROOT/ready_for_approval/lipsync-test.mp4}
export HF_HOME="$ROOT/cache/huggingface"
export HF_HUB_CACHE="$HF_HOME/hub"
export TRANSFORMERS_CACHE="$HF_HOME/transformers"
export HF_HUB_ENABLE_HF_TRANSFER=0
cd "$ROOT/src/LatentSync"
"$ROOT/envs/latentsync/bin/python" -m scripts.inference \
  --unet_config_path configs/unet/stage2_512.yaml \
  --inference_ckpt_path checkpoints/latentsync_unet.pt \
  --inference_steps 20 \
  --guidance_scale 1.5 \
  --enable_deepcache \
  --video_path "$VIDEO" \
  --audio_path "$AUDIO" \
  --video_out_path "$OUT"
ffprobe -v error -show_entries format=duration -show_streams -of json "$OUT" > "${OUT%.mp4}.ffprobe.json"
echo "$OUT"
WRAP
    chmod +x "$WRAPPER"
    echo REFRESHED_LIPSYNC_WRAPPER_CACHE
  fi
fi

test -x "$WRAPPER" || { echo LIPSYNC_WRAPPER_MISSING; exit 22; }
test -x "$PY" || { echo LATENTSYNC_PYTHON_MISSING; exit 27; }
rm -f "$OUT" "${OUT%.mp4}.ffprobe.json"
HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 "$WRAPPER" \
  "$ROOT/src/LatentSync/assets/demo1_video.mp4" \
  "$ROOT/src/LatentSync/assets/demo1_audio.wav" \
  "$OUT"

test -s "$OUT"
VIDEO_STREAMS=$(ffprobe -v error -select_streams v -show_entries stream=index -of csv=p=0 "$OUT" | wc -l)
AUDIO_STREAMS=$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$OUT" | wc -l)
DURATION=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$OUT")
python3 -c "v=int('$VIDEO_STREAMS'); a=int('$AUDIO_STREAMS'); d=float('$DURATION'); assert v>=1; assert a>=1; assert d>0.5; print(f'QC PASS video_streams={v} audio_streams={a} duration={d:.2f}s')"
echo PASS > "$STATUS/lipsync_smoke.status"
echo "OUTPUT=$OUT"
'''
    encoded = base64.b64encode(shell.encode()).decode()
    command = (
        f"echo {encoded} | base64 -d >/tmp/ctn-lipsync-smoke.sh; "
        "bash /tmp/ctn-lipsync-smoke.sh; rc=$?; "
        "echo __CTN_LIPSYNC_SMOKE_DONE__:$rc\n"
    )
    ws.send(json.dumps(["stdin", command]))
    deadline = time.time() + 3300
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
                match = re.search(r"__CTN_LIPSYNC_SMOKE_DONE__:(\d+)", output)
                if match:
                    rc = int(match.group(1))
                    break
    finally:
        ws.close()
        try:
            SESSION.delete(BASE + f"/api/terminals/{terminal}", headers=headers, timeout=10)
        except Exception:
            pass
    if rc is None:
        raise RuntimeError("Lip sync smoke test timed out before completion marker")
    if rc != 0:
        raise RuntimeError(f"Lip sync smoke test failed rc={rc}")


def download_result():
    urls = [
        BASE + "/files/ctnetwork-local/ready_for_approval/latentsync-official-smoke.mp4",
        BASE + "/files/workspace/ctnetwork-local/ready_for_approval/latentsync-official-smoke.mp4",
    ]
    for url in urls:
        try:
            r = SESSION.get(url, timeout=180)
            if r.ok and len(r.content) > 1024:
                Path("/tmp/latentsync-official-smoke.mp4").write_bytes(r.content)
                print(f"downloaded smoke output bytes={len(r.content)}", flush=True)
                return
        except Exception as exc:
            print(f"download attempt failed: {exc}", flush=True)
    print("warning: artifact download failed; persistent server copy still exists", flush=True)


def main():
    headers = login()
    run_remote(headers)
    download_result()


if __name__ == "__main__":
    main()
