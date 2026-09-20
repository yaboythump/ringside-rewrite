#!/usr/bin/env python3
from __future__ import annotations
import base64, json, os, pathlib, re, sys, time
import requests, websocket

REPO = pathlib.Path(__file__).resolve().parents[1]
CMD = json.loads((REPO / "ringside-austin-f06-command.json").read_text())
POD_ID = os.environ["POD_ID"]
PASSWORD = pathlib.Path(os.environ["JUPYTER_PASSWORD_FILE"]).read_text().strip()
BASE = f"https://{POD_ID}-8888.proxy.runpod.net"

def connect():
    s=requests.Session(); last=None
    for _ in range(120):
        try:
            r=s.get(BASE+"/login",timeout=15)
            if r.status_code==200: break
            last=f"HTTP {r.status_code}"
        except Exception as exc:
            last=repr(exc)
        time.sleep(4)
    else:
        raise RuntimeError(f"Jupyter unavailable: {last}")
    m=re.search(r'name="_xsrf" value="([^"]+)"',r.text)
    if not m: raise RuntimeError("XSRF token missing")
    rr=s.post(BASE+"/login",data={"_xsrf":m.group(1),"password":PASSWORD,"next":"/"},timeout=30,allow_redirects=False)
    if rr.status_code not in (200,302,303): rr.raise_for_status()
    xs=s.cookies.get("_xsrf"); headers={"X-XSRFToken":xs} if xs else {}
    s.get(BASE+"/api/status",headers=headers,timeout=30).raise_for_status()
    t=s.post(BASE+"/api/terminals",headers=headers,json={},timeout=30); t.raise_for_status()
    name=t.json()["name"]
    cookie="; ".join(f"{c.name}={c.value}" for c in s.cookies)
    ws=websocket.create_connection(f"wss://{POD_ID}-8888.proxy.runpod.net/terminals/websocket/{name}",cookie=cookie,origin=BASE,timeout=60)
    return s,headers,name,ws

def remote_source():
    cmd_b64=base64.b64encode(json.dumps(CMD).encode()).decode()
    src=r'''
import base64,json,pathlib,textwrap,subprocess
ROOT=pathlib.Path("/workspace/ctnetwork-local")
OUT=ROOT/"episodes/ringside_austin_neck/narration_only"
OUT.mkdir(parents=True,exist_ok=True)
cmd=json.loads(base64.b64decode("__CMD__"))
ref=pathlib.Path(cmd["narrator_reference_path"])
if not ref.exists() or ref.stat().st_size<4096:
    raise RuntimeError(f"F06 reference missing: {ref}")
if (ROOT/"status/qwen_smoke.status").read_text().strip()!="PASS":
    raise RuntimeError("Qwen narrator engine not certified")

paragraphs=[p.strip() for p in cmd["narration_text"].split("\n\n") if p.strip()]
chunks=[]; buf=""
for p in paragraphs:
    cand=(buf+"\n\n"+p).strip() if buf else p
    if len(cand)>850 and buf:
        chunks.append(buf); buf=p
    else:
        buf=cand
if buf: chunks.append(buf)
(OUT/"chunks.json").write_text(json.dumps(chunks,indent=2))
(OUT/"reference.txt").write_text(cmd["narrator_reference_text"].strip()+"\n")
script=OUT/"make_f06.py"
script.write_text(textwrap.dedent("""
import json,pathlib,numpy as np,soundfile as sf,torch
from qwen_tts import Qwen3TTSModel
root=pathlib.Path("/workspace/ctnetwork-local/episodes/ringside_austin_neck/narration_only")
chunks=json.loads((root/"chunks.json").read_text())
ref_text=(root/"reference.txt").read_text().strip()
model=Qwen3TTSModel.from_pretrained(
    "/workspace/ctnetwork-local/models/qwen3-tts/1.7B-Base",
    device_map="cuda:0",
    dtype=torch.bfloat16,
)
parts=[]; sr=None
for i,txt in enumerate(chunks,1):
    print(f"F06_CHUNK {i}/{len(chunks)} chars={len(txt)}",flush=True)
    wavs,this_sr=model.generate_voice_clone(
        text=txt, language="English",
        ref_audio="/workspace/ctnetwork-local/narrator-auditions/female-urban-10/F06.wav",
        ref_text=ref_text
    )
    x=np.asarray(wavs[0],dtype=np.float32).squeeze()
    if sr is None: sr=this_sr
    if this_sr!=sr: raise RuntimeError("sample rate changed")
    parts.append(x)
    parts.append(np.zeros(int(sr*0.28),dtype=np.float32))
out=np.concatenate(parts[:-1])
sf.write(str(root/"F06_Austin.wav"),out,sr)
print("F06_READY",len(out)/sr,sr,flush=True)
"""))
qpy=ROOT/"envs/qwen3-tts/bin/python"
subprocess.run([str(qpy),str(script)],check=True)
print("F06_PATH",OUT/"F06_Austin.wav",flush=True)
'''.replace("__CMD__",cmd_b64)
    return src

def main():
    s,headers,term,ws=connect()
    enc=base64.b64encode(remote_source().encode()).decode()
    marker="__AUSTIN_F06_DONE__"
    ws.send(json.dumps(["stdin",f"echo {enc} | base64 -d >/tmp/austin_f06.py; python3 /tmp/austin_f06.py; rc=$?; echo {marker}:$rc\n"]))
    output=""; rc=None; deadline=time.time()+5400
    try:
        while time.time()<deadline:
            try: msg=ws.recv()
            except Exception as exc:
                print("websocket",repr(exc),flush=True); continue
            try: data=json.loads(msg)
            except Exception: continue
            if isinstance(data,list) and len(data)>=2 and data[0]=="stdout":
                txt=data[1]; output+=txt; sys.stdout.write(txt); sys.stdout.flush()
                mm=re.search(re.escape(marker)+r":(\d+)",output)
                if mm:
                    rc=int(mm.group(1)); break
    finally:
        ws.close()
        try: s.delete(BASE+f"/api/terminals/{term}",headers=headers,timeout=10)
        except Exception: pass
    if rc is None: raise RuntimeError("F06 narration timed out")
    if rc!=0: raise RuntimeError(f"F06 narration failed rc={rc}")
    outdir=REPO/"deliverables"; outdir.mkdir(exist_ok=True)
    rel="ctnetwork-local/episodes/ringside_austin_neck/narration_only/F06_Austin.wav"
    dest=outdir/"F06_Austin.wav"
    ok=False
    for candidate in (f"/files/workspace/{rel}",f"/files/{rel}"):
        resp=s.get(BASE+candidate,headers=headers,stream=True,timeout=900)
        if resp.status_code==200:
            with open(dest,"wb") as f:
                for chunk in resp.iter_content(4*1024*1024):
                    if chunk: f.write(chunk)
            if dest.stat().st_size>4096:
                print("DOWNLOADED",dest,dest.stat().st_size,flush=True)
                ok=True; break
    if not ok: raise RuntimeError("could not download F06 narration")
if __name__=="__main__":
    main()
