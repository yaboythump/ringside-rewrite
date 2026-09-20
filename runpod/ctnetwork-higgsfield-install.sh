#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${CTN_ROOT:-/workspace/ctnetwork-local}"
VENV="$ROOT/envs/higgsfield"
CONTROLLER="$ROOT/controller"
BIN="$ROOT/bin"
SRC="${CTN_HF_HELPER_SRC:-/tmp/ctnetwork_higgsfield_video.py}"

echo "=== CTNETWORK HIGGSFIELD INSTALL ==="
mkdir -p "$CONTROLLER" "$BIN" "$ROOT/status"

PYTHON=""
for candidate in /usr/bin/python3 /usr/bin/python python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 || [[ -x "$candidate" ]]; then
    PYTHON="$candidate"
    break
  fi
done
[[ -n "$PYTHON" ]] || { echo "Python not found"; exit 10; }

if [[ ! -x "$VENV/bin/python" ]]; then
  "$PYTHON" -m venv "$VENV"
fi

"$VENV/bin/python" -m pip install --upgrade pip
"$VENV/bin/python" -m pip install "higgsfield-client==0.2.0" "requests>=2.31,<3"

install -m 0755 "$SRC" "$CONTROLLER/ctnetwork_higgsfield_video.py"

cat >"$BIN/ctn-kling" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec "$VENV/bin/python" "$CONTROLLER/ctnetwork_higgsfield_video.py" "\$@"
EOF
chmod +x "$BIN/ctn-kling"

cat >"$CONTROLLER/higgsfield-defaults.json" <<'EOF'
{
  "engine": "higgsfield",
  "model": "kling-video/v2.5-turbo/pro/image-to-video",
  "duration_seconds": 5,
  "cfg_scale": 0.5,
  "generated_audio": false,
  "aspect_target": "16:9",
  "fallback": "use_still_and_continue_assembly"
}
EOF

"$VENV/bin/python" - <<'PY'
import higgsfield_client
print("HIGGSFIELD_SDK_IMPORT_PASS")
PY

SELF_TEST=$("$BIN/ctn-kling" --self-test)
echo "$SELF_TEST"

if [[ -n "${HF_KEY:-}" || ( -n "${HF_API_KEY:-}" && -n "${HF_API_SECRET:-}" ) ]]; then
  KEY_STATUS=present
else
  KEY_STATUS=missing
fi

{
  echo "PASS"
  echo "installed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "sdk=higgsfield-client==0.2.0"
  echo "model=kling-video/v2.5-turbo/pro/image-to-video"
  echo "credential_status=$KEY_STATUS"
  echo "billable_generation_submitted=false"
} > "$ROOT/status/higgsfield.status"

echo "HIGGSFIELD_INSTALL_PASS"
echo "HIGGSFIELD_CREDENTIAL_STATUS=$KEY_STATUS"
echo "HIGGSFIELD_WRAPPER=$BIN/ctn-kling"
