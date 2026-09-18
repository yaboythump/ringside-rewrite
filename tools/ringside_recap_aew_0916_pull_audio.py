#!/usr/bin/env python3
from __future__ import annotations
import os, re, secrets, time
from pathlib import Path
import requests

KEY=os.environ["RUNPOD_API_KEY"]
AUTH={"Authorization":f"Bearer {KEY}"}
VOL="9wjb3sa5zm"
DC="EU-RO-1"
OUT=Path("aew0916-audio-pull")
OUT.mkdir(exist_ok=True)

def create_pod():
    payload={
      "name":f"rwn-audio-pull-{int(time.time())}",
      "imageName":"runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404",
      "cloudType":"SECURE","computeType":"GPU",
      "gpuTypeIds":["NVIDIA RTX PRO 4500 Blackwell","NVIDIA GeForce RTX 5090","NVIDIA RTX PRO 6000 Blackwell Server Edition","NVIDIA A100 80GB PCIe"],
      "gpuTypePriority":"availability","gpuCount":1,
      "dataCenterIds":[DC],"dataCenterPriority":"availability",
      "containerDiskInGb":10,"networkVolumeId":VOL,"volumeMountPath":"/workspace",
      "ports":["8888/http"],"env":{"JUPYTER_PASSWORD":secrets.token_hex(24)}
    }
    r=requests.post("https://rest.runpod.io/v1/pods",headers={**AUTH,"Content-Type":"application/json"},json=payload,timeout=60)
    r.raise_for_status()
    j=r.json()
    return j["id"],payload["env"]["JUPYTER_PASSWORD"]

def wait_running(pid):
    for _ in range(120):
        r=requests.get(f"https://rest.runpod.io/v1/pods/{pid}",headers=AUTH,timeout=30)
        r.raise_for_status()
        if r.json().get("desiredStatus")=="RUNNING":
            return
        time.sleep(2)
    raise RuntimeError("pod start timeout")

def login(base,pw):
    for _ in range(60):
        try:
            s=requests.Session()
            r=s.get(base+"/login",timeout=15)
            if r.status_code!=200:
                raise RuntimeError(r.status_code)
            m=re.search(r'name="_xsrf" value="([^"]+)"',r.text)
            if not m: raise RuntimeError("no xsrf")
            rr=s.post(base+"/login",data={"_xsrf":m.group(1),"password":pw,"next":"/"},timeout=15,allow_redirects=False)
            if rr.status_code not in (200,302,303):
                raise RuntimeError(rr.status_code)
            x=s.cookies.get("_xsrf")
            h={"X-XSRFToken":x} if x else {}
            s.get(base+"/api/status",headers=h,timeout=15).raise_for_status()
            return s,h
        except Exception:
            time.sleep(2)
    raise RuntimeError("login failed")

def pull(base,s,h):
    candidates=[
      "workspace/ctnetwork-local/ringside-recap-aew-0916/output/narration.wav",
      "ctnetwork-local/ringside-recap-aew-0916/output/narration.wav",
    ]
    for p in candidates:
        url=base+"/files/"+p
        try:
            r=s.get(url,headers=h,timeout=900)
            print("TRY",p,r.status_code,len(r.content),flush=True)
            if r.ok and len(r.content)>1000000:
                (OUT/"narration.wav").write_bytes(r.content)
                print("AUDIO_PULL_OK",len(r.content),flush=True)
                return
        except Exception as e:
            print("TRY_ERR",p,repr(e),flush=True)

    # Fallback through Jupyter contents API, which returns base64 for binary files.
    for p in candidates:
        api=base+"/api/contents/"+p
        try:
            r=s.get(api,headers=h,params={"content":1},timeout=900)
            print("API_TRY",p,r.status_code,flush=True)
            if r.ok:
                j=r.json()
                if j.get("type")=="file" and j.get("format")=="base64" and j.get("content"):
                    import base64
                    b=base64.b64decode(j["content"])
                    if len(b)>1000000:
                        (OUT/"narration.wav").write_bytes(b)
                        print("AUDIO_PULL_OK_API",len(b),flush=True)
                        return
        except Exception as e:
            print("API_ERR",p,repr(e),flush=True)
    raise RuntimeError("could not retrieve narration.wav")

def main():
    pid,pw=create_pod()
    print("AUDIO_PULL_POD",pid,flush=True)
    try:
        wait_running(pid)
        base=f"https://{pid}-8888.proxy.runpod.net"
        s,h=login(base,pw)
        pull(base,s,h)
    finally:
        try:
            requests.post(f"https://rest.runpod.io/v1/pods/{pid}/stop",headers=AUTH,timeout=30)
            print("AUDIO_PULL_POD_STOPPED",pid,flush=True)
        except Exception as e:
            print("STOP_WARN",repr(e),flush=True)

if __name__=="__main__":
    main()
