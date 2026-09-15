#!/usr/bin/env python3
"""Local HTTP runtime for real LTX-2.5 generation on the CTNETWORK factory."""
from __future__ import annotations

import json
import os
import subprocess
import threading
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Literal

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

ROOT = Path(os.getenv("CTN_ROOT", "/workspace/ctnetwork-local"))
STATE = ROOT / "ltx-runtime" / "jobs"
CONTROLLER = ROOT / "controller"
HELPER = CONTROLLER / "ctnetwork_ltx_generate.py"
CORE_PY = ROOT / "envs/core/bin/python"
STATUS = ROOT / "status"
STATE.mkdir(parents=True, exist_ok=True)

app = FastAPI(title="CTNETWORK Local LTX Runtime", version="1.0.0")


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


class GenerateRequest(BaseModel):
    prompt: str = Field(min_length=3)
    quality: Literal["distilled", "dfr"] = "distilled"
    width: int = 512
    height: int = 320
    frames: int = 33
    seed: int = 42


def path_for(job_id: str) -> Path:
    return STATE / f"{job_id}.json"


def load(job_id: str) -> dict:
    p = path_for(job_id)
    if not p.exists(): raise HTTPException(404, "Unknown LTX job")
    return json.loads(p.read_text())


def save(d: dict) -> None:
    path_for(d["job_id"]).write_text(json.dumps(d, indent=2) + "\n")


def worker(job_id: str, req: GenerateRequest) -> None:
    work = STATE / job_id
    work.mkdir(parents=True, exist_ok=True)
    prompt = work / "prompt.txt"
    output = work / "output.mp4"
    log = work / "runtime.log"
    prompt.write_text(req.prompt.strip() + "\n")
    rec = load(job_id)
    rec.update(status="running", started_at=now(), output=str(output), log=str(log))
    save(rec)
    cmd = [str(CORE_PY), str(HELPER), "--prompt-file", str(prompt), "--output", str(output),
           "--quality", req.quality, "--width", str(req.width), "--height", str(req.height),
           "--frames", str(req.frames), "--seed", str(req.seed)]
    try:
        with log.open("w") as f:
            proc = subprocess.run(cmd, stdout=f, stderr=subprocess.STDOUT, text=True)
        if proc.returncode != 0:
            rec.update(status="failed", completed_at=now(), returncode=proc.returncode,
                       error=(log.read_text(errors="replace")[-4000:] if log.exists() else "LTX generation failed"))
        elif not output.exists() or output.stat().st_size < 4096:
            rec.update(status="failed", completed_at=now(), error="LTX artifact missing or too small")
        else:
            probe = subprocess.run(["ffprobe","-v","error","-show_entries","format=duration","-of","default=nw=1:nk=1",str(output)],
                                   text=True,capture_output=True)
            duration = float((probe.stdout or "0").strip() or 0)
            if probe.returncode or duration <= 0.5:
                rec.update(status="failed", completed_at=now(), error="Generated artifact failed ffprobe")
            else:
                rec.update(status="completed", completed_at=now(), bytes=output.stat().st_size, duration=duration,
                           artifact=str(output))
    except Exception as exc:
        rec.update(status="failed", completed_at=now(), error=repr(exc))
    save(rec)


@app.get("/health")
def health() -> dict:
    required = {
        "core_python": CORE_PY.exists(),
        "generator": HELPER.exists(),
        "ltx_models": (STATUS / "ltx25_models.status").exists() and (STATUS / "ltx25_models.status").read_text().strip() == "PASS",
    }
    return {"ok": all(required.values()), "service": "ctnetwork-local-ltx-runtime", "checks": required,
            "publishing": False}


@app.post("/v1/generate")
def generate(req: GenerateRequest) -> dict:
    h = health()
    if not h["ok"]: raise HTTPException(503, h)
    job_id = uuid.uuid4().hex
    rec = {"job_id": job_id, "status": "queued", "created_at": now(), "quality": req.quality,
           "width": req.width, "height": req.height, "frames": req.frames, "seed": req.seed}
    save(rec)
    threading.Thread(target=worker, args=(job_id, req), daemon=True).start()
    return rec


@app.get("/v1/jobs/{job_id}")
def job(job_id: str) -> dict:
    return load(job_id)


@app.get("/v1/jobs/{job_id}/artifact")
def artifact(job_id: str):
    rec = load(job_id)
    if rec.get("status") != "completed": raise HTTPException(409, "Artifact not ready")
    p = Path(rec["artifact"])
    if not p.exists(): raise HTTPException(404, "Artifact missing")
    return FileResponse(p, media_type="video/mp4", filename=f"{job_id}.mp4")
