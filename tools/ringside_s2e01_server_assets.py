#!/usr/bin/env python3
from __future__ import annotations
import base64, json, os, re, secrets, sys, tarfile, time
from pathlib import Path
import requests, websocket

RUNPOD_API_KEY = os.environ["RUNPOD_API_KEY"]
REPO = os.environ.get("GITHUB_REPOSITORY", "yaboythump/ringside-rewrite")
VOLUME = "9wjb3sa5zm"
DC = "EU-RO-1"
OUT = Path("server-assets")
OUT.mkdir(parents=True, exist_ok=True)
AUTH = {"Authorization": f"Bearer {RUNPOD_API_KEY}"}

KEVIN_URL = "https://d2ol7oe51mr4n9.cloudfront.net/user_3FizZ6bh2NS9JMdxemkwXokQMsk/6f0fe649-2f2a-4a48-9f30-cb41c51cf87c.mp3"
REF_TEXT = "One bell changed professional wrestling forever."

SECTIONS = ['Imagine Monday Night Raw in 1998 without the chaos. No weekly feeling that the show could fly off the rails. No rebellion becoming the identity of the company. No full-blown war between Stone Cold Steve Austin and Mr. McMahon driving millions of fans back every week. The Rock is still charismatic. Mick Foley is still fearless. D-Generation X still has attitude. But the era around them never catches fire.\n\nThat is the branch point for this Ringside Rewrite. What if the World Wrestling Federation never embraced the Attitude Era?\n\nThis is not a world where one wrestler gets injured or one match ends differently. This is bigger. We are removing the creative shift that changed how WWF television looked, sounded, and felt. And once that shift disappears, the Monday Night War becomes a very different fight. Because in the mid-nineties, WWF did not have the luxury of standing still. WCW was winning attention, Nitro had momentum, and the old larger-than-life cartoon formula was losing its grip. In our timeline, pressure forced evolution. In this one, the evolution never fully happens.', 'The real history matters because the Attitude Era was not created by one moment. It was a collection of changes arriving at the same time. Characters became less polished and more personal. Rivalries became more chaotic. The line between authority figure and performer blurred. Raw became faster, louder, and more unpredictable. WWF leaned into antiheroes, controversy, surprise appearances, and cliffhangers that made the next Monday feel important.\n\nNow erase that commitment.\n\nIn this timeline, management sees the changing culture but refuses to go all the way. The company modernizes around the edges, but it stays safer. The language is cleaner. The stories are more traditional. The authority figures stay mostly behind the curtain. The presentation changes, but the philosophy does not.\n\nThat sounds like a small creative choice until you look at Steve Austin. Austin was already an elite talker and wrestler, and the Austin 3:16 moment still gives him momentum. But the version of Stone Cold who becomes a cultural phenomenon needs a world built for rebellion. If WWF never fully embraces that tone, Austin still rises, but the ceiling changes. He can fight wrestlers. He can chase championships. What he does not get is the perfect enemy: the company itself.', 'Without the Attitude Era, the Austin versus McMahon rivalry never becomes the same weekly engine. Vince McMahon may still appear on television, especially after Montreal, but he does not transform into the all-consuming villain boss in quite the same way. That matters because Austin was not just fighting one opponent. He was fighting every boss, every rule, and every person who told the audience what they were allowed to be. The conflict was simple enough to understand in seconds and big enough to carry television for years.\n\nTake that away, and Raw loses its strongest emotional shortcut.\n\nThen look at The Rock. His charisma does not disappear. His timing does not disappear. He probably still becomes a major star. But the environment around him is different. The Rock benefited from a show where characters could become louder, sharper, funnier, and more confrontational every week. In a safer WWF, his rise may be slower and his persona less explosive.\n\nThe same ripple reaches D-Generation X and Mick Foley. DX can still exist, but without the company-wide creative permission to push boundaries, the group becomes less dangerous. Foley can still create unforgettable matches, but some of his most important moments land inside a product that no longer feels like a cultural uprising. The stars remain. The ecosystem that supercharged them does not.', 'And that is where WCW becomes the biggest beneficiary.\n\nWCW did not suddenly become perfect in this alternate timeline. The company still has the same internal problems that eventually hurt it: aging top stars, creative instability, politics, and a habit of letting hot ideas run too long. So saying WCW automatically wins forever would be too easy.\n\nBut WWF no longer gets the same comeback weapon.\n\nNitro can remain the hotter destination for longer because Raw never develops the same dangerous energy. The gap in perception stays open. Wrestlers deciding where they want to work see a weaker WWF brand. Fans flipping between channels have fewer reasons to stay on Raw. Advertising, merchandise, and mainstream attention shift differently because the competition is no longer producing two equally explosive television products.\n\nMaybe WCW still stumbles. But now its mistakes do not have to compete against peak Austin, peak Rock, peak McMahon, and a WWF machine operating at maximum cultural momentum. The Monday Night War stretches out. The balance of power stays uncertain far longer. A sale, a merger, or even the eventual shape of both companies could look completely different.\n\nAnd the ripple does not stop with the war. If wrestling never reaches the same late-nineties fever pitch, the next generation inherits a smaller stage. Triple H rises in a different company. The idea of the evil authority figure may never become wrestling\'s default storytelling device. The Ruthless Aggression era grows from a different foundation. Even the way modern promotions chase viral moments and rebellious stars changes, because the template everyone copied was never fully written.', 'So what does professional wrestling look like without the Attitude Era?\n\nNot dead. Not empty. And not a world where every star disappears.\n\nIt is a world where WWF survives a much harder fight. Stone Cold can still become a star, but not necessarily the same pop-culture force. The Rock can still break through, but without the same creative furnace around him. Mr. McMahon can still be a powerful executive, but not the defining villain who turns corporate authority into a main-event character. WCW gets more time, more leverage, and a much better chance to reshape the industry\'s future.\n\nThe biggest change is not one championship or one pay-per-view. It is momentum.\n\nThe Attitude Era gave WWF an identity at the exact moment identity mattered most. Remove it, and every decision after that is made by a company with less heat, less cultural power, and less certainty that it will become the dominant force we know today.\n\nOne era missing. A completely different wrestling history.\n\nThis is Ringside Rewrite.']
MOTION_PROMPTS = ['Premium 1990s professional wrestling alternate-history documentary transition. Dark arena, analog television static, red timeline fracture ripping through smoky air, crowd lights pulsing softly, slow cinematic push-in, subtle parallax, no readable text, no logos, no close-up faces, grounded realistic motion, 16:9.', 'Premium wrestling documentary branch-point visual. Shadowy corporate production room overlooking a wrestling arena, old CRT monitors flicker, a planned rebrand visually stalls as screens fade back to a safer traditional presentation, slow camera drift, red and white practical lights, no readable text, no close-up faces, restrained realistic motion, 16:9.', 'Alternate-history antihero rise visual inspired by late-1990s wrestling. Boots stride through a curtain toward a roaring arena, shattered-glass reflections, bald rebellious wrestler seen only as a backlit silhouette from behind, crowd signs out of focus, energy builds then subtly fades, no readable text, avoid face detail, cinematic slow motion, 16:9.', 'Monday night wrestling war momentum visual. Huge arena crowd, opposing red and blue broadcast-light walls, analog ratings-board style lights shift toward one side without readable numbers or logos, camera sweeps across cheering audience, pyro haze and CRT scanlines, premium documentary realism, no close-up faces, 16:9.', 'Final alternate-history payoff. Empty wrestling ring under a single overhead spotlight, smoky late-1990s arena, ghostlike timeline reflections split into two possible futures, distant crowd seats fade into darkness, subtle ring-rope vibration, slow dolly backward, red fracture light dissolves, no readable text, cinematic and reflective, 16:9.']

def create_pod():
    password = secrets.token_hex(24)
    payload = {"name": f"ringside-s2e01-{int(time.time())}", "imageName": "runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404", "cloudType": "SECURE", "computeType": "GPU", "gpuTypeIds": ["NVIDIA RTX PRO 4500 Blackwell", "NVIDIA GeForce RTX 5090", "NVIDIA RTX PRO 6000 Blackwell Server Edition", "NVIDIA A100 80GB PCIe"], "gpuTypePriority": "availability", "gpuCount": 1, "dataCenterIds": [DC], "dataCenterPriority": "availability", "containerDiskInGb": 40, "networkVolumeId": VOLUME, "volumeMountPath": "/workspace", "ports": ["8888/http", "22/tcp"], "env": {"JUPYTER_PASSWORD": password}}
    r = requests.post("https://rest.runpod.io/v1/pods", headers={**AUTH, "Content-Type":"application/json"}, json=payload, timeout=60); r.raise_for_status()
    pod_id = r.json()["id"]; print("POD_CREATED", pod_id, flush=True); return pod_id, password

def wait_running(pod_id, max_attempts=120):
    for i in range(1, max_attempts+1):
        r = requests.get(f"https://rest.runpod.io/v1/pods/{pod_id}", headers=AUTH, timeout=30); r.raise_for_status()
        state = r.json().get("desiredStatus",""); print(f"POD_WAIT {i}/{max_attempts} {state}", flush=True)
        if state == "RUNNING": return
        time.sleep(5)
    raise RuntimeError("RunPod did not reach RUNNING")

def wait_jupyter(base):
    for i in range(1, 121):
        try:
            r=requests.get(base+"/login", timeout=15); print("JUPYTER_WAIT",i,r.status_code,flush=True)
            if r.status_code == 200: return
        except Exception as e: print("JUPYTER_WAIT",i,repr(e),flush=True)
        time.sleep(5)
    raise RuntimeError("Jupyter not ready")

def login(base,password):
    s=requests.Session(); r=s.get(base+"/login",timeout=30); r.raise_for_status(); m=re.search(r'name="_xsrf" value="([^"]+)"',r.text)
    if not m: raise RuntimeError("no xsrf")
    rr=s.post(base+"/login",data={"_xsrf":m.group(1),"password":password,"next":"/"},timeout=30,allow_redirects=False)
    if rr.status_code not in (200,302,303): raise RuntimeError(f"login {rr.status_code}")
    cx=s.cookies.get("_xsrf"); return s, ({"X-XSRFToken":cx} if cx else {})

def terminal_run(base,pod_id,s,headers,shell,timeout=10800):
    r=s.post(base+"/api/terminals",headers=headers,json={},timeout=30); r.raise_for_status(); name=r.json()["name"]
    cookie="; ".join(f"{c.name}={c.value}" for c in s.cookies)
    ws=websocket.create_connection(f"wss://{pod_id}-8888.proxy.runpod.net/terminals/websocket/{name}",cookie=cookie,origin=base,timeout=90)
    marker=f"__RR_DONE_{int(time.time()*1000)}__"; enc=base64.b64encode(shell.encode()).decode(); ws.send(json.dumps(["stdin",f"echo {enc} | base64 -d >/tmp/rr_s2e01.sh; bash /tmp/rr_s2e01.sh; rc=$?; echo {marker}:$rc\n"]))
    buf=""; deadline=time.time()+timeout; rc=None
    try:
        while time.time()<deadline:
            try: msg=ws.recv()
            except Exception as e: print("WS",repr(e),flush=True); continue
            try: data=json.loads(msg)
            except Exception: continue
            if isinstance(data,list) and len(data)>=2 and data[0]=="stdout":
                text=data[1]; buf+=text; sys.stdout.write(text); sys.stdout.flush(); mm=re.search(re.escape(marker)+r":(\d+)",buf)
                if mm: rc=int(mm.group(1)); break
    finally:
        ws.close()
        try: s.delete(base+f"/api/terminals/{name}",headers=headers,timeout=15)
        except Exception: pass
    if rc is None: raise RuntimeError("remote timed out")
    if rc != 0: raise RuntimeError(f"remote rc={rc}")

def download_file(base,s,headers,remote_rel,dest):
    r=s.get(base+"/files/"+remote_rel.lstrip("/"),headers=headers,timeout=600); r.raise_for_status(); dest.write_bytes(r.content)
    print("DOWNLOADED",dest,len(r.content),flush=True)
    if dest.stat().st_size<1024: raise RuntimeError(f"tiny download {dest}")

def stop_pod(pod_id):
    try: requests.post(f"https://rest.runpod.io/v1/pods/{pod_id}/stop",headers=AUTH,timeout=30); print("POD_STOP_SENT",pod_id,flush=True)
    except Exception as e: print("POD_STOP_WARNING",repr(e),flush=True)

def main():
    pod_id,password=create_pod()
    try:
        wait_running(pod_id); base=f"https://{pod_id}-8888.proxy.runpod.net"; wait_jupyter(base); s,headers=login(base,password)
        sec_payload=base64.b64encode(json.dumps(SECTIONS).encode()).decode(); motion_payload=base64.b64encode(json.dumps(MOTION_PROMPTS).encode()).decode(); ref_payload=base64.b64encode(REF_TEXT.encode()).decode()
        shell=f'''set -Eeuo pipefail
ROOT=/workspace/ctnetwork-local
JOB=$ROOT/ringside-s2e01-attitude-era
rm -rf "$JOB"
mkdir -p "$JOB"/{{text,audio,motion,raw}}
command -v ffmpeg >/dev/null
command -v ffprobe >/dev/null
test "$(cat "$ROOT/status/production_ready.status" 2>/dev/null || true)" = PASS
test "$(cat "$ROOT/status/qwen_smoke.status" 2>/dev/null || true)" = PASS
test "$(cat "$ROOT/status/ltx25_smoke.status" 2>/dev/null || true)" = PASS
QHELP="$ROOT/controller/ctnetwork_qwen_narrate.py"
LHELP="$ROOT/controller/ctnetwork_ltx_generate.py"
if [ ! -s "$QHELP" ]; then mkdir -p "$ROOT/controller"; curl -L --fail --retry 4 "https://raw.githubusercontent.com/{REPO}/main/runpod/ctnetwork_qwen_narrate.py" -o "$QHELP"; fi
if [ ! -s "$LHELP" ]; then mkdir -p "$ROOT/controller"; curl -L --fail --retry 4 "https://raw.githubusercontent.com/{REPO}/main/runpod/ctnetwork_ltx_generate.py" -o "$LHELP"; fi
chmod +x "$QHELP" "$LHELP"
curl -L --fail --retry 5 "{KEVIN_URL}" -o "$JOB/raw/kevin_master.mp3"
ffmpeg -y -loglevel error -i "$JOB/raw/kevin_master.mp3" -t 3.4 -ar 24000 -ac 1 "$JOB/raw/kevin_ref.wav"
echo {ref_payload} | base64 -d > "$JOB/text/ref.txt"
echo {sec_payload} | base64 -d > "$JOB/text/sections.json"
echo {motion_payload} | base64 -d > "$JOB/text/motion.json"
python3 - <<'PYREMOTE'
import json, pathlib
job=pathlib.Path('/workspace/ctnetwork-local/ringside-s2e01-attitude-era')
sections=json.load(open(job/'text/sections.json')); motions=json.load(open(job/'text/motion.json'))
for i,t in enumerate(sections,1): (job/'text'/f'section_{{i:02d}}.txt').write_text(t.strip()+'\\n')
for i,t in enumerate(motions,1): (job/'text'/f'motion_{{i:02d}}.txt').write_text(t.strip()+'\\n')
PYREMOTE
QPY="$ROOT/envs/qwen3-tts/bin/python"
test -x "$QPY"
for I in 01 02 03 04 05; do "$QPY" "$QHELP" --text-file "$JOB/text/section_${{I}}.txt" --ref-audio "$JOB/raw/kevin_ref.wav" --ref-text-file "$JOB/text/ref.txt" --output "$JOB/audio/section_${{I}}.wav" --language English; done
: > "$JOB/audio/concat.txt"
for I in 01 02 03 04 05; do echo "file '$JOB/audio/section_${{I}}.wav'" >> "$JOB/audio/concat.txt"; done
ffmpeg -y -loglevel error -f concat -safe 0 -i "$JOB/audio/concat.txt" -ar 48000 -ac 1 -c:a pcm_s16le "$JOB/narration.wav"
CPY="$ROOT/envs/core/bin/python"
test -x "$CPY"
for I in 01 02 03 04 05; do "$CPY" "$LHELP" --prompt-file "$JOB/text/motion_${{I}}.txt" --output "$JOB/raw/motion_${{I}}.mp4" --quality distilled --width 768 --height 432 --frames 97 --seed $((260916 + 10#$I)); ffmpeg -y -loglevel error -i "$JOB/raw/motion_${{I}}.mp4" -an -vf "scale=1280:720:flags=lanczos,format=yuv420p" -c:v libx264 -preset fast -crf 19 -movflags +faststart "$JOB/motion/motion_${{I}}.mp4"; done
ffprobe -v error -show_entries format=duration,size -of json "$JOB/narration.wav" > "$JOB/narration_qc.json"
for I in 01 02 03 04 05; do ffprobe -v error -show_entries format=duration,size -show_entries stream=codec_name,width,height -of json "$JOB/motion/motion_${{I}}.mp4" > "$JOB/motion/motion_${{I}}_qc.json"; done
cat > "$JOB/README.txt" <<'EOF'
Ringside Rewrite S2E01 server assets
Topic: What If the Attitude Era Didn't Exist?
Narrator: Kevin voice-preserved via approved Bret Hart Kevin master reference
Motion: 5 subtle LTX server inserts
Publishing: DISABLED — approval assets only
EOF
cd "$ROOT"
tar -czf ringside-s2e01-server-assets.tar.gz ringside-s2e01-attitude-era/narration.wav ringside-s2e01-attitude-era/narration_qc.json ringside-s2e01-attitude-era/motion ringside-s2e01-attitude-era/README.txt
ls -lh ringside-s2e01-server-assets.tar.gz
echo RR_SERVER_ASSETS_READY
'''
        terminal_run(base,pod_id,s,headers,shell)
        download_file(base,s,headers,"ctnetwork-local/ringside-s2e01-server-assets.tar.gz",OUT/"ringside-s2e01-server-assets.tar.gz")
    finally: stop_pod(pod_id)

if __name__=="__main__": main()
