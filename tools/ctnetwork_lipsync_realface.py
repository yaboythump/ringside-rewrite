#!/usr/bin/env python3
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
SOURCE_VIDEO_URL = os.environ["SOURCE_VIDEO_URL"]
SOURCE_AUDIO_URL = os.environ["SOURCE_AUDIO_URL"]
BASE = f"https://{POD_ID}-8888.proxy.runpod.net"
SESSION = requests.Session()


def login():
    last = None
    for _ in range(120):
        try:
            r = SESSION.get(BASE + "/login", timeout=15)
            last = r
            if r.ok:
                break
        except Exception:
            pass
        time.sleep(5)
    else:
        raise RuntimeError(f"Jupyter not reachable; last={getattr(last, 'status_code', None)}")
    m = re.search(r'name="_xsrf" value="([^"]+)"', r.text)
    if not m:
        raise RuntimeError("Could not find Jupyter XSRF token")
    r = SESSION.post(
        BASE + "/login",
        data={"_xsrf": m.group(1), "password": PASSWORD, "next": "/"},
        timeout=30,
        allow_redirects=False,
    )
    if r.status_code not in (200, 302, 303):
        r.raise_for_status()
    xsrf = SESSION.cookies.get("_xsrf")
    headers = {"X-XSRFToken": xsrf} if xsrf else {}
    SESSION.get(BASE + "/api/status", headers=headers, timeout=30).raise_for_status()
    return headers


def run_remote(headers):
    r = SESSION.post(BASE + "/api/terminals", headers=headers, json={}, timeout=30)
    r.raise_for_status()
    terminal = r.json()["name"]
    cookie = "; ".join(f"{c.name}={c.value}" for c in SESSION.cookies)
    ws = websocket.create_connection(
        f"wss://{POD_ID}-8888.proxy.runpod.net/terminals/websocket/{terminal}",
        cookie=cookie,
        origin=BASE,
        timeout=60,
    )

    shell = r'''set -Eeuo pipefail
ROOT=/workspace/ctnetwork-local
STATUS="$ROOT/status"
JOB="$ROOT/jobs/realface-lipsync-certification"
OUT="$ROOT/ready_for_approval/ctnetwork-realface-latentsync.mp4"
WRAPPER="$ROOT/bin/ctn-lipsync-test"
mkdir -p "$JOB" "$ROOT/ready_for_approval"

test "$(cat "$STATUS/lipsync_smoke.status" 2>/dev/null || true)" = PASS || { echo DEMO_CERTIFICATION_NOT_PASSED; exit 31; }
test -x "$WRAPPER" || { echo LIPSYNC_WRAPPER_MISSING; exit 32; }
test "$(cat "$STATUS/latentsync_vae_persistent.status" 2>/dev/null || true)" = PASS || { echo PERSISTENT_VAE_NOT_READY; exit 33; }

curl -fL --retry 3 --connect-timeout 30 "$SOURCE_VIDEO_URL" -o "$JOB/source.mp4"
curl -fL --retry 3 --connect-timeout 30 "$SOURCE_AUDIO_URL" -o "$JOB/source_audio.mp3"
ffmpeg -hide_banner -loglevel error -y -i "$JOB/source.mp4" -an -vf fps=25 -c:v libx264 -preset fast -crf 17 "$JOB/source_25.mp4"
ffmpeg -hide_banner -loglevel error -y -i "$JOB/source_audio.mp3" -ar 16000 -ac 1 "$JOB/source_audio.wav"

rm -f "$OUT" "${OUT%.mp4}.ffprobe.json"
HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 "$WRAPPER" "$JOB/source_25.mp4" "$JOB/source_audio.wav" "$OUT"

test -s "$OUT"
VIDEO_STREAMS=$(ffprobe -v error -select_streams v -show_entries stream=index -of csv=p=0 "$OUT" | wc -l)
AUDIO_STREAMS=$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$OUT" | wc -l)
DURATION=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$OUT")
SIZE=$(stat -c%s "$OUT")
python3 -c "v=int('$VIDEO_STREAMS'); a=int('$AUDIO_STREAMS'); d=float('$DURATION'); s=int('$SIZE'); assert v>=1; assert a>=1; assert d>3.0; assert s>100000; print(f'REALFACE QC PASS video={v} audio={a} duration={d:.2f}s bytes={s}')"
echo PASS > "$STATUS/realface_lipsync.status"
echo "OUTPUT=$OUT"
'''
    prefix = f"SOURCE_VIDEO_URL={json.dumps(SOURCE_VIDEO_URL)}\nSOURCE_AUDIO_URL={json.dumps(SOURCE_AUDIO_URL)}\n"
    encoded = base64.b64encode((prefix + shell).encode()).decode()
    cmd = f"echo {encoded} | base64 -d >/tmp/ctn-realface-lipsync.sh; bash /tmp/ctn-realface-lipsync.sh; rc=$?; echo __CTN_REALFACE_DONE__:$rc\n"
    ws.send(json.dumps(["stdin", cmd]))
    deadline = time.time() + 3300
    rc = None
    output = ""
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
                m = re.search(r"__CTN_REALFACE_DONE__:(\d+)", output)
                if m:
                    rc = int(m.group(1))
                    break
    finally:
        ws.close()
        try:
            SESSION.delete(BASE + f"/api/terminals/{terminal}", headers=headers, timeout=10)
        except Exception:
            pass
    if rc is None:
        raise RuntimeError("Real-face test timed out before completion marker")
    if rc != 0:
        raise RuntimeError(f"Real-face test failed rc={rc}")


def download_result():
    for url in (
        BASE + "/files/ctnetwork-local/ready_for_approval/ctnetwork-realface-latentsync.mp4",
        BASE + "/files/workspace/ctnetwork-local/ready_for_approval/ctnetwork-realface-latentsync.mp4",
    ):
        try:
            r = SESSION.get(url, timeout=180)
            if r.ok and len(r.content) > 1024:
                Path("/tmp/ctnetwork-realface-latentsync.mp4").write_bytes(r.content)
                print(f"downloaded real-face output bytes={len(r.content)}", flush=True)
                return
        except Exception as exc:
            print(f"download attempt failed: {exc}", flush=True)
    print("warning: artifact download failed; persistent ready_for_approval copy still exists", flush=True)


def main():
    headers = login()
    run_remote(headers)
    download_result()


if __name__ == "__main__":
    main()
