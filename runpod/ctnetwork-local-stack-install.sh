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

# RunPod images may export this even when hf_transfer is absent. Disable it globally;
# hf_xet is installed explicitly in each model environment instead.
export HF_HUB_ENABLE_HF_TRANSFER=0

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
  fi
  export PATH="$HOME/.local/bin:$PATH"
  uv --version
  mark system PASS
}

install_core() {
  phase CORE_ENV
  export PATH="$HOME/.local/bin:$PATH"
  uv python install 3.12
  if [ ! -x "$ENVS/core/bin/python" ]; then
    uv venv --python 3.12 "$ENVS/core"
  fi
  uv pip install --python "$ENVS/core/bin/python" \
    fastapi 'uvicorn[standard]' pydantic pyyaml typer rich tenacity filelock psutil watchdog \
    httpx orjson sqlalchemy aiosqlite numpy scipy soundfile librosa pyloudnorm pedalboard \
    noisereduce ffmpeg-python scenedetect opencv-python-headless faster-whisper pillow \
    huggingface-hub hf_xet
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
  if [ ! -x "$ENVS/qwen3-tts/bin/python" ]; then
    uv venv --python 3.12 "$ENVS/qwen3-tts"
  fi
  uv pip install --python "$ENVS/qwen3-tts/bin/python" torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
  uv pip install --python "$ENVS/qwen3-tts/bin/python" -e "$SRC/Qwen3-TTS"
  uv pip install --python "$ENVS/qwen3-tts/bin/python" huggingface-hub hf_xet

  QMODEL="$MODELS/qwen3-tts/1.7B-Base"
  mkdir -p "$QMODEL"
  if ! find "$QMODEL" -type f \( -name '*.safetensors' -o -name '*.bin' \) -print -quit | grep -q .; then
    [ "$(free_gb)" -ge 18 ] || { mark qwen3_tts BLOCKED_LOW_DISK; return 11; }
    HF_HUB_ENABLE_HF_TRANSFER=0 "$ENVS/qwen3-tts/bin/hf" download Qwen/Qwen3-TTS-12Hz-1.7B-Base --local-dir "$QMODEL"
  fi
  find "$QMODEL" -type f \( -name '*.safetensors' -o -name '*.bin' \) -print -quit | grep -q . || { mark qwen3_tts MODEL_MISSING; return 12; }
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
  if [ ! -x "$ENVS/latentsync/bin/python" ]; then
    uv venv --python 3.10 "$ENVS/latentsync"
  fi
  uv pip install --python "$ENVS/latentsync/bin/python" torch torchvision --index-url https://download.pytorch.org/whl/cu128
  awk '!/^torch==/ && !/^torchvision==/ && !/^--extra-index-url/' "$SRC/LatentSync/requirements.txt" > "$STATUS/latentsync-requirements-blackwell.txt"
  uv pip install --python "$ENVS/latentsync/bin/python" -r "$STATUS/latentsync-requirements-blackwell.txt"
  uv pip install --python "$ENVS/latentsync/bin/python" huggingface-hub hf_xet
  mkdir -p "$SRC/LatentSync/checkpoints"
  HF_HUB_ENABLE_HF_TRANSFER=0 "$ENVS/latentsync/bin/huggingface-cli" download ByteDance/LatentSync-1.6 whisper/tiny.pt --local-dir "$SRC/LatentSync/checkpoints"
  HF_HUB_ENABLE_HF_TRANSFER=0 "$ENVS/latentsync/bin/huggingface-cli" download ByteDance/LatentSync-1.6 latentsync_unet.pt --local-dir "$SRC/LatentSync/checkpoints"
  test -s "$SRC/LatentSync/checkpoints/whisper/tiny.pt" || { mark latentsync CHECKPOINT_MISSING_WHISPER; return 21; }
  test -s "$SRC/LatentSync/checkpoints/latentsync_unet.pt" || { mark latentsync CHECKPOINT_MISSING_UNET; return 22; }
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

  [ "$(free_gb)" -ge 90 ] || { mark ltx25_models BLOCKED_LOW_DISK_NEED_90GB_FREE; return 31; }
  uv pip install --python .venv/bin/python huggingface-hub hf_xet
  [ -n "${HF_TOKEN:-}" ] && .venv/bin/hf auth login --token "$HF_TOKEN" >/dev/null 2>&1 || true
  HF_HUB_ENABLE_HF_TRANSFER=0 .venv/bin/hf download Lightricks/LTX-2.5 \
    diffusion_models/ltx-2.5-22b-distilled-transformer-bf16.safetensors \
    text_encoders/gemma4-12b-with-proj-ltx-2.5-bf16.safetensors \
    vae/ltx-2.5-video-vae-bf16.safetensors \
    vae/ltx-2.5-audio-vae-bf16.safetensors \
    model_patches/ltx-2.5-duration-head-bf16.safetensors \
    latent_upscale_models/ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors \
    --local-dir "$MODELS/ltx-2.5"
  test -s "$MODELS/ltx-2.5/diffusion_models/ltx-2.5-22b-distilled-transformer-bf16.safetensors" || { mark ltx25_models TRANSFORMER_MISSING; return 32; }
  test -s "$MODELS/ltx-2.5/text_encoders/gemma4-12b-with-proj-ltx-2.5-bf16.safetensors" || { mark ltx25_models TEXT_ENCODER_MISSING; return 33; }
  test -s "$MODELS/ltx-2.5/vae/ltx-2.5-video-vae-bf16.safetensors" || { mark ltx25_models VIDEO_VAE_MISSING; return 34; }
  test -s "$MODELS/ltx-2.5/vae/ltx-2.5-audio-vae-bf16.safetensors" || { mark ltx25_models AUDIO_VAE_MISSING; return 35; }
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
  "lip_sync_primary": "latentsync-1.6",
  "lip_sync_experimental": "ltx-2.3-dub-it",
  "video_primary": "ltx-2.5",
  "assembly": "ffmpeg",
  "qc": ["ffprobe", "loudness", "silence", "blackframe", "duration", "aspect", "audio_present", "stage_checksums"],
  "workspace": "/workspace/ctnetwork-local",
  "ready_dir": "/workspace/ctnetwork-local/ready_for_approval"
}
EOF
  cat > "$BIN/ctn-lipsync-test" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=/workspace/ctnetwork-local
VIDEO=${1:?usage: ctn-lipsync-test input_video input_audio [output]}
AUDIO=${2:?usage: ctn-lipsync-test input_video input_audio [output]}
OUT=${3:-$ROOT/ready_for_approval/lipsync-test.mp4}
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
EOF
  chmod +x "$BIN/ctn-lipsync-test"
  mark runtime PASS
}

verify() {
  phase VERIFY
  local bad=0
  "$BIN/ctn-health" || true
  test -x "$ENVS/core/bin/python" && mark verify_core PASS || { mark verify_core FAIL; bad=1; }
  test "$(cat "$STATUS/qwen3_tts.status" 2>/dev/null || true)" = PASS && mark verify_qwen PASS || { mark verify_qwen FAIL; bad=1; }
  test "$(cat "$STATUS/latentsync.status" 2>/dev/null || true)" = PASS && mark verify_latentsync PASS || { mark verify_latentsync FAIL; bad=1; }
  test "$(cat "$STATUS/ltx25_models.status" 2>/dev/null || true)" = PASS && mark verify_ltx25 PASS || { mark verify_ltx25 FAIL; bad=1; }
  test -x "$BIN/ctn-lipsync-test" || { mark verify_lipsync_wrapper FAIL; bad=1; }
  if [ "$bad" -ne 0 ]; then
    echo FAIL > "$STATUS/install.status"
    return 41
  fi
  echo PASS > "$STATUS/install.status"
  mark verify_lipsync_wrapper PASS
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
  resume)
    install_qwen_tts
    install_latentsync
    install_ltx25
    write_runtime
    verify
    ;;
  verify) write_runtime; verify ;;
  *) echo "unsupported action: $ACTION"; exit 64 ;;
esac
