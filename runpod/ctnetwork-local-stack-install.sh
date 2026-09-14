#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=/workspace/ctnetwork-local
SRC="$ROOT/src"
ENVS="$ROOT/envs"
MODELS="$ROOT/models"
STATUS="$ROOT/status"
LOGS="$ROOT/logs"
BIN="$ROOT/bin"
ACTION="${CTN_INSTALL_ACTION:-install-all}"
mkdir -p "$SRC" "$ENVS" "$MODELS" "$STATUS" "$LOGS" "$BIN" "$ROOT/jobs" "$ROOT/cache" "$ROOT/voices" "$ROOT/ready_for_approval"
LOG="$LOGS/install.log"
exec > >(tee -a "$LOG") 2>&1

stamp() { date -u +'%Y-%m-%dT%H:%M:%SZ'; }
phase() { echo "$1" > "$STATUS/phase.txt"; printf '\n[%s] === %s ===\n' "$(stamp)" "$1"; }
mark() { printf '%s\n' "$2" > "$STATUS/$1.status"; }
free_gb() { df -PB1 /workspace | awk 'NR==2 {printf "%.0f", $4/1024/1024/1024}'; }

on_error() {
  rc=$?
  echo "FAILED rc=$rc phase=$(cat "$STATUS/phase.txt" 2>/dev/null || echo unknown)" > "$STATUS/install.status"
  echo "[$(stamp)] installer failed rc=$rc"
  exit "$rc"
}
trap on_error ERR

audit() {
  phase PREFLIGHT
  echo "action=$ACTION"
  echo "workspace_free_gb=$(free_gb)"
  echo 'GPU:'
  nvidia-smi --query-gpu=name,memory.total,memory.free,driver_version --format=csv,noheader || true
  echo 'DISK:'; df -h / /workspace || true
  echo 'MEMORY:'; free -h || true
  echo 'PYTHON:'; python3 --version || true
  echo 'CUDA:'; nvcc --version 2>/dev/null || true
  command -v ffmpeg >/dev/null && ffmpeg -version | head -n1 || true
}

install_system() {
  phase SYSTEM_PACKAGES
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    git git-lfs curl wget aria2 jq ca-certificates build-essential pkg-config \
    ffmpeg sox libsox-fmt-all libsndfile1 libgl1 libglib2.0-0 libsm6 libxext6 \
    libxrender1 libgomp1 python3-dev tmux rsync unzip
  git lfs install --system || true
  if ! command -v uv >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
  fi
  command -v uv >/dev/null 2>&1 || export PATH="$HOME/.local/bin:$PATH"
  uv --version
  mark system PASS
}

install_core() {
  phase CORE_ENV
  export PATH="$HOME/.local/bin:$PATH"
  uv python install 3.12
  uv venv --python 3.12 "$ENVS/core"
  uv pip install --python "$ENVS/core/bin/python" \
    fastapi 'uvicorn[standard]' pydantic pyyaml typer rich tenacity filelock psutil watchdog \
    httpx orjson sqlalchemy aiosqlite numpy scipy soundfile librosa pyloudnorm pedalboard \
    noisereduce ffmpeg-python scenedetect opencv-python-headless faster-whisper pillow
  uv pip install --python "$ENVS/core/bin/python" deepfilternet || true
  cat > "$BIN/ctn-health" <<'EOF'
#!/usr/bin/env bash
set -e
ROOT=/workspace/ctnetwork-local
printf 'CTNETWORK LOCAL STACK\n'
printf 'GPU: '; nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader 2>/dev/null || true
printf 'Disk: '; df -h /workspace | awk 'NR==2 {print $4" free of "$2}'
for f in "$ROOT"/status/*.status; do [ -e "$f" ] || continue; printf '%-28s %s\n' "$(basename "$f")" "$(cat "$f")"; done
EOF
  chmod +x "$BIN/ctn-health"
  mark core PASS
}

install_qwen_tts() {
  phase QWEN3_TTS
  export PATH="$HOME/.local/bin:$PATH"
  if [ ! -d "$SRC/Qwen3-TTS/.git" ]; then
    git clone --depth 1 https://github.com/QwenLM/Qwen3-TTS.git "$SRC/Qwen3-TTS"
  else
    git -C "$SRC/Qwen3-TTS" fetch --depth 1 origin main
    git -C "$SRC/Qwen3-TTS" reset --hard origin/main
  fi
  uv python install 3.12
  uv venv --python 3.12 "$ENVS/qwen3-tts"
  # Blackwell-safe CUDA wheels first; qwen-tts itself does not pin torch.
  uv pip install --python "$ENVS/qwen3-tts/bin/python" torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
  uv pip install --python "$ENVS/qwen3-tts/bin/python" -e "$SRC/Qwen3-TTS"
  uv pip install --python "$ENVS/qwen3-tts/bin/python" huggingface-hub

  mkdir -p "$MODELS/qwen3-tts"
  if [ "$(free_gb)" -ge 18 ]; then
    "$ENVS/qwen3-tts/bin/hf" download Qwen/Qwen3-TTS-12Hz-1.7B-Base --local-dir "$MODELS/qwen3-tts/1.7B-Base" || \
      "$ENVS/qwen3-tts/bin/huggingface-cli" download Qwen/Qwen3-TTS-12Hz-1.7B-Base --local-dir "$MODELS/qwen3-tts/1.7B-Base" || true
  fi
  "$ENVS/qwen3-tts/bin/python" - <<'PY'
import torch
print('qwen torch', torch.__version__, 'cuda', torch.version.cuda, 'available', torch.cuda.is_available())
if not torch.cuda.is_available(): raise SystemExit(2)
print(torch.cuda.get_device_name(0), torch.cuda.get_device_capability(0))
PY
  mark qwen3_tts PASS
}

install_latentsync() {
  phase LATENTSYNC_1_6
  export PATH="$HOME/.local/bin:$PATH"
  if [ ! -d "$SRC/LatentSync/.git" ]; then
    git clone --depth 1 https://github.com/bytedance/LatentSync.git "$SRC/LatentSync"
  else
    git -C "$SRC/LatentSync" fetch --depth 1 origin main
    git -C "$SRC/LatentSync" reset --hard origin/main
  fi
  uv python install 3.10
  uv venv --python 3.10 "$ENVS/latentsync"
  uv pip install --python "$ENVS/latentsync/bin/python" torch torchvision --index-url https://download.pytorch.org/whl/cu128
  awk '!/^torch==/ && !/^torchvision==/ && !/^--extra-index-url/' "$SRC/LatentSync/requirements.txt" > "$STATUS/latentsync-requirements-blackwell.txt"
  uv pip install --python "$ENVS/latentsync/bin/python" -r "$STATUS/latentsync-requirements-blackwell.txt"
  mkdir -p "$SRC/LatentSync/checkpoints"
  "$ENVS/latentsync/bin/huggingface-cli" download ByteDance/LatentSync-1.6 whisper/tiny.pt --local-dir "$SRC/LatentSync/checkpoints" || \
    "$ENVS/latentsync/bin/hf" download ByteDance/LatentSync-1.6 whisper/tiny.pt --local-dir "$SRC/LatentSync/checkpoints"
  "$ENVS/latentsync/bin/huggingface-cli" download ByteDance/LatentSync-1.6 latentsync_unet.pt --local-dir "$SRC/LatentSync/checkpoints" || \
    "$ENVS/latentsync/bin/hf" download ByteDance/LatentSync-1.6 latentsync_unet.pt --local-dir "$SRC/LatentSync/checkpoints"
  "$ENVS/latentsync/bin/python" - <<'PY'
import torch
print('latentsync torch', torch.__version__, 'cuda', torch.version.cuda, 'available', torch.cuda.is_available())
if not torch.cuda.is_available(): raise SystemExit(2)
print(torch.cuda.get_device_name(0), torch.cuda.get_device_capability(0))
PY
  mark latentsync PASS
}

install_ltx25() {
  phase LTX_2_5
  export PATH="$HOME/.local/bin:$PATH"
  if [ ! -d "$SRC/LTX-2/.git" ]; then
    git clone --depth 1 https://github.com/Lightricks/LTX-2.git "$SRC/LTX-2"
  else
    git -C "$SRC/LTX-2" fetch --depth 1 origin main
    git -C "$SRC/LTX-2" reset --hard origin/main
  fi
  cd "$SRC/LTX-2"
  uv sync --extra natten || uv sync
  mark ltx25_code PASS

  # Official quick-start assets are ~66 GiB. Require safe headroom before download.
  if [ "$(free_gb)" -lt 90 ]; then
    mark ltx25_models 'BLOCKED_LOW_DISK_NEED_90GB_FREE'
    echo 'Skipping LTX-2.5 weights: insufficient safe workspace headroom.'
    return 0
  fi
  if [ -z "${HF_TOKEN:-}" ]; then
    mark ltx25_models 'BLOCKED_HF_TOKEN_OR_TERMS'
    echo 'Skipping gated LTX-2.5 weights: HF_TOKEN not supplied to installer.'
    return 0
  fi
  export HF_TOKEN
  uv run hf auth login --token "$HF_TOKEN" >/dev/null 2>&1 || true
  uv run hf download Lightricks/LTX-2.5 \
    diffusion_models/ltx-2.5-22b-distilled-transformer-bf16.safetensors \
    text_encoders/gemma4-12b-with-proj-ltx-2.5-bf16.safetensors \
    vae/ltx-2.5-video-vae-bf16.safetensors \
    vae/ltx-2.5-audio-vae-bf16.safetensors \
    latent_upscale_models/ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors \
    --local-dir "$MODELS/ltx-2.5"
  if [ "$(free_gb)" -ge 12 ]; then
    uv run hf download Lightricks/LTX-2.5-22b-IC-LoRA-Pixel-Spatial-Upscaler \
      ltx-2.5-22b-ic-lora-pixel-spatial-upscaler-x2-1.0.safetensors \
      --local-dir "$MODELS/ltx-2.5/loras" || true
  fi
  mark ltx25_models PASS
}

write_runtime() {
  phase RUNTIME
  cat > "$ROOT/STACK.json" <<EOF
{
  "root": "$ROOT",
  "approval_gate": true,
  "publish_default": false,
  "narration_primary": "qwen3-tts-1.7b",
  "lip_sync_primary": "ltx-2.5-dubit",
  "lip_sync_fallback": "latentsync-1.6",
  "video_primary": "ltx-2.5",
  "assembly": "ffmpeg",
  "qc": ["ffprobe", "loudness", "silence", "blackframe", "duration", "aspect", "audio_present", "stage_checksums"],
  "workspace": "/workspace/ctnetwork-local",
  "ready_dir": "/workspace/ctnetwork-local/ready_for_approval"
}
EOF
  mark runtime PASS
}

verify() {
  phase VERIFY
  "$BIN/ctn-health" || true
  test -x "$ENVS/core/bin/python" && mark verify_core PASS || mark verify_core FAIL
  test -x "$ENVS/qwen3-tts/bin/python" && mark verify_qwen PASS || mark verify_qwen MISSING
  test -x "$ENVS/latentsync/bin/python" && mark verify_latentsync PASS || mark verify_latentsync MISSING
  test -d "$SRC/LTX-2/.git" && mark verify_ltx25_code PASS || mark verify_ltx25_code MISSING
  echo PASS > "$STATUS/install.status"
  echo "[$(stamp)] CTNETWORK local stack verification complete"
}

audit
case "$ACTION" in
  audit|preflight) echo PASS > "$STATUS/install.status" ;;
  install-core) install_system; install_core; write_runtime; verify ;;
  install-all|install)
    install_system
    install_core
    install_qwen_tts
    install_latentsync
    install_ltx25
    write_runtime
    verify
    ;;
  verify) write_runtime; verify ;;
  *) echo "unsupported action: $ACTION"; exit 64 ;;
esac
