from __future__ import annotations

import json
import os
import subprocess
import tempfile
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Literal

from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

APPROVAL_LOCK = True
STATE_DIR = Path(os.getenv("LTX_BRIDGE_STATE_DIR", "/tmp/ctnetwork-ltx-bridge"))
STATE_DIR.mkdir(parents=True, exist_ok=True)
CONTROL_CMD = os.getenv("LTX_CONTROL_CMD", "").strip()
BRIDGE_TOKEN = os.getenv("LTX_BRIDGE_TOKEN", "").strip()

app = FastAPI(
    title="CTNETWORK LTX Production Bridge",
    version="1.1.0",
    description=(
        "Control bridge between ChatGPT and the CTNETWORK LTX production server. "
        "Production may start, retry, render, build Shorts and run QC. Publishing is "
        "intentionally not exposed; final publishing remains behind Thump's approval gate."
    ),
)


class ProductionRequest(BaseModel):
    show: str
    episode: str
    package_ref: str | None = None
    visual_refs: list[str] = Field(default_factory=list)
    narrator: dict[str, Any] = Field(default_factory=dict)
    shorts_count: int | None = None
    auto_fix: bool = True
    publish: bool = False
    metadata: dict[str, Any] = Field(default_factory=dict)


class JobAction(BaseModel):
    reason: str | None = None
    auto_fix: bool = True
    metadata: dict[str, Any] = Field(default_factory=dict)


class ShortsRequest(BaseModel):
    count: int
    auto_fix: bool = True
    metadata: dict[str, Any] = Field(default_factory=dict)


class JobRecord(BaseModel):
    job_id: str
    show: str
    episode: str
    status: Literal[
        "queued",
        "running",
        "retrying",
        "qc",
        "ready_for_review",
        "blocked",
        "failed",
    ]
    created_at: str
    updated_at: str
    auto_fix: bool
    publish_locked: bool = True
    last_action: str
    result: dict[str, Any] = Field(default_factory=dict)
    error: str | None = None


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _auth(authorization: str | None = Header(default=None)) -> None:
    if not BRIDGE_TOKEN:
        raise HTTPException(status_code=503, detail="LTX_BRIDGE_TOKEN is not configured")
    if authorization != f"Bearer {BRIDGE_TOKEN}":
        raise HTTPException(status_code=401, detail="Unauthorized")


def _job_path(job_id: str) -> Path:
    return STATE_DIR / f"{job_id}.json"


def _save(record: JobRecord) -> None:
    _job_path(record.job_id).write_text(record.model_dump_json(indent=2), encoding="utf-8")


def _load(job_id: str) -> JobRecord:
    path = _job_path(job_id)
    if not path.exists():
        raise HTTPException(status_code=404, detail="Unknown job")
    return JobRecord.model_validate_json(path.read_text(encoding="utf-8"))


def _run_control(action: str, payload: dict[str, Any]) -> dict[str, Any]:
    """Invoke the real LTX controller without shell interpolation."""
    if not CONTROL_CMD:
        raise RuntimeError("LTX_CONTROL_CMD is not configured")
    if Path(CONTROL_CMD).name == "fake_controller.py" or "fake_controller" in CONTROL_CMD:
        raise RuntimeError("mock/fake controller is forbidden in production")

    command = [CONTROL_CMD, action]
    proc = subprocess.run(
        command,
        input=json.dumps(payload),
        text=True,
        capture_output=True,
        timeout=int(os.getenv("LTX_CONTROL_TIMEOUT_SECONDS", "900")),
        check=False,
    )
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "LTX controller failed").strip()
        raise RuntimeError(detail[:4000])
    raw = proc.stdout.strip()
    if not raw:
        return {"ok": True}
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"LTX controller returned non-JSON output: {raw[:1000]}") from exc
    if not isinstance(parsed, dict):
        raise RuntimeError("LTX controller response must be a JSON object")
    return parsed


def _apply_action(record: JobRecord, action: str, extra: dict[str, Any] | None = None) -> JobRecord:
    payload = {
        "job_id": record.job_id,
        "show": record.show,
        "episode": record.episode,
        "auto_fix": record.auto_fix,
        "publish": False,
        **(extra or {}),
    }
    record.last_action = action
    record.updated_at = _now()
    try:
        record.status = "retrying" if action == "retry" else ("qc" if action == "qc" else "running")
        _save(record)
        result = _run_control(action, payload)
        record.result = result
        remote_status = str(result.get("status", "")).lower()
        if remote_status in {"ready", "ready_for_review", "complete", "completed"}:
            record.status = "ready_for_review"
        elif remote_status in {"blocked"}:
            record.status = "blocked"
        elif remote_status in {"failed", "error"}:
            record.status = "failed"
        else:
            record.status = "running"
        record.error = None
    except Exception as exc:
        record.error = str(exc)
        record.status = "failed"
    record.updated_at = _now()
    _save(record)
    return record


@app.get("/health")
def health() -> dict[str, Any]:
    fake = bool(CONTROL_CMD) and (Path(CONTROL_CMD).name == "fake_controller.py" or "fake_controller" in CONTROL_CMD)
    return {
        "ok": bool(CONTROL_CMD) and bool(BRIDGE_TOKEN) and not fake,
        "service": "ctnetwork-ltx-bridge",
        "controller_configured": bool(CONTROL_CMD),
        "token_configured": bool(BRIDGE_TOKEN),
        "mock_controller": fake,
        "publishing_locked": APPROVAL_LOCK,
    }


@app.post("/v1/production/start", response_model=JobRecord, dependencies=[Depends(_auth)])
def start_production(req: ProductionRequest) -> JobRecord:
    if req.publish:
        raise HTTPException(status_code=409, detail="Publishing is locked until explicit approval")
    job_id = uuid.uuid4().hex
    record = JobRecord(
        job_id=job_id,
        show=req.show,
        episode=req.episode,
        status="queued",
        created_at=_now(),
        updated_at=_now(),
        auto_fix=req.auto_fix,
        last_action="queued",
        result={
            "package_ref": req.package_ref,
            "visual_refs": req.visual_refs,
            "narrator": req.narrator,
            "shorts_count": req.shorts_count,
            "metadata": req.metadata,
        },
    )
    _save(record)
    return _apply_action(
        record,
        "start",
        {
            "package_ref": req.package_ref,
            "visual_refs": req.visual_refs,
            "narrator": req.narrator,
            "shorts_count": req.shorts_count,
            "metadata": req.metadata,
        },
    )


@app.get("/v1/production/{job_id}", response_model=JobRecord, dependencies=[Depends(_auth)])
def production_status(job_id: str) -> JobRecord:
    record = _load(job_id)
    try:
        result = _run_control("status", {"job_id": job_id, "publish": False})
        record.result = result
        remote_status = str(result.get("status", "")).lower()
        if remote_status in {"ready", "ready_for_review", "complete", "completed"}:
            record.status = "ready_for_review"
        elif remote_status == "blocked":
            record.status = "blocked"
        elif remote_status in {"failed", "error"}:
            record.status = "failed"
        elif remote_status:
            record.status = "running"
        record.updated_at = _now()
        _save(record)
    except Exception as exc:
        record.error = str(exc)
        record.updated_at = _now()
        _save(record)
    return record


@app.post("/v1/production/{job_id}/retry", response_model=JobRecord, dependencies=[Depends(_auth)])
def retry(job_id: str, action: JobAction) -> JobRecord:
    record = _load(job_id)
    record.auto_fix = action.auto_fix
    return _apply_action(record, "retry", action.model_dump())


@app.post("/v1/production/{job_id}/render", response_model=JobRecord, dependencies=[Depends(_auth)])
def render(job_id: str, action: JobAction) -> JobRecord:
    return _apply_action(_load(job_id), "render", action.model_dump())


@app.post("/v1/production/{job_id}/shorts", response_model=JobRecord, dependencies=[Depends(_auth)])
def shorts(job_id: str, req: ShortsRequest) -> JobRecord:
    return _apply_action(_load(job_id), "shorts", req.model_dump())


@app.post("/v1/production/{job_id}/qc", response_model=JobRecord, dependencies=[Depends(_auth)])
def qc(job_id: str, action: JobAction) -> JobRecord:
    record = _apply_action(_load(job_id), "qc", action.model_dump())
    if record.status == "running" and record.result.get("qc_passed") is True:
        record.status = "ready_for_review"
        record.updated_at = _now()
        _save(record)
    return record


@app.get("/v1/production/{job_id}/outputs", dependencies=[Depends(_auth)])
def outputs(job_id: str) -> dict[str, Any]:
    record = _load(job_id)
    try:
        result = _run_control("outputs", {"job_id": job_id, "publish": False})
    except Exception as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    return {
        "job_id": job_id,
        "show": record.show,
        "episode": record.episode,
        "publishing_locked": True,
        "outputs": result,
    }


@app.get("/v1/production/{job_id}/artifact/{artifact_name}", dependencies=[Depends(_auth)])
def download_artifact(job_id: str, artifact_name: str):
    from fastapi.responses import FileResponse

    _load(job_id)
    try:
        result = _run_control("outputs", {"job_id": job_id, "publish": False})
    except Exception as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    candidates: dict[str, str] = {}
    if isinstance(result.get("master"), str):
        candidates["master"] = result["master"]
    if isinstance(result.get("thumbnail"), str):
        candidates["thumbnail"] = result["thumbnail"]
    for idx, p in enumerate(result.get("shorts") or [], 1):
        if isinstance(p, str):
            candidates[f"short_{idx:02d}"] = p

    if artifact_name not in candidates:
        raise HTTPException(status_code=404, detail="Artifact not available")
    path = Path(candidates[artifact_name]).resolve()
    ready_root = Path("/workspace/ctnetwork-local/ready_for_approval").resolve()
    try:
        path.relative_to(ready_root)
    except ValueError as exc:
        raise HTTPException(status_code=403, detail="Artifact escaped approval directory") from exc
    if not path.exists() or not path.is_file() or path.stat().st_size < 1:
        raise HTTPException(status_code=404, detail="Artifact file missing")
    media = "video/mp4" if path.suffix.lower() == ".mp4" else "application/octet-stream"
    return FileResponse(path, media_type=media, filename=path.name)


@app.post("/v1/publish")
def publish_disabled() -> None:
    raise HTTPException(
        status_code=423,
        detail="Publishing is intentionally disabled in the LTX production bridge. Approval is required first.",
    )
