#!/usr/bin/env python3
"""Restore The Case Against LeBron episode 1 Shorts without manual uploading.

The source episode is the corrected public YouTube master. This script:
1. downloads that exact master,
2. rebuilds the six approved vertical Shorts with the locked CTNETWORK layout,
3. submits them to the Case Upload-Post profile with YouTube scheduling,
4. persists an idempotent receipt for every upload.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import time
from datetime import datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

import requests

ROOT = Path(__file__).resolve().parent
WORK = ROOT / "lebron_restore_work"
OUT = WORK / "shorts"
RECEIPT = WORK / "restore-receipt.json"
VIDEO_ID = "42ALSvtFJG8"
VIDEO_URL = f"https://www.youtube.com/watch?v={VIDEO_ID}"
PROFILE = "Case"
API = "https://api.upload-post.com/api"
TZ = ZoneInfo("America/New_York")
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

# Start points were recovered against the corrected 17:34 master. Durations are the
# actual saved corrected Short durations, not estimates from the old restore note.
SHORTS = [
    {
        "n": 1,
        "start": 91.70,
        "duration": 46.466667,
        "hook": ["4 WINS. 6 LOSSES.", "FAIR EVIDENCE?"],
        "title": "Why LeBron’s Finals Record Still Gets Used Against Him | The Case Against LeBron #Shorts",
        "description": "The prosecution starts with the simplest GOAT argument: 10 Finals, 4 championships, 6 losses. Is that fair evidence against LeBron — or does reaching 10 Finals make the case stronger?\n\n⚖️ Case made. You decide.\n\n#LeBronJames #GOATDebate #NBA #Basketball #Shorts",
    },
    {
        "n": 2,
        "start": 138.12,
        "duration": 51.0,
        "hook": ["THE 2011 FINALS", "THE HARDEST EXHIBIT"],
        "title": "2011 Is the Hardest Part of LeBron’s GOAT Case | The Case Against LeBron #Shorts",
        "description": "The 2011 Finals are still the prosecution’s strongest exhibit. Miami had huge expectations — and LeBron had one of the toughest series of his prime.\n\n⚖️ Case made. You decide.\n\n#LeBronJames #NBAFinals #GOATDebate #NBA #Shorts",
    },
    {
        "n": 3,
        "start": 232.50,
        "duration": 64.266667,
        "hook": ["SUPERTEAMS", "OR SUPERSTAR POWER?"],
        "title": "Did LeBron Control His Title Windows Too Much? | The Case Against LeBron #Shorts",
        "description": "Player movement changed the modern NBA, and LeBron helped redefine what superstar control could look like. Does that weaken the GOAT case — or prove adaptability?\n\n⚖️ Case made. You decide.\n\n#LeBronJames #NBA #GOATDebate #Basketball #Shorts",
    },
    {
        "n": 4,
        "start": 898.05,
        "duration": 56.4,
        "hook": ["LEBRON VS JORDAN", "LONGEVITY OR PEAK?"],
        "title": "LeBron vs Jordan: Longevity or Peak? | The Case Against LeBron #Shorts",
        "description": "This may be the real GOAT argument: do you value the longest sustained greatness, or the most overwhelming peak?\n\n⚖️ Case made. You decide.\n\n#LeBronJames #MichaelJordan #GOATDebate #NBA #Shorts",
    },
    {
        "n": 5,
        "start": 817.55,
        "duration": 51.2,
        "hook": ["DOWN 3-1.", "THE DEFENSE ANSWERS."],
        "title": "2016 Is LeBron’s Strongest GOAT Defense | The Case Against LeBron #Shorts",
        "description": "If the Finals record is evidence against LeBron, then the 2016 comeback belongs on the biggest screen in the courtroom. Down 3–1 against a 73-win team — and Cleveland finished the comeback.\n\n⚖️ Case made. You decide.\n\n#LeBronJames #NBAFinals #Cavaliers #GOATDebate #Shorts",
    },
    {
        "n": 6,
        "start": 981.00,
        "duration": 73.27,
        "hook": ["THE FINAL VERDICT", "CASE MADE. YOU DECIDE."],
        "title": "Did the Case Against LeBron Actually Survive? | The Case Against LeBron #Shorts",
        "description": "After the evidence and the defense, what actually survives cross-examination? That’s the real point of the GOAT debate.\n\n⚖️ Case made. You decide.\n\n#LeBronJames #GOATDebate #NBA #Basketball #Shorts",
    },
]


def run(cmd: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    print("+", " ".join(cmd), flush=True)
    return subprocess.run(cmd, text=True, check=check)


def probe_duration(path: Path) -> float:
    p = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", str(path)],
        capture_output=True,
        text=True,
        check=True,
    )
    return float(p.stdout.strip())


def download_master() -> Path:
    WORK.mkdir(parents=True, exist_ok=True)
    target = WORK / "lebron_corrected_master.mp4"
    if target.exists() and probe_duration(target) > 1000:
        return target

    attempts = [
        [
            "yt-dlp", "--no-playlist", "--retries", "10", "--fragment-retries", "10",
            "--merge-output-format", "mp4", "-f", "bv*[height<=720]+ba/b[height<=720]",
            "-o", str(WORK / "download.%(ext)s"), VIDEO_URL,
        ],
        [
            "yt-dlp", "--no-playlist", "--retries", "10", "--fragment-retries", "10",
            "--extractor-args", "youtube:player_client=web,android_vr",
            "--merge-output-format", "mp4", "-f", "b[height<=720]/best[height<=720]/best",
            "-o", str(WORK / "download.%(ext)s"), VIDEO_URL,
        ],
    ]
    last_error: Exception | None = None
    for cmd in attempts:
        try:
            run(cmd)
            candidates = sorted(WORK.glob("download.*"), key=lambda p: p.stat().st_mtime, reverse=True)
            if not candidates:
                raise RuntimeError("yt-dlp completed without a downloaded file")
            src = candidates[0]
            run([
                "ffmpeg", "-y", "-i", str(src), "-map", "0:v:0", "-map", "0:a:0",
                "-c", "copy", "-movflags", "+faststart", str(target),
            ])
            if probe_duration(target) < 1000:
                raise RuntimeError("Downloaded LeBron master is unexpectedly short")
            return target
        except Exception as exc:  # try the fallback extractor settings
            last_error = exc
            target.unlink(missing_ok=True)
    raise RuntimeError(f"Could not download corrected LeBron master: {last_error}")


def esc(text: str) -> str:
    return text.replace("\\", r"\\").replace("'", r"\'").replace(":", r"\:").replace("%", r"\%")


def render_short(master: Path, spec: dict) -> Path:
    OUT.mkdir(parents=True, exist_ok=True)
    out = OUT / f"LeBron_EP01_Short_{spec['n']:02d}.mp4"
    if out.exists() and abs(probe_duration(out) - float(spec["duration"])) < 1.0:
        return out

    hook1, hook2 = map(esc, spec["hook"])
    gold = "0xE1BB66"
    bg = "0x0E0B18"
    duration = float(spec["duration"])
    vf = (
        f"color=c={bg}:s=720x1280:r=15:d={duration:.3f}[bg];"
        "[0:v]scale=720:405:flags=lanczos[clip];"
        "[bg][clip]overlay=0:420[base];"
        "[base]"
        f"drawbox=x=30:y=401:w=660:h=3:color={gold}:t=fill,"
        f"drawbox=x=30:y=843:w=660:h=3:color={gold}:t=fill,"
        f"drawtext=fontfile={FONT}:text='THE CASE AGAINST':fontsize=29:fontcolor={gold}:x=(w-text_w)/2:y=176,"
        f"drawtext=fontfile={FONT}:text='{hook1}':fontsize=38:fontcolor=white:x=(w-text_w)/2:y=257,"
        f"drawtext=fontfile={FONT}:text='{hook2}':fontsize=38:fontcolor=white:x=(w-text_w)/2:y=315,"
        f"drawtext=fontfile={FONT}:text='LEBRON ON TRIAL':fontsize=31:fontcolor={gold}:x=(w-text_w)/2:y=907,"
        f"drawtext=fontfile={FONT}:text='FULL EPISODE ON THE CHANNEL':fontsize=23:fontcolor=white:x=(w-text_w)/2:y=963,"
        f"drawtext=fontfile={FONT}:text='CTNETWORK':fontsize=26:fontcolor={gold}:x=(w-text_w)/2:y=1054,"
        "format=yuv420p[v]"
    )
    run([
        "ffmpeg", "-y", "-ss", f"{float(spec['start']):.3f}", "-t", f"{duration:.3f}", "-i", str(master),
        "-filter_complex", vf, "-map", "[v]", "-map", "0:a:0", "-r", "15",
        "-c:v", "libx264", "-preset", "veryfast", "-crf", "22",
        "-c:a", "aac", "-b:a", "160k", "-ar", "48000", "-movflags", "+faststart", str(out),
    ])
    actual = probe_duration(out)
    if abs(actual - duration) > 1.2:
        raise RuntimeError(f"Short {spec['n']} duration mismatch: {actual:.3f} vs {duration:.3f}")
    return out


def upcoming_slots(count: int) -> list[datetime]:
    # Preserve the established staggered Shorts cadence. Keep the first restored Short
    # at least two hours ahead so YouTube has time to finish processing the private upload.
    now = datetime.now(TZ)
    earliest = now + timedelta(hours=2)
    slots: list[datetime] = []
    day = now.date()
    for offset in range(5):
        current_day = day + timedelta(days=offset)
        for hour in (8, 10, 12, 14, 16, 18):
            candidate = datetime(current_day.year, current_day.month, current_day.day, hour, 0, tzinfo=TZ)
            if candidate >= earliest:
                slots.append(candidate)
                if len(slots) == count:
                    return slots
    raise RuntimeError("Could not allocate enough release slots")


def response_json(response: requests.Response) -> dict:
    try:
        payload = response.json()
    except Exception:
        payload = {"raw": response.text}
    if not response.ok or payload.get("success") is False:
        raise RuntimeError(f"Upload-Post rejected request HTTP {response.status_code}: {payload}")
    return payload


def result_for(payload: dict, platform: str) -> dict:
    results = payload.get("results", {})
    if isinstance(results, list):
        return next((r for r in results if r.get("platform") == platform), {})
    return results.get(platform, {}) if isinstance(results, dict) else {}


def terminal_result(payload: dict) -> tuple[bool, bool]:
    result = result_for(payload, "youtube")
    status = str(result.get("status") or payload.get("status") or "").lower()
    if result.get("success") is True or status == "completed":
        return True, True
    if result.get("skipped") or status in {"failed", "skipped", "error"}:
        return True, False
    return False, False


def save_receipts(receipts: dict) -> None:
    RECEIPT.parent.mkdir(parents=True, exist_ok=True)
    RECEIPT.write_text(json.dumps(receipts, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def publish(short_files: list[Path]) -> None:
    key = os.environ.get("UPLOAD_POST_API_KEY", "").strip()
    if not key:
        raise RuntimeError("UPLOAD_POST_API_KEY secret is missing")
    headers = {"Authorization": f"Apikey {key}"}
    # Verify the configured API key/profile before touching uploads.
    response_json(requests.get(API + "/uploadposts/me", headers=headers, timeout=60))

    receipts = json.loads(RECEIPT.read_text(encoding="utf-8")) if RECEIPT.exists() else {}
    slots = upcoming_slots(len(SHORTS))

    # Submit all uploads first; poll after submission so one slow transcode does not block the others.
    for spec, path, scheduled in zip(SHORTS, short_files, slots):
        identity = f"case-lebron-ep01-restored-short-{spec['n']:02d}-20260911"
        entry = receipts.setdefault(identity, {})
        entry.update({"title": spec["title"], "file": path.name, "requested_release_at": scheduled.isoformat()})
        if entry.get("accepted") or entry.get("final"):
            continue
        data = {
            "user": PROFILE,
            "platform[]": "youtube",
            "title": spec["title"],
            "description": spec["description"],
            "async_upload": "true",
            "external_id": identity,
            "privacyStatus": "private",
            "youtube_publish_at": scheduled.isoformat(),
            "selfDeclaredMadeForKids": "false",
        }
        upload_headers = {**headers, "Idempotency-Key": identity}
        try:
            with path.open("rb") as fp:
                resp = requests.post(
                    API + "/upload",
                    headers=upload_headers,
                    data=data,
                    files={"video": (path.name, fp, "video/mp4")},
                    timeout=900,
                )
            entry["accepted"] = response_json(resp)
            entry["state"] = "submitted"
        except Exception as exc:
            entry["state"] = "submit_failed"
            entry["error"] = str(exc)
        save_receipts(receipts)

    deadline = time.monotonic() + 1800
    pending = {k for k, v in receipts.items() if v.get("state") == "submitted"}
    while pending and time.monotonic() < deadline:
        for identity in list(pending):
            entry = receipts[identity]
            payload = entry.get("accepted", {})
            request_id = payload.get("request_id") or payload.get("job_id")
            if not request_id:
                entry["state"] = "failed"
                entry["error"] = "Upload response missing request_id/job_id"
                pending.remove(identity)
                save_receipts(receipts)
                continue
            try:
                current = response_json(requests.get(
                    API + "/uploadposts/status", headers=headers,
                    params={"request_id": request_id}, timeout=60,
                ))
                terminal, success = terminal_result(current)
                entry["last_status"] = current
                if terminal:
                    entry["final"] = current
                    entry["state"] = "scheduled" if success else "failed"
                    pending.remove(identity)
                save_receipts(receipts)
            except Exception as exc:
                entry["last_poll_error"] = str(exc)
                save_receipts(receipts)
        if pending:
            time.sleep(12)

    for identity in pending:
        receipts[identity]["state"] = "poll_timeout"
    save_receipts(receipts)

    failed = {k: v for k, v in receipts.items() if v.get("state") not in {"scheduled"}}
    if failed:
        print(json.dumps({"restore_incomplete": failed}, indent=2, ensure_ascii=False))
        raise SystemExit(1)

    summary = [
        {"short": i + 1, "title": SHORTS[i]["title"], "release_at": slots[i].isoformat()}
        for i in range(len(SHORTS))
    ]
    print(json.dumps({"LEBRON_SHORTS_RESTORE_COMPLETE": summary}, indent=2, ensure_ascii=False))


def main() -> None:
    master = download_master()
    rendered = [render_short(master, spec) for spec in SHORTS]
    publish(rendered)


if __name__ == "__main__":
    main()
