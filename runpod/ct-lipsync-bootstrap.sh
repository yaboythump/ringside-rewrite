#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=/workspace/ct-lipsync
STATUS_DIR="$ROOT/status"
APP_DIR="$ROOT/MuseTalk-API"
VENV="$ROOT/venv"
LOG="$STATUS_DIR/bootstrap.log"
PHASE="$STATUS_DIR/phase.txt"

mkdir -p "$STATUS_DIR"
: > "$LOG"

echo BOOTING > "$PHASE"

# Expose only setup status/logs on the secondary HTTP port.
nohup python3 -m http.server 8888 --bind 0.0.0.0 --directory "$STATUS_DIR" \
  > "$STATUS_DIR/http.log" 2>&1 &

exec > >(tee -a "$LOG") 2>&1

phase() {
  echo "$1" > "$PHASE"
  echo "[CT LipSync] phase=$1"
}

on_error() {
  rc=$?
  echo "[CT LipSync] bootstrap failed with exit code $rc"
  phase FAILED
  # Keep the pod alive just long enough for the deploy workflow to collect logs.
  while true; do sleep 300; done
}
trap on_error ERR

phase SYSTEM_PACKAGES
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  git curl ca-certificates ffmpeg libgl1 libglib2.0-0 libsm6 libxext6 \
  libxrender-dev libgomp1 python3.10-venv build-essential

phase SOURCE
if [[ ! -d "$APP_DIR/.git" ]]; then
  git clone --depth 1 https://github.com/ruxir-ig/MuseTalk-API.git "$APP_DIR"
else
  git -C "$APP_DIR" fetch --depth 1 origin main
  git -C "$APP_DIR" reset --hard origin/main
fi

phase PYTHON_ENV
if [[ ! -x "$VENV/bin/python" ]]; then
  python3.10 -m venv --system-site-packages "$VENV"
fi
source "$VENV/bin/activate"
python -m pip install --upgrade pip setuptools wheel

# Keep the large dependency install on the persistent /workspace volume.
if [[ ! -f "$ROOT/.deps-v1-ok" ]]; then
  phase DEPENDENCIES
  python -m pip install -U openmim
  mim install mmengine
  mim install 'mmcv==2.0.1'
  mim install 'mmdet==3.1.0'
  python -m pip install --no-build-isolation 'mmpose==1.1.0'
  python -m pip install \
    'diffusers==0.30.2' \
    'accelerate==0.28.0' \
    'transformers==4.39.2' \
    'huggingface_hub>=0.20.0,<1.0' \
    'numpy==1.23.5' \
    'scipy>=1.10.0' \
    'librosa>=0.10.0' \
    'soundfile>=0.12.0' \
    'opencv-python>=4.8.0' \
    'imageio[ffmpeg]' \
    ffmpeg-python \
    'moviepy==1.0.3' \
    'gfpgan>=1.3.8' \
    'facexlib>=0.3.0' \
    'basicsr>=1.4.2' \
    'realesrgan>=0.3.0' \
    'fastapi>=0.100.0,<1.0' \
    'uvicorn[standard]>=0.22.0' \
    'python-multipart>=0.0.6' \
    omegaconf \
    'einops>=0.7.0' \
    'pyyaml>=6.0' \
    tqdm gdown requests \
    'filterpy>=1.4.5' \
    'lmdb>=1.4.0' \
    'yapf>=0.40.0' \
    'psutil>=5.9.0'
  touch "$ROOT/.deps-v1-ok"
fi

cd "$APP_DIR"

phase MODELS
python download_models.py

# Add bearer-token protection in front of the upstream FastAPI app. The token
# is supplied only as a RunPod environment variable and is never written here.
cat > secure_api.py <<'PY'
import os
import secrets
from fastapi import Request
from fastapi.responses import JSONResponse
from api.main import app

TOKEN = os.environ.get("CT_LIPSYNC_TOKEN", "")
if not TOKEN:
    raise RuntimeError("CT_LIPSYNC_TOKEN is required")

@app.middleware("http")
async def require_token(request: Request, call_next):
    supplied = request.headers.get("authorization", "")
    expected = f"Bearer {TOKEN}"
    if not secrets.compare_digest(supplied, expected):
        return JSONResponse(status_code=401, content={"detail": "Unauthorized"})
    return await call_next(request)
PY

phase GPU_CHECK
python - <<'PY'
import torch
print('torch=', torch.__version__)
print('cuda_available=', torch.cuda.is_available())
if not torch.cuda.is_available():
    raise SystemExit('CUDA is not available')
print('gpu=', torch.cuda.get_device_name(0))
print('vram_gb=', round(torch.cuda.get_device_properties(0).total_memory / 1024**3, 2))
PY

phase STARTING_API
export PYTHONPATH="$APP_DIR:${PYTHONPATH:-}"
exec "$VENV/bin/uvicorn" secure_api:app --host 0.0.0.0 --port 8000
