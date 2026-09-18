#!/usr/bin/env python3
from __future__ import annotations
import requests
from tools.ringside_recap_aew_0916_narration import create_pod, wait_running, login, terminal_run, AUTH

ASSET_URL="https://sdmntprcentralus.oaiusercontent.com/files/00000000-ac24-81f5-ae53-81ff26d9cf39/raw?se=2026-09-18T16%3A37%3A31Z&sp=r&sv=2026-02-06&sr=b&scid=e3d4bd0f-16b1-56a3-975a-b0e6f18cd560&skoid=d1cabc79-3240-4866-94fe-6005330cb49e&sktid=a48cca56-e6da-484e-a814-9c849652bcb3&skt=2026-09-18T13%3A31%3A49Z&ske=2026-09-19T13%3A31%3A49Z&sks=b&skv=2026-02-06&sig=OgeuEd%2BtWANCord68ECX1SEnz9nAi0EwXGd79qVYcXw%3D"

def main():
    pid,pw=create_pod()
    print("ASSET_STAGE_POD",pid,flush=True)
    try:
        wait_running(pid)
        base=f"https://{pid}-8888.proxy.runpod.net"
        for _ in range(120):
            try:
                if requests.get(base+"/login",timeout=15).status_code==200:
                    break
            except Exception:
                pass
            import time; time.sleep(5)
        s,h=login(base,pw)
        shell=f"""set -Eeuo pipefail
ROOT=/workspace/ctnetwork-local
STAGE=$ROOT/staged-assets/ringside-recap-aew-0916
rm -rf "$STAGE"
mkdir -p "$STAGE"
curl -fL --retry 5 --retry-delay 2 'https://sdmntprcentralus.oaiusercontent.com/files/00000000-ac24-81f5-ae53-81ff26d9cf39/raw?se=2026-09-18T16%3A37%3A31Z&sp=r&sv=2026-02-06&sr=b&scid=e3d4bd0f-16b1-56a3-975a-b0e6f18cd560&skoid=d1cabc79-3240-4866-94fe-6005330cb49e&sktid=a48cca56-e6da-484e-a814-9c849652bcb3&skt=2026-09-18T13%3A31%3A49Z&ske=2026-09-19T13%3A31%3A49Z&sks=b&skv=2026-02-06&sig=OgeuEd%2BtWANCord68ECX1SEnz9nAi0EwXGd79qVYcXw%3D' -o /tmp/aew0916-assets.zip
unzip -q /tmp/aew0916-assets.zip -d "$STAGE"
python3 - <<'PY'
from pathlib import Path
from PIL import Image
p=Path('/workspace/ctnetwork-local/staged-assets/ringside-recap-aew-0916')
files=sorted(p.glob('scene_*.jpg'))
assert len(files)==12, len(files)
assert (p/'thumbnail.jpg').exists()
for f in files+[p/'thumbnail.jpg']:
    im=Image.open(f)
    assert im.width>0 and im.height>0
print('ASSETS_STAGED_PASS', len(files), (p/'thumbnail.jpg').stat().st_size)
PY
echo PASS > "$STAGE/ASSETS_READY.status"
"""
        terminal_run(base,pid,s,h,shell)
    finally:
        try:
            requests.post(f"https://rest.runpod.io/v1/pods/{pid}/stop",headers=AUTH,timeout=30)
        except Exception:
            pass

if __name__=="__main__":
    main()
