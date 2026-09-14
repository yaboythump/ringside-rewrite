#!/usr/bin/env python3
"""Verified CTNETWORK factory migration between RunPod network volumes.

The source factory is never modified. Transfers are resumable with rsync and
post-copy verification uses the same direct SSH channel as the transfer, so a
RunPod Jupyter/8888 proxy outage cannot turn a completed copy into a false
migration failure.
"""
from __future__ import annotations

import base64
import json
import os
import re
import time
from dataclasses import dataclass

import requests
import websocket

ROOT = "/workspace/ctnetwork-local"
KEY = "/tmp/ctn_migrate_key"
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


def direct_endpoint(pod: dict) -> tuple[str, str]:
    ip = str(pod.get("publicIp") or "").strip()
    mappings = pod.get("portMappings") or {}
    port = str(mappings.get("22") or mappings.get(22) or "").strip()
    return ip, port


def ssh_opts(ip: str, port: str) -> str:
    return (
        f"ssh -p {port} -i {KEY} "
        "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "
        "-o ServerAliveInterval=30 -o ServerAliveCountMax=20 -o ConnectTimeout=30"
    )


def main() -> None:
    # Source Jupyter is needed only to launch one long-lived migration shell.
    # Destination Jupyter is bootstrap-only; all copy + verification traffic
    # after SSH is ready stays on direct SSH.
    src = JupyterShell(pod_auth(SOURCE_POD_ID))
    dest_pod = wait_running(DEST_POD_ID)

    src.run(f"test -d {ROOT}; du -sh {ROOT}; test -r {ROOT}", timeout=1800)
    src.run(
        "command -v rsync >/dev/null || (apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq rsync openssh-client)",
        timeout=900,
    )

    dest_ip, dest_port = direct_endpoint(dest_pod)
    dst = None
    if not dest_ip or not dest_port:
        dst = JupyterShell(pod_auth(DEST_POD_ID))
        env_out = dst.run(
            "echo CTN_IP:${RUNPOD_PUBLIC_IP:-}; echo CTN_SSH_PORT:${RUNPOD_TCP_PORT_22:-}",
            timeout=60,
        )
        dest_ip = parse_marker(env_out, "CTN_IP")
        dest_port = parse_marker(env_out, "CTN_SSH_PORT")
    if not dest_ip or not dest_port or not dest_port.isdigit():
        raise RuntimeError(f"Destination has no valid direct SSH endpoint: {dest_ip}:{dest_port}")
    print(f"DEST_SSH_ENDPOINT={dest_ip}:{dest_port}")

    # Reuse the existing temporary key on retries so a transient Jupyter outage
    # cannot prevent resuming a partial rsync copy.
    key_out = src.run(
        f"if [ ! -s {KEY} ] || [ ! -s {KEY}.pub ]; then rm -f {KEY} {KEY}.pub; ssh-keygen -q -t ed25519 -N '' -f {KEY}; fi; chmod 600 {KEY}; echo CTN_PUBKEY_B64:$(base64 -w0 {KEY}.pub)",
        timeout=120,
    )
    pub_b64 = parse_marker(key_out, "CTN_PUBKEY_B64")
    ssh = ssh_opts(dest_ip, dest_port)

    # First try the already-authorized key from the previous partial migration.
    # Only touch destination Jupyter if SSH bootstrap is actually required.
    try:
        src.run(f"{ssh} -n root@{dest_ip} 'echo CTN_SSH_READY'", timeout=120)
    except Exception:
        if dst is None:
            dst = JupyterShell(pod_auth(DEST_POD_ID))
        dst.run(
            "command -v rsync >/dev/null && command -v sshd >/dev/null || (apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq rsync openssh-server); mkdir -p /run/sshd /root/.ssh; chmod 700 /root/.ssh; pgrep -x sshd >/dev/null || /usr/sbin/sshd",
            timeout=900,
        )
        dst.run(
            f"echo {pub_b64} | base64 -d >> /root/.ssh/authorized_keys; sort -u /root/.ssh/authorized_keys -o /root/.ssh/authorized_keys; chmod 600 /root/.ssh/authorized_keys; pgrep -x sshd >/dev/null || /usr/sbin/sshd",
            timeout=120,
        )
        src.run(f"{ssh} -n root@{dest_ip} 'echo CTN_SSH_READY'", timeout=120)

    # Resume into the existing Norway tree. Do NOT rename/delete the partial
    # destination on retry: rsync --partial will reuse what is already there.
    src.run(
        f"{ssh} -n root@{dest_ip} 'command -v rsync >/dev/null; mkdir -p {ROOT}'",
        timeout=120,
    )

    # One long-lived source terminal performs COPY + STATS + CHECKSUM + PASS.
    # This intentionally avoids creating any new destination Jupyter terminal
    # after the copy, which was the exact failure mode of the previous run.
    transfer = f'''ROOT={ROOT}
SSH_CMD="{ssh}"

echo "=== CTNETWORK RESUMABLE RSYNC START ==="
rsync -aH --numeric-ids --partial --info=stats2,progress2 -e "$SSH_CMD" "$ROOT/" root@{dest_ip}:"$ROOT/"

echo "=== CTNETWORK SSH VERIFICATION START ==="
SRC_COUNT=$(find "$ROOT" -type f | wc -l)
SRC_BYTES=$(find "$ROOT" -type f -printf '%s\\n' | awk '{{s+=$1}} END{{printf "%.0f",s}}')
DST_STATS=$($SSH_CMD -n root@{dest_ip} "ROOT={ROOT}; c=\\$(find \\"\\$ROOT\\" -type f | wc -l); b=\\$(find \\"\\$ROOT\\" -type f -printf '%s\\n' | awk '{{s+=\\$1}} END{{printf \\"%.0f\\",s}}'); printf '%s:%s' \\"\\$c\\" \\"\\$b\\"")
DST_COUNT=${{DST_STATS%%:*}}
DST_BYTES=${{DST_STATS#*:}}
printf 'CTN_SOURCE_STATS:%s:%s\\n' "$SRC_COUNT" "$SRC_BYTES"
printf 'CTN_DEST_STATS:%s:%s\\n' "$DST_COUNT" "$DST_BYTES"
test "$SRC_COUNT" = "$DST_COUNT"
test "$SRC_BYTES" = "$DST_BYTES"

echo "=== CTNETWORK CHECKSUM DRY RUN START ==="
CHANGES=$(rsync -aHnc --delete --numeric-ids --out-format='%i %n%L' -e "$SSH_CMD" "$ROOT/" root@{dest_ip}:"$ROOT/")
printf 'CTN_CHECKSUM_CHANGES_BEGIN\\n%s\\nCTN_CHECKSUM_CHANGES_END\\n' "$CHANGES"
test -z "$CHANGES"

STATUS=$(printf 'PASS\\nmethod=rsync_ssh_checksum\\nsource_pod=%s\\ndestination_pod=%s\\nverified_files=%s\\nverified_bytes=%s\\n' '{SOURCE_POD_ID}' '{DEST_POD_ID}' "$DST_COUNT" "$DST_BYTES")
STATUS_B64=$(printf '%s' "$STATUS" | base64 -w0)
$SSH_CMD -n root@{dest_ip} "mkdir -p {ROOT}/status; printf '%s' '$STATUS_B64' | base64 -d > {ROOT}/status/factory_migration.status; cat {ROOT}/status/factory_migration.status"
echo CTNETWORK_FACTORY_MIGRATION_PASS
'''
    out = src.run(transfer, timeout=21600)
    if "CTNETWORK_FACTORY_MIGRATION_PASS" not in out:
        raise RuntimeError("Migration command completed without PASS marker")


if __name__ == "__main__":
    main()
