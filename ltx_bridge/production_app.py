from __future__ import annotations

from pathlib import Path
from typing import Any

from fastapi import Depends, HTTPException
from fastapi.responses import FileResponse

from app import app, _auth, _load, _run_control


@app.get("/v1/production/{job_id}/artifact/{artifact_name}", dependencies=[Depends(_auth)])
def download_artifact(job_id: str, artifact_name: str):
    """Retrieve a real finished artifact from the local factory.

    Only files explicitly returned by the real production controller are eligible;
    arbitrary filesystem paths are never accepted from the caller.
    """
    _load(job_id)
    try:
        outputs: dict[str, Any] = _run_control("outputs", {"job_id": job_id, "publish": False})
    except Exception as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    candidates: dict[str, str] = {}
    master = outputs.get("master")
    if isinstance(master, str):
        candidates["master"] = master
    thumb = outputs.get("thumbnail")
    if isinstance(thumb, str):
        candidates["thumbnail"] = thumb
    for idx, p in enumerate(outputs.get("shorts") or [], 1):
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
