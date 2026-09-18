#!/usr/bin/env python3
from pathlib import Path
from ringside_wcw_full_episode import resolve_running_pod, wait_jupyter, login, terminal_run, download, stop_pod, JOB_ID

OUT=Path("ringside-wcw-review")
OUT.mkdir(parents=True,exist_ok=True)

def main():
    pod_id,password,created=resolve_running_pod()
    print("USING_RECOVERY_POD",pod_id,"created_fresh=",created,flush=True)
    base=f"https://{pod_id}-8888.proxy.runpod.net"
    try:
        wait_jupyter(base)
        s,headers=login(base,password)
        shell=f"""set -Eeuo pipefail
ROOT=/workspace/ctnetwork-local
JOB=$ROOT/{JOB_ID}
MASTER="$JOB/output/RINGSIDE_REWRITE_WCW_WON_REVIEW_MASTER.mp4"
test -s "$MASTER"
ffprobe -v error -show_entries format=duration,size -show_entries stream=codec_name,width,height -of json "$MASTER" > "$JOB/output/qc.json"
python3 - <<'PY'
import json,pathlib
p=pathlib.Path("/workspace/ctnetwork-local/{JOB_ID}/output/RINGSIDE_REWRITE_WCW_WON_REVIEW_MASTER.mp4")
q=json.load(open(p.parent/"qc.json"))
fmt=q.get("format",{{}})
streams=q.get("streams",[])
assert p.exists() and p.stat().st_size>1_000_000
assert float(fmt.get("duration") or 0)>120
assert any(s.get("codec_name")=="h264" and int(s.get("width") or 0)==1920 and int(s.get("height") or 0)==1080 for s in streams)
assert any(s.get("codec_name")=="aac" for s in streams)
(p.parent/"READY_FOR_APPROVAL.txt").write_text("READY_FOR_APPROVAL\\npublish_allowed=false\\n")
print("WCW_RECOVERED_MASTER_QC_PASS",p.stat().st_size,fmt.get("duration"),flush=True)
PY
cd "$ROOT"
tar -czf ringside-wcw-review.tar.gz \
  {JOB_ID}/output/RINGSIDE_REWRITE_WCW_WON_REVIEW_MASTER.mp4 \
  {JOB_ID}/output/qc.json \
  {JOB_ID}/output/READY_FOR_APPROVAL.txt
ls -lh ringside-wcw-review.tar.gz
"""
        terminal_run(base,pod_id,s,headers,shell,timeout=1800)
        download(base,s,headers,"ctnetwork-local/ringside-wcw-review.tar.gz",OUT/"ringside-wcw-review.tar.gz")
    finally:
        stop_pod(pod_id)

if __name__=="__main__":
    main()
