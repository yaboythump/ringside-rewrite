#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re
import shlex
import time
from pathlib import Path

import requests
import websocket

POD_ID = os.environ['POD_ID']
PASSWORD = Path(os.environ['JUPYTER_PASSWORD_FILE']).read_text().strip()
BASE = f'https://{POD_ID}-8888.proxy.runpod.net'
SESSION = requests.Session()


def login() -> dict[str, str]:
    last = 'not-started'
    for attempt in range(1, 121):
        try:
            SESSION.cookies.clear()
            r = SESSION.get(BASE + '/login', timeout=15)
            last = f'GET {r.status_code}'
            if r.status_code != 200:
                time.sleep(4)
                continue
            m = re.search(r'name="_xsrf" value="([^"]+)"', r.text)
            if not m:
                last = 'GET 200 without xsrf'
                time.sleep(4)
                continue
            rr = SESSION.post(
                BASE + '/login',
                data={'_xsrf': m.group(1), 'password': PASSWORD, 'next': '/'},
                timeout=20,
                allow_redirects=False,
            )
            last = f'POST {rr.status_code}'
            if rr.status_code not in (200, 302, 303):
                time.sleep(4)
                continue
            cx = SESSION.cookies.get('_xsrf')
            headers = {'X-XSRFToken': cx} if cx else {}
            sr = SESSION.get(BASE + '/api/status', headers=headers, timeout=20)
            last = f'STATUS {sr.status_code}'
            if sr.status_code != 200:
                time.sleep(4)
                continue
            print(f'JUPYTER_AUTH_READY attempt={attempt}', flush=True)
            return headers
        except Exception as exc:
            last = repr(exc)
            time.sleep(4)
    raise RuntimeError(f'Jupyter authentication unavailable: {last}')


def terminal(headers: dict[str, str]):
    last = None
    for attempt in range(1, 61):
        name = None
        try:
            r = SESSION.post(BASE + '/api/terminals', headers=headers, json={}, timeout=30)
            r.raise_for_status()
            name = r.json()['name']
            cookie = '; '.join(f'{c.name}={c.value}' for c in SESSION.cookies)
            ws = websocket.create_connection(
                f'wss://{POD_ID}-8888.proxy.runpod.net/terminals/websocket/{name}',
                cookie=cookie,
                origin=BASE,
                timeout=60,
            )
            print(f'TERMINAL_READY attempt={attempt}', flush=True)
            return name, ws
        except Exception as exc:
            last = exc
            if name:
                try:
                    SESSION.delete(BASE + f'/api/terminals/{name}', headers=headers, timeout=10)
                except Exception:
                    pass
            time.sleep(3)
    raise RuntimeError(f'Jupyter terminal unavailable: {last!r}')


def main() -> None:
    cfg = json.loads(Path('ctnetwork-export-command.json').read_text())
    folder = cfg['folder']
    target = f'/workspace/ctnetwork-local/ready_for_approval/{folder}'
    headers = login()
    term, ws = terminal(headers)
    marker = f'__CTN_APPROVAL_HTTP_{int(time.time() * 1000)}__'
    q = shlex.quote(target)
    cmd = (
        f"if test -f {q}/master.mp4; then "
        f"cd {q} && nohup python3 -m http.server 8000 --bind 0.0.0.0 >/tmp/ctn-approval-http.log 2>&1 </dev/null & "
        f"echo {marker}:0; "
        f"else echo {marker}:44; fi\n"
    )
    ws.send(json.dumps(['stdin', cmd]))
    deadline = time.time() + 90
    output = ''
    rc = None
    try:
        while time.time() < deadline:
            msg = ws.recv()
            try:
                data = json.loads(msg)
            except Exception:
                continue
            if isinstance(data, list) and len(data) >= 2 and data[0] == 'stdout':
                text = data[1]
                output += text
                print(text, end='', flush=True)
                m = re.search(re.escape(marker) + r':(\d+)', output)
                if m:
                    rc = int(m.group(1))
                    break
    finally:
        ws.close()
        try:
            SESSION.delete(BASE + f'/api/terminals/{term}', headers=headers, timeout=10)
        except Exception:
            pass
    if rc is None:
        raise RuntimeError('approval HTTP startup marker not received')
    if rc != 0:
        raise RuntimeError(f'approval output folder missing or HTTP server failed rc={rc}')
    print(f'APPROVAL_HTTP_SERVER_STARTED {target}', flush=True)


if __name__ == '__main__':
    main()
