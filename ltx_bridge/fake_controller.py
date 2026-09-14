#!/usr/bin/env python3
import json
import sys

action = sys.argv[1]
payload = json.load(sys.stdin)

if payload.get("publish") is not False:
    print(json.dumps({"status": "failed", "error": "publish lock missing"}))
    raise SystemExit(2)

if action == "qc":
    result = {"status": "ready_for_review", "qc_passed": True}
elif action == "outputs":
    result = {"status": "ready_for_review", "master": "/tmp/final.mp4", "shorts": []}
else:
    result = {"status": "running", "action": action, "job_id": payload.get("job_id")}

print(json.dumps(result))
