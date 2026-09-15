#!/usr/bin/env python3
"""Real CTNETWORK production controller used by the LTX bridge.

Contract: ctnetwork_production_control.py <action>, JSON on stdin, JSON on stdout.
No publishing action exists. All work lands under ready_for_approval.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(os.environ.get("CTN_ROOT", "/workspace/ctnetwork-local"))
JOBS = ROOT / "jobs"
READY = ROOT / "ready_for_approval"
CONTROLLER = ROOT / "controller"
FACTORY = CONTROLLER / "ctnetwork_factory_v2.py"
CORE_PY = ROOT / "envs/core/bin/python"


def emit(obj: dict[str, Any], rc: int = 0) -> None:
    print(json.dumps(obj, sort_keys=True))
    raise SystemExit(rc)


def read_json(path: Path, default: Any = None) -> Any:
    try:
        return json.loads(path.read_text())
    except Exception:
        return default


def state(job_id: str) -> dict[str, Any]:
    return read_json(JOBS / job_id / "state.json", {"job_id": job_id, "state": "UNKNOWN"})


def output_record(job_id: str) -> dict[str, Any]:
    out = READY / job_id
    files = {}
    if out.exists():
        for p in sorted(out.iterdir()):
            if p.is_file():
                files[p.name] = {"path": str(p), "bytes": p.stat().st_size}
    st = state(job_id)
    ready = st.get("state") == "READY_FOR_APPROVAL"
    result: dict[str, Any] = {
        "status": "ready_for_review" if ready else str(st.get("state", "unknown")).lower(),
        "job_id": job_id,
        "state": st,
        "output_dir": str(out),
        "files": files,
        "publish_allowed": False,
    }
    master = out / "master.mp4"
    if master.exists(): result["master"] = str(master)
    result["shorts"] = [str(p) for p in sorted(out.glob("short_*.mp4"))]
    thumb = out / "thumbnail.jpg"
    if thumb.exists(): result["thumbnail"] = str(thumb)
    meta = out / "metadata.json"
    if meta.exists(): result["metadata"] = str(meta)
    qc = read_json(out / "qc.json", {})
    if qc: result["qc"] = qc; result["qc_passed"] = bool(qc.get("pass"))
    return result


def manifest_from_payload(payload: dict[str, Any]) -> Path:
    job_id = str(payload["job_id"])
    md = payload.get("metadata") or {}
    package_ref = payload.get("package_ref")
    candidates = [md.get("manifest_path"), package_ref]
    for raw in candidates:
        if raw:
            p = Path(str(raw))
            if p.exists() and p.suffix.lower() in {".json", ".yaml", ".yml"}:
                return p

    narrator = payload.get("narrator") or {}
    script = md.get("script") or md.get("narration_text") or payload.get("script")
    voice_ref = narrator.get("voice_reference") or md.get("voice_reference")
    voice_ref_text = narrator.get("voice_reference_text") or md.get("voice_reference_text")
    visual_prompt = md.get("visual_prompt") or md.get("prompt")
    if not script or not voice_ref or not voice_ref_text or not visual_prompt:
        raise RuntimeError("REAL_CONTROLLER_REQUIRES_SCRIPT_VOICE_REFERENCE_VOICE_REFERENCE_TEXT_AND_VISUAL_PROMPT")

    work = JOBS / job_id
    work.mkdir(parents=True, exist_ok=True)
    manifest = {
        "job_id": job_id,
        "show": payload.get("show") or "CTNETWORK",
        "title": payload.get("episode") or job_id,
        "description": md.get("description", ""),
        "tags": md.get("tags", []),
        "narration": {
            "text": script,
            "voice_reference": voice_ref,
            "voice_reference_text": voice_ref_text,
            "language": narrator.get("language") or md.get("language") or "English",
        },
        "visuals": {
            "prompt": visual_prompt,
            "quality": md.get("quality", "dfr"),
            "width": int(md.get("width", 768)),
            "height": int(md.get("height", 512)),
            "frames": int(md.get("frames", 121)),
            "seed": int(md.get("seed", 42)),
        },
        "shorts": {
            "count": int(payload.get("shorts_count") or md.get("shorts_count") or 1),
            "seconds": float(md.get("short_seconds", 12)),
        },
    }
    p = work / "bridge-manifest.json"
    p.write_text(json.dumps(manifest, indent=2) + "\n")
    return p


def run_factory(manifest: Path) -> None:
    if not CORE_PY.exists(): raise RuntimeError(f"CORE_PYTHON_MISSING:{CORE_PY}")
    if not FACTORY.exists(): raise RuntimeError(f"FACTORY_CONTROLLER_MISSING:{FACTORY}")
    proc = subprocess.run([str(CORE_PY), str(FACTORY), "run-manifest", str(manifest)], text=True, capture_output=True)
    log = manifest.parent / "bridge-controller.log"
    log.write_text((proc.stdout or "") + "\n--- STDERR ---\n" + (proc.stderr or ""))
    if proc.returncode:
        raise RuntimeError((proc.stderr or proc.stdout or "factory failed")[-3500:])


def main() -> None:
    if len(sys.argv) != 2: emit({"status": "failed", "error": "action required"}, 2)
    action = sys.argv[1].lower()
    if action not in {"start", "status", "retry", "render", "shorts", "qc", "outputs"}:
        emit({"status": "failed", "error": f"unsupported action:{action}"}, 2)
    payload = json.load(sys.stdin)
    if payload.get("publish") is not False:
        emit({"status": "failed", "error": "publishing lock missing"}, 2)
    job_id = str(payload.get("job_id") or "")
    if not job_id: emit({"status": "failed", "error": "job_id missing"}, 2)

    try:
        if action in {"status", "outputs"}:
            emit(output_record(job_id))

        current = state(job_id)
        if action in {"qc", "render", "shorts"} and current.get("state") == "READY_FOR_APPROVAL":
            emit(output_record(job_id))

        if action == "start":
            manifest = manifest_from_payload(payload)
            run_factory(manifest)
            emit(output_record(job_id))

        if action == "retry":
            manifest = JOBS / job_id / "bridge-manifest.json"
            if not manifest.exists():
                manifest = manifest_from_payload(payload)
            run_factory(manifest)
            emit(output_record(job_id))

        # The real factory runs render/shorts/QC as one deterministic transaction.
        # If a client requests an intermediate action before completion, return the
        # real state rather than simulating success.
        emit(output_record(job_id))
    except Exception as exc:
        emit({"status": "failed", "job_id": job_id, "error": str(exc), "publish_allowed": False}, 1)


if __name__ == "__main__":
    main()
