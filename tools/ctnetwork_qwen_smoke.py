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
ENV="$ROOT/envs/qwen3-tts"
MODEL="$ROOT/models/qwen3-tts/1.7B-Base"
OUT="$ROOT/ready_for_approval/qwen-official-smoke.wav"
REF="$ROOT/cache/qwen-smoke-reference.wav"
mkdir -p "$ROOT/python" "$ROOT/cache/uv" "$ROOT/ready_for_approval" "$STATUS"
export UV_PYTHON_INSTALL_DIR="$ROOT/python"
export UV_CACHE_DIR="$ROOT/cache/uv"
export HF_HUB_ENABLE_HF_TRANSFER=0

# The model payload must already exist from the factory install. Do not silently
# redownload multi-GB model weights during a certification run.
find "$MODEL" -type f \( -name '*.safetensors' -o -name '*.bin' \) -print -quit | grep -q . || { echo QWEN_MODEL_MISSING; exit 31; }

# Cold-start self-heal. Older factory envs were created with uv-managed Python
# under the pod's disposable root filesystem; recreate only the runtime on the
# persistent /workspace volume and reuse the existing model payload.
if [ ! -x "$ENV/bin/python" ]; then
  echo SELF_HEAL_QWEN_RUNTIME
  if ! command -v uv >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
  fi
  uv python install 3.12
  rm -rf "$ENV"
  uv venv --python 3.12 "$ENV"
  uv pip install --python "$ENV/bin/python" torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
  uv pip install --python "$ENV/bin/python" -e "$ROOT/src/Qwen3-TTS"
  uv pip install --python "$ENV/bin/python" soundfile huggingface-hub hf_xet
fi

"$ENV/bin/python" - <<'PY'
import torch
print('qwen torch', torch.__version__, 'cuda', torch.version.cuda, 'available', torch.cuda.is_available())
if not torch.cuda.is_available():
    raise SystemExit(32)
print('gpu', torch.cuda.get_device_name(0), torch.cuda.get_device_capability(0))
PY

# Small official reference clip used only for engine certification. Production
# narrator references remain show-specific and must be user-owned/authorized.
if [ ! -s "$REF" ]; then
  curl -fL --retry 4 --retry-delay 3 \
    'https://qianwen-res.oss-cn-beijing.aliyuncs.com/Qwen3-TTS-Repo/clone.wav' \
    -o "$REF"
fi

test -s "$REF" || { echo QWEN_REFERENCE_MISSING; exit 33; }
rm -f "$OUT"

MODEL_PATH="$MODEL" REF_PATH="$REF" OUT_PATH="$OUT" "$ENV/bin/python" - <<'PY'
import os
import torch
import soundfile as sf
from qwen_tts import Qwen3TTSModel

model_path = os.environ['MODEL_PATH']
ref = os.environ['REF_PATH']
out = os.environ['OUT_PATH']

model = Qwen3TTSModel.from_pretrained(
    model_path,
    device_map='cuda:0',
    dtype=torch.bfloat16,
)
text = (
    'CTNETWORK local narration certification is online. '
    'This voice was generated on the factory GPU and is ready for quality control.'
)
ref_text = (
    'Okay. Yeah. I resent you. I love you. I respect you. '
    'But you know what? You blew it! And thanks to you.'
)
wavs, sr = model.generate_voice_clone(
    text=text,
    language='English',
    ref_audio=ref,
    ref_text=ref_text,
)
sf.write(out, wavs[0], sr)
print(f'WROTE {out} sr={sr}')
PY

test -s "$OUT" || { echo QWEN_OUTPUT_MISSING; exit 34; }
AUDIO_STREAMS=$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$OUT" | wc -l)
DURATION=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$OUT")
SAMPLE_RATE=$(ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate -of default=nw=1:nk=1 "$OUT")
python3 -c "a=int('$AUDIO_STREAMS'); d=float('$DURATION'); sr=int('$SAMPLE_RATE'); assert a>=1; assert d>1.0; assert sr>=16000; print(f'QC PASS audio_streams={a} duration={d:.2f}s sample_rate={sr}')"
echo PASS > "$STATUS/qwen_smoke.status"
echo PASS > "$STATUS/qwen3_tts.status"
echo "OUTPUT=$OUT"
'''

    encoded = base64.b64encode(shell.encode()).decode()
    command = (
        f"echo {encoded} | base64 -d >/tmp/ctn-qwen-smoke.sh; "
        "bash /tmp/ctn-qwen-smoke.sh; rc=$?; "
        "echo __CTN_QWEN_SMOKE_DONE__:$rc\n"
    )
    ws.send(json.dumps(["stdin", command]))
    deadline = time.time() + 6900
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
                match = re.search(r"__CTN_QWEN_SMOKE_DONE__:(\d+)", output)
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
        raise RuntimeError("Qwen smoke test timed out before completion marker")
    if rc != 0:
        raise RuntimeError(f"Qwen smoke test failed rc={rc}")


def download_result():
    urls = [
        BASE + "/files/ctnetwork-local/ready_for_approval/qwen-official-smoke.wav",
        BASE + "/files/workspace/ctnetwork-local/ready_for_approval/qwen-official-smoke.wav",
    ]
    for url in urls:
        try:
            r = SESSION.get(url, timeout=180)
            if r.ok and len(r.content) > 1024:
                Path("/tmp/qwen-official-smoke.wav").write_bytes(r.content)
                print(f"downloaded qwen output bytes={len(r.content)}", flush=True)
                return
        except Exception as exc:
            print(f"download attempt failed: {exc}", flush=True)
    print("warning: qwen artifact download failed; persistent server copy still exists", flush=True)


def main():
    headers = login()
    run_remote(headers)
    download_result()


if __name__ == "__main__":
    main()
