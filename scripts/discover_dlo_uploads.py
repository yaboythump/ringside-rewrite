#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

from ringside.config import load_settings
from ringside.youtube import youtube_service

FULL_ID = "O4DB032Y22U"


def norm(text: str) -> str:
    return text.replace("’", "'").replace("‘", "'").casefold()


def main() -> None:
    settings = load_settings(Path.cwd())
    service = youtube_service(settings, interactive=False)
    channel = service.channels().list(part="contentDetails", mine=True).execute()["items"][0]
    uploads = channel["contentDetails"]["relatedPlaylists"]["uploads"]

    items = []
    token = None
    while len(items) < 100:
        page = service.playlistItems().list(
            part="contentDetails,snippet",
            playlistId=uploads,
            maxResults=min(50, 100-len(items)),
            pageToken=token,
        ).execute()
        items.extend(page.get("items", []))
        token = page.get("nextPageToken")
        if not token:
            break

    ids = [x.get("contentDetails", {}).get("videoId") for x in items]
    ids = [x for x in ids if x]
    details = {}
    for start in range(0, len(ids), 50):
        response = service.videos().list(
            part="snippet,status,contentDetails",
            id=",".join(ids[start:start+50]),
        ).execute()
        for item in response.get("items", []):
            details[item["id"]] = item

    report = []
    for order, p in enumerate(items, start=1):
        vid = p.get("contentDetails", {}).get("videoId", "")
        title = p.get("snippet", {}).get("title", "")
        d = details.get(vid, {})
        row = {
            "order": order,
            "id": vid,
            "title": title,
            "publishedAt": p.get("snippet", {}).get("publishedAt"),
            "privacyStatus": d.get("status", {}).get("privacyStatus"),
            "publishAt": d.get("status", {}).get("publishAt"),
            "duration": d.get("contentDetails", {}).get("duration"),
            "is_full_dlo": vid == FULL_ID,
        }
        report.append(row)
        t = norm(title)
        if order <= 25 or "d'lo" in t or "droz" in t:
            print(json.dumps(row, ensure_ascii=False))

    Path("dlo-youtube-discovery.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8"
    )


if __name__ == "__main__":
    main()
