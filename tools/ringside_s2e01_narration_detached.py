#!/usr/bin/env python3
from __future__ import annotations

import base64, json, os, re, secrets, sys, time
from pathlib import Path

import requests, websocket
import ringside_s2e01_server_assets as src

KEY = os.environ['RUNPOD_API_KEY']
AUTH = {'Authorization': f'Bearer {KEY}'}
VOL = src.VOLUME
DC = src.DC
OUT = Path('narration-detached')
OUT.mkdir(exist_ok=True)
REF_URL = 'https://raw.githubusercontent.com/yaboythump/ringside-rewrite/main/server_refs/kevin_ref_short.b64'
REF_TEXT = 'One bell changed professional wrestling'
REPO = os.environ.get('GITHUB_REPOSITORY', 'yaboythump/ringside-rewrite')


def create_pod():
    payload = {
        'name': f'rr-s2e01-narr-detached-{int(time.time())}',
        'imageName': 'runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404',
        'cloudType': 'SECURE',
        'computeType': 'GPU',
        'gpuTypeIds': [
            'NVIDIA RTX PRO 4500 Blackwell',
            'NVIDIA GeForce RTX 5090',
            'NVIDIA RTX PRO 6000 Blackwell Server Edition',
            'NVIDIA A100 80GB PCIe',
        ],
        'gpuTypePriority': 'availability',
        'gpuCount': 1,
        'dataCenterIds': [DC],
        'dataCenterPriority': 'availability',
        'containerDiskInGb': 40,
        'networkVolumeId': VOL,
        'volumeMountPath': '/workspace',
        'ports': ['8888/http', '22/tcp'],
        'env': {'JUPYTER_PASSWORD': secrets.token_hex(24)},
    }
    last = None
    for attempt in range(1, 7):
        try:
            r = requests.post('https://rest.runpod.io/v1/pods', headers={**AUTH, 'Content-Type': 'application/json'}, json=payload, timeout=60)
            r.raise_for_status()
            return r.json()['id'], payload['env']['JUPYTER_PASSWORD']
        except Exception as exc:
            last = exc
            print('CREATE_RETRY', attempt, repr(exc), flush=True)
            time.sleep(min(20, attempt * 4))
    raise RuntimeError(f'pod create failed: {last!r}')


def wait_running(pid):
    for _ in range(120):
        r = requests.get(f'https://rest.runpod.io/v1/pods/{pid}', headers=AUTH, timeout=30)
        r.raise_for_status()
        if r.json().get('desiredStatus') == 'RUNNING':
            return
        time.sleep(5)
    raise RuntimeError('pod did not reach RUNNING')


def login(base, password):
    for attempt in range(1, 31):
        try:
            s = requests.Session()
            r = s.get(base + '/login', timeout=30)
            if r.status_code != 200:
                raise RuntimeError(f'login page {r.status_code}')
            m = re.search(r'name="_xsrf" value="([^"]+)"', r.text)
            if not m:
                raise RuntimeError('no xsrf token')
            rr = s.post(base + '/login', data={'_xsrf': m.group(1), 'password': password, 'next': '/'}, timeout=30, allow_redirects=False)
            if rr.status_code not in (200, 302, 303):
                raise RuntimeError(f'login post {rr.status_code}')
            x = s.cookies.get('_xsrf')
            return s, ({'X-XSRFToken': x} if x else {})
        except Exception as exc:
            print('LOGIN_RETRY', attempt, repr(exc), flush=True)
            time.sleep(min(12, attempt * 2))
    raise RuntimeError('login failed')


def start_detached(base, pid, session, headers, shell):
    last = None
    for attempt in range(1, 15):
        try:
            r = session.post(base + '/api/terminals', headers=headers, json={}, timeout=30)
            r.raise_for_status()
            name = r.json()['name']
            cookie = '; '.join(f'{c.name}={c.value}' for c in session.cookies)
            ws = websocket.create_connection(
                f'wss://{pid}-8888.proxy.runpod.net/terminals/websocket/{name}',
                cookie=cookie,
                origin=base,
                timeout=90,
            )
            marker = '__DETACHED_STARTED__'
            encoded = base64.b64encode(shell.encode()).decode()
            cmd = f"echo {encoded} | base64 -d >/tmp/rr_detached.sh; nohup bash /tmp/rr_detached.sh >/tmp/rr_detached_boot.log 2>&1 </dev/null & echo {marker}"
            ws.send(json.dumps(['stdin', cmd + '\n']))
            deadline = time.time() + 60
            buf = ''
            while time.time() < deadline:
                msg = ws.recv()
                data = json.loads(msg)
                if isinstance(data, list) and len(data) > 1 and data[0] == 'stdout':
                    text = data[1]
                    sys.stdout.write(text)
                    sys.stdout.flush()
                    buf += text
                    if marker in buf:
                        ws.close()
                        return
            ws.close()
            raise RuntimeError('detached start marker missing')
        except Exception as exc:
            last = exc
            print('DETACHED_START_RETRY', attempt, repr(exc), flush=True)
            time.sleep(min(15, attempt * 2))
    raise RuntimeError(f'detached start failed: {last!r}')


def exists(session, base, path):
    try:
        r = session.get(base + '/files/' + path.lstrip('/'), timeout=30)
        return r.status_code == 200
    except Exception:
        return False


def get_text(session, base, path):
    r = session.get(base + '/files/' + path.lstrip('/'), timeout=60)
    r.raise_for_status()
    return r.text


def main():
    pid, password = create_pod()
    try:
        wait_running(pid)
        base = f'https://{pid}-8888.proxy.runpod.net'
        session, headers = login(base, password)

        sections_b64 = base64.b64encode(json.dumps(src.SECTIONS).encode()).decode()
        ref_text_b64 = base64.b64encode(REF_TEXT.encode()).decode()
        shell = f'''set -Eeuo pipefail
ROOT=/workspace/ctnetwork-local
JOB=$ROOT/ringside-s2e01-narration-only
mkdir -p "$JOB"/text "$JOB"/audio "$JOB"/raw
rm -f "$JOB/DONE" "$JOB/FAILED"
if ! command -v ffmpeg >/dev/null; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y --no-install-recommends ffmpeg curl ca-certificates
fi
QPY="$ROOT/envs/qwen3-tts/bin/python"
QRESUME="$ROOT/controller/ctnetwork_qwen_narrate_resume.py"
test -x "$QPY"
curl -L --fail --retry 5 "https://raw.githubusercontent.com/{REPO}/main/runpod/ctnetwork_qwen_narrate_resume.py" -o "$QRESUME"
chmod +x "$QRESUME"
curl -L --fail --retry 5 "{REF_URL}" | tr -d '\\r\\n ' | base64 -d > "$JOB/raw/kevin.mp3"
ffprobe -v error "$JOB/raw/kevin.mp3"
ffmpeg -y -loglevel error -i "$JOB/raw/kevin.mp3" -t 3.4 -ar 24000 -ac 1 "$JOB/raw/kevin_ref.wav"
echo {ref_text_b64} | base64 -d > "$JOB/text/ref.txt"
echo {sections_b64} | base64 -d > "$JOB/text/sections.json"
set +e
"$QPY" "$QRESUME" --sections-json "$JOB/text/sections.json" --ref-audio "$JOB/raw/kevin_ref.wav" --ref-text-file "$JOB/text/ref.txt" --output-dir "$JOB/audio" --language English > "$JOB/narration.log" 2>&1
RC=$?
set -e
if [ "$RC" -ne 0 ]; then
  echo "$RC" > "$JOB/FAILED"
  exit 0
fi
: > "$JOB/audio/concat.txt"
for I in 01 02 03 04 05; do
  test -s "$JOB/audio/section_${{I}}.wav"
  echo "file '$JOB/audio/section_${{I}}.wav'" >> "$JOB/audio/concat.txt"
done
ffmpeg -y -loglevel error -f concat -safe 0 -i "$JOB/audio/concat.txt" -ar 48000 -ac 1 -c:a pcm_s16le "$JOB/narration.wav"
ffprobe -v error -show_entries format=duration,size -of json "$JOB/narration.wav" > "$JOB/qc.json"
cd "$ROOT"
tar -czf ringside-s2e01-narration-only.tar.gz ringside-s2e01-narration-only/narration.wav ringside-s2e01-narration-only/qc.json ringside-s2e01-narration-only/narration.log
printf 'ok\n' > "$JOB/DONE"
'''
        start_detached(base, pid, session, headers, shell)

        done_path = 'ctnetwork-local/ringside-s2e01-narration-only/DONE'
        failed_path = 'ctnetwork-local/ringside-s2e01-narration-only/FAILED'
        log_path = 'ctnetwork-local/ringside-s2e01-narration-only/narration.log'
        archive_path = 'ctnetwork-local/ringside-s2e01-narration-only.tar.gz'
        for tick in range(1, 721):
            if exists(session, base, done_path):
                r = session.get(base + '/files/' + archive_path, headers=headers, timeout=600)
                r.raise_for_status()
                target = OUT / 'ringside-s2e01-narration-only.tar.gz'
                target.write_bytes(r.content)
                print('NARRATION_ARCHIVE_DOWNLOADED', target, len(r.content), flush=True)
                return
            if exists(session, base, failed_path):
                log = ''
                try:
                    log = get_text(session, base, log_path)
                except Exception:
                    pass
                raise RuntimeError('detached narration failed\n' + log[-12000:])
            if tick % 4 == 0:
                print('DETACHED_NARRATION_STILL_RUNNING', tick, flush=True)
            time.sleep(15)
        raise RuntimeError('detached narration timed out')
    finally:
        try:
            requests.post(f'https://rest.runpod.io/v1/pods/{pid}/stop', headers=AUTH, timeout=30)
        except Exception:
            pass


if __name__ == '__main__':
    main()
