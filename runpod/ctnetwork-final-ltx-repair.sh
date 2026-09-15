#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=/workspace/ctnetwork-local
SRC="$ROOT/src"; ENVS="$ROOT/envs"; MODELS="$ROOT/models"; STATUS="$ROOT/status"; BIN="$ROOT/bin"; CACHE="$ROOT/cache"
mkdir -p "$ROOT/python" "$CACHE/uv" "$CACHE/huggingface" "$MODELS/ltx-2.5" "$STATUS" "$BIN" "$ROOT/controller" "$ROOT/bridge-state" "$ROOT/ready_for_approval"
export UV_PYTHON_INSTALL_DIR="$ROOT/python"
export UV_CACHE_DIR="$CACHE/uv"
export HF_HOME="$CACHE/huggingface"
export HF_HUB_CACHE="$HF_HOME/hub"
export TRANSFORMERS_CACHE="$HF_HOME/transformers"
export HF_HUB_ENABLE_HF_TRANSFER=0
export PATH="$BIN:$HOME/.local/bin:$PATH"

stamp(){ date -u +'%Y-%m-%dT%H:%M:%SZ'; }
mark(){ printf '%s\n' "$2" > "$STATUS/$1.status"; }
fail(){ echo "FINAL_REPAIR_FAIL:$*"; echo "FAILED:$*" > "$STATUS/final_repair.status"; exit 1; }

echo "[$(stamp)] CTNETWORK FINAL LTX REPAIR START"
nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader

if ! command -v uv >/dev/null 2>&1; then
  if [ -x "$BIN/uv" ]; then :; else curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="$BIN" sh; fi
fi
uv --version
uv python install 3.12
uv python install 3.10
PY312=$(find "$ROOT/python" -type f -path '*/bin/python3.12' -print | head -n1)
PY310=$(find "$ROOT/python" -type f -path '*/bin/python3.10' -print | head -n1)
[ -x "$PY312" ] || fail "persistent Python 3.12 missing"
[ -x "$PY310" ] || fail "persistent Python 3.10 missing"

env_persistent(){
  local path="$1"; local root
  [ -e "$path" ] || return 1
  root=$(readlink -f "$path" 2>/dev/null || true)
  [[ "$root" == "$ROOT/python/"* ]]
}

# Core environment: rebuild only when its interpreter points into disposable container storage.
if ! env_persistent "$ENVS/core/bin/python"; then
  echo REPAIR_CORE_PERSISTENT_PYTHON
  rm -rf "$ENVS/core"
  uv venv --python "$PY312" "$ENVS/core"
  uv pip install --python "$ENVS/core/bin/python" torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
  uv pip install --python "$ENVS/core/bin/python" \
    fastapi 'uvicorn[standard]' pydantic pyyaml typer rich tenacity filelock psutil watchdog \
    httpx requests orjson sqlalchemy aiosqlite numpy scipy soundfile librosa pyloudnorm pedalboard \
    noisereduce ffmpeg-python scenedetect opencv-python-headless faster-whisper pillow \
    huggingface-hub hf_xet safetensors
else
  # Older core envs may have been created before torch was an explicit dependency.
  "$ENVS/core/bin/python" -c 'import torch' 2>/dev/null || \
    uv pip install --python "$ENVS/core/bin/python" torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
fi
"$ENVS/core/bin/python" -c 'import fastapi,torch; assert torch.cuda.is_available(); print("CORE_PY_OK", torch.__version__, torch.version.cuda, torch.cuda.get_device_name(0))' || fail "core env/CUDA invalid"
mark core PASS

# Qwen environment. Recreate only a disposable/broken runtime; preserve/download weights separately.
if ! env_persistent "$ENVS/qwen3-tts/bin/python"; then
  echo REPAIR_QWEN_PERSISTENT_PYTHON
  rm -rf "$ENVS/qwen3-tts"
  uv venv --python "$PY312" "$ENVS/qwen3-tts"
  uv pip install --python "$ENVS/qwen3-tts/bin/python" torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
  uv pip install --python "$ENVS/qwen3-tts/bin/python" -e "$SRC/Qwen3-TTS"
  uv pip install --python "$ENVS/qwen3-tts/bin/python" huggingface-hub hf_xet safetensors
fi
QMODEL="$MODELS/qwen3-tts/1.7B-Base"
mkdir -p "$QMODEL"
QHF="$ENVS/qwen3-tts/bin/hf"
[ -x "$QHF" ] || fail "Qwen hf CLI missing"
if ! find -L "$QMODEL" -type f \( -name '*.safetensors' -o -name '*.bin' \) -size +1M -print -quit | grep -q .; then
  echo DOWNLOAD_OR_RESUME_QWEN3_TTS
  HF_HUB_ENABLE_HF_TRANSFER=0 "$QHF" download Qwen/Qwen3-TTS-12Hz-1.7B-Base --local-dir "$QMODEL" || fail "Qwen model download failed"
fi
find -L "$QMODEL" -type f \( -name '*.safetensors' -o -name '*.bin' \) -size +1M -print -quit | grep -q . || fail "Qwen weights missing after download"
# Validate every local safetensors shard that exists; broken/partial shards fail here.
while IFS= read -r qf; do
  "$ENVS/qwen3-tts/bin/python" - "$qf" <<'PY'
import sys
from safetensors import safe_open
p=sys.argv[1]
with safe_open(p,framework='pt',device='cpu') as f:
    if not list(f.keys()): raise SystemExit('empty safetensors:'+p)
print('QWEN_SAFETENSORS_OK',p)
PY
done < <(find -L "$QMODEL" -type f -name '*.safetensors' -size +1M | sort)
"$ENVS/qwen3-tts/bin/python" - <<'PY'
import torch
assert torch.cuda.is_available(), 'Qwen CUDA unavailable'
print('QWEN_CUDA_OK',torch.__version__,torch.version.cuda,torch.cuda.get_device_name(0))
PY
mark qwen3_tts PASS

# LatentSync was already made persistent; validate rather than rebuild unless it is broken.
if ! env_persistent "$ENVS/latentsync/bin/python"; then
  echo REPAIR_LATENTSYNC_PERSISTENT_PYTHON
  rm -rf "$ENVS/latentsync"
  uv venv --python "$PY310" "$ENVS/latentsync"
  uv pip install --python "$ENVS/latentsync/bin/python" torch torchvision --index-url https://download.pytorch.org/whl/cu128
  awk '!/^torch==/ && !/^torchvision==/ && !/^--extra-index-url/' "$SRC/LatentSync/requirements.txt" > "$STATUS/latentsync-requirements-blackwell.txt"
  uv pip install --python "$ENVS/latentsync/bin/python" -r "$STATUS/latentsync-requirements-blackwell.txt"
  uv pip install --python "$ENVS/latentsync/bin/python" huggingface-hub hf_xet
fi
test -s "$SRC/LatentSync/checkpoints/whisper/tiny.pt" || fail "LatentSync whisper checkpoint missing"
test -s "$SRC/LatentSync/checkpoints/latentsync_unet.pt" || fail "LatentSync UNet checkpoint missing"
"$ENVS/latentsync/bin/python" - <<'PY'
import torch
assert torch.cuda.is_available(), 'LatentSync CUDA unavailable'
print('LATENTSYNC_CUDA_OK',torch.__version__,torch.version.cuda,torch.cuda.get_device_name(0))
PY
mark latentsync PASS
mark latentsync_runtime_persistent PASS

# LTX code/env: rebuild the disposable .venv against persistent managed Python.
cd "$SRC/LTX-2"
if ! env_persistent "$SRC/LTX-2/.venv/bin/python"; then
  echo REPAIR_LTX_PERSISTENT_PYTHON
  rm -rf .venv
  UV_PROJECT_ENVIRONMENT="$SRC/LTX-2/.venv" uv sync --python "$PY312" --extra natten || UV_PROJECT_ENVIRONMENT="$SRC/LTX-2/.venv" uv sync --python "$PY312"
else
  UV_PROJECT_ENVIRONMENT="$SRC/LTX-2/.venv" uv sync --python "$PY312" --extra natten || UV_PROJECT_ENVIRONMENT="$SRC/LTX-2/.venv" uv sync --python "$PY312"
fi
LTXPY="$SRC/LTX-2/.venv/bin/python"
uv pip install --python "$LTXPY" huggingface-hub hf_xet safetensors
"$LTXPY" -c 'import ltx_pipelines,torch; assert torch.cuda.is_available(); print("LTX_IMPORT_CUDA_OK",torch.__version__,torch.version.cuda,torch.cuda.get_device_name(0))' || fail "LTX import/CUDA failed"
mark ltx25_code PASS

HF="$SRC/LTX-2/.venv/bin/hf"
[ -x "$HF" ] || HF="$ENVS/qwen3-tts/bin/hf"
[ -x "$HF" ] || fail "hf CLI missing"

BASE_FILES=(
  diffusion_models/ltx-2.5-22b-distilled-transformer-bf16.safetensors
  text_encoders/gemma4-12b-with-proj-ltx-2.5-bf16.safetensors
  vae/ltx-2.5-video-vae-bf16.safetensors
  vae/ltx-2.5-audio-vae-bf16.safetensors
  model_patches/ltx-2.5-duration-head-bf16.safetensors
  latent_upscale_models/ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors
  latent_upscale_models/ltx-2.5-latent-temporal-upscaler-x2-bf16-1.0.safetensors
)
echo DOWNLOAD_OR_RESUME_LTX25_BASE
HF_HUB_ENABLE_HF_TRANSFER=0 "$HF" download Lightricks/LTX-2.5 "${BASE_FILES[@]}" --local-dir "$MODELS/ltx-2.5" || {
  mark ltx25_models BLOCKED_HF_ACCESS
  fail "LTX-2.5 gated model download failed; HF token/access required"
}

DETAIL_DIR="$MODELS/ltx-2.5/loras"
DETAIL="$DETAIL_DIR/ltx-2.5-22b-ic-lora-pixel-spatial-upscaler-x2-1.0.safetensors"
mkdir -p "$DETAIL_DIR"
echo DOWNLOAD_OR_RESUME_DFR_DETAILER
HF_HUB_ENABLE_HF_TRANSFER=0 "$HF" download Lightricks/LTX-2.5-22b-IC-LoRA-Pixel-Spatial-Upscaler \
  ltx-2.5-22b-ic-lora-pixel-spatial-upscaler-x2-1.0.safetensors --local-dir "$DETAIL_DIR" || {
  mark ltx25_dfr BLOCKED_HF_ACCESS
  fail "DFR detailing LoRA download failed; HF token/access required"
}

# Verify every required artifact exists, has no unfinished sibling, and has a readable safetensors header.
REQUIRED=("${BASE_FILES[@]}" "loras/ltx-2.5-22b-ic-lora-pixel-spatial-upscaler-x2-1.0.safetensors")
for rel in "${REQUIRED[@]}"; do
  p="$MODELS/ltx-2.5/$rel"
  test -s "$p" || fail "required model missing:$rel"
  case "$p" in *.safetensors) "$LTXPY" - "$p" <<'PY'
import sys
from safetensors import safe_open
p=sys.argv[1]
with safe_open(p,framework='pt',device='cpu') as f:
    keys=list(f.keys())
    if not keys: raise SystemExit('empty safetensors:'+p)
print('SAFETENSORS_OK',p,len(keys))
PY
  ;; esac
done
if find "$MODELS/ltx-2.5" -type f \( -name '*.incomplete' -o -name '*.part' \) -print -quit | grep -q .; then
  fail "partial model download remains"
fi
mark ltx25_models PASS
mark ltx25_dfr_models PASS

cat > "$ROOT/STACK.json" <<'JSON'
{
  "root":"/workspace/ctnetwork-local",
  "approval_gate":true,
  "publish_default":false,
  "narration_primary":"qwen3-tts-1.7b",
  "lip_sync_primary":"latentsync-1.6",
  "video_primary":"ltx-2.5",
  "video_premium":"ltx-2.5-dfr",
  "assembly":"ffmpeg",
  "ready_dir":"/workspace/ctnetwork-local/ready_for_approval"
}
JSON
ffmpeg -version | head -n1
printf 'PASS\n' > "$STATUS/final_repair.status"
printf 'PASS\n' > "$STATUS/install.status"
echo "[$(stamp)] CTNETWORK FINAL LTX REPAIR PASS"
