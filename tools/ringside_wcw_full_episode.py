#!/usr/bin/env python3
from __future__ import annotations
import base64, json, os, re, sys, time
from pathlib import Path
import requests, websocket

RUNPOD_API_KEY = os.environ['RUNPOD_API_KEY']
REPO = os.environ.get('GITHUB_REPOSITORY', 'yaboythump/ringside-rewrite')
VOLUME = '9wjb3sa5zm'
PREFERRED_POD_IDS = [x for x in [os.environ.get('PREFERRED_POD_ID'), 'v92zliqqi85bwj', 'y59d4mxapkqgkz'] if x]
AUTH = {'Authorization': f'Bearer {RUNPOD_API_KEY}'}
OUT = Path('ringside-wcw-review')
OUT.mkdir(parents=True, exist_ok=True)
JOB_ID = 'ringside-wcw-won-20260918'

SECTIONS = [
"For years, wrestling fans have asked one question: what if WCW actually won the Monday Night War? Not for a week. Not for a month. What if Nitro stayed on top, WWF never completed the comeback, and the company Vince McMahon built was forced to survive in somebody else's wrestling world?",
"The real Monday Night War changed the business because fans had a choice. Every Monday night, Raw and Nitro fought for the same audience, the same stars, and the same headlines. In our timeline, WWF eventually took control. In this rewrite, WCW never gives that control back.",
"The turning point comes when WCW fixes the mistakes that hurt it in real life. Creative gets tighter. Contracts get controlled. Younger wrestlers get real opportunities. Instead of wasting its lead, WCW starts protecting it.",
"That changes everything for WWF. Vince McMahon is no longer running the hottest company in wrestling. He is fighting to keep his roster, keep his television deal, and keep the company from slipping into second place permanently.",
"WCW already has star power. Goldberg feels unstoppable. Sting remains the franchise icon. Hogan, Nash and Hall still carry massive recognition. But now the company finally treats that roster like a foundation instead of a collection of expensive names.",
"The biggest change may be who WCW does not lose. Booker T becomes a centerpiece. Diamond Dallas Page stays important. Chris Jericho gets the push he wanted. Younger talent sees a path to the main event, and suddenly leaving for WWF is not automatically the better career move.",
"By the early 2000s, WCW is no longer just the company that won the ratings war. It becomes the industry standard. Bigger television audiences lead to stronger sponsorships, bigger tours, and more leverage when the next generation of stars begins choosing where to sign.",
"WWF would still have weapons. Stone Cold. The Rock. Triple H. Those stars do not disappear. But now they are carrying the underdog company. Every big WWF moment feels like rebellion against a wrestling empire based in Atlanta.",
"And then comes the biggest butterfly effect of all: the 2001 sale never happens. WWF never buys WCW. There is no one-company era. No instant monopoly at the top of American wrestling. The war does not end. It evolves.",
"Now imagine the 2002 rookie class entering a two-company world. Brock Lesnar has options. John Cena has options. Batista and Randy Orton have options. Maybe some still choose WWF. Maybe some do not. One signing could completely rewrite the next twenty years.",
"WrestleMania also loses something it eventually gained in our timeline: unquestioned control of the wrestling calendar. Starrcade survives as a true rival super-show. Instead of one biggest night in wrestling, fans argue every year over which company delivered the bigger event.",
"The entire industry gets healthier and more chaotic. Wrestlers have leverage. Networks have competing products. Creative ideas move faster because neither company can afford to get comfortable. Competition becomes permanent.",
"In this world, WCW is remembered as the company that changed wrestling and then finished the job. WWF is remembered differently too: not as the empire that swallowed its biggest rival, but as the stubborn challenger that refused to die.",
"And that is where the rewrite gets interesting. The same stars could exist. The same rivalries could still happen. But the power structure is completely different. Every contract, every title reign, every WrestleMania, every major debut happens under a different set of rules.",
"So if WCW had won the Monday Night War, would WWE ever become the global empire we know today? Or would WCW still be the name sitting at the top of professional wrestling? Same history. Different outcome. This is Ringside Rewrite."
]

CROPS = [
[0,205,318,160],[318,205,329,160],[647,205,316,160],[963,205,349,160],
[0,455,318,145],[318,455,329,145],[647,455,316,145],[963,455,349,145],
[0,705,318,125],[318,705,329,125],[647,705,316,125],[963,705,349,125],
[0,930,620,140],[620,930,341,140],[961,930,351,140]
]


def resolve_running_pod():
    r = requests.get('https://rest.runpod.io/v1/pods', headers=AUTH, timeout=30)
    r.raise_for_status()
    candidates = []
    for p in r.json():
        vol = p.get('networkVolumeId') or (p.get('networkVolume') or {}).get('id')
        pw = (p.get('env') or {}).get('JUPYTER_PASSWORD')
        if p.get('desiredStatus') == 'RUNNING' and vol == VOLUME and pw:
            candidates.append(p)
    if not candidates:
        raise RuntimeError('NO_RUNNING_CTNETWORK_POD_WITH_PERSISTENT_VOLUME')
    byid = {p.get('id'): p for p in candidates}
    for pid in PREFERRED_POD_IDS:
        if pid in byid:
            p = byid[pid]
            return p['id'], p['env']['JUPYTER_PASSWORD']
    candidates.sort(key=lambda x: x.get('lastStartedAt') or '', reverse=True)
    p = candidates[0]
    return p['id'], p['env']['JUPYTER_PASSWORD']


def wait_jupyter(base):
    for i in range(1, 121):
        try:
            r = requests.get(base + '/login', timeout=15)
            print('JUPYTER_WAIT', i, r.status_code, flush=True)
            if r.status_code == 200:
                return
        except Exception as e:
            print('JUPYTER_WAIT', i, repr(e), flush=True)
        time.sleep(3)
    raise RuntimeError('JUPYTER_NOT_READY')


def login(base, password):
    s = requests.Session(); last = None
    for _ in range(30):
        try:
            r = s.get(base + '/login', timeout=20); r.raise_for_status()
            m = re.search(r'name="_xsrf" value="([^"]+)"', r.text)
            if not m:
                raise RuntimeError('no xsrf')
            rr = s.post(base + '/login', data={'_xsrf': m.group(1), 'password': password, 'next': '/'}, timeout=20, allow_redirects=False)
            if rr.status_code not in (200, 302, 303):
                raise RuntimeError(f'login {rr.status_code}')
            cx = s.cookies.get('_xsrf')
            return s, ({'X-XSRFToken': cx} if cx else {})
        except Exception as e:
            last = e; time.sleep(2)
    raise RuntimeError(f'JUPYTER_LOGIN_FAILED:{last!r}')


def terminal_run(base, pod_id, s, headers, shell, timeout=14400):
    r = s.post(base + '/api/terminals', headers=headers, json={}, timeout=30); r.raise_for_status(); name = r.json()['name']
    cookie = '; '.join(f'{c.name}={c.value}' for c in s.cookies)
    ws = websocket.create_connection(f'wss://{pod_id}-8888.proxy.runpod.net/terminals/websocket/{name}', cookie=cookie, origin=base, timeout=90)
    marker = f'__WCW_DONE_{int(time.time()*1000)}__'; enc = base64.b64encode(shell.encode()).decode()
    ws.send(json.dumps(['stdin', f'echo {enc} | base64 -d >/tmp/ringside-wcw.sh; bash /tmp/ringside-wcw.sh; rc=$?; echo {marker}:$rc\n']))
    buf = ''; deadline = time.time() + timeout; rc = None
    try:
        while time.time() < deadline:
            try:
                msg = ws.recv()
            except Exception as e:
                print('WS', repr(e), flush=True); continue
            try:
                data = json.loads(msg)
            except Exception:
                continue
            if isinstance(data, list) and len(data) >= 2 and data[0] == 'stdout':
                t = data[1]; buf += t; sys.stdout.write(t); sys.stdout.flush()
                mm = re.search(re.escape(marker) + r':(\d+)', buf)
                if mm:
                    rc = int(mm.group(1)); break
    finally:
        ws.close()
        try:
            s.delete(base + f'/api/terminals/{name}', headers=headers, timeout=10)
        except Exception:
            pass
    if rc is None:
        raise RuntimeError('REMOTE_TIMEOUT')
    if rc != 0:
        raise RuntimeError(f'REMOTE_RC_{rc}')


def download(base, s, headers, remote, dest):
    r = s.get(base + '/files/' + remote.lstrip('/'), headers=headers, timeout=1200)
    r.raise_for_status(); dest.write_bytes(r.content)
    print('DOWNLOADED', dest, dest.stat().st_size, flush=True)
    if dest.stat().st_size < 4096:
        raise RuntimeError('DOWNLOADED_FILE_TOO_SMALL')


def stop_pod(pod_id):
    try:
        requests.post(f'https://rest.runpod.io/v1/pods/{pod_id}/stop', headers=AUTH, timeout=30)
        print('POD_STOP_SENT', pod_id, flush=True)
    except Exception as e:
        print('POD_STOP_WARNING', repr(e), flush=True)


def main():
    pod_id, password = resolve_running_pod()
    print('USING_RUNNING_POD', pod_id, flush=True)
    base = f'https://{pod_id}-8888.proxy.runpod.net'
    try:
        wait_jupyter(base); s, headers = login(base, password)
        sections_b64 = base64.b64encode(json.dumps(SECTIONS).encode()).decode()
        crops_b64 = base64.b64encode(json.dumps(CROPS).encode()).decode()
        shell = f'''set -Eeuo pipefail
ROOT=/workspace/ctnetwork-local
JOB=$ROOT/{JOB_ID}
rm -rf "$JOB"
mkdir -p "$JOB"/{{text,audio,visuals,clips,sfx,output,raw}}
if ! command -v ffmpeg >/dev/null 2>&1; then apt-get update -y >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get install -y ffmpeg curl >/dev/null; fi
QPY="$ROOT/envs/qwen3-tts/bin/python"
test -x "$QPY"
QBATCH="$ROOT/controller/ctnetwork_qwen_narrate_batch.py"
curl -L --fail --retry 5 "https://raw.githubusercontent.com/{REPO}/main/runpod/ctnetwork_qwen_narrate_batch.py" -o "$QBATCH"
chmod +x "$QBATCH"
curl -L --fail --retry 5 "https://raw.githubusercontent.com/{REPO}/main/server_refs/kevin_ref_short.b64" | tr -d '\\r\\n ' | base64 -d > "$JOB/raw/kevin_ref.mp3"
ffmpeg -y -loglevel error -i "$JOB/raw/kevin_ref.mp3" -t 3.4 -ar 24000 -ac 1 "$JOB/raw/kevin_ref.wav"
printf '%s' 'One bell changed professional wrestling' > "$JOB/text/ref.txt"
echo {sections_b64} | base64 -d > "$JOB/text/sections.json"
echo {crops_b64} | base64 -d > "$JOB/text/crops.json"
curl -L --fail --retry 5 "https://cdn.creativeclaw.co/u/6d1d5f99/images/afc54cc6-452b-4706-9af1-298ccfc0eeb3.jpg" -o "$JOB/raw/storyboard.jpg"
ffprobe -v error -show_entries stream=width,height -of default=nw=1 "$JOB/raw/storyboard.jpg"

"$QPY" "$QBATCH" --sections-json "$JOB/text/sections.json" --ref-audio "$JOB/raw/kevin_ref.wav" --ref-text-file "$JOB/text/ref.txt" --output-dir "$JOB/audio" --language English

: > "$JOB/audio/concat.txt"
for I in $(seq -w 1 15); do
  ffmpeg -y -loglevel error -i "$JOB/audio/section_${I}.wav" -ar 48000 -ac 1 -af "loudnorm=I=-16:TP=-1.5:LRA=11" "$JOB/audio/norm_${I}.wav"
  echo "file '$JOB/audio/norm_${I}.wav'" >> "$JOB/audio/concat.txt"
done
ffmpeg -y -loglevel error -f concat -safe 0 -i "$JOB/audio/concat.txt" -c:a pcm_s16le "$JOB/audio/narration.wav"

python3 - <<'PY_CROP'
import json, pathlib, subprocess
job=pathlib.Path('/workspace/ctnetwork-local/{JOB_ID}')
for i,(x,y,w,h) in enumerate(json.load(open(job/'text/crops.json')),1):
    out=job/'visuals'/f'scene_{{i:02d}}.jpg'
    vf=f'crop={{w}}:{{h}}:{{x}}:{{y}},scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080'
    subprocess.run(['ffmpeg','-y','-loglevel','error','-i',str(job/'raw/storyboard.jpg'),'-vf',vf,'-frames:v','1','-q:v','2',str(out)],check=True)
PY_CROP

python3 - <<'PY_DUR'
import json, pathlib, subprocess
job=pathlib.Path('/workspace/ctnetwork-local/{JOB_ID}')
d=[]
for i in range(1,16):
    p=job/'audio'/f'norm_{{i:02d}}.wav'
    sec=float(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-of','default=nw=1:nk=1',str(p)],text=True).strip())
    d.append(max(2.0,sec))
(job/'text'/'durations.json').write_text(json.dumps(d))
PY_DUR

python3 - <<'PY_MOTION'
import json, pathlib, subprocess
job=pathlib.Path('/workspace/ctnetwork-local/{JOB_ID}')
durs=json.load(open(job/'text/durations.json')); concat=[]
for i,dur in enumerate(durs,1):
    img=job/'visuals'/f'scene_{{i:02d}}.jpg'; out=job/'clips'/f'scene_{{i:02d}}.mp4'; frames=max(60,int((dur+0.12)*30)); variant=(i-1)%5
    if variant==0: zp="zoompan=z='min(zoom+0.00065,1.08)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)'"
    elif variant==1: zp="zoompan=z='min(zoom+0.00055,1.07)':x='(iw-iw/zoom)*on/max(1,d-1)':y='ih/2-(ih/zoom/2)'"
    elif variant==2: zp="zoompan=z='min(zoom+0.00055,1.07)':x='iw-iw/zoom-(iw-iw/zoom)*on/max(1,d-1)':y='ih/2-(ih/zoom/2)'"
    elif variant==3: zp="zoompan=z='1.055':x='iw/2-(iw/zoom/2)':y='(ih-ih/zoom)*on/max(1,d-1)'"
    else: zp="zoompan=z='1.055':x='iw/2-(iw/zoom/2)':y='ih-ih/zoom-(ih-ih/zoom)*on/max(1,d-1)'"
    extra=',eq=contrast=1.08:saturation=1.06' if i in (2,3,7,9,14,15) else ''
    vf=f"scale=1920:1080,{{zp}}:d={{frames}}:s=1920x1080:fps=30{{extra}},format=yuv420p"
    subprocess.run(['ffmpeg','-y','-loglevel','error','-loop','1','-t',f'{{dur+0.08:.3f}}','-i',str(img),'-vf',vf,'-an','-c:v','libx264','-preset','fast','-crf','18','-movflags','+faststart',str(out)],check=True)
    concat.append(f"file '{{out}}'\n")
(job/'clips'/'concat.txt').write_text(''.join(concat))
PY_MOTION
ffmpeg -y -loglevel error -f concat -safe 0 -i "$JOB/clips/concat.txt" -c copy "$JOB/visual_master.mp4"

DUR=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$JOB/audio/narration.wav")
ENDFADE=$(awk -v d="$DUR" 'BEGIN{{e=d-2; if(e<0)e=0; printf "%.3f",e}}')
ffmpeg -y -loglevel error \
  -f lavfi -i "sine=frequency=55:sample_rate=48000:duration=$DUR" \
  -f lavfi -i "sine=frequency=110:sample_rate=48000:duration=$DUR" \
  -f lavfi -i "anoisesrc=color=pink:amplitude=0.035:sample_rate=48000:duration=$DUR" \
  -filter_complex "[0:a]volume=0.10[a0];[1:a]volume=0.035,tremolo=f=2.0:d=0.35[a1];[2:a]highpass=f=180,lowpass=f=4200,volume=0.18[a2];[a0][a1][a2]amix=inputs=3:duration=longest,afade=t=in:st=0:d=1.5,afade=t=out:st=$ENDFADE:d=2[m]" \
  -map "[m]" -c:a pcm_s16le "$JOB/sfx/music_bed.wav"
ffmpeg -y -loglevel error -f lavfi -i "sine=frequency=880:sample_rate=48000:duration=1.2" -f lavfi -i "sine=frequency=1320:sample_rate=48000:duration=1.2" -filter_complex "[0:a]afade=t=out:st=.15:d=1.0,volume=.28[a];[1:a]afade=t=out:st=.10:d=1.0,volume=.18[b];[a][b]amix=inputs=2" "$JOB/sfx/bell.wav"
ffmpeg -y -loglevel error -f lavfi -i "anoisesrc=color=pink:amplitude=0.10:sample_rate=48000:duration=3" -af "highpass=f=250,lowpass=f=5000,afade=t=in:d=.2,afade=t=out:st=1.8:d=1.2,volume=.18" "$JOB/sfx/crowd.wav"

ffmpeg -y -loglevel error \
  -i "$JOB/audio/narration.wav" -stream_loop -1 -i "$JOB/sfx/music_bed.wav" -i "$JOB/sfx/bell.wav" -i "$JOB/sfx/crowd.wav" \
  -filter_complex "[1:a]atrim=0:$DUR,volume=0.36[bed];[2:a]adelay=0|0[bell0];[2:a]adelay=220000|220000[bell1];[3:a]adelay=35000|35000[c1];[3:a]adelay=105000|105000[c2];[3:a]adelay=185000|185000[c3];[0:a][bed][bell0][bell1][c1][c2][c3]amix=inputs=7:duration=first:dropout_transition=1,loudnorm=I=-15:TP=-1.0:LRA=9[a]" \
  -map "[a]" -c:a pcm_s16le "$JOB/audio/final_mix.wav"

ffmpeg -y -loglevel error -stream_loop -1 -i "$JOB/visual_master.mp4" -i "$JOB/audio/final_mix.wav" \
  -map 0:v:0 -map 1:a:0 -vf "format=yuv420p" -c:v libx264 -preset medium -crf 18 -c:a aac -b:a 192k -ar 48000 -shortest -movflags +faststart "$JOB/output/RINGSIDE_REWRITE_WCW_WON_REVIEW_MASTER.mp4"

ffprobe -v error -show_entries format=duration,size -show_entries stream=codec_name,width,height -of json "$JOB/output/RINGSIDE_REWRITE_WCW_WON_REVIEW_MASTER.mp4" > "$JOB/output/qc.json"
python3 - <<'PY_QC'
import json,pathlib
p=pathlib.Path('/workspace/ctnetwork-local/{JOB_ID}/output/RINGSIDE_REWRITE_WCW_WON_REVIEW_MASTER.mp4')
q=json.load(open(p.parent/'qc.json')); fmt=q.get('format',{{}}); streams=q.get('streams',[])
assert p.stat().st_size>1024*1024, p.stat().st_size
assert float(fmt.get('duration') or 0)>120
assert any(s.get('codec_name')=='h264' and int(s.get('width') or 0)==1920 and int(s.get('height') or 0)==1080 for s in streams)
assert any(s.get('codec_name')=='aac' for s in streams)
(p.parent/'READY_FOR_APPROVAL.txt').write_text('READY_FOR_APPROVAL\\npublish_allowed=false\\nshorts_deferred_until_master_approval=true\\n')
print('WCW_MASTER_QC_PASS',p,p.stat().st_size,fmt.get('duration'),flush=True)
PY_QC
cd "$ROOT"
tar -czf ringside-wcw-review.tar.gz {JOB_ID}/output/RINGSIDE_REWRITE_WCW_WON_REVIEW_MASTER.mp4 {JOB_ID}/output/qc.json {JOB_ID}/output/READY_FOR_APPROVAL.txt
ls -lh ringside-wcw-review.tar.gz
'''
        terminal_run(base, pod_id, s, headers, shell)
        download(base, s, headers, 'ctnetwork-local/ringside-wcw-review.tar.gz', OUT / 'ringside-wcw-review.tar.gz')
    finally:
        stop_pod(pod_id)


if __name__ == '__main__':
    main()
