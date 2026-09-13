#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import subprocess
import urllib.error
import urllib.request
from pathlib import Path

from ringside.config import load_settings
from ringside.models import EpisodePlan
from ringside.youtube import (
    _short_description,
    _short_tags,
    _short_title,
    _upload_video,
    youtube_service,
)


def norm(text: str) -> str:
    return (
        text.replace("’", "'")
        .replace("‘", "'")
        .replace("–", "-")
        .replace("—", "-")
        .casefold()
        .strip()
    )


def probe(path: Path) -> dict:
    raw = subprocess.check_output(
        [
            "ffprobe",
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=width,height:format=duration",
            "-of",
            "json",
            str(path),
        ],
        text=True,
    )
    return json.loads(raw)


def validate_shorts(episode_dir: Path, expected: int) -> list[Path]:
    paths = [episode_dir / "shorts" / f"short-{i:02d}.mp4" for i in range(1, expected + 1)]
    missing = [str(p) for p in paths if not p.exists()]
    if missing:
        raise RuntimeError(f"Missing rebuilt Shorts: {missing}")
    for path in paths:
        data = probe(path)
        stream = data["streams"][0]
        width = int(stream["width"])
        height = int(stream["height"])
        duration = float(data["format"]["duration"])
        print(f"QC {path.name}: {width}x{height}, {duration:.3f}s")
        if (width, height) != (1080, 1920):
            raise RuntimeError(f"{path.name} is not 1080x1920 vertical.")
        if duration > 59.2:
            raise RuntimeError(f"{path.name} is too long for the locked Shorts gate: {duration:.3f}s")
    return paths


def recent_uploads(service, limit: int = 100) -> list[dict]:
    channel = service.channels().list(part="contentDetails", mine=True).execute()["items"][0]
    playlist_id = channel["contentDetails"]["relatedPlaylists"]["uploads"]
    items: list[dict] = []
    token = None
    while len(items) < limit:
        response = service.playlistItems().list(
            part="contentDetails,snippet",
            playlistId=playlist_id,
            maxResults=min(50, limit - len(items)),
            pageToken=token,
        ).execute()
        items.extend(response.get("items", []))
        token = response.get("nextPageToken")
        if not token:
            break
    return items


def unpublish_upload_post(video_id: str) -> None:
    api_key = os.environ.get("UPLOAD_POST_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError("UPLOAD_POST_API_KEY is missing.")
    payload = json.dumps(
        {"platform": "youtube", "user": "Ringsiderewrite", "post_id": video_id}
    ).encode("utf-8")
    request = urllib.request.Request(
        "https://api.upload-post.com/api/uploadposts/posts/unpublish",
        data=payload,
        method="POST",
        headers={
            "Authorization": f"Apikey {api_key}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            body = response.read().decode("utf-8", "replace")
            code = response.status
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", "replace")
        code = exc.code
    print(f"Unpublish {video_id}: HTTP {code} {body[:500]}")
    if code == 404:
        return
    if code == 400 and any(
        phrase in body.casefold()
        for phrase in ("does not exist", "cannot be found", "unsupported delete request")
    ):
        return
    if not (200 <= code < 300):
        raise RuntimeError(f"Could not delete old YouTube upload {video_id}: HTTP {code}")
    try:
        parsed = json.loads(body)
    except json.JSONDecodeError:
        parsed = {}
    if parsed and parsed.get("success") is not True:
        raise RuntimeError(f"Upload-Post did not confirm deletion for {video_id}: {body}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--episode-dir", required=True)
    parser.add_argument("--long-id", required=True)
    args = parser.parse_args()

    episode_dir = Path(args.episode_dir).resolve()
    plan = EpisodePlan.load(episode_dir / "episode.json")
    if "droz" not in norm(plan.episode_title) or "d'lo" not in norm(plan.episode_title):
        raise RuntimeError(f"Refusing to run against wrong episode: {plan.episode_title}")
    if len(plan.shorts) != 3:
        raise RuntimeError(f"Expected exactly 3 D'Lo/Droz Shorts, found {len(plan.shorts)}")

    shorts = validate_shorts(episode_dir, 3)
    settings = load_settings(Path.cwd())
    service = youtube_service(settings, interactive=False)

    expected_titles = [_short_title(plan, cut) for cut in plan.shorts]
    expected_norm = [norm(title) for title in expected_titles]
    parent_norm = norm(plan.episode_title)

    candidates: list[dict] = []
    print("Expected replacement titles:")
    for title in expected_titles:
        print(f"  - {title}")

    for item in recent_uploads(service, 100):
        video_id = item.get("contentDetails", {}).get("videoId", "")
        title = item.get("snippet", {}).get("title", "")
        if not video_id or video_id == args.long_id:
            continue
        t = norm(title)
        exact_expected = t in expected_norm
        dlo_episode_variant = ("d'lo brown" in t and "droz" in t and "#shorts" in t)
        parent_variant = parent_norm in t and "#shorts" in t
        if exact_expected or dlo_episode_variant or parent_variant:
            candidates.append({"id": video_id, "title": title})

    # Deduplicate IDs while preserving order.
    unique: list[dict] = []
    seen: set[str] = set()
    for item in candidates:
        if item["id"] not in seen:
            unique.append(item)
            seen.add(item["id"])
    candidates = unique

    print("Old D'Lo/Droz Short candidates:")
    for item in candidates:
        print(f"  - {item['id']} :: {item['title']}")
    if len(candidates) != 3:
        raise RuntimeError(
            f"Safety stop: expected exactly 3 old D'Lo/Droz short-form uploads, found {len(candidates)}. Nothing was deleted or uploaded."
        )

    for item in candidates:
        unpublish_upload_post(item["id"])

    new_ids: list[dict] = []
    for index, (cut, path) in enumerate(zip(plan.shorts, shorts, strict=True), start=1):
        new_id = _upload_video(
            service,
            settings,
            path,
            _short_title(plan, cut),
            _short_description(plan, cut, args.long_id),
            _short_tags(settings, plan, cut),
            "public",
            None,
        )
        print(f"Uploaded replacement Short {index}: {new_id}")
        new_ids.append({"index": index, "id": new_id, "url": f"https://youtu.be/{new_id}"})

    receipt = {
        "episode": plan.episode_title,
        "long_form_id": args.long_id,
        "deleted": candidates,
        "replacement_shorts": new_ids,
    }
    (episode_dir / "dlo-shorts-repair.json").write_text(
        json.dumps(receipt, indent=2), encoding="utf-8"
    )
    print(json.dumps(receipt, indent=2))


if __name__ == "__main__":
    main()
