from __future__ import annotations

import json
import mimetypes
import os
import re
import sys
import time
from pathlib import Path
from typing import Any

import requests

API_BASE = "https://api.upload-post.com/api"
PROFILE = "Whathappen"
STATUS_URL = f"{API_BASE}/uploadposts/status"
UPLOAD_URL = f"{API_BASE}/upload"


def require_file(path: Path) -> Path:
    if not path.exists() or not path.is_file():
        raise FileNotFoundError(f"Required file missing: {path}")
    if path.stat().st_size < 1024:
        raise RuntimeError(f"File is suspiciously small: {path}")
    return path


def auth_headers() -> dict[str, str]:
    key = os.environ.get("UPLOAD_POST_API_KEY", "").strip()
    if not key:
        raise RuntimeError("UPLOAD_POST_API_KEY is missing")
    return {"Authorization": f"Apikey {key}"}


def extract_youtube_result(payload: dict[str, Any]) -> dict[str, Any] | None:
    results = payload.get("results")
    if isinstance(results, dict):
        yt = results.get("youtube")
        if isinstance(yt, dict):
            return yt
    if isinstance(results, list):
        for item in results:
            if isinstance(item, dict) and item.get("platform") == "youtube":
                return item
    if payload.get("platform") == "youtube":
        return payload
    return None


def infer_video_id(result: dict[str, Any] | None) -> str | None:
    if not result:
        return None
    for key in ("video_id", "publish_id", "post_id", "id"):
        value = result.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    url = result.get("url")
    if isinstance(url, str):
        patterns = (
            r"[?&]v=([A-Za-z0-9_-]{6,})",
            r"youtu\.be/([A-Za-z0-9_-]{6,})",
            r"youtube\.com/shorts/([A-Za-z0-9_-]{6,})",
        )
        for pattern in patterns:
            match = re.search(pattern, url)
            if match:
                return match.group(1)
    return None


def poll_request(request_id: str, timeout_seconds: int = 1800) -> dict[str, Any]:
    deadline = time.time() + timeout_seconds
    last: dict[str, Any] = {}
    while time.time() < deadline:
        response = requests.get(
            STATUS_URL,
            headers=auth_headers(),
            params={"request_id": request_id},
            timeout=60,
        )
        response.raise_for_status()
        last = response.json()
        status = str(last.get("status", "")).lower()
        yt = extract_youtube_result(last)
        yt_status = str((yt or {}).get("status", "")).lower()
        yt_success = bool((yt or {}).get("success"))
        if status in {"success", "completed", "done"} or yt_success or yt_status in {"success", "completed", "done"}:
            return last
        if status in {"failed", "error"} or yt_status in {"failed", "error"}:
            raise RuntimeError(f"Upload-Post reported failure: {json.dumps(last, ensure_ascii=False)}")
        time.sleep(10)
    raise TimeoutError(f"Upload status timed out for request_id={request_id}: {json.dumps(last, ensure_ascii=False)}")


def upload_one(
    video_path: Path,
    *,
    title: str,
    description: str,
    thumbnail_path: Path | None = None,
    scheduled_date: str | None = None,
    idempotency_key: str | None = None,
) -> dict[str, Any]:
    require_file(video_path)
    files: dict[str, tuple[str, Any, str]] = {}
    handles = []
    try:
        video_handle = video_path.open("rb")
        handles.append(video_handle)
        video_type = mimetypes.guess_type(video_path.name)[0] or "video/mp4"
        files["video"] = (video_path.name, video_handle, video_type)

        if thumbnail_path is not None:
            require_file(thumbnail_path)
            thumb_handle = thumbnail_path.open("rb")
            handles.append(thumb_handle)
            thumb_type = mimetypes.guess_type(thumbnail_path.name)[0] or "image/jpeg"
            files["thumbnail"] = (thumbnail_path.name, thumb_handle, thumb_type)

        data: list[tuple[str, str]] = [
            ("user", PROFILE),
            ("platform[]", "youtube"),
            ("title", title),
            ("description", description),
            ("privacyStatus", "public"),
            ("async_upload", "true"),
            ("selfDeclaredMadeForKids", "false"),
        ]
        if scheduled_date:
            data.append(("scheduled_date", scheduled_date))

        headers = auth_headers()
        if idempotency_key:
            headers["Idempotency-Key"] = idempotency_key

        response = requests.post(
            UPLOAD_URL,
            headers=headers,
            data=data,
            files=files,
            timeout=900,
        )
        try:
            payload = response.json()
        except Exception:
            payload = {"raw": response.text}
        if response.status_code >= 400:
            raise RuntimeError(f"Upload-Post HTTP {response.status_code}: {json.dumps(payload, ensure_ascii=False)}")
        if payload.get("success") is False:
            raise RuntimeError(f"Upload-Post rejected upload: {json.dumps(payload, ensure_ascii=False)}")

        if payload.get("job_id"):
            return {
                "mode": "scheduled",
                "job_id": payload.get("job_id"),
                "scheduled_date": scheduled_date,
                "raw": payload,
            }

        request_id = payload.get("request_id")
        if request_id:
            final_payload = poll_request(str(request_id))
        else:
            final_payload = payload

        yt = extract_youtube_result(final_payload) or extract_youtube_result(payload)
        if yt and yt.get("success") is False:
            raise RuntimeError(f"YouTube publish failed: {json.dumps(yt, ensure_ascii=False)}")

        return {
            "mode": "published",
            "request_id": request_id,
            "video_id": infer_video_id(yt),
            "url": (yt or {}).get("url"),
            "youtube": yt,
            "raw": final_payload,
        }
    finally:
        for handle in handles:
            try:
                handle.close()
            except Exception:
                pass


def main() -> None:
    job_path = Path(sys.argv[1] if len(sys.argv) > 1 else "whatever_happened_to/current/job.json")
    job = json.loads(job_path.read_text(encoding="utf-8"))
    root = job_path.parent
    output_dir = root / "output"
    output_dir.mkdir(parents=True, exist_ok=True)

    if job.get("profile") not in (None, PROFILE):
        raise RuntimeError(f"This publisher is hard-locked to Upload-Post profile {PROFILE}")

    slug = str(job.get("slug") or "episode").strip().replace(" ", "-")
    full = job.get("full") or {}
    full_path = root / full.get("path", "output/full.mp4")
    thumbnail = root / full.get("thumbnail", "output/thumbnail.jpg")
    full_title = str(full.get("title") or "").strip()
    full_description = str(full.get("description") or "").strip()
    if not full_title or not full_description:
        raise RuntimeError("Full episode title and description are required")

    print(f"Publishing full episode to profile={PROFILE}: {full_title}")
    full_receipt = upload_one(
        full_path,
        title=full_title,
        description=full_description,
        thumbnail_path=thumbnail,
        scheduled_date=full.get("scheduled_date"),
        idempotency_key=f"whatever-happened-{slug}-full",
    )

    receipts: dict[str, Any] = {"profile": PROFILE, "slug": slug, "full": full_receipt, "shorts": []}

    shorts = job.get("shorts") or []
    if shorts:
        if len(shorts) != 6:
            raise RuntimeError(f"Whatever Happened To requires exactly 6 Shorts; got {len(shorts)}")
        for index, short in enumerate(shorts, start=1):
            short_path = root / short.get("path", f"output/short_{index:02d}.mp4")
            title = str(short.get("title") or "").strip()
            description = str(short.get("description") or "").strip()
            if not title or not description:
                raise RuntimeError(f"Short {index} title/description missing")
            scheduled_date = short.get("scheduled_date")
            publish_now = short.get("publish_now") is True
            if not scheduled_date and not publish_now:
                raise RuntimeError(
                    f"Short {index} has no scheduled_date and publish_now is not true. "
                    "Refusing to silently dump all six Shorts at once."
                )
            receipt = upload_one(
                short_path,
                title=title,
                description=description,
                thumbnail_path=None,
                scheduled_date=scheduled_date,
                idempotency_key=f"whatever-happened-{slug}-short-{index:02d}",
            )
            receipts["shorts"].append(receipt)

    receipt_path = output_dir / "publish-receipt.json"
    receipt_path.write_text(json.dumps(receipts, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps(receipts, indent=2, ensure_ascii=False))

    if not full_receipt.get("video_id") and full_receipt.get("mode") != "scheduled":
        raise RuntimeError("Full episode published but YouTube video_id could not be resolved; thumbnail verification cannot continue")


if __name__ == "__main__":
    main()
