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
            if i % 10 == 0: print("jupyter wait", repr(exc), flush=True)
        time.sleep(5)
    else:
        raise RuntimeError(f"Jupyter did not become ready; last={getattr(last,'status_code',None)}")
    m = re.search(r'name="_xsrf" value="([^"]+)"', last.text)
    if not m: raise RuntimeError("Jupyter XSRF token missing")
    r = S.post(BASE + "/login", data={"_xsrf": m.group(1), "password": PASSWORD, "next": "/"},
               allow_redirects=False, timeout=30)
    if r.status_code not in (200,302,303): r.raise_for_status()
    xs = S.cookies.get("_xsrf")
    headers = {"X-XSRFToken": xs} if xs else {}
    S.get(BASE + "/api/status", headers=headers, timeout=30).raise_for_status()
    return headers


HEADERS = login()


def terminal():
    r = S.post(BASE + "/api/terminals", headers=HEADERS, json={}, timeout=30)
    r.raise_for_status()
    name = r.json()["name"]
    cookie = "; ".join(f"{c.name}={c.value}" for c in S.cookies)
    ws = websocket.create_connection(f"wss://{POD_ID}-8888.proxy.runpod.net/terminals/websocket/{name}",
                                     cookie=cookie, origin=BASE, timeout=60)
    return name, ws


def run(command: str, timeout: int = 600, label: str = "remote") -> str:
    name, ws = terminal()
    marker = f"__CTN_{int(time.time()*1000)}__"
    wrapped = f"set +e\n{command}\nrc=$?\necho {marker}:$rc\n"
    ws.send(json.dumps(["stdin", wrapped]))
    out = ""; rc = None; deadline = time.time() + timeout
    try:
        while time.time() < deadline:
            try:
                msg = ws.recv()
            except Exception as exc:
                print(f"[{label}] websocket {exc!r}", flush=True)
                continue
            if not msg: continue
            try: d = json.loads(msg)
            except Exception: continue
            if isinstance(d, list) and len(d) >= 2 and d[0] == "stdout":
                text = d[1]; out += text; sys.stdout.write(text); sys.stdout.flush()
                m = re.search(re.escape(marker) + r":(\d+)", out)
                if m:
                    rc = int(m.group(1)); break
    finally:
        ws.close()
        try: S.delete(BASE + f"/api/terminals/{name}", headers=HEADERS, timeout=10)
        except Exception: pass
    if rc is None: raise RuntimeError(f"{label} timed out after {timeout}s")
    if rc != 0: raise RuntimeError(f"{label} failed rc={rc}\n{out[-6000:]}")
    return out


def deploy(local: str, remote: str, mode: str = "644"):
    data = Path(local).read_bytes()
    b64 = base64.b64encode(data).decode()
    parent = str(Path(remote).parent)
    run(f"mkdir -p {json.dumps(parent)}; echo {b64} | base64 -d > {json.dumps(remote)}; chmod {mode} {json.dumps(remote)}", 180, "deploy")
    print(f"DEPLOYED {local} -> {remote} bytes={len(data)}", flush=True)


# Persist every executable/module used by the factory before repair starts.
deploy("runpod/ctnetwork-final-ltx-repair.sh", "/workspace/ctnetwork-local/bin/final-ltx-repair", "755")
deploy("runpod/ctnetwork-final-certify.sh", "/workspace/ctnetwork-local/bin/final-certify", "755")
deploy("runpod/ctnetwork_factory_v2.py", "/workspace/ctnetwork-local/controller/ctnetwork_factory_v2.py")
deploy("runpod/ctnetwork_ltx_generate.py", "/workspace/ctnetwork-local/controller/ctnetwork_ltx_generate.py")
deploy("runpod/ctnetwork_qwen_narrate.py", "/workspace/ctnetwork-local/controller/ctnetwork_qwen_narrate.py")
deploy("runpod/ctnetwork_production_control.py", "/workspace/ctnetwork-local/controller/ctnetwork_production_control.py", "755")
deploy("runpod/ctnetwork_ltx_runtime.py", "/workspace/ctnetwork-local/controller/ctnetwork_ltx_runtime.py")
deploy("ltx_bridge/app.py", "/workspace/ctnetwork-local/bridge/app.py")
deploy("published-assets/the-case-against/narrator-audition/malik_am_onyx_mastered.mp3",
       "/workspace/ctnetwork-local/voices/malik_reference.mp3")

# Final repair: package/env fixes + resumable gated model downloads + integrity checks.
hf64 = base64.b64encode(HF_TOKEN.encode()).decode()
run(f"export HF_TOKEN=$(echo {hf64} | base64 -d); /workspace/ctnetwork-local/bin/final-ltx-repair",
    timeout=14400, label="final-repair")

# Full commissioning: CUDA, base LTX, DFR, Qwen, runtime API, real bridge, E2E CTNETWORK package.
run("/workspace/ctnetwork-local/bin/final-certify", timeout=18000, label="final-certify")

# Pull concise final state to stdout for the workflow report.
run("""ROOT=/workspace/ctnetwork-local
printf '\n=== FINAL STATUS ===\n'
for f in "$ROOT"/status/*.status; do [ -f "$f" ] || continue; printf '%s=%s\n' "$(basename "$f")" "$(cat "$f")"; done | sort
printf '\nE2E_JOB='; cat "$ROOT/status/final_e2e_job_id.txt"
printf 'E2E_MASTER='; cat "$ROOT/status/final_e2e_master.txt"
printf '\nSTACK='; cat "$ROOT/STACK.json"
printf '\nGPU='; nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader
""", timeout=180, label="final-report")
