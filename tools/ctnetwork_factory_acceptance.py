#!/usr/bin/env python3
import base64
import io
import json
import os
import re
import sys
import tarfile
import time
from pathlib import Path

import requests
import websocket

POD_ID = os.environ["POD_ID"]
PASSWORD = Path(os.environ["JUPYTER_PASSWORD_FILE"]).read_text().strip()
BASE = f"https://{POD_ID}-8888.proxy.runpod.net"
SESSION = requests.Session()
REPO = Path(__file__).resolve().parents[1]


def build_payload() -> str:
    bio = io.BytesIO()
    with tarfile.open(fileobj=bio, mode="w:gz") as tf:
        controller = REPO / "runpod" / "ctnetwork_factory.py"
        tf.add(controller, arcname="controller/ctnetwork_factory.py")
        shows = REPO / "ctnetwork" / "shows"
        for p in sorted(shows.glob("*.yaml")):
            tf.add(p, arcname=f"recipes/{p.name}")
    return base64.b64encode(bio.getvalue()).decode()


def login():
    last = None
    for _ in range(60):
        try:
            last = SESSION.get(BASE + "/login", timeout=15)
            if last.ok:
                break
        except Exception:
            pass
        time.sleep(5)
    else:
        raise RuntimeError(f"Jupyter not reachable; last={getattr(last, 'status_code', None)}")
    m = re.search(r'name="_xsrf" value="([^"]+)"', last.text)
    if not m:
        raise RuntimeError("Could not find Jupyter XSRF token")
    xsrf = m.group(1)
    r = SESSION.post(BASE + "/login", data={"_xsrf": xsrf, "password": PASSWORD, "next": "/"}, timeout=30, allow_redirects=False)
    if r.status_code not in (200, 302, 303):
        r.raise_for_status()
    cx = SESSION.cookies.get("_xsrf")
    headers = {"X-XSRFToken": cx} if cx else {}
    SESSION.get(BASE + "/api/status", headers=headers, timeout=30).raise_for_status()
    return headers


def run(headers):
    r = SESSION.post(BASE + "/api/terminals", headers=headers, json={}, timeout=30)
    r.raise_for_status()
    term = r.json()["name"]
    cookie = "; ".join(f"{c.name}={c.value}" for c in SESSION.cookies)
    ws = websocket.create_connection(f"wss://{POD_ID}-8888.proxy.runpod.net/terminals/websocket/{term}", cookie=cookie, origin=BASE, timeout=60)
    payload = build_payload()
    shell = f'''set -Eeuo pipefail
ROOT=/workspace/ctnetwork-local
mkdir -p "$ROOT/controller" "$ROOT/recipes" "$ROOT/ready_for_approval"
echo {payload} | base64 -d > /tmp/ctn-factory-code.tar.gz
tar -xzf /tmp/ctn-factory-code.tar.gz -C "$ROOT"
chmod +x "$ROOT/controller/ctnetwork_factory.py"
test "$(cat "$ROOT/status/qwen_smoke.status" 2>/dev/null || true)" = PASS || {{ echo QWEN_SMOKE_NOT_CERTIFIED; exit 61; }}
test "$(cat "$ROOT/status/ltx25_smoke.status" 2>/dev/null || true)" = PASS || {{ echo LTX25_SMOKE_NOT_CERTIFIED; exit 62; }}
test "$(cat "$ROOT/status/lipsync_smoke.status" 2>/dev/null || true)" = PASS || {{ echo LATENTSYNC_SMOKE_NOT_CERTIFIED; exit 63; }}
test "$(cat "$ROOT/status/ltx25_dfr.status" 2>/dev/null || true)" = PASS || {{ echo LTX25_DFR_NOT_CERTIFIED; exit 64; }}
"$ROOT/envs/core/bin/python" "$ROOT/controller/ctnetwork_factory.py" acceptance --job-id factory-acceptance

test "$(cat "$ROOT/status/factory_acceptance.status" 2>/dev/null || true)" = PASS || {{ echo FACTORY_ACCEPTANCE_STATUS_MISSING; exit 65; }}
test -s "$ROOT/ready_for_approval/factory-acceptance/master.mp4"
test -s "$ROOT/ready_for_approval/factory-acceptance/short_01_9x16.mp4"
test -s "$ROOT/ready_for_approval/factory-acceptance/thumbnail.jpg"
test -s "$ROOT/ready_for_approval/factory-acceptance/qc.json"
test -s "$ROOT/ready_for_approval/factory-acceptance/approval.json"
python3 - <<'PY'
import json
p='/workspace/ctnetwork-local/ready_for_approval/factory-acceptance/approval.json'
a=json.load(open(p))
assert a['requires_manual_approval'] is True
assert a['approved'] is False
assert a['publish_allowed'] is False
print('APPROVAL_GATE_PASS')
q=json.load(open('/workspace/ctnetwork-local/ready_for_approval/factory-acceptance/qc.json'))
assert q['pass'] is True
print('FACTORY_QC_PASS')
PY
tar -czf "$ROOT/ready_for_approval/factory-acceptance.tar.gz" -C "$ROOT/ready_for_approval" factory-acceptance
echo FACTORY_ACCEPTANCE_COMPLETE
'''
    enc = base64.b64encode(shell.encode()).decode()
    ws.send(json.dumps(["stdin", f"echo {enc} | base64 -d >/tmp/ctn-factory-acceptance.sh; bash /tmp/ctn-factory-acceptance.sh; rc=$?; echo __CTN_FACTORY_ACCEPTANCE_DONE__:$rc\n"]))
    deadline = time.time() + 3600
    output = ""
    rc = None
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
                m = re.search(r"__CTN_FACTORY_ACCEPTANCE_DONE__:(\d+)", output)
                if m:
                    rc = int(m.group(1))
                    break
    finally:
        ws.close()
        try:
            SESSION.delete(BASE + f"/api/terminals/{term}", headers=headers, timeout=10)
        except Exception:
            pass
    if rc is None:
        raise RuntimeError("factory acceptance timed out")
    if rc != 0:
        raise RuntimeError(f"factory acceptance failed rc={rc}")


def download():
    candidates = [
        "/files/ctnetwork-local/ready_for_approval/factory-acceptance.tar.gz",
        "/files/workspace/ctnetwork-local/ready_for_approval/factory-acceptance.tar.gz",
    ]
    for rel in candidates:
        try:
            r = SESSION.get(BASE + rel, timeout=300)
            if r.ok and len(r.content) > 4096:
                Path("/tmp/factory-acceptance.tar.gz").write_bytes(r.content)
                print(f"downloaded factory acceptance bytes={len(r.content)}")
                return
        except Exception as exc:
            print("download attempt failed", exc)
    print("warning: acceptance tar download failed; persistent approval package remains on server")


def main():
    headers = login()
    run(headers)
    download()


if __name__ == "__main__":
    main()
