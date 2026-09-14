#!/usr/bin/env python3
"""Verified CTNETWORK factory migration between two RunPod pods via runpodctl.

The source and destination pods each mount their own network volume at /workspace.
The transfer uses RunPod's peer-to-peer runpodctl send/receive transport and then
compares deterministic manifests before declaring PASS.
"""
from __future__ import annotations

import base64
import json
import os
import re
import sys
import time
from dataclasses import dataclass
from pathlib import Path

import requests
import websocket

ROOT = "/workspace/ctnetwork-local"
TRANSFER_CODE = os.environ.get("CTN_TRANSFER_CODE", "ctn-factory-no-20260914")
RUNPOD_API_KEY = os.environ["RUNPOD_API_KEY"]
SOURCE_POD_ID = os.environ["SOURCE_POD_ID"]
DEST_POD_ID = os.environ["DEST_POD_ID"]


@dataclass
class Pod:
    pod_id: str
    password: str


def get_pod(pod_id: str) -> dict:
    r = requests.get(
        f"https://rest.runpod.io/v1/pods/{pod_id}",
        headers={"Authorization": f"Bearer {RUNPOD_API_KEY}"},
        timeout=30,
    )
    r.raise_for_status()
    return r.json()


def wait_running(pod_id: str, timeout: int = 600) -> dict:
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        p = get_pod(pod_id)
        last = p.get("desiredStatus")
        if last == "RUNNING":
            return p
        if last in {"EXITED", "STOPPED"}:
            r = requests.post(
                f"https://rest.runpod.io/v1/pods/{pod_id}/start",
                headers={"Authorization": f"Bearer {RUNPOD_API_KEY}"},
                timeout=30,
            )
            # A capacity failure should be explicit rather than silently looping.
            if r.status_code >= 400 and r.status_code != 409:
                raise RuntimeError(f"Pod {pod_id} start failed HTTP={r.status_code}: {r.text[:500]}")
        time.sleep(5)
    raise TimeoutError(f"Pod {pod_id} did not reach RUNNING; last={last}")


def pod_auth(pod_id: str) -> Pod:
    p = wait_running(pod_id)
    password = ((p.get("env") or {}).get("JUPYTER_PASSWORD") or "").strip()
    if not password:
        raise RuntimeError(f"Pod {pod_id} has no JUPYTER_PASSWORD")
    return Pod(pod_id, password)


class JupyterShell:
    def __init__(self, pod: Pod, ready_timeout: int = 600):
        self.pod = pod
        self.base = f"https://{pod.pod_id}-8888.proxy.runpod.net"
        self.s = requests.Session()
        deadline = time.time() + ready_timeout
        login = None
        while time.time() < deadline:
            try:
                login = self.s.get(self.base + "/login", timeout=10)
                if login.status_code == 200:
                    break
            except requests.RequestException:
                pass
            time.sleep(5)
        if login is None or login.status_code != 200:
            raise RuntimeError(f"Jupyter not ready on {pod.pod_id}")
        m = re.search(r'name="_xsrf" value="([^"]+)"', login.text)
        if not m:
            raise RuntimeError(f"No Jupyter xsrf token on {pod.pod_id}")
        rr = self.s.post(
            self.base + "/login",
            data={"_xsrf": m.group(1), "password": pod.password, "next": "/"},
            allow_redirects=False,
            timeout=20,
        )
        if rr.status_code not in (200, 302, 303):
            raise RuntimeError(f"Jupyter login failed on {pod.pod_id}: {rr.status_code}")
        xsrf = self.s.cookies.get("_xsrf")
        self.headers = {"X-XSRFToken": xsrf} if xsrf else {}
        self.s.get(self.base + "/api/status", headers=self.headers, timeout=20).raise_for_status()

    def run(self, script: str, timeout: int = 600) -> str:
        t = self.s.post(self.base + "/api/terminals", headers=self.headers, json={}, timeout=20)
        t.raise_for_status()
        name = t.json()["name"]
        cookie = "; ".join(f"{c.name}={c.value}" for c in self.s.cookies)
        ws = websocket.create_connection(
            f"wss://{self.pod.pod_id}-8888.proxy.runpod.net/terminals/websocket/{name}",
            cookie=cookie,
            origin=self.base,
            timeout=30,
        )
        marker = f"__CTN_DONE_{int(time.time()*1000)}__"
        wrapped = f"set -o pipefail\n{script}\nrc=$?\necho {marker}:$rc\n"
        enc = base64.b64encode(wrapped.encode()).decode()
        ws.send(json.dumps(["stdin", f"echo {enc} | base64 -d | bash\n"]))
        out = ""
        deadline = time.time() + timeout
        rc = None
        try:
            while time.time() < deadline:
                try:
                    msg = ws.recv()
                except websocket.WebSocketTimeoutException:
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
                    print(f"[{self.pod.pod_id}] {text}", end="", flush=True)
                    m = re.search(re.escape(marker) + r":(\d+)", out)
                    if m:
                        rc = int(m.group(1))
                        break
        finally:
            try:
                ws.close()
            finally:
                try:
                    self.s.delete(self.base + f"/api/terminals/{name}", headers=self.headers, timeout=10)
                except Exception:
                    pass
        if rc is None:
            raise TimeoutError(f"Remote command timed out on {self.pod.pod_id}")
        if rc != 0:
            raise RuntimeError(f"Remote command failed on {self.pod.pod_id} rc={rc}\n{out[-5000:]}")
        return out


def parse_stats(text: str) -> tuple[int, int, str]:
    m = re.search(r"CTN_STATS:(\d+):(\d+):([0-9a-f]{64})", text)
    if not m:
        raise RuntimeError("Could not parse CTN_STATS")
    return int(m.group(1)), int(m.group(2)), m.group(3)


def main() -> None:
    src = JupyterShell(pod_auth(SOURCE_POD_ID))
    dst = JupyterShell(pod_auth(DEST_POD_ID))

    # Ensure source is real and destination starts clean. Never alter source.
    src.run(f"test -d {ROOT}; command -v runpodctl; du -sh {ROOT}; find {ROOT} -maxdepth 2 -type f | head")
    dst.run(f"command -v runpodctl; rm -rf {ROOT}.incoming; test ! -e {ROOT} || mv {ROOT} {ROOT}.pre_migration_$(date +%s)")

    # Start sender in the background, then receiver in the foreground.
    src.run(
        f"cd /workspace; nohup runpodctl send ctnetwork-local --code {TRANSFER_CODE} > /tmp/ctn-send.log 2>&1 & echo SENDER_PID:$!",
        timeout=60,
    )
    time.sleep(3)
    dst.run(
        f"cd /workspace; runpodctl receive {TRANSFER_CODE} > /tmp/ctn-receive.log 2>&1; cat /tmp/ctn-receive.log; test -d {ROOT}",
        timeout=14400,
    )

    # Deterministic verification: regular-file count, total regular-file bytes,
    # and a hash of sorted path+size+symlink-target metadata.
    stat_script = r'''ROOT=/workspace/ctnetwork-local
count=$(find "$ROOT" -type f | wc -l)
bytes=$(find "$ROOT" -type f -printf '%s\n' | awk '{s+=$1} END{printf "%.0f",s}')
hash=$({ find "$ROOT" -type f -printf '%P\t%s\n'; find "$ROOT" -type l -printf '%P\t%l\n'; } | LC_ALL=C sort | sha256sum | awk '{print $1}')
echo CTN_STATS:${count}:${bytes}:${hash}
'''
    sstats = parse_stats(src.run(stat_script, timeout=1800))
    dstats = parse_stats(dst.run(stat_script, timeout=1800))
    print(f"SOURCE_STATS={sstats}")
    print(f"DEST_STATS={dstats}")
    if sstats != dstats:
        raise RuntimeError(f"Migration verification mismatch source={sstats} dest={dstats}")

    # Key health markers must survive the copy.
    dst.run(
        r'''ROOT=/workspace/ctnetwork-local
for f in status/qwen.status status/latentsync.status; do
  if [ -f "$ROOT/$f" ]; then echo "$f=$(cat "$ROOT/$f")"; fi
done
mkdir -p "$ROOT/status"
printf 'PASS\nsource_pod=%s\ndestination_pod=%s\nverified_files=%s\nverified_bytes=%s\nmanifest_sha256=%s\n' \
  "$SOURCE_POD_ID" "$DEST_POD_ID" "''' + str(0) + r'''" "''' + str(0) + r'''" "pending" > /tmp/migration-placeholder
'''.replace("$SOURCE_POD_ID", SOURCE_POD_ID).replace("$DEST_POD_ID", DEST_POD_ID),
        timeout=120,
    )
    # Write definitive marker with verified values.
    marker = (
        "PASS\n"
        f"source_pod={SOURCE_POD_ID}\n"
        f"destination_pod={DEST_POD_ID}\n"
        f"verified_files={dstats[0]}\n"
        f"verified_bytes={dstats[1]}\n"
        f"manifest_sha256={dstats[2]}\n"
    )
    encoded = base64.b64encode(marker.encode()).decode()
    dst.run(f"echo {encoded} | base64 -d > {ROOT}/status/factory_migration.status; cat {ROOT}/status/factory_migration.status")
    print("CTNETWORK_FACTORY_MIGRATION_PASS")


if __name__ == "__main__":
    main()
