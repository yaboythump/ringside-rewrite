#!/usr/bin/env python3
"""Verified CTNETWORK factory migration between two RunPod network volumes.

For the 50GB+ factory, use rsync over temporary SSH credentials rather than the
small/medium-file runpodctl relay. The source volume is read-only from this
script's perspective. Migration is only marked PASS after an rsync checksum
comparison reports no differences.
"""
from __future__ import annotations

import base64
import json
import os
import re
import time
from dataclasses import dataclass
from pathlib import Path

import requests
import websocket

ROOT = "/workspace/ctnetwork-local"
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
            if r.status_code >= 400 and r.status_code != 409:
                raise RuntimeError(
                    f"Pod {pod_id} start failed HTTP={r.status_code}: {r.text[:500]}"
                )
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
        wrapped = f"set -Eeuo pipefail\n{script}\nrc=$?\necho {marker}:$rc\n"
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
                    self.s.delete(
                        self.base + f"/api/terminals/{name}",
                        headers=self.headers,
                        timeout=10,
                    )
                except Exception:
                    pass
        if rc is None:
            raise TimeoutError(f"Remote command timed out on {self.pod.pod_id}")
        if rc != 0:
            raise RuntimeError(
                f"Remote command failed on {self.pod.pod_id} rc={rc}\n{out[-8000:]}"
            )
        return out


def parse_marker(text: str, name: str) -> str:
    m = re.search(rf"{re.escape(name)}:([^\r\n]+)", text)
    if not m:
        raise RuntimeError(f"Missing {name} marker")
    return m.group(1).strip()


def stat_tuple(shell: JupyterShell) -> tuple[int, int, str]:
    script = r'''ROOT=/workspace/ctnetwork-local
count=$(find "$ROOT" -type f | wc -l)
bytes=$(find "$ROOT" -type f -printf '%s\n' | awk '{s+=$1} END{printf "%.0f",s}')
hash=$({ find "$ROOT" -type f -printf '%P\t%s\n'; find "$ROOT" -type l -printf '%P\t%l\n'; } | LC_ALL=C sort | sha256sum | awk '{print $1}')
echo CTN_STATS:${count}:${bytes}:${hash}
'''
    out = shell.run(script, timeout=1800)
    m = re.search(r"CTN_STATS:(\d+):(\d+):([0-9a-f]{64})", out)
    if not m:
        raise RuntimeError("Could not parse CTN_STATS")
    return int(m.group(1)), int(m.group(2)), m.group(3)


def main() -> None:
    src = JupyterShell(pod_auth(SOURCE_POD_ID))
    dst = JupyterShell(pod_auth(DEST_POD_ID))

    src.run(f"test -d {ROOT}; du -sh {ROOT}; test -r {ROOT}", timeout=1800)

    # Prepare reliable large-transfer tooling. These containers normally already
    # include OpenSSH; install only if something is missing.
    src.run(
        "command -v rsync >/dev/null || (apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq rsync openssh-client)",
        timeout=900,
    )
    dst.run(
        "command -v rsync >/dev/null && command -v sshd >/dev/null || (apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq rsync openssh-server); mkdir -p /run/sshd /root/.ssh; chmod 700 /root/.ssh; pgrep -x sshd >/dev/null || /usr/sbin/sshd",
        timeout=900,
    )

    # Discover destination's direct TCP SSH endpoint from RunPod-provided env;
    # REST values are used as a fallback.
    env_out = dst.run(
        "echo CTN_IP:${RUNPOD_PUBLIC_IP:-}; echo CTN_SSH_PORT:${RUNPOD_TCP_PORT_22:-}",
        timeout=60,
    )
    dest_ip = parse_marker(env_out, "CTN_IP")
    dest_port = parse_marker(env_out, "CTN_SSH_PORT")
    if not dest_ip or not dest_port:
        p = get_pod(DEST_POD_ID)
        dest_ip = dest_ip or str(p.get("publicIp") or "")
        mappings = p.get("portMappings") or {}
        dest_port = dest_port or str(mappings.get("22") or mappings.get(22) or "")
    if not dest_ip or not dest_port:
        raise RuntimeError("Destination has no direct TCP SSH endpoint")
    if not dest_port.isdigit():
        raise RuntimeError(f"Invalid SSH port: {dest_port!r}")
    print(f"DEST_SSH_ENDPOINT={dest_ip}:{dest_port}")

    # One-time migration key exists only inside the disposable source pod.
    key_out = src.run(
        "rm -f /tmp/ctn_migrate_key /tmp/ctn_migrate_key.pub; ssh-keygen -q -t ed25519 -N '' -f /tmp/ctn_migrate_key; chmod 600 /tmp/ctn_migrate_key; echo CTN_PUBKEY_B64:$(base64 -w0 /tmp/ctn_migrate_key.pub)",
        timeout=120,
    )
    pub_b64 = parse_marker(key_out, "CTN_PUBKEY_B64")
    dst.run(
        f"echo {pub_b64} | base64 -d >> /root/.ssh/authorized_keys; sort -u /root/.ssh/authorized_keys -o /root/.ssh/authorized_keys; chmod 600 /root/.ssh/authorized_keys; pgrep -x sshd >/dev/null || /usr/sbin/sshd",
        timeout=120,
    )

    ssh_opts = (
        f"ssh -p {dest_port} -i /tmp/ctn_migrate_key "
        "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "
        "-o ServerAliveInterval=30 -o ServerAliveCountMax=20 -o ConnectTimeout=30"
    )
    src.run(
        f"{ssh_opts} root@{dest_ip} 'echo CTN_SSH_READY'",
        timeout=120,
    )

    # Never overwrite an existing destination factory in place. Preserve it as
    # a rollback snapshot, then transfer into a fresh directory.
    dst.run(
        f"if [ -e {ROOT} ]; then mv {ROOT} {ROOT}.pre_migration_$(date +%s); fi; mkdir -p {ROOT}",
        timeout=120,
    )

    # Large verified copy. Archive mode preserves symlinks, modes and mtimes;
    # partial files make retrying efficient if networking is interrupted.
    src.run(
        f"rsync -aH --numeric-ids --partial --info=stats2,progress2 -e \"{ssh_opts}\" {ROOT}/ root@{dest_ip}:{ROOT}/",
        timeout=21600,
    )

    sstats = stat_tuple(src)
    dstats = stat_tuple(dst)
    print(f"SOURCE_STATS={sstats}")
    print(f"DEST_STATS={dstats}")
    if sstats != dstats:
        raise RuntimeError(f"Metadata verification mismatch source={sstats} dest={dstats}")

    # Content verification: rsync checksum dry-run must report ZERO changes.
    verify_out = src.run(
        f"CHANGES=$(rsync -aHnc --delete --numeric-ids --out-format='%i %n%L' -e \"{ssh_opts}\" {ROOT}/ root@{dest_ip}:{ROOT}/); printf 'CTN_CHECKSUM_CHANGES_BEGIN\\n%s\\nCTN_CHECKSUM_CHANGES_END\\n' \"$CHANGES\"; test -z \"$CHANGES\"",
        timeout=21600,
    )
    if "CTN_CHECKSUM_CHANGES_BEGIN\n\nCTN_CHECKSUM_CHANGES_END" not in verify_out.replace("\r", ""):
        raise RuntimeError("Checksum verification did not produce an empty change set")

    marker = (
        "PASS\n"
        "method=rsync_ssh_checksum\n"
        f"source_pod={SOURCE_POD_ID}\n"
        f"destination_pod={DEST_POD_ID}\n"
        f"verified_files={dstats[0]}\n"
        f"verified_bytes={dstats[1]}\n"
        f"metadata_sha256={dstats[2]}\n"
    )
    marker_b64 = base64.b64encode(marker.encode()).decode()
    dst.run(
        f"mkdir -p {ROOT}/status; echo {marker_b64} | base64 -d > {ROOT}/status/factory_migration.status; cat {ROOT}/status/factory_migration.status",
        timeout=120,
    )
    print("CTNETWORK_FACTORY_MIGRATION_PASS")


if __name__ == "__main__":
    main()
