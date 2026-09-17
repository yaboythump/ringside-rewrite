#!/usr/bin/env python3
from __future__ import annotations
import base64, json, os, re, time
from pathlib import Path
import requests, websocket

REPO = Path(__file__).resolve().parents[1]
POD_ID = os.environ["POD_ID"]
PASSWORD = Path(os.environ["JUPYTER_PASSWORD_FILE"]).read_text().strip()
BASE = f"https://{POD_ID}-8888.proxy.runpod.net"
S = requests.Session()

def login():
    for attempt in range(1, 121):
        try:
            S.cookies.clear()
            r = S.get(BASE + "/login", timeout=15)
            if r.status_code != 200:
                time.sleep(3); continue
            m = re.search(r'name="_xsrf" value="([^"]+)"', r.text)
            if not m:
                time.sleep(3); continue
            rr = S.post(BASE + "/login", data={"_xsrf": m.group(1), "password": PASSWORD, "next": "/"}, timeout=20, allow_redirects=False)
            if rr.status_code not in (200,302,303):
                time.sleep(3); continue
            xsrf = S.cookies.get("_xsrf")
            headers = {"X-XSRFToken": xsrf} if xsrf else {}
            if S.get(BASE + "/api/status", headers=headers, timeout=20).status_code == 200:
                print(f"JUPYTER_AUTH_READY attempt={attempt}", flush=True)
                return headers
        except Exception as exc:
            print("auth retry", attempt, repr(exc), flush=True)
        time.sleep(3)
    raise RuntimeError("Jupyter authentication unavailable")

def terminal(headers):
    r = S.post(BASE + "/api/terminals", headers=headers, json={}, timeout=30)
    r.raise_for_status()
    name = r.json()["name"]
    cookie = "; ".join(f"{c.name}={c.value}" for c in S.cookies)
    ws = websocket.create_connection(f"wss://{POD_ID}-8888.proxy.runpod.net/terminals/websocket/{name}", cookie=cookie, origin=BASE, timeout=60)
    return ws

def run_remote(headers):
    payload = base64.b64encode((REPO / "tools" / "breaking_cap_auto_replace_v2.sh").read_bytes()).decode()
    ws = terminal(headers)
    marker = "__BC_AUTO_REPLACE_DONE__"
    cmd = f"echo {payload} | base64 -d >/tmp/bc_auto.sh; chmod +x /tmp/bc_auto.sh; /tmp/bc_auto.sh; rc=$?; echo {marker}:$rc\n"
    ws.send(json.dumps(["stdin", cmd]))
    seen = ""
    deadline = time.time() + 18000
    rc = None
    while time.time() < deadline:
        try:
            msg = ws.recv()
        except websocket.WebSocketTimeoutException:
            continue
        try:
            d = json.loads(msg)
        except Exception:
            continue
        if isinstance(d, list) and len(d) > 1 and d[0] == "stdout":
            text = d[1]
            seen += text
            print(text, end="", flush=True)
            m = re.search(re.escape(marker) + r":(\d+)", seen)
            if m:
                rc = int(m.group(1)); break
    ws.close()
    if rc != 0:
        raise RuntimeError(f"remote renderer failed rc={rc}")

def download(headers):
    p = "workspace/breaking_cap_photo_lock_FINAL.mp4"
    q = S.get(BASE + "/api/contents/" + p, headers=headers, params={"content":"1","format":"base64"}, timeout=600)
    q.raise_for_status()
    b = base64.b64decode(q.json()["content"])
    out = REPO / "breaking_cap_phx_parody_FINAL.mp4"
    out.write_bytes(b)
    print(f"DOWNLOADED {out} bytes={len(b)}", flush=True)
    if len(b) < 1_000_000:
        raise RuntimeError("final artifact unexpectedly small")

if __name__ == "__main__":
    h = login()
    run_remote(h)
    download(h)
