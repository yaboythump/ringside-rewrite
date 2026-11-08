from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from pathlib import Path

from ringside.youtube import _fit_youtube_tags, _resumable_upload

from .episode import ROOT, Episode

SCOPES = [
    "https://www.googleapis.com/auth/youtube.upload",
    "https://www.googleapis.com/auth/youtube.readonly",
]
TOKEN_PATH = ROOT / os.getenv("TTU_YOUTUBE_TOKEN", "secrets/tiny_turn_up_token.json")
CLIENT_SECRET_PATH = ROOT / os.getenv("YOUTUBE_CLIENT_SECRET", "secrets/client_secret.json")
EXPECTED_TITLE = os.getenv("TTU_CHANNEL_TITLE", "Tiny Turn Up")
CATEGORY_MUSIC = "10"


def youtube_service(interactive: bool = False):
    """Separate login from Ringside, and refuses to upload to any channel but Tiny Turn Up."""
    from google.auth.transport.requests import Request
    from google.oauth2.credentials import Credentials
    from google_auth_oauthlib.flow import InstalledAppFlow
    from googleapiclient.discovery import build

    creds = None
    if TOKEN_PATH.exists():
        creds = Credentials.from_authorized_user_file(str(TOKEN_PATH), SCOPES)
    elif os.getenv("TTU_YOUTUBE_REFRESH_TOKEN"):
        creds = Credentials(
            token=None,
            refresh_token=os.environ["TTU_YOUTUBE_REFRESH_TOKEN"],
            token_uri="https://oauth2.googleapis.com/token",
            client_id=os.getenv("TTU_YOUTUBE_CLIENT_ID") or os.getenv("YOUTUBE_CLIENT_ID", ""),
            client_secret=os.getenv("TTU_YOUTUBE_CLIENT_SECRET_VALUE")
            or os.getenv("YOUTUBE_CLIENT_SECRET_VALUE", ""),
            scopes=SCOPES,
        )
    if creds and creds.refresh_token and not creds.valid:
        creds.refresh(Request())
    if not creds or not creds.valid:
        if not interactive:
            raise RuntimeError("Tiny Turn Up YouTube login missing. Run: tinyturnup auth")
        if not CLIENT_SECRET_PATH.exists():
            raise RuntimeError(f"Put your Google OAuth desktop client JSON at {CLIENT_SECRET_PATH}")
        flow = InstalledAppFlow.from_client_secrets_file(str(CLIENT_SECRET_PATH), SCOPES)
        print("A browser will open. Pick the TINY TURN UP channel (not Ringside Rewrite).")
        creds = flow.run_local_server(port=0, access_type="offline", prompt="consent")
        TOKEN_PATH.parent.mkdir(parents=True, exist_ok=True)
        TOKEN_PATH.write_text(creds.to_json(), encoding="utf-8")
    service = build("youtube", "v3", credentials=creds, cache_discovery=False)
    items = service.channels().list(part="id,snippet", mine=True).execute().get("items", [])
    expected_id = os.getenv("TTU_YOUTUBE_CHANNEL_ID", "").strip()
    ok = any(
        (expected_id and item.get("id") == expected_id)
        or item.get("snippet", {}).get("title", "").casefold() == EXPECTED_TITLE.casefold()
        for item in items
    )
    if not ok:
        names = ", ".join(i.get("snippet", {}).get("title", "?") for i in items) or "no channel"
        raise RuntimeError(f"Logged into the wrong channel ({names}). Expected '{EXPECTED_TITLE}'.")
    return service


def _upload(service, path: Path, title: str, description: str, tags: list[str],
            privacy: str, publish_at: str | None) -> str:
    from googleapiclient.http import MediaFileUpload

    status = {
        "privacyStatus": "private" if publish_at else privacy,
        "selfDeclaredMadeForKids": True,  # required for kids content (COPPA)
        "containsSyntheticMedia": True,
    }
    if publish_at:
        status["publishAt"] = publish_at
    body = {
        "snippet": {
            "title": title[:100],
            "description": description[:5000],
            "tags": _fit_youtube_tags(tags),
            "categoryId": CATEGORY_MUSIC,
            "defaultLanguage": "en",
        },
        "status": status,
    }
    media = MediaFileUpload(str(path), chunksize=8 * 1024 * 1024, resumable=True)
    request = service.videos().insert(part="snippet,status", body=body, media_body=media)
    return _resumable_upload(request)


def upload_episode(episode: Episode, privacy: str = "private", publish_at: str | None = None) -> dict:
    """Uploads long video + Shorts once. Re-running never creates duplicates (see uploaded.json)."""
    record_path = episode.folder / "uploaded.json"
    record: dict = json.loads(record_path.read_text()) if record_path.exists() else {}
    service = youtube_service()

    def save() -> None:
        record_path.write_text(json.dumps(record, indent=2), encoding="utf-8")

    long_path = episode.build / "long.mp4"
    if "long" not in record:
        if not long_path.exists():
            raise RuntimeError("Nothing rendered yet. Run: tinyturnup make " + episode.slug)
        video_id = _upload(service, long_path, episode.title, episode.description,
                           episode.tags, privacy, publish_at)
        record["long"] = {"id": video_id, "at": datetime.now(timezone.utc).isoformat()}
        save()
        print(f"  long uploaded: https://youtu.be/{video_id}")
        thumb = episode.build / "thumbnail.jpg"
        if thumb.exists():
            from googleapiclient.http import MediaFileUpload
            try:
                service.thumbnails().set(videoId=video_id, media_body=MediaFileUpload(str(thumb))).execute()
                print("  thumbnail set")
            except Exception as exc:  # unverified channels can't set custom thumbnails
                print(f"  thumbnail NOT set ({exc}). Verify the channel by phone, then add it in Studio.")
    long_id = record["long"]["id"]
    for index, cut in enumerate(episode.shorts, start=1):
        key = f"short_{index:02d}"
        path = episode.build / f"{key}.mp4"
        if key in record or not path.exists():
            continue
        description = (
            f"Full song 👉 https://youtu.be/{long_id}\n\n"
            + episode.description.split("\n\n")[0]
            + "\n\n#shorts #kidsdance #brainbreak"
        )
        video_id = _upload(service, path, cut.title, description, episode.tags, privacy, publish_at)
        record[key] = {"id": video_id, "at": datetime.now(timezone.utc).isoformat()}
        save()
        print(f"  {key} uploaded: https://youtube.com/shorts/{video_id}")
    return record
