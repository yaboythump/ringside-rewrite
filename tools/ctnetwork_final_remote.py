#!/usr/bin/env python3
"""Deploy and execute the final CTNETWORK repair/certification on one RunPod."""
from __future__ import annotations

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
PASSWORD = Path(os.environ["JUPYTER_PASSWORD_FILE"]).read_text().strip()
HF_TOKEN = os.environ.get("REMOTE_HF_TOKEN", "")
BASE = f"https://{POD_ID}-8888.proxy.runpod.net"
S = requests.Session()


def login():
    last = None
    for i in range(120):
        try:
            last = S.get(BASE + "/login", timeout=15)
            if last.status_code == 200:
                print(f"JUPYTER_READY attempt={i+1}", flush=True)
                break
        except Exception as exc:
            if i % 10 == 0:
                print("jupyter wait", repr(exc), flush=True)
        time.sleep(5)
    else:
        raise RuntimeError(f"Jupyter did not become ready; last={getattr(last,'status_code',None)}")
    m = re.search(r'name="_xsrf" value="([^"]+)"', last.text)
    if not m:
        raise RuntimeError("Jupyter XSRF token missing")
    r = S.post(
        BASE + "/login",
        data={"_xsrf": m.group(1), "password": PASSWORD, "next": "/"},
        allow_redirects=False,
        timeout=30,
    )
    if r.status_code not in (200, 302, 303):
        r.raise_for_status()
    xs = S.cookies.get("_xsrf")
    headers = {"X-XSRFToken": xs} if xs else {}
    S.get(BASE + "/api/status", headers=headers, timeout=30).raise_for_status()
    return headers


HEADERS = login()


def terminal():
    """Create a Jupyter terminal and tolerate RunPod's short HTTP/WebSocket readiness race."""
    last_exc = None
    for attempt in range(1, 41):
        name = None
        try:
            r = S.post(BASE + "/api/terminals", headers=HEADERS, json={}, timeout=30)
            r.raise_for_status()
            name = r.json()["name"]
            cookie = "; ".join(f"{c.name}={c.value}" for c in S.cookies)
            ws = websocket.create_connection(
                f"wss://{POD_ID}-8888.proxy.runpod.net/terminals/websocket/{name}",
                cookie=cookie,
                origin=BASE,
                timeout=30,
            )
            print(f"TERMINAL_READY attempt={attempt} name={name}", flush=True)
            return name, ws
        except Exception as exc:
            last_exc = exc
            print(f"terminal handshake attempt={attempt} failed: {exc!r}", flush=True)
            if name:
                try:
                    S.delete(BASE + f"/api/terminals/{name}", headers=HEADERS, timeout=10)
                except Exception:
                    pass
            time.sleep(3)
    raise RuntimeError(f"Jupyter terminal websocket never became ready: {last_exc!r}")


def run(command: str, timeout: int = 600, label: str = "remote") -> str:
    name, ws = terminal()
    marker = f"__CTN_{int(time.time()*1000)}__"
    wrapped = f"set +e\n{command}\nrc=$?\necho {marker}:$rc\n"
    ws.send(json.dumps(["stdin", wrapped]))
    out = ""
    rc = None
    deadline = time.time() + timeout
    try:
        while time.time() < deadline:
            try:
                msg = ws.recv()
            except Exception as exc:
                print(f"[{label}] websocket {exc!r}", flush=True)
                continue
            if not msg:
                continue
            try:
                d = json.loads(msg)
            except Exception:
                continue
            if isinstance(d, list) and len(d) >= 2 and d[0] == "stdout":
                text = d[1]
                out += text
                sys.stdout.write(text)
                sys.stdout.flush()
                m = re.search(re.escape(marker) + r":(\d+)", out)
                if m:
                    rc = int(m.group(1))
                    break
    finally:
        ws.close()
        try:
            S.delete(BASE + f"/api/terminals/{name}", headers=HEADERS, timeout=10)
        except Exception:
            pass
    if rc is None:
        raise RuntimeError(f"{label} timed out after {timeout}s")
    if rc != 0:
        raise RuntimeError(f"{label} failed rc={rc}\n{out[-6000:]}")
    return out


def deploy(local: str, remote: str, mode: str = "644"):
    data = Path(local).read_bytes()
    b64 = base64.b64encode(data).decode()
    parent = str(Path(remote).parent)
    run(
        f"mkdir -p {json.dumps(parent)}; echo {b64} | base64 -d > {json.dumps(remote)}; chmod {mode} {json.dumps(remote)}",
        180,
        "deploy",
    )
    print(f"DEPLOYED {local} -> {remote} bytes={len(data)}", flush=True)


def recover_existing_ltx_weights() -> str:
    """Find complete persistent LTX-2.5 files left by any prior install and relink them."""
    mapping = {
        "ltx-2.5-22b-distilled-transformer-bf16.safetensors": "diffusion_models/ltx-2.5-22b-distilled-transformer-bf16.safetensors",
        "gemma4-12b-with-proj-ltx-2.5-bf16.safetensors": "text_encoders/gemma4-12b-with-proj-ltx-2.5-bf16.safetensors",
        "ltx-2.5-video-vae-bf16.safetensors": "vae/ltx-2.5-video-vae-bf16.safetensors",
        "ltx-2.5-audio-vae-bf16.safetensors": "vae/ltx-2.5-audio-vae-bf16.safetensors",
        "ltx-2.5-duration-head-bf16.safetensors": "model_patches/ltx-2.5-duration-head-bf16.safetensors",
        "ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors": "latent_upscale_models/ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors",
        "ltx-2.5-latent-temporal-upscaler-x2-bf16-1.0.safetensors": "latent_upscale_models/ltx-2.5-latent-temporal-upscaler-x2-bf16-1.0.safetensors",
        "ltx-2.5-22b-ic-lora-pixel-spatial-upscaler-x2-1.0.safetensors": "loras/ltx-2.5-22b-ic-lora-pixel-spatial-upscaler-x2-1.0.safetensors",
    }
    script = [
        "set -u",
        "ROOT=/workspace/ctnetwork-local",
        'DEST="$ROOT/models/ltx-2.5"',
        "echo '=== GLOBAL LTX-2.5 RECOVERY SEARCH ==='",
        "recovered=0",
    ]
    for name, rel in mapping.items():
        qname = json.dumps(name)
        qrel = json.dumps(rel)
        script.extend(
            [
                f"name={qname}; rel={qrel}",
                'target="$DEST/$rel"',
                'mkdir -p "$(dirname "$target")"',
                'if [ -s "$target" ]; then echo "ALREADY_PRESENT|$target|$(stat -Lc %s "$target")"; continue; fi',
                'src=$(find /workspace -xdev -maxdepth 10 -type f -name "$name" -size +1M ! -path "$target" -print -quit 2>/dev/null || true)',
                'if [ -n "$src" ] && [ -s "$src" ]; then ln -sfn "$src" "$target"; echo "RECOVERED|$src|$target|$(stat -Lc %s "$src")"; recovered=$((recovered+1)); else echo "NOT_FOUND|$name"; fi',
            ]
        )
    script.extend(
        [
            "echo RECOVERED_COUNT=$recovered",
            "echo '--- OTHER LTX SAFETENSORS ---'",
            "find /workspace -xdev -maxdepth 10 -type f -iname '*ltx*.safetensors' -printf '%p|%s bytes\\n' 2>/dev/null | sort | head -200",
            "echo '--- LARGE SAFETENSORS CANDIDATES ---'",
            "find /workspace -xdev -maxdepth 10 -type f -name '*.safetensors' -size +500M -printf '%p|%s bytes\\n' 2>/dev/null | sort | head -200",
        ]
    )
    return run("\n".join(script), timeout=1800, label="ltx-recovery-search")


# Persist every executable/module used by the factory before repair starts.
deploy("runpod/ctnetwork-final-ltx-repair.sh", "/workspace/ctnetwork-local/bin/final-ltx-repair", "755")
deploy("runpod/ctnetwork-final-certify.sh", "/workspace/ctnetwork-local/bin/final-certify", "755")
deploy("runpod/ctnetwork_factory_v2.py", "/workspace/ctnetwork-local/controller/ctnetwork_factory_v2.py")
deploy("runpod/ctnetwork_ltx_generate.py", "/workspace/ctnetwork-local/controller/ctnetwork_ltx_generate.py")
deploy("runpod/ctnetwork_qwen_narrate.py", "/workspace/ctnetwork-local/controller/ctnetwork_qwen_narrate.py")
deploy("runpod/ctnetwork_production_control.py", "/workspace/ctnetwork-local/controller/ctnetwork_production_control.py", "755")
deploy("runpod/ctnetwork_ltx_runtime.py", "/workspace/ctnetwork-local/controller/ctnetwork_ltx_runtime.py")
deploy("ltx_bridge/app.py", "/workspace/ctnetwork-local/bridge/app.py")
deploy(
    "published-assets/the-case-against/narrator-audition/malik_am_onyx_mastered.mp3",
    "/workspace/ctnetwork-local/voices/malik_reference.mp3",
)

# Final repair: package/env fixes + resumable gated model downloads + integrity checks.
hf64 = base64.b64encode(HF_TOKEN.encode()).decode()
repair_cmd = f"export HF_TOKEN=$(echo {hf64} | base64 -d); /workspace/ctnetwork-local/bin/final-ltx-repair"
try:
    run(repair_cmd, timeout=14400, label="final-repair")
except RuntimeError as first_error:
    print("FINAL_REPAIR_FIRST_ATTEMPT_FAILED", repr(first_error), flush=True)
    recovery_output = recover_existing_ltx_weights()
    if "RECOVERED|" not in recovery_output and "ALREADY_PRESENT|" not in recovery_output:
        raise
    print("RETRYING_FINAL_REPAIR_AFTER_PERSISTENT_WEIGHT_RECOVERY", flush=True)
    run(repair_cmd, timeout=14400, label="final-repair-retry")

# Full commissioning: CUDA, base LTX, DFR, Qwen, runtime API, real bridge, E2E CTNETWORK package.
run("/workspace/ctnetwork-local/bin/final-certify", timeout=18000, label="final-certify")

# Pull concise final state to stdout for the workflow report.
run(
    """ROOT=/workspace/ctnetwork-local
printf '\n=== FINAL STATUS ===\n'
for f in "$ROOT"/status/*.status; do [ -f "$f" ] || continue; printf '%s=%s\n' "$(basename "$f")" "$(cat "$f")"; done | sort
printf '\nE2E_JOB='; cat "$ROOT/status/final_e2e_job_id.txt"
printf 'E2E_MASTER='; cat "$ROOT/status/final_e2e_master.txt"
printf '\nSTACK='; cat "$ROOT/STACK.json"
printf '\nGPU='; nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader
""",
    timeout=180,
    label="final-report",
)
