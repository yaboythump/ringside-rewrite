#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re
import subprocess
import time
from pathlib import Path

import requests

API = "https://api.upload-post.com/api"
USER = "HipHopWhatIf"
FB_PAGE = "1305726102625399"
VIDEO = Path("/tmp/eazy/full.mp4")
THUMB = Path("/tmp/eazy/thumbnail.jpg")
RECEIPT = Path("/tmp/eazy/restore-receipt-20260911.json")
TITLE = "What If Eazy-E Never Died? | Hip Hop What If"
DESCRIPTION = """What if Eazy-E survived 1995 and got the chance to shape the next era of West Coast hip hop? Hip Hop What If follows the documented timeline through Eazy-E's final months, then branches into a fictional alternate future involving Ruthless Records, Bone Thugs-N-Harmony, a possible N.W.A reunion, and a very different West Coast power map.

The real-history setup is documented: Eazy-E founded Ruthless Records and helped form N.W.A.; Bone Thugs-N-Harmony had become a major Ruthless success; and in February 1995 the Los Angeles Times reported that long-rumored N.W.A reunion talks were stepping up after Eazy parted ways with Jerry Heller, with a reunion album being discussed for 1996. Eazy-E died March 26, 1995 from complications of AIDS. Everything after that historical cutoff in this episode is hypothetical alternate-history commentary.

Sources: Los Angeles Times, Feb. 26, 1995 and Mar. 27, 1995.

#EazyE #NWA #HipHopHistory #WestCoastHipHop #HipHopWhatIf #RuthlessRecords #RapHistory"""


def headers() -> dict[str, str]:
    key = os.environ.get("UPLOAD_POST_API_KEY", "").strip()
    if not key:
        raise RuntimeError("UPLOAD_POST_API_KEY missing")
    return {"Authorization": f"Apikey {key}"}


def verify() -> None:
    if VIDEO.stat().st_size != 117614760:
        raise RuntimeError(f"Wrong full.mp4 size: {VIDEO.stat().st_size}")
    probe = subprocess.check_output(
        [
            "ffprobe", "-v", "error", "-select_streams", "v:0",
            "-show_entries", "stream=width,height,r_frame_rate",
            "-of", "csv=p=0", str(VIDEO),
        ],
        text=True,
    ).strip()
    if probe != "1920,1080,30/1":
        raise RuntimeError(f"Wrong video fingerprint: {probe}")
    duration = float(subprocess.check_output(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", str(VIDEO)],
        text=True,
    ).strip())
    if abs(duration - 347.3) >= 0.05:
        raise RuntimeError(f"Wrong duration: {duration}")
    if not THUMB.exists() or THUMB.stat().st_size != 242051:
        raise RuntimeError("Exact thumbnail missing or changed")


def response_json(r: requests.Response) -> dict:
    try:
        payload = r.json()
    except Exception:
        payload = {"raw": r.text}
    if r.status_code >= 400 or payload.get("success") is False:
        raise RuntimeError(f"HTTP {r.status_code}: {payload}")
    return payload


def upload(platform: str, idem: str) -> dict:
    data = [
        ("user", USER),
        ("platform[]", platform),
        ("title", TITLE),
        ("description", DESCRIPTION),
        ("async_upload", "true"),
    ]
    if platform == "youtube":
        data += [("privacyStatus", "public"), ("selfDeclaredMadeForKids", "false")]
    else:
        data += [("facebook_page_id", FB_PAGE), ("facebook_media_type", "VIDEO")]
    hs = {**headers(), "Idempotency-Key": idem}
    with VIDEO.open("rb") as video:
        files = {"video": (VIDEO.name, video, "video/mp4")}
        thumb = None
        if platform == "youtube":
            thumb = THUMB.open("rb")
            files["thumbnail"] = (THUMB.name, thumb, "image/jpeg")
        try:
            r = requests.post(API + "/upload", headers=hs, data=data, files=files, timeout=900)
        finally:
            if thumb:
                thumb.close()
    return response_json(r)


def platform_result(payload: dict, platform: str) -> dict:
    results = payload.get("results", {})
    if isinstance(results, list):
        return next((x for x in results if x.get("platform") == platform), {})
    if isinstance(results, dict):
        return results.get(platform, {})
    return {}


def poll(request_id: str, platform: str, timeout: int = 1800) -> tuple[dict, dict]:
    deadline = time.monotonic() + timeout
    last: dict = {}
    while time.monotonic() < deadline:
        r = requests.get(API + "/uploadposts/status", headers=headers(), params={"request_id": request_id}, timeout=60)
        last = response_json(r)
        item = platform_result(last, platform)
        status = str(item.get("status") or last.get("status") or "").lower()
        if item.get("success") is True or status in {"completed", "success", "done"}:
            return last, item
        if item.get("skipped") or status in {"failed", "error", "skipped"}:
            raise RuntimeError(f"{platform} failed: {last}")
        time.sleep(10)
    raise TimeoutError(f"{platform} timed out: {last}")


def youtube_video_id(item: dict) -> str | None:
    for key in ("video_id", "post_id", "publish_id", "id"):
        value = item.get(key)
        if isinstance(value, str) and value:
            return value
    url = item.get("url") or item.get("post_url") or ""
    match = re.search(r"(?:v=|youtu\.be/|shorts/)([A-Za-z0-9_-]{11})", url)
    return match.group(1) if match else None


def main() -> None:
    verify()
    receipts: dict = {"fingerprint_verified": True}
    for platform, idem in (
        ("youtube", "hhwi-eazy-exact-restore-20260911-youtube-v2"),
        ("facebook", "hhwi-eazy-exact-restore-20260911-facebook-v2"),
    ):
        accepted = upload(platform, idem)
        request_id = accepted.get("request_id")
        if not request_id:
            raise RuntimeError(f"{platform}: missing request_id: {accepted}")
        final, item = poll(str(request_id), platform)
        receipts[platform] = {"accepted": accepted, "final": final, "item": item}
        if platform == "youtube":
            video_id = youtube_video_id(item)
            if not video_id:
                raise RuntimeError(f"YouTube video ID unresolved: {item}")
            with THUMB.open("rb") as image:
                patch = requests.post(
                    API + "/uploadposts/youtube/thumbnail",
                    headers=headers(),
                    data={"user": USER, "video_id": video_id},
                    files={"thumbnail": (THUMB.name, image, "image/jpeg")},
                    timeout=180,
                )
            thumbnail_payload = response_json(patch)
            receipts["thumbnail"] = thumbnail_payload
            receipts["youtube_video_id"] = video_id
            receipts["youtube_url"] = item.get("url") or item.get("post_url") or f"https://www.youtube.com/watch?v={video_id}"
    RECEIPT.write_text(json.dumps(receipts, indent=2), encoding="utf-8")
    print(json.dumps({
        "RESTORE_COMPLETE": True,
        "youtube_video_id": receipts.get("youtube_video_id"),
        "youtube_url": receipts.get("youtube_url"),
        "facebook_result": receipts["facebook"]["item"],
    }, indent=2))


if __name__ == "__main__":
    main()
