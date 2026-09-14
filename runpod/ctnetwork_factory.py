#!/usr/bin/env python3
"""CTNETWORK local production controller.

This controller owns deterministic post-generation production: package assembly,
audio mastering, Shorts, thumbnail extraction/association, QC, checksums and the
manual approval gate. It intentionally contains no publishing implementation.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

try:
    import yaml
except Exception:
    yaml = None

ROOT = Path(os.environ.get("CTN_ROOT", "/workspace/ctnetwork-local"))
READY = ROOT / "ready_for_approval"
JOBS = ROOT / "jobs"
STATUS = ROOT / "status"
RECIPE_ROOT = ROOT / "recipes"
REPO_RECIPE_ROOT = Path(__file__).resolve().parents[1] / "ctnetwork" / "shows"

STAGES = [
    "PLANNED", "NARRATION", "VISUALS", "ASSEMBLY", "AUDIO", "SHORTS",
    "THUMBNAIL", "QC", "READY_FOR_APPROVAL"
]


def utcnow() -> str:
    return datetime.now(timezone.utc).isoformat()


def sh(cmd: list[str], *, check: bool = True, capture: bool = False) -> subprocess.CompletedProcess:
    print("+", " ".join(map(str, cmd)), flush=True)
    return subprocess.run(cmd, check=check, text=True, capture_output=capture)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(4 * 1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def ffprobe(path: Path) -> dict:
    p = sh([
        "ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", str(path)
    ], capture=True)
    return json.loads(p.stdout)


def media_summary(path: Path) -> dict:
    data = ffprobe(path)
    streams = data.get("streams", [])
    fmt = data.get("format", {})
    video = [s for s in streams if s.get("codec_type") == "video"]
    audio = [s for s in streams if s.get("codec_type") == "audio"]
    duration = float(fmt.get("duration") or 0)
    out = {
        "path": str(path),
        "exists": path.exists(),
        "bytes": path.stat().st_size if path.exists() else 0,
        "duration": duration,
        "video_streams": len(video),
        "audio_streams": len(audio),
    }
    if video:
        out.update({
            "width": int(video[0].get("width") or 0),
            "height": int(video[0].get("height") or 0),
            "video_codec": video[0].get("codec_name"),
        })
    if audio:
        out.update({
            "audio_codec": audio[0].get("codec_name"),
            "sample_rate": int(audio[0].get("sample_rate") or 0),
        })
    return out


def write_json(path: Path, obj: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, indent=2, sort_keys=True) + "\n")


class Job:
    def __init__(self, job_id: str, show: str, title: str):
        self.job_id = job_id
        self.show = show
        self.title = title
        self.work = JOBS / job_id
        self.out = READY / job_id
        self.state_path = self.work / "state.json"
        self.work.mkdir(parents=True, exist_ok=True)
        self.out.mkdir(parents=True, exist_ok=True)
        if not self.state_path.exists():
            self.state = {
                "job_id": job_id,
                "show": show,
                "title": title,
                "state": "PLANNED",
                "history": [{"state": "PLANNED", "at": utcnow()}],
                "retryable_failures": [],
                "blocked_failures": [],
                "publish_allowed": False,
                "approved": False,
            }
            self.save()
        else:
            self.state = json.loads(self.state_path.read_text())

    def save(self):
        write_json(self.state_path, self.state)

    def stage(self, name: str, detail: str | None = None):
        self.state["state"] = name
        event = {"state": name, "at": utcnow()}
        if detail:
            event["detail"] = detail
        self.state.setdefault("history", []).append(event)
        self.save()
        print(f"STATE {name}: {detail or ''}", flush=True)

    def retryable(self, stage: str, error: str):
        self.state.setdefault("retryable_failures", []).append({"stage": stage, "error": error, "at": utcnow()})
        self.save()

    def block(self, stage: str, error: str):
        self.state["state"] = "FAILED_BLOCKED"
        self.state.setdefault("blocked_failures", []).append({"stage": stage, "error": error, "at": utcnow()})
        self.save()
        raise RuntimeError(f"BLOCKED {stage}: {error}")


def validate_source(path: Path, kind: str, job: Job):
    if not path.exists() or path.stat().st_size < 1024:
        job.block(kind.upper(), f"missing or empty source: {path}")


def master_video(video: Path, narration: Path, out: Path, job: Job) -> None:
    job.stage("ASSEMBLY", "assemble visual master with narration")
    out.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        "ffmpeg", "-y", "-stream_loop", "-1", "-i", str(video), "-i", str(narration),
        "-map", "0:v:0", "-map", "1:a:0",
        "-vf", "format=yuv420p",
        "-af", "loudnorm=I=-16:TP=-1.5:LRA=11",
        "-c:v", "libx264", "-preset", "medium", "-crf", "18",
        "-c:a", "aac", "-b:a", "192k", "-ar", "48000",
        "-shortest", "-movflags", "+faststart", str(out),
    ]
    try:
        sh(cmd)
    except Exception as exc:
        job.retryable("ASSEMBLY", repr(exc))
        # Targeted repair: conservative codec/preset only; do not regenerate sources.
        sh([
            "ffmpeg", "-y", "-stream_loop", "-1", "-i", str(video), "-i", str(narration),
            "-map", "0:v:0", "-map", "1:a:0", "-vf", "format=yuv420p",
            "-af", "loudnorm=I=-16:TP=-1.5:LRA=11",
            "-c:v", "libx264", "-preset", "fast", "-crf", "20",
            "-c:a", "aac", "-b:a", "160k", "-ar", "48000", "-shortest",
            "-movflags", "+faststart", str(out),
        ])
    job.stage("AUDIO", "narration normalized to -16 LUFS target with peak protection")


def make_short(master: Path, out: Path, seconds: float = 12.0) -> None:
    sh([
        "ffmpeg", "-y", "-i", str(master), "-t", f"{seconds:.2f}",
        "-vf", "scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,format=yuv420p",
        "-c:v", "libx264", "-preset", "fast", "-crf", "19",
        "-c:a", "aac", "-b:a", "160k", "-ar", "48000", "-movflags", "+faststart", str(out),
    ])


def make_thumbnail(master: Path, out: Path) -> None:
    sh([
        "ffmpeg", "-y", "-ss", "0.5", "-i", str(master), "-frames:v", "1",
        "-vf", "scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720",
        "-q:v", "2", str(out),
    ])


def blackframe_check(path: Path) -> dict:
    p = subprocess.run([
        "ffmpeg", "-hide_banner", "-i", str(path), "-vf", "blackdetect=d=1:pix_th=0.98",
        "-an", "-f", "null", "-"
    ], text=True, capture_output=True)
    durations = [float(x) for x in re_findall(r"black_duration:([0-9.]+)", p.stderr)]
    total_black = sum(durations)
    duration = media_summary(path)["duration"]
    return {
        "detected_black_seconds": round(total_black, 3),
        "duration": duration,
        "black_ratio": round(total_black / duration, 4) if duration else 1.0,
        "pass": bool(duration and total_black / duration < 0.80),
    }


def re_findall(pattern: str, text: str):
    import re
    return re.findall(pattern, text)


def qc_media(path: Path, *, expect_video: bool, expect_audio: bool, vertical: bool = False) -> dict:
    s = media_summary(path)
    checks = {
        "file_nonempty": s["bytes"] > 4096,
        "duration": s["duration"] > 0.5,
        "video_present": (s["video_streams"] >= 1) if expect_video else True,
        "audio_present": (s["audio_streams"] >= 1) if expect_audio else True,
    }
    if vertical and expect_video:
        checks["vertical_aspect"] = s.get("height", 0) > s.get("width", 0)
    if expect_video:
        black = blackframe_check(path)
        checks["not_mostly_black"] = black["pass"]
    else:
        black = None
    return {"summary": s, "checks": checks, "blackframe": black, "pass": all(checks.values())}


def copy_recipes_to_factory() -> None:
    if not REPO_RECIPE_ROOT.exists():
        return
    RECIPE_ROOT.mkdir(parents=True, exist_ok=True)
    for src in REPO_RECIPE_ROOT.glob("*.yaml"):
        shutil.copy2(src, RECIPE_ROOT / src.name)


def acceptance(job_id: str = "factory-acceptance") -> Path:
    show = "CTNETWORK Factory Acceptance"
    job = Job(job_id, show, "Local Factory Acceptance")
    source_video = READY / "ltx25-official-smoke.mp4"
    source_audio = READY / "qwen-official-smoke.wav"
    validate_source(source_video, "visuals", job)
    validate_source(source_audio, "narration", job)
    job.stage("NARRATION", str(source_audio))
    job.stage("VISUALS", str(source_video))

    master = job.out / "master.mp4"
    short = job.out / "short_01_9x16.mp4"
    thumb = job.out / "thumbnail.jpg"
    master_video(source_video, source_audio, master, job)

    job.stage("SHORTS", "build vertical platform-safe acceptance Short")
    make_short(master, short, 12.0)
    job.stage("THUMBNAIL", "extract 1280x720 review thumbnail")
    make_thumbnail(master, thumb)

    metadata = {
        "show": show,
        "title": "CTNETWORK Local Factory Acceptance",
        "description": "Mechanical acceptance package. Not for publication.",
        "shorts": [{"file": short.name, "format": "9:16", "publish": False}],
        "thumbnail": thumb.name,
        "burned_in_captions": False,
        "publish": False,
    }
    write_json(job.out / "metadata.json", metadata)

    job.stage("QC", "ffprobe + stream/aspect/blackframe/checksum verification")
    qc = {
        "master": qc_media(master, expect_video=True, expect_audio=True),
        "short_01": qc_media(short, expect_video=True, expect_audio=True, vertical=True),
        "thumbnail": {
            "exists": thumb.exists(),
            "bytes": thumb.stat().st_size if thumb.exists() else 0,
            "pass": thumb.exists() and thumb.stat().st_size > 4096,
        },
    }
    qc["pass"] = qc["master"]["pass"] and qc["short_01"]["pass"] and qc["thumbnail"]["pass"]
    checksums = {}
    for p in (master, short, thumb, job.out / "metadata.json"):
        checksums[p.name] = sha256(p)
    write_json(job.out / "checksums.json", checksums)
    write_json(job.out / "qc.json", qc)
    if not qc["pass"]:
        job.block("QC", "acceptance package failed media QC")

    approval = {
        "job_id": job.job_id,
        "state": "READY_FOR_APPROVAL",
        "requires_manual_approval": True,
        "approved": False,
        "publish_allowed": False,
        "publishing_implemented": False,
        "created_at": utcnow(),
        "files": [master.name, short.name, thumb.name, "metadata.json", "qc.json", "checksums.json"],
        "note": "No external upload/publish action is permitted by this controller.",
    }
    write_json(job.out / "approval.json", approval)
    job.state["approved"] = False
    job.state["publish_allowed"] = False
    job.stage("READY_FOR_APPROVAL", str(job.out))
    (STATUS / "factory_acceptance.status").parent.mkdir(parents=True, exist_ok=True)
    (STATUS / "factory_acceptance.status").write_text("PASS\n")
    copy_recipes_to_factory()
    print(f"FACTORY_ACCEPTANCE_PASS={job.out}")
    return job.out


def load_manifest(path: Path) -> dict:
    if path.suffix.lower() == ".json":
        return json.loads(path.read_text())
    if yaml is None:
        raise RuntimeError("PyYAML is required for YAML manifests")
    return yaml.safe_load(path.read_text())


def run_manifest(path: Path) -> Path:
    m = load_manifest(path)
    job_id = m.get("job_id") or datetime.now().strftime("ctn-%Y%m%d-%H%M%S")
    job = Job(job_id, m.get("show", "CTNETWORK"), m.get("title", job_id))
    narration = Path(m["inputs"]["narration"])
    visual = Path(m["inputs"]["visual"])
    validate_source(narration, "narration", job)
    validate_source(visual, "visuals", job)
    job.stage("NARRATION", str(narration))
    job.stage("VISUALS", str(visual))
    master = job.out / "master.mp4"
    master_video(visual, narration, master, job)
    shorts_count = int(m.get("shorts", {}).get("count", 1))
    shorts = []
    job.stage("SHORTS", f"count={shorts_count}")
    for i in range(shorts_count):
        p = job.out / f"short_{i+1:02d}_9x16.mp4"
        make_short(master, p, float(m.get("shorts", {}).get("seconds", 12)))
        shorts.append(p)
    job.stage("THUMBNAIL")
    thumb = job.out / "thumbnail.jpg"
    make_thumbnail(master, thumb)
    job.stage("QC")
    qc = {"master": qc_media(master, expect_video=True, expect_audio=True)}
    for i, p in enumerate(shorts, 1):
        qc[f"short_{i:02d}"] = qc_media(p, expect_video=True, expect_audio=True, vertical=True)
    qc["pass"] = all(v.get("pass", False) for v in qc.values() if isinstance(v, dict))
    write_json(job.out / "qc.json", qc)
    if not qc["pass"]:
        job.block("QC", "manifest output failed QC")
    write_json(job.out / "approval.json", {
        "job_id": job_id, "requires_manual_approval": True, "approved": False,
        "publish_allowed": False, "publishing_implemented": False, "created_at": utcnow()
    })
    job.stage("READY_FOR_APPROVAL", str(job.out))
    return job.out


def approve(job_id: str) -> None:
    p = READY / job_id / "approval.json"
    if not p.exists():
        raise SystemExit(f"approval manifest not found: {p}")
    a = json.loads(p.read_text())
    a["approved"] = True
    a["approved_at"] = utcnow()
    # Approval does not implicitly enable publishing. Publisher is a separate explicit gate.
    a["publish_allowed"] = False
    write_json(p, a)
    print(f"APPROVED_FOR_REVIEW_COMPLETE={job_id}; PUBLISH_ALLOWED=false")


def status(job_id: str | None) -> None:
    if job_id:
        p = JOBS / job_id / "state.json"
        print(p.read_text() if p.exists() else json.dumps({"job_id": job_id, "state": "UNKNOWN"}))
        return
    rows = []
    for p in sorted(JOBS.glob("*/state.json")):
        try:
            rows.append(json.loads(p.read_text()))
        except Exception:
            pass
    print(json.dumps(rows, indent=2))


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("acceptance")
    a.add_argument("--job-id", default="factory-acceptance")
    r = sub.add_parser("run-manifest")
    r.add_argument("manifest", type=Path)
    s = sub.add_parser("status")
    s.add_argument("--job-id")
    p = sub.add_parser("approve")
    p.add_argument("job_id")
    args = ap.parse_args()
    if args.cmd == "acceptance": acceptance(args.job_id)
    elif args.cmd == "run-manifest": run_manifest(args.manifest)
    elif args.cmd == "status": status(args.job_id)
    elif args.cmd == "approve": approve(args.job_id)


if __name__ == "__main__":
    main()
