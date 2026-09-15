#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=/workspace/ctnetwork-local
STATUS="$ROOT/status"; READY="$ROOT/ready_for_approval"; SRC="$ROOT/src/LTX-2"; MODELS="$ROOT/models/ltx-2.5"
CORE="$ROOT/envs/core/bin/python"; LTXPY="$SRC/.venv/bin/python"
mkdir -p "$STATUS" "$READY" "$ROOT/runtime-logs" "$ROOT/secrets" "$ROOT/voices"
fail(){ echo "FINAL_CERT_FAIL:$*"; echo "FAILED:$*" > "$STATUS/final_certification.status"; exit 1; }

# ---------- CUDA / dependency gate ----------
"$CORE" - <<'PY'
import torch
assert torch.cuda.is_available(), 'CUDA unavailable'
print('CUDA_VERIFIED',torch.__version__,torch.version.cuda,torch.cuda.get_device_name(0),torch.cuda.get_device_capability(0))
PY
"$LTXPY" -c 'import ltx_pipelines,torch; assert torch.cuda.is_available(); print("LTX_IMPORT_OK",torch.__version__,torch.cuda.get_device_name(0))' || fail "LTX import failed"
for s in core qwen3_tts latentsync ltx25_code ltx25_models final_repair; do test "$(cat "$STATUS/$s.status" 2>/dev/null || true)" = PASS || fail "status $s not PASS"; done
echo PASS > "$STATUS/cuda_verified.status"

TRANS="$MODELS/diffusion_models/ltx-2.5-22b-distilled-transformer-bf16.safetensors"
TEXT="$MODELS/text_encoders/gemma4-12b-with-proj-ltx-2.5-bf16.safetensors"
VVIDEO="$MODELS/vae/ltx-2.5-video-vae-bf16.safetensors"
VAUDIO="$MODELS/vae/ltx-2.5-audio-vae-bf16.safetensors"
UPSCALE="$MODELS/latent_upscale_models/ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors"
TEMPUP="$MODELS/latent_upscale_models/ltx-2.5-latent-temporal-upscaler-x2-bf16-1.0.safetensors"
DETAIL="$MODELS/loras/ltx-2.5-22b-ic-lora-pixel-spatial-upscaler-x2-1.0.safetensors"
for f in "$TRANS" "$TEXT" "$VVIDEO" "$VAUDIO" "$UPSCALE" "$TEMPUP" "$DETAIL"; do test -s "$f" || fail "model missing $f"; done

# ---------- cheap base LTX generation ----------
BASE_OUT="$READY/ltx25-install-smoke.mp4"
rm -f "$BASE_OUT"
cd "$SRC"
"$LTXPY" -m ltx_pipelines.distilled \
  --transformer-path "$TRANS" --text-encoder-path "$TEXT" \
  --video-vae-path "$VVIDEO" --audio-vae-path "$VAUDIO" \
  --spatial-upsampler-path "$UPSCALE" \
  --width 512 --height 320 --num-frames 33 --seed 121 \
  --quantization fp8-cast --offload cpu \
  --output-path "$BASE_OUT" \
  --prompt "Cinematic CTNETWORK production studio, polished dark metal, realistic broadcast lighting, subtle controlled camera move, premium professional finish, no text, no captions."
test -s "$BASE_OUT" || fail "base smoke output missing"
BDUR=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$BASE_OUT")
BVID=$(ffprobe -v error -select_streams v -show_entries stream=index -of csv=p=0 "$BASE_OUT" | wc -l)
python3 -c "assert int('$BVID')>=1 and float('$BDUR')>0.5"
echo PASS > "$STATUS/ltx25_smoke.status"
echo PASS > "$STATUS/ltx_server_engine.status"

# ---------- premium DFR generation ----------
DFR_OUT="$READY/ltx25-dfr-install-smoke.mp4"
rm -f "$DFR_OUT"
"$LTXPY" -m ltx_pipelines.dfr_pipeline \
  --transformer-path "$TRANS" --text-encoder-path "$TEXT" \
  --video-vae-path "$VVIDEO" --audio-vae-path "$VAUDIO" \
  --detailing-lora "$DETAIL" --spatial-upsampler-path "$UPSCALE" \
  --width 512 --height 320 --num-frames 33 --seed 122 \
  --quantization fp8-cast --offload cpu \
  --output-path "$DFR_OUT" \
  --prompt "Premium cinematic CTNETWORK production stage, realistic surfaces, fine-detail broadcast lighting, subtle camera movement, polished commercial finish, no text, no captions."
test -s "$DFR_OUT" || fail "DFR smoke output missing"
DDUR=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$DFR_OUT")
DVID=$(ffprobe -v error -select_streams v -show_entries stream=index -of csv=p=0 "$DFR_OUT" | wc -l)
python3 -c "assert int('$DVID')>=1 and float('$DDUR')>0.5"
echo PASS > "$STATUS/ltx25_dfr.status"

# ---------- Qwen real voice-clone certification ----------
REF="$ROOT/voices/malik_reference.mp3"
REF_TEXT="$ROOT/voices/malik_reference.txt"
QTEXT="$ROOT/voices/final_cert_text.txt"
QOUT="$READY/qwen-final-cert.wav"
test -s "$REF" || fail "Malik reference audio missing"
cat > "$REF_TEXT" <<'TXT'
LeBron James has one of the greatest résumés basketball has ever seen. But greatest résumé and greatest player are not automatically the same thing. Tonight, we put the GOAT case on trial. Finals record. Team construction. Peak versus longevity. No hate. No fan fiction. Just the strongest case the other side can make. Case made. You decide.
TXT
cat > "$QTEXT" <<'TXT'
CTNETWORK local production is online. This narration, video generation, assembly, and quality control test is running entirely through the local factory.
TXT
rm -f "$QOUT"
"$ROOT/envs/qwen3-tts/bin/python" "$ROOT/controller/ctnetwork_qwen_narrate.py" \
  --text-file "$QTEXT" --ref-audio "$REF" --ref-text-file "$REF_TEXT" --output "$QOUT" --language English
test -s "$QOUT" || fail "Qwen certification audio missing"
QDUR=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$QOUT")
QAUD=$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$QOUT" | wc -l)
python3 -c "assert int('$QAUD')>=1 and float('$QDUR')>1.0"
echo PASS > "$STATUS/qwen_smoke.status"

# ---------- real local LTX runtime server ----------
pkill -f 'uvicorn ctnetwork_ltx_runtime:app' 2>/dev/null || true
PYTHONPATH="$ROOT/controller" nohup "$CORE" -m uvicorn ctnetwork_ltx_runtime:app --host 127.0.0.1 --port 8090 \
  > "$ROOT/runtime-logs/ltx-runtime.log" 2>&1 &
echo $! > "$ROOT/runtime-logs/ltx-runtime.pid"
for i in $(seq 1 30); do sleep 1; curl -fsS http://127.0.0.1:8090/health > /tmp/ltx-health.json && break || true; done
"$CORE" - <<'PY'
import json
x=json.load(open('/tmp/ltx-health.json')); assert x['ok'] is True, x; print('LTX_RUNTIME_HEALTH_PASS',x)
PY
echo PASS > "$STATUS/ltx_runtime_server.status"

# Submit a real runtime job, poll status, verify and retrieve the artifact.
cat > /tmp/ltx-runtime-job.json <<'JSON'
{"prompt":"CTNETWORK metallic studio ident in a dark broadcast room, realistic reflections and a slow cinematic push, no text, no captions.","quality":"distilled","width":512,"height":320,"frames":17,"seed":123}
JSON
curl -fsS -X POST http://127.0.0.1:8090/v1/generate -H 'Content-Type: application/json' --data-binary @/tmp/ltx-runtime-job.json > /tmp/ltx-runtime-start.json
RID=$(python3 -c 'import json;print(json.load(open("/tmp/ltx-runtime-start.json"))["job_id"])')
RSTATUS=""
for i in $(seq 1 180); do
  curl -fsS "http://127.0.0.1:8090/v1/jobs/$RID" > /tmp/ltx-runtime-status.json
  RSTATUS=$(python3 -c 'import json;print(json.load(open("/tmp/ltx-runtime-status.json"))["status"])')
  echo "LTX_RUNTIME_JOB status=$RSTATUS attempt=$i"
  [[ "$RSTATUS" == completed || "$RSTATUS" == failed ]] && break
  sleep 5
done
[[ "$RSTATUS" == completed ]] || { cat /tmp/ltx-runtime-status.json; fail "LTX runtime job failed/timeout"; }
curl -fsS "http://127.0.0.1:8090/v1/jobs/$RID/artifact" -o "$READY/ltx-runtime-retrieved.mp4"
test -s "$READY/ltx-runtime-retrieved.mp4" || fail "runtime artifact retrieval failed"
ffprobe -v error -show_streams -show_format -of json "$READY/ltx-runtime-retrieved.mp4" > "$READY/ltx-runtime-retrieved.ffprobe.json"
echo PASS > "$STATUS/ltx_runtime_job.status"

# ---------- real bridge, real controller, no mock ----------
CONTROL="$ROOT/bin/ctnetwork-production-control"
cat > "$CONTROL" <<EOF
#!/usr/bin/env bash
exec "$CORE" "$ROOT/controller/ctnetwork_production_control.py" "\$@"
EOF
chmod +x "$CONTROL"
TOKEN_FILE="$ROOT/secrets/bridge_token"
if [ ! -s "$TOKEN_FILE" ]; then openssl rand -hex 32 > "$TOKEN_FILE"; chmod 600 "$TOKEN_FILE"; fi
TOKEN=$(cat "$TOKEN_FILE")
pkill -f 'uvicorn app:app' 2>/dev/null || true
cd "$ROOT/bridge"
LTX_BRIDGE_TOKEN="$TOKEN" LTX_CONTROL_CMD="$CONTROL" LTX_BRIDGE_STATE_DIR="$ROOT/bridge-state" LTX_CONTROL_TIMEOUT_SECONDS=7200 \
  PYTHONPATH="$ROOT/bridge" nohup "$CORE" -m uvicorn app:app --host 127.0.0.1 --port 8080 \
  > "$ROOT/runtime-logs/bridge.log" 2>&1 &
echo $! > "$ROOT/runtime-logs/bridge.pid"
for i in $(seq 1 30); do sleep 1; curl -fsS http://127.0.0.1:8080/health > /tmp/bridge-health.json && break || true; done
"$CORE" - <<'PY'
import json
x=json.load(open('/tmp/bridge-health.json'))
assert x['ok'] is True and x['controller_configured'] is True and x['token_configured'] is True and x['publishing_locked'] is True and x.get('mock_controller') is False, x
print('BRIDGE_HEALTH_PASS',x)
PY

# ---------- CTNETWORK -> bridge -> Qwen/LTX -> package end-to-end ----------
cat > /tmp/bridge-e2e.json <<JSON
{
  "show":"The Case Against",
  "episode":"Local Factory Commissioning Test",
  "narrator":{
    "voice_reference":"$REF",
    "voice_reference_text":"$(cat "$REF_TEXT" | sed 's/"/\\"/g')",
    "language":"English"
  },
  "shorts_count":1,
  "auto_fix":true,
  "publish":false,
  "metadata":{
    "script":"CTNETWORK local factory commissioning is complete. This package was produced locally and stops at the approval gate.",
    "visual_prompt":"Cinematic investigative documentary studio, premium dark broadcast lighting, polished realistic surfaces, restrained camera movement, no text, no captions.",
    "quality":"distilled",
    "width":512,
    "height":320,
    "frames":17,
    "seed":124,
    "short_seconds":3
  }
}
JSON
curl -fsS -X POST http://127.0.0.1:8080/v1/production/start \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' --data-binary @/tmp/bridge-e2e.json > /tmp/bridge-e2e-start.json
cat /tmp/bridge-e2e-start.json
BJOB=$(python3 -c 'import json;d=json.load(open("/tmp/bridge-e2e-start.json")); print(d["job_id"])')
BSTAT=$(python3 -c 'import json;d=json.load(open("/tmp/bridge-e2e-start.json")); print(d["status"])')
[[ "$BSTAT" == ready_for_review ]] || fail "bridge end-to-end status=$BSTAT"
curl -fsS -H "Authorization: Bearer $TOKEN" "http://127.0.0.1:8080/v1/production/$BJOB" > /tmp/bridge-e2e-status.json
curl -fsS -H "Authorization: Bearer $TOKEN" "http://127.0.0.1:8080/v1/production/$BJOB/outputs" > /tmp/bridge-e2e-outputs.json
MASTER=$(python3 -c 'import json;d=json.load(open("/tmp/bridge-e2e-outputs.json")); o=d["outputs"]; print(o.get("master", ""))')
test -s "$MASTER" || fail "bridge master missing"
ffprobe -v error -show_streams -show_format -of json "$MASTER" > "$READY/bridge-e2e-master.ffprobe.json"
APPROVAL=$(dirname "$MASTER")/approval.json
test -s "$APPROVAL" || fail "approval manifest missing"
"$CORE" - "$APPROVAL" <<'PY'
import json,sys
x=json.load(open(sys.argv[1])); assert x['state']=='READY_FOR_APPROVAL'; assert x['publish_allowed'] is False; assert x['requires_manual_approval'] is True
print('APPROVAL_GATE_PASS',x['job_id'])
PY

# Retrieve the real MP4 through the authenticated bridge, then verify it matches the source artifact.
RETRIEVED="$READY/bridge-retrieved-master.mp4"
curl -fsS -H "Authorization: Bearer $TOKEN" \
  "http://127.0.0.1:8080/v1/production/$BJOB/artifact/master" -o "$RETRIEVED"
test -s "$RETRIEVED" || fail "bridge artifact download missing"
ffprobe -v error -show_streams -show_format -of json "$RETRIEVED" > "$READY/bridge-retrieved-master.ffprobe.json"
SRC_SHA=$(sha256sum "$MASTER" | awk '{print $1}')
GET_SHA=$(sha256sum "$RETRIEVED" | awk '{print $1}')
[[ "$SRC_SHA" == "$GET_SHA" ]] || fail "retrieved bridge artifact checksum mismatch"
echo "BRIDGE_ARTIFACT_RETRIEVAL_PASS sha256=$GET_SHA"

echo PASS > "$STATUS/ctnetwork_bridge.status"
echo PASS > "$STATUS/bridge_artifact_retrieval.status"
echo PASS > "$STATUS/end_to_end.status"
echo PASS > "$STATUS/final_certification.status"
printf '%s\n' "$BJOB" > "$STATUS/final_e2e_job_id.txt"
printf '%s\n' "$MASTER" > "$STATUS/final_e2e_master.txt"
echo "CTNETWORK_FINAL_CERTIFICATION_PASS job=$BJOB master=$MASTER"
