#!/usr/bin/env python3
import os, requests
KEY=os.environ["RUNPOD_API_KEY"]
H={"Authorization":f"Bearer {KEY}"}
r=requests.get("https://rest.runpod.io/v1/pods",headers=H,timeout=30)
r.raise_for_status()
pods=r.json()
if isinstance(pods,dict):
    pods=pods.get("pods") or pods.get("items") or []
stopped=[]
for p in pods:
    name=str(p.get("name",""))
    pid=p.get("id")
    status=p.get("desiredStatus") or p.get("status")
    if pid and name.startswith("rwn-aew-recap-narr-") and status not in ("EXITED","STOPPED","TERMINATED"):
        rr=requests.post(f"https://rest.runpod.io/v1/pods/{pid}/stop",headers=H,timeout=30)
        print("STOP",pid,name,rr.status_code,rr.text[:300],flush=True)
        stopped.append(pid)
print("STOPPED_COUNT",len(stopped),flush=True)
