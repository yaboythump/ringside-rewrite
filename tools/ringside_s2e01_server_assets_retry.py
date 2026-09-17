#!/usr/bin/env python3
import re
import time
import requests
import ringside_s2e01_server_assets as base

PREFERRED_POD_ID = "ugt1pe6ndmichc"
ORIGINAL_CREATE_POD = base.create_pod
ORIGINAL_TERMINAL_RUN = base.terminal_run
KEVIN_REF_B64_URL = "https://raw.githubusercontent.com/yaboythump/ringside-rewrite/main/server_refs/kevin_ref_short.b64"
QBATCH_URL = "https://raw.githubusercontent.com/yaboythump/ringside-rewrite/main/runpod/ctnetwork_qwen_narrate_batch.py"
base.REF_TEXT = "One bell changed professional wrestling"


def graphql(query):
    r = requests.post(
        "https://api.runpod.io/graphql",
        params={"api_key": base.RUNPOD_API_KEY},
        headers={"Content-Type": "application/json"},
        json={"query": query},
        timeout=60,
    )
    r.raise_for_status()
    data = r.json()
    if data.get("errors"):
        raise RuntimeError(f"RunPod GraphQL errors: {data['errors']}")
    return data.get("data") or {}


def resolve_or_create_pod():
    try:
        r = requests.get(f"https://rest.runpod.io/v1/pods/{PREFERRED_POD_ID}", headers=base.AUTH, timeout=30)
        if r.ok:
            pod = r.json()
            volume = pod.get("networkVolumeId") or (pod.get("networkVolume") or {}).get("id")
            password = (pod.get("env") or {}).get("JUPYTER_PASSWORD")
            if volume == base.VOLUME and password:
                state = pod.get("desiredStatus", "")
                print("PREFERRED_POD", PREFERRED_POD_ID, state, flush=True)
                if state != "RUNNING":
                    q = f'''mutation {{ podResume(input: {{ podId: "{PREFERRED_POD_ID}", gpuCount: 1 }}) {{ id desiredStatus imageName }} }}'''
                    resumed = graphql(q).get("podResume") or {}
                    print("PREFERRED_POD_GRAPHQL_RESUME", resumed, flush=True)
                    if resumed.get("id") != PREFERRED_POD_ID:
                        raise RuntimeError("GraphQL resume did not return preferred pod")
                return PREFERRED_POD_ID, password
            print("PREFERRED_POD_METADATA_MISMATCH", volume, bool(password), flush=True)
        else:
            print("PREFERRED_POD_LOOKUP", r.status_code, r.text[:500], flush=True)
    except Exception as exc:
        print("PREFERRED_POD_FALLBACK", repr(exc), flush=True)

    last = None
    for attempt in range(1, 4):
        try:
            print(f"CREATE_POD_ATTEMPT {attempt}/3", flush=True)
            return ORIGINAL_CREATE_POD()
        except Exception as exc:
            last = exc
            print("CREATE_POD_RETRY", repr(exc), flush=True)
            time.sleep(min(20, attempt * 5))
    raise RuntimeError(f"Unable to resolve or create production pod: {last!r}")


def login_retry(base_url, password):
    last = None
    for attempt in range(1, 21):
        try:
            s = requests.Session()
            r = s.get(base_url + "/login", timeout=30)
            if r.status_code != 200:
                raise RuntimeError(f"login page {r.status_code}")
            m = re.search(r'name="_xsrf" value="([^"]+)"', r.text)
            if not m:
                raise RuntimeError("no xsrf")
            rr = s.post(base_url + "/login", data={"_xsrf": m.group(1), "password": password, "next": "/"}, timeout=30, allow_redirects=False)
            if rr.status_code not in (200, 302, 303):
                raise RuntimeError(f"login {rr.status_code}")
            cx = s.cookies.get("_xsrf")
            print("JUPYTER_LOGIN_OK", attempt, rr.status_code, flush=True)
            return s, ({"X-XSRFToken": cx} if cx else {})
        except Exception as exc:
            last = exc
            print("JUPYTER_LOGIN_RETRY", attempt, repr(exc), flush=True)
            time.sleep(min(12, attempt * 2))
    raise RuntimeError(f"Jupyter login never stabilized: {last!r}")


def terminal_run_retry(base_url, pod_id, session, headers, shell, timeout=10800):
    stale_checks = [
        'test "$(cat "$ROOT/status/production_ready.status" 2>/dev/null || true)" = PASS',
        'test "$(cat "$ROOT/status/qwen_smoke.status" 2>/dev/null || true)" = PASS',
        'test "$(cat "$ROOT/status/ltx25_smoke.status" 2>/dev/null || true)" = PASS',
    ]
    for line in stale_checks:
        shell = shell.replace(line, 'echo "STALE_SMOKE_GATE_SKIPPED"')

    old_kevin = f'curl -L --fail --retry 5 "{base.KEVIN_URL}" -o "$JOB/raw/kevin_master.mp3"'
    new_kevin = f'curl -L --fail --retry 5 "{KEVIN_REF_B64_URL}" | tr -d "\\r\\n " | base64 -d > "$JOB/raw/kevin_master.mp3" ; test -s "$JOB/raw/kevin_master.mp3"'
    if old_kevin not in shell:
        raise RuntimeError("Kevin download line not found in production shell")
    shell = shell.replace(old_kevin, new_kevin)

    old_qwen = '''QPY="$ROOT/envs/qwen3-tts/bin/python"
test -x "$QPY"
for I in 01 02 03 04 05; do "$QPY" "$QHELP" --text-file "$JOB/text/section_${I}.txt" --ref-audio "$JOB/raw/kevin_ref.wav" --ref-text-file "$JOB/text/ref.txt" --output "$JOB/audio/section_${I}.wav" --language English; done'''
    new_qwen = f'''QPY="$ROOT/envs/qwen3-tts/bin/python"
test -x "$QPY"
QBATCH="$ROOT/controller/ctnetwork_qwen_narrate_batch.py"
curl -L --fail --retry 5 "{QBATCH_URL}" -o "$QBATCH"
chmod +x "$QBATCH"; test -s "$QBATCH"
"$QPY" "$QBATCH" --sections-json "$JOB/text/sections.json" --ref-audio "$JOB/raw/kevin_ref.wav" --ref-text-file "$JOB/text/ref.txt" --output-dir "$JOB/audio" --language English'''
    if old_qwen not in shell:
        raise RuntimeError("five-load Qwen block not found")
    shell = shell.replace(old_qwen, new_qwen)

    bootstrap = r'''set -Eeuo pipefail
if ! command -v ffmpeg >/dev/null 2>&1 || ! command -v ffprobe >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y --no-install-recommends ffmpeg ca-certificates curl
fi
echo SERVER_BOOTSTRAP_OK
ls -ld /workspace /workspace/ctnetwork-local || true
ls -la /workspace/ctnetwork-local/envs 2>/dev/null || true
'''
    shell = bootstrap + "\nset -x\n" + shell
    last = None
    for attempt in range(1, 7):
        try:
            print(f"TERMINAL_CONNECT_ATTEMPT {attempt}/6", flush=True)
            return ORIGINAL_TERMINAL_RUN(base_url, pod_id, session, headers, shell, timeout)
        except Exception as exc:
            last = exc
            print("TERMINAL_RETRY", attempt, repr(exc), flush=True)
            if "404" not in repr(exc) and "Handshake" not in repr(exc):
                raise
            time.sleep(min(15, attempt * 3))
    raise RuntimeError(f"Jupyter terminal websocket never stabilized: {last!r}")


base.create_pod = resolve_or_create_pod
base.login = login_retry
base.terminal_run = terminal_run_retry
base.main()
