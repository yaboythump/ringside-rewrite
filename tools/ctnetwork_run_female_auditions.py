#!/usr/bin/env python3
from __future__ import annotations

import base64
import json
import os
import pathlib
import re
import sys
import time

import requests
import websocket

POD_ID = os.environ["POD_ID"]
PASSWORD = pathlib.Path(os.environ["JUPYTER_PASSWORD_FILE"]).read_text().strip()
BASE = f"https://{POD_ID}-8888.proxy.runpod.net"
SESSION = requests.Session()
OUT = pathlib.Path("/tmp/CTNETWORK_F01-F10_Female_Auditions.tar.gz")


def login() -> dict[str, str]:
    for attempt in range(1, 61):
        try:
            r = SESSION.get(BASE + "/login", timeout=20)
            if not r.ok:
                raise RuntimeError(f"login page {r.status_code}")
            m = re.search(r'name="_xsrf" value="([^"]+)"', r.text)
            if not m:
                raise RuntimeError("no xsrf")
            rr = SESSION.post(
                BASE + "/login",
                data={"_xsrf": m.group(1), "password": PASSWORD, "next": "/"},
                timeout=20,
                allow_redirects=False,
            )
            if rr.status_code not in (200, 302, 303):
                raise RuntimeError(f"login post {rr.status_code}")
            xc = SESSION.cookies.get("_xsrf")
            headers = {"X-XSRFToken": xc} if xc else {}
            st = SESSION.get(BASE + "/api/status", headers=headers, timeout=20)
            if st.status_code == 200:
                print(f"JUPYTER_API_READY attempt={attempt}", flush=True)
                return headers
            print(f"api status attempt={attempt} http={st.status_code}", flush=True)
        except Exception as exc:
            print(f"login retry={attempt} err={exc!r}", flush=True)
        time.sleep(3)
    raise RuntimeError("Jupyter authentication unavailable")


def run_remote(headers: dict[str, str]) -> None:
    r = SESSION.post(BASE + "/api/terminals", headers=headers, json={}, timeout=30)
    r.raise_for_status()
    term = r.json()["name"]
    cookie = "; ".join(f"{c.name}={c.value}" for c in SESSION.cookies)
    ws = websocket.create_connection(
        f"wss://{POD_ID}-8888.proxy.runpod.net/terminals/websocket/{term}",
        cookie=cookie,
        origin=BASE,
        timeout=90,
    )

    shell = r'''set -Eeuo pipefail
ROOT=/workspace/ctnetwork-local
QPY="$ROOT/envs/qwen3-tts/bin/python"
test -x "$QPY" || { echo "QWEN_ENV_MISSING:$QPY"; exit 20; }

if ! command -v ffmpeg >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y --no-install-recommends ffmpeg curl ca-certificates
fi

curl -L --fail --retry 5   "https://raw.githubusercontent.com/yaboythump/ringside-rewrite/main/tools/ctnetwork_generate_female_auditions_remote.py"   -o /tmp/ctnetwork_generate_female_auditions_remote.py

"$QPY" /tmp/ctnetwork_generate_female_auditions_remote.py
test -s /workspace/CTNETWORK_F01-F10_Female_Auditions.tar.gz
echo FEMALE_AUDITIONS_REMOTE_COMPLETE
'''

    marker = f"__FEMALE_AUDITION_RC__{int(time.time() * 1000)}"
    enc = base64.b64encode(shell.encode()).decode()
    ws.send(json.dumps([
        "stdin",
        f"echo {enc} | base64 -d >/tmp/female-auditions.sh; "
        f"bash /tmp/female-auditions.sh; rc=$?; echo {marker}:$rc\n",
    ]))

    buf = ""
    rc = None
    deadline = time.time() + 6600
    try:
        while time.time() < deadline:
            try:
                msg = ws.recv()
            except Exception:
                continue
            try:
                data = json.loads(msg)
            except Exception:
                continue
            if isinstance(data, list) and len(data) >= 2 and data[0] == "stdout":
                text = data[1]
                buf += text
                sys.stdout.write(text)
                sys.stdout.flush()
                mm = re.search(re.escape(marker) + r":(\d+)", buf)
                if mm:
                    rc = int(mm.group(1))
                    break
    finally:
        ws.close()
        try:
            SESSION.delete(BASE + f"/api/terminals/{term}", headers=headers, timeout=10)
        except Exception:
            pass

    if rc != 0:
        raise RuntimeError(f"remote audition generation failed rc={rc}")


def download(headers: dict[str, str]) -> None:
    rel = "CTNETWORK_F01-F10_Female_Auditions.tar.gz"
    for url in (BASE + "/files/" + rel, BASE + "/files/workspace/" + rel):
        try:
            r = SESSION.get(url, headers=headers, timeout=600)
            if r.ok and len(r.content) > 10000:
                OUT.write_bytes(r.content)
                print(f"DOWNLOADED_AUDITIONS bytes={len(r.content)}", flush=True)
                return
        except Exception as exc:
            print(f"download failed {exc!r}", flush=True)
    raise RuntimeError("could not download audition package")


def main() -> None:
    h = login()
    run_remote(h)
    download(h)


if __name__ == "__main__":
    main()
