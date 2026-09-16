#!/usr/bin/env python3
from __future__ import annotations

import base64, json, os, re, sys, time
from pathlib import Path
import requests, websocket

REPO = Path(__file__).resolve().parents[1]
CMD = json.loads((REPO / 'breaking-cap-phx-command.json').read_text())
POD_ID = os.environ['POD_ID']
PASSWORD = Path(os.environ['JUPYTER_PASSWORD_FILE']).read_text().strip()
BASE = f'https://{POD_ID}-8888.proxy.runpod.net'
S = requests.Session()


def login():
    for attempt in range(1, 121):
        try:
            S.cookies.clear()
            r = S.get(BASE + '/login', timeout=15)
            if r.status_code != 200:
                time.sleep(3); continue
            m = re.search(r'name="_xsrf" value="([^"]+)"', r.text)
            if not m:
                time.sleep(3); continue
            rr = S.post(BASE + '/login', data={'_xsrf': m.group(1), 'password': PASSWORD, 'next': '/'}, timeout=20, allow_redirects=False)
            if rr.status_code not in (200, 302, 303):
                time.sleep(3); continue
            xsrf = S.cookies.get('_xsrf')
            headers = {'X-XSRFToken': xsrf} if xsrf else {}
            if S.get(BASE + '/api/status', headers=headers, timeout=20).status_code == 200:
                print(f'JUPYTER_READY attempt={attempt}', flush=True)
                return headers
        except Exception as exc:
            print('auth retry', attempt, repr(exc), flush=True)
        time.sleep(3)
    raise RuntimeError('Jupyter authentication unavailable')


def terminal(headers):
    r = S.post(BASE + '/api/terminals', headers=headers, json={}, timeout=30); r.raise_for_status()
    name = r.json()['name']
    cookie = '; '.join(f'{c.name}={c.value}' for c in S.cookies)
    ws = websocket.create_connection(f'wss://{POD_ID}-8888.proxy.runpod.net/terminals/websocket/{name}', cookie=cookie, origin=BASE, timeout=60)
    return name, ws


def shell_script():
    dur = float(CMD.get('duration_seconds', 20.408345))
    return rf'''set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
ROOT=/workspace/ctnetwork/breaking-cap/phx-postgame
mkdir -p "$ROOT" /workspace/ctnetwork-local/envs /workspace/ctnetwork-local/pythons
cd "$ROOT"
rm -f /workspace/breaking_cap_phx_final.mp4

echo '=== GPU ==='
nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader || true
apt-get update -qq
apt-get install -y -qq ffmpeg git curl libgl1 libglib2.0-0 fonts-dejavu-core >/dev/null

# Pull the exact user-provided production assets from the CTNETWORK repo.
curl -L --fail --retry 4 'https://raw.githubusercontent.com/yaboythump/ringside-rewrite/main/assets/breaking-cap/phx-interview.jpg' -o phx-interview.jpg
curl -L --fail --retry 4 'https://raw.githubusercontent.com/yaboythump/ringside-rewrite/main/assets/breaking-cap/master-audio.m4a' -o master-audio.m4a
curl -L --fail --retry 4 'https://raw.githubusercontent.com/yaboythump/ringside-rewrite/main/assets/breaking-cap/breaking-cap-logo.webp' -o breaking-cap-logo.webp

# Persistent LatentSync install. First run installs; later Breaking Cap jobs reuse it.
LS=/workspace/LatentSync
if [ ! -d "$LS/.git" ]; then
  git clone --depth 1 https://github.com/bytedance/LatentSync.git "$LS"
else
  git -C "$LS" pull --ff-only || true
fi

python3 -m pip install -q --upgrade uv
export UV_PYTHON_INSTALL_DIR=/workspace/ctnetwork-local/pythons
VENV=/workspace/ctnetwork-local/envs/latentsync
if [ ! -x "$VENV/bin/python" ]; then
  uv venv --python 3.10 "$VENV"
fi
PY="$VENV/bin/python"
if [ ! -f "$VENV/.breaking_cap_ready" ]; then
  cd "$LS"
  uv pip install --python "$PY" -r requirements.txt
  touch "$VENV/.breaking_cap_ready"
fi
cd "$LS"

# Download inference checkpoints once onto the persistent factory volume.
if [ ! -s checkpoints/latentsync_unet.pt ]; then
  "$VENV/bin/huggingface-cli" download ByteDance/LatentSync-1.6 latentsync_unet.pt --local-dir checkpoints
fi
if [ ! -s checkpoints/whisper/tiny.pt ]; then
  "$VENV/bin/huggingface-cli" download ByteDance/LatentSync-1.6 whisper/tiny.pt --local-dir checkpoints
fi

# Exact audio becomes the timing master. WAV is only for model inference; final uses untouched AAC stream.
ffmpeg -y -i "$ROOT/master-audio.m4a" -ac 1 -ar 16000 "$ROOT/master-model.wav" >/dev/null 2>&1

# Crop out the reporter's face so the model can only choose the athlete, upscale, and make a 25fps still-video.
ffmpeg -y -loop 1 -framerate 25 -i "$ROOT/phx-interview.jpg" -t {dur + 0.25:.3f} \
  -vf "crop=215:350:0:100,scale=430:700:flags=lanczos,format=yuv420p" \
  -r 25 -c:v libx264 -preset veryfast -crf 16 "$ROOT/athlete-source.mp4" >/dev/null 2>&1

# Audio-driven lip sync on the athlete crop.
cd "$LS"
"$PY" -m scripts.inference \
  --unet_config_path configs/unet/stage2_512.yaml \
  --inference_ckpt_path checkpoints/latentsync_unet.pt \
  --inference_steps 20 \
  --guidance_scale 1.5 \
  --enable_deepcache \
  --video_path "$ROOT/athlete-source.mp4" \
  --audio_path "$ROOT/master-model.wav" \
  --video_out_path "$ROOT/athlete-lipsync.mp4"

# Build the 9:16 social master. Restore the animated athlete crop over the original interview frame,
# add the safe-zone headline, Breaking Cap watermark, AI PARODY label, then remux the exact AAC audio.
ffmpeg -y \
  -loop 1 -framerate 25 -i "$ROOT/phx-interview.jpg" \
  -i "$ROOT/athlete-lipsync.mp4" \
  -i "$ROOT/breaking-cap-logo.webp" \
  -i "$ROOT/master-audio.m4a" \
  -filter_complex "\
[0:v]scale=576:1024:flags=lanczos,format=yuv420p[bg];\
[1:v]scale=370:601:flags=lanczos[ath];\
[bg][ath]overlay=x=0:y=171:shortest=0[scene];\
[2:v]scale=78:78:flags=lanczos[logo];\
[scene]drawbox=x=0:y=0:w=576:h=154:color=black@0.78:t=fill,\
drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='SHE ASKED HIM HOW HE FELT':x=(w-text_w)/2:y=28:fontsize=31:fontcolor=white:borderw=2:bordercolor=black,\
drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='ABOUT THE GAME TONIGHT':x=(w-text_w)/2:y=76:fontsize=35:fontcolor=white:borderw=2:bordercolor=black,\
drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='AI PARODY':x=16:y=h-52:fontsize=19:fontcolor=white:box=1:boxcolor=black@0.70:boxborderw=7[tag];\
[tag][logo]overlay=x=W-w-16:y=H-h-16[v]" \
  -map '[v]' -map 3:a:0 -t {dur:.6f} -r 25 \
  -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p \
  -c:a copy -movflags +faststart "$ROOT/breaking_cap_phx_final.mp4"

ffprobe -v error -show_entries format=duration -show_entries stream=codec_type,width,height,codec_name -of json "$ROOT/breaking_cap_phx_final.mp4" | tee "$ROOT/qc.json"
"$PY" - "$ROOT/qc.json" <<'PYQC'
import json,sys
j=json.load(open(sys.argv[1])); streams=j['streams']
v=[x for x in streams if x['codec_type']=='video']; a=[x for x in streams if x['codec_type']=='audio']
assert v and v[0].get('width')==576 and v[0].get('height')==1024
assert a
assert 20.0 <= float(j['format']['duration']) <= 20.6
PYQC
cp "$ROOT/breaking_cap_phx_final.mp4" /workspace/breaking_cap_phx_final.mp4
echo 'FINAL_READY=/workspace/breaking_cap_phx_final.mp4'
'''


def launch(headers):
    name, ws = terminal(headers)
    shell = shell_script()
    enc = base64.b64encode(shell.encode()).decode()
    cmd = (
        "rm -f /workspace/bc_phx.rc /workspace/bc_phx.log; "
        f"echo {enc} | base64 -d > /tmp/bc_phx.sh; "
        "chmod +x /tmp/bc_phx.sh; "
        "nohup bash -c 'bash /tmp/bc_phx.sh > /workspace/bc_phx.log 2>&1; echo $? > /workspace/bc_phx.rc' >/dev/null 2>&1 &\n"
    )
    ws.send(json.dumps(['stdin', cmd]))
    time.sleep(2)
    ws.close()
    try: S.delete(BASE+f'/api/terminals/{name}', headers=headers, timeout=10)
    except Exception: pass


def get_raw(headers, path, timeout=30):
    r=S.get(BASE+path, headers=headers, timeout=timeout)
    if r.status_code==200: return r.content
    return None


def monitor(headers):
    last=''
    deadline=time.time()+7200
    while time.time()<deadline:
        rc=get_raw(headers,'/files/workspace/bc_phx.rc',10)
        log=get_raw(headers,'/files/workspace/bc_phx.log',20)
        if log:
            text=log.decode('utf-8','replace')
            tail='\n'.join(text.splitlines()[-20:])
            if tail != last:
                print('--- REMOTE LOG TAIL ---', flush=True); print(tail, flush=True); last=tail
        if rc:
            val=rc.decode().strip()
            print('REMOTE_RC',val,flush=True)
            if val!='0': raise RuntimeError(f'remote render failed rc={val}')
            return
        time.sleep(15)
    raise RuntimeError('remote render timed out')


def download(headers):
    r=S.get(BASE+'/files/workspace/breaking_cap_phx_final.mp4',headers=headers,timeout=300,stream=True)
    r.raise_for_status()
    out=REPO/'breaking_cap_phx_final.mp4'
    with out.open('wb') as f:
        for chunk in r.iter_content(1024*1024):
            if chunk:f.write(chunk)
    if out.stat().st_size < 100_000: raise RuntimeError('downloaded final is unexpectedly small')
    print('DOWNLOADED_FINAL',out,out.stat().st_size,flush=True)


def main():
    assert CMD.get('publish_allowed') is False
    headers=login(); launch(headers); monitor(headers); download(headers)

if __name__=='__main__': main()
