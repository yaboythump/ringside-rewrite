#!/usr/bin/env python3
from __future__ import annotations
import base64, json, os, re, secrets, sys, time
from pathlib import Path
import requests, websocket

KEY=os.environ["RUNPOD_API_KEY"]
AUTH={"Authorization":f"Bearer {KEY}"}
VOL="9wjb3sa5zm"
DC="EU-RO-1"
OUT=Path("ringside-recap-aew-0916-narration")
OUT.mkdir(exist_ok=True)
REF_URL="https://raw.githubusercontent.com/yaboythump/ringside-rewrite/main/server_refs/kevin_ref_short.b64"
BATCH_URL="https://raw.githubusercontent.com/yaboythump/ringside-rewrite/main/runpod/ctnetwork_qwen_narrate_batch.py"
REF_TEXT="One bell changed professional wrestling"

SECTIONS=[
"""AEW hit Norfolk with All Out only ten days away, and Dynamite did not feel like a quiet stop on the road. Will Ospreay and Jon Moxley turned the main event into a warning shot, Hangman Page and Brodido earned a championship opportunity, the women’s title picture changed because Mercedes Moné will miss All Out, and several grudges got a whole lot hotter. This is Ringside Recap. Here is what changed on AEW Dynamite, September sixteenth.""",
"""Start with the AEW World Champion, Will Ospreay. The biggest story hanging over this show was simple: Ospreay and Jon Moxley are headed toward each other at All Out, and neither man was interested in waiting quietly. Ospreay teamed with AEW National Champion Andrade El Ídolo and United Empire’s Francisco Akira. Across the ring stood Moxley, PAC and Gabe Kidd. Before the bell ever rang, the main event already felt less like a tune-up and more like a preview of a collision.""",
"""Moxley spent the night making the point that a championship belt does not automatically make somebody the best. When the match finally reached its closing stretch, he made that message physical. Francisco Akira pushed him hard and nearly stole a fall, but Moxley answered with escalating punishment: a Paradigm Shift, another Paradigm Shift, then a Death Rider. Even after that, Moxley locked in the Bulldog Choke until the referee stopped the match. The win was official. Moxley still was not finished.""",
"""The trios main event gave AEW exactly the kind of disorder it wanted going into All Out. Ospreay and Moxley finally traded strikes. Andrade brought speed and fire against PAC. Akira spent long stretches isolated but kept fighting his way back into the match. Outside the ring, Gabe Kidd repeatedly made himself a problem. By the end, this stopped feeling like three wrestlers against three wrestlers. It felt like every rivalry connected to the Death Riders and United Empire was trying to explode at the same time.""",
"""Then came the part that really mattered. Moxley kept the choke on Akira after the bell. Andrade broke it up, Wheeler Yuta got involved, and the fight spread again. David Finlay and Clark Connors joined the attack. Gabe Kidd ended up with a chair positioned around Akira’s head and neck, and suddenly this had moved way past a normal post-match beatdown. That is when Ospreay came back into the ring. One Hidden Blade dropped Moxley. Another took out Kidd. The champion finally stopped the numbers game.""",
"""Dynamite ended with Ospreay and Andrade holding the ring and protecting Akira while Moxley, the Death Riders and The Dogs backed away through the crowd. That closing image matters. Moxley won the match, but Ospreay got the final visual before All Out. Neither side left Norfolk looking comfortable, and the world-title story now has something more dangerous underneath it than a simple challenger-versus-champion matchup.""",
"""Elsewhere, Hangman Adam Page and Brodido punched their ticket to All Out. Hangman, Bandido and Brody King defeated The Conglomeration in the World Trios Championship Series, earning a shot at the AEW World Trios titles. Their opponent is not settled yet. Swerve Strickland and The New Level are scheduled to defend against The Demand on the next Dynamite, and whoever leaves with the belts moves on to face Hangman and Brodido. One result created another major reason to watch the final show before All Out.""",
"""The women’s division changed too. Mercedes Moné is not cleared to compete at All Out, but AEW says she is expected back for WrestleDream in October. So instead of forcing a title match before she is ready, AEW set Willow Nightingale against Thekla at All Out. The winner gets Moné for the AEW Women’s World Championship at WrestleDream. That gives Willow and Thekla immediate stakes and turns an injury update into a number-one-contender fight.""",
"""There is history underneath that match as well. Willow pointed directly at the damage between herself and Moné, while Thekla made it clear she sees Willow as somebody who came back and took an opportunity she wanted. So the All Out match is not just about waiting for Mercedes to return. It is about who gets to claim the next position at the top of the division while the champion is temporarily out of action.""",
"""Tommaso Ciampa also made his intentions impossible to miss. Ciampa wants AEW International Champion Kazuchika Okada at All Out. After Okada responded to the challenge, Ciampa attacked him backstage, drove him into the road cases and finished the message with a bicycle knee. Ciampa said he does not just want a match. He wants the Psycho Killer against the Rainmaker. Whether the championship match becomes official or not, the issue is clearly personal now.""",
"""The opening eight-man tag also pushed several All Out stories forward. Steven Borden and TNT Champion Darby Allin teamed with AEW World Tag Team Champions Cage and Cope against FTR, Kyle Fletcher and Kevin Knight. Borden got the deciding fall on Dax Harwood after the closing combination with Darby. More importantly, Allin and Borden are now headed toward Fletcher and Knight at All Out, while the tension around the TNT title and the veteran teams keeps building around them.""",
"""So the biggest takeaway from Dynamite is not one match result. It is how many pieces moved at once. Moxley won, but Ospreay stood tall. Hangman and Brodido earned their title shot. Willow and Thekla now have a direct path to Mercedes Moné. Ciampa put Okada on notice. And Darby, Borden, Fletcher and Knight moved one step closer to settling their issue. All Out got louder in Norfolk. This is Ringside Recap on Ringside Wrestling Network TV. Subscribe, and we will see you after the next bell."""
]

def create_pod():
    payload={
        "name":f"rwn-aew-recap-narr-{int(time.time())}",
        "imageName":"runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404",
        "cloudType":"SECURE","computeType":"GPU",
        "gpuTypeIds":["NVIDIA RTX PRO 4500 Blackwell","NVIDIA GeForce RTX 5090","NVIDIA RTX PRO 6000 Blackwell Server Edition","NVIDIA A100 80GB PCIe"],
        "gpuTypePriority":"availability","gpuCount":1,
        "dataCenterIds":[DC],"dataCenterPriority":"availability",
        "containerDiskInGb":40,"networkVolumeId":VOL,"volumeMountPath":"/workspace",
        "ports":["8888/http","22/tcp"],"env":{"JUPYTER_PASSWORD":secrets.token_hex(24)}
    }
    last=None
    for i in range(1,7):
        try:
            r=requests.post("https://rest.runpod.io/v1/pods",headers={**AUTH,"Content-Type":"application/json"},json=payload,timeout=60)
            r.raise_for_status()
            j=r.json()
            return j["id"],payload["env"]["JUPYTER_PASSWORD"]
        except Exception as e:
            last=e
            print("CREATE_RETRY",i,repr(e),flush=True)
            time.sleep(min(20,i*4))
    raise RuntimeError(f"pod create failed: {last!r}")

def wait_running(pid):
    for i in range(120):
        r=requests.get(f"https://rest.runpod.io/v1/pods/{pid}",headers=AUTH,timeout=30)
        r.raise_for_status()
        state=r.json().get("desiredStatus")
        print("POD_STATUS",i+1,state,flush=True)
        if state=="RUNNING":
            return
        time.sleep(5)
    raise RuntimeError("pod did not reach RUNNING")

def login(base,password):
    for i in range(1,31):
        try:
            s=requests.Session()
            r=s.get(base+"/login",timeout=30)
            if r.status_code!=200:
                raise RuntimeError(r.status_code)
            m=re.search(r'name="_xsrf" value="([^"]+)"',r.text)
            if not m:
                raise RuntimeError("no xsrf")
            rr=s.post(base+"/login",data={"_xsrf":m.group(1),"password":password,"next":"/"},timeout=30,allow_redirects=False)
            if rr.status_code not in (200,302,303):
                raise RuntimeError(rr.status_code)
            x=s.cookies.get("_xsrf")
            headers={"X-XSRFToken":x} if x else {}
            p=s.get(base+"/api/status",headers=headers,timeout=30)
            p.raise_for_status()
            return s,headers
        except Exception as e:
            print("LOGIN_RETRY",i,repr(e),flush=True)
            time.sleep(min(12,i*2))
    raise RuntimeError("login failed")

def terminal_run(base,pid,s,h,shell):
    last=None
    for attempt in range(1,10):
        try:
            r=s.post(base+"/api/terminals",headers=h,json={},timeout=30)
            r.raise_for_status()
            name=r.json()["name"]
            ck="; ".join(f"{c.name}={c.value}" for c in s.cookies)
            ws=websocket.create_connection(f"wss://{pid}-8888.proxy.runpod.net/terminals/websocket/{name}",cookie=ck,origin=base,timeout=90)
            marker="__AEW_RECAP_DONE__"+str(int(time.time()*1000))
            enc=base64.b64encode(shell.encode()).decode()
            ws.send(json.dumps(["stdin",f"echo {enc} | base64 -d >/tmp/rwn-aew-recap.sh; bash /tmp/rwn-aew-recap.sh; rc=$?; echo {marker}:$rc\n"]))
            buf=""
            deadline=time.time()+10800
            while time.time()<deadline:
                msg=ws.recv()
                data=json.loads(msg)
                if isinstance(data,list) and len(data)>1 and data[0]=="stdout":
                    t=data[1]
                    sys.stdout.write(t); sys.stdout.flush()
                    buf+=t
                    mm=re.search(re.escape(marker)+r":(\d+)",buf)
                    if mm:
                        ws.close()
                        rc=int(mm.group(1))
                        if rc:
                            raise RuntimeError(f"remote rc {rc}")
                        return
            raise RuntimeError("remote timeout")
        except Exception as e:
            last=e
            print("TERMINAL_RETRY",attempt,repr(e),flush=True)
            time.sleep(min(20,attempt*3))
    raise RuntimeError(f"terminal failed: {last!r}")

def download(base,s,h,remote,local):
    for i in range(1,8):
        try:
            r=s.get(base+"/files/"+remote.lstrip("/"),headers=h,timeout=600)
            if r.ok and len(r.content)>100000:
                Path(local).write_bytes(r.content)
                print("DOWNLOADED",local,len(r.content),flush=True)
                return
            print("DOWNLOAD_RETRY",i,r.status_code,len(r.content),flush=True)
        except Exception as e:
            print("DOWNLOAD_RETRY",i,repr(e),flush=True)
        time.sleep(i*3)
    raise RuntimeError("artifact download failed")

def main():
    pid,pw=create_pod()
    print("POD_ID",pid,flush=True)
    try:
        wait_running(pid)
        base=f"https://{pid}-8888.proxy.runpod.net"
        for _ in range(120):
            try:
                if requests.get(base+"/login",timeout=15).status_code==200:
                    break
            except Exception:
                pass
            time.sleep(5)
        s,h=login(base,pw)
        sections=base64.b64encode(json.dumps(SECTIONS).encode()).decode()
        ref_text=base64.b64encode(REF_TEXT.encode()).decode()
        shell=f"""set -Eeuo pipefail
ROOT=/workspace/ctnetwork-local
JOB=$ROOT/ringside-recap-aew-0916
rm -rf "$JOB"
mkdir -p "$JOB"/{{text,audio,raw,output}}
if ! command -v ffmpeg >/dev/null; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y --no-install-recommends ffmpeg curl ca-certificates
fi
QPY="$ROOT/envs/qwen3-tts/bin/python"
QBATCH="$ROOT/controller/ctnetwork_qwen_narrate_batch.py"
test -x "$QPY" || {{ echo QWEN_RUNTIME_MISSING; exit 31; }}
curl -L --fail --retry 5 "{BATCH_URL}" -o "$QBATCH"
chmod +x "$QBATCH"
curl -L --fail --retry 5 "{REF_URL}" | tr -d '\\r\\n ' | base64 -d > "$JOB/raw/kevin.mp3"
ffprobe -v error "$JOB/raw/kevin.mp3"
ffmpeg -y -loglevel error -i "$JOB/raw/kevin.mp3" -t 3.4 -ar 24000 -ac 1 "$JOB/raw/kevin_ref.wav"
echo {ref_text} | base64 -d > "$JOB/text/ref.txt"
echo {sections} | base64 -d > "$JOB/text/sections.json"
"$QPY" "$QBATCH" --sections-json "$JOB/text/sections.json" --ref-audio "$JOB/raw/kevin_ref.wav" --ref-text-file "$JOB/text/ref.txt" --output-dir "$JOB/audio/raw_sections" --language English
mkdir -p "$JOB/audio/norm"
: > "$JOB/audio/concat.txt"
for I in $(seq -w 1 12); do
  test -s "$JOB/audio/raw_sections/section_$I.wav"
  ffmpeg -y -loglevel error -i "$JOB/audio/raw_sections/section_$I.wav" -ar 48000 -ac 1 -af "loudnorm=I=-16:TP=-1.5:LRA=11" "$JOB/audio/norm/section_$I.wav"
  echo "file '$JOB/audio/norm/section_$I.wav'" >> "$JOB/audio/concat.txt"
done
ffmpeg -y -loglevel error -f concat -safe 0 -i "$JOB/audio/concat.txt" -c:a pcm_s16le "$JOB/output/narration.wav"
ffprobe -v error -show_entries format=duration,size -show_entries stream=codec_name,sample_rate,channels -of json "$JOB/output/narration.wav" > "$JOB/output/qc.json"
python3 - <<'PY'
import json, pathlib, subprocess
job=pathlib.Path("/workspace/ctnetwork-local/ringside-recap-aew-0916")
d=[]
for i in range(1,13):
    p=job/"audio"/"norm"/f"section_{{i:02d}}.wav"
    d.append(float(subprocess.check_output(["ffprobe","-v","error","-show_entries","format=duration","-of","default=nw=1:nk=1",str(p)],text=True).strip()))
(job/"output"/"durations.json").write_text(json.dumps(d))
q=json.load(open(job/"output"/"qc.json"))
dur=float(q.get("format",{{}}).get("duration") or 0)
assert dur>240, dur
print("NARRATION_QC_PASS duration=",dur,"sections=",len(d),flush=True)
PY
cd "$ROOT"
tar -czf ringside-recap-aew-0916-narration.tar.gz ringside-recap-aew-0916/output/narration.wav ringside-recap-aew-0916/output/qc.json ringside-recap-aew-0916/output/durations.json ringside-recap-aew-0916/audio/norm
echo RINGSIDE_RECAP_AEW_NARRATION_READY
"""
        terminal_run(base,pid,s,h,shell)
        download(base,s,h,"ctnetwork-local/ringside-recap-aew-0916-narration.tar.gz",OUT/"ringside-recap-aew-0916-narration.tar.gz")
    finally:
        try:
            requests.post(f"https://rest.runpod.io/v1/pods/{pid}/stop",headers=AUTH,timeout=30)
        except Exception:
            pass

if __name__=="__main__":
    main()
