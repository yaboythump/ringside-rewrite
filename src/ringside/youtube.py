from __future__ import annotations

import json
import random
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from .config import Settings
from .models import EpisodePlan


SCOPES = [
    "https://www.googleapis.com/auth/youtube.upload",
    "https://www.googleapis.com/auth/youtube.readonly",
]


def youtube_service(settings: Settings, interactive: bool = False):
    try:
        from google.auth.transport.requests import Request
        from google.oauth2.credentials import Credentials
        from google_auth_oauthlib.flow import InstalledAppFlow
        from googleapiclient.discovery import build
    except ImportError as exc:
        raise RuntimeError("Install the project dependencies with: pip install -e .") from exc

    credentials = None
    if settings.youtube_token.exists():
        credentials = Credentials.from_authorized_user_file(str(settings.youtube_token), SCOPES)
    elif (
        settings.youtube_client_id
        and settings.youtube_client_secret_value
        and settings.youtube_refresh_token
    ):
        credentials = Credentials(
            token=None,
            refresh_token=settings.youtube_refresh_token,
            token_uri="https://oauth2.googleapis.com/token",
            client_id=settings.youtube_client_id,
            client_secret=settings.youtube_client_secret_value,
            scopes=SCOPES,
        )
    if credentials and credentials.refresh_token and not credentials.valid:
        credentials.refresh(Request())
    if not credentials or not credentials.valid:
        if not interactive:
            raise RuntimeError("YouTube is not authorized. Run: ringside youtube-auth")
        if not settings.youtube_client_secret.exists():
            raise RuntimeError(
                "Missing YouTube OAuth credentials. Add the three cloud secret values "
                "YOUTUBE_CLIENT_ID, YOUTUBE_CLIENT_SECRET_VALUE, and "
                "YOUTUBE_REFRESH_TOKEN, or put the Desktop OAuth JSON at "
                f"{settings.youtube_client_secret}."
            )
        flow = InstalledAppFlow.from_client_secrets_file(
            str(settings.youtube_client_secret), SCOPES
        )
        credentials = flow.run_local_server(port=0, access_type="offline", prompt="consent")
        settings.youtube_token.parent.mkdir(parents=True, exist_ok=True)
        settings.youtube_token.write_text(credentials.to_json(), encoding="utf-8")
    service = build("youtube", "v3", credentials=credentials, cache_discovery=False)
    response = service.channels().list(part="id,snippet", mine=True).execute()
    items = response.get("items", [])
    expected_title = settings.channel.get("channel", {}).get(
        "name", "RINGSIDE REWRITE"
    )
    title_matches = [
        item
        for item in items
        if item.get("snippet", {}).get("title", "").casefold()
        == expected_title.casefold()
    ]
    if not title_matches:
        actual = ", ".join(
            f"{item.get('snippet', {}).get('title', 'unknown')} ({item.get('id', 'unknown')})"
            for item in items
        ) or "no channel"
        raise RuntimeError(
            "YouTube authorization points to the wrong channel. "
            f"Expected title '{expected_title}'; authorized: {actual}."
        )
    if settings.youtube_expected_channel_id:
        actual_ids = {item.get("id", "") for item in title_matches}
        if settings.youtube_expected_channel_id not in actual_ids:
            raise RuntimeError(
                "YouTube channel title matched, but its ID did not match "
                "YOUTUBE_EXPECTED_CHANNEL_ID."
            )
    return service


def authorize(settings: Settings) -> str:
    service = youtube_service(settings, interactive=True)
    response = service.channels().list(part="snippet", mine=True).execute()
    items = response.get("items", [])
    if not items:
        raise RuntimeError("The authorized Google account has no YouTube channel.")
    return items[0]["snippet"]["title"]


def _resumable_upload(request, max_retries: int = 10) -> str:
    try:
        from googleapiclient.errors import HttpError
    except ImportError as exc:
        raise RuntimeError("Google API client dependencies are missing.") from exc

    response = None
    retry = 0
    while response is None:
        try:
            status, response = request.next_chunk()
            if status:
                print(f"Upload progress: {int(status.progress() * 100)}%")
        except HttpError as exc:
            if exc.resp.status not in {500, 502, 503, 504} or retry >= max_retries:
                raise
            sleep_for = random.random() * (2**retry)
            print(f"Temporary YouTube error; retrying in {sleep_for:.1f}s")
            time.sleep(sleep_for)
            retry += 1
        except (OSError, TimeoutError, ConnectionError):
            if retry >= max_retries:
                raise
            sleep_for = random.random() * (2**retry)
            time.sleep(sleep_for)
            retry += 1
    video_id = response.get("id")
    if not video_id:
        raise RuntimeError(f"YouTube upload returned no video id: {response}")
    return video_id


def _description(settings: Settings, plan: EpisodePlan) -> str:
    footer = settings.channel.get("youtube", {}).get("description_footer", "")
    disclosure = "Visuals and narration in this hypothetical episode include AI-generated elements."
    baseline = "DOCUMENTED STARTING POINT\n" + "\n".join(
        f"• {fact}" for fact in plan.factual_baseline
    )
    sources = "SOURCES\n" + "\n".join(
        f"• {note.source_title}: {note.source_url}" for note in plan.source_notes
    )
    cutoff = f"THE REWRITE BEGINS\n{plan.historical_cutoff}"
    question = f"YOUR BOOKING CALL\n{plan.viewer_question}"
    hashtags = " ".join(plan.hashtags)
    parts = [
        plan.description.strip(),
        cutoff,
        baseline,
        sources,
        question,
        hashtags,
        disclosure,
    ]
    if footer and footer.casefold() not in plan.description.casefold():
        parts.append(footer.strip())
    return "\n\n".join(dict.fromkeys(part for part in parts if part))[:5000]


def _upload_video(
    service,
    settings: Settings,
    file_path: Path,
    title: str,
    description: str,
    tags: list[str],
    privacy: str,
    publish_at: str | None,
) -> str:
    try:
        from googleapiclient.http import MediaFileUpload
    except ImportError as exc:
        raise RuntimeError("Google API client dependencies are missing.") from exc

    status: dict[str, Any] = {
        "privacyStatus": "private" if publish_at else privacy,
        "selfDeclaredMadeForKids": False,
        "containsSyntheticMedia": True,
    }
    if publish_at:
        status["publishAt"] = publish_at
    body = {
        "snippet": {
            "title": title[:100],
            "description": description[:5000],
            "tags": tags,
            "categoryId": settings.channel.get("channel", {}).get("category_id", "24"),
            "defaultLanguage": settings.channel.get("channel", {}).get(
                "default_language", "en"
            ),
        },
        "status": status,
    }
    media = MediaFileUpload(str(file_path), chunksize=8 * 1024 * 1024, resumable=True)
    request = service.videos().insert(
        part="snippet,status",
        body=body,
        media_body=media,
        notifySubscribers=False,
    )
    return _resumable_upload(request)


def _future_iso(base: str | None, days: int) -> str | None:
    if not base:
        return None
    parsed = datetime.fromisoformat(base.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return (parsed + timedelta(days=days)).astimezone(timezone.utc).isoformat().replace(
        "+00:00", "Z"
    )


def _short_title(plan: EpisodePlan, cut) -> str:
    """Keep every Short visibly tied to its parent episode within YouTube's limit."""
    parent = plan.episode_title.strip()
    hook = cut.title.strip()
    if hook.casefold().startswith(parent.casefold()):
        title = f"{hook} #Shorts"
    else:
        title = f"{parent} — {hook} #Shorts"
    if len(title) <= 100:
        return title
    suffix = " #Shorts"
    separator = " — "
    available = 100 - len(parent) - len(separator) - len(suffix)
    if available >= 12:
        return f"{parent}{separator}{hook[:available].rstrip()}{suffix}"
    available_parent = max(20, 100 - len(separator) - len(hook) - len(suffix))
    return f"{parent[:available_parent].rstrip()}{separator}{hook}{suffix}"[:100]


def _fit_youtube_tags(values: list[str], limit: int = 500) -> list[str]:
    output: list[str] = []
    seen: set[str] = set()
    used = 0
    for value in values:
        tag = " ".join(value.strip().split()).strip("#, ")
        key = tag.casefold()
        if not tag or key in seen:
            continue
        added = len(tag) + (1 if output else 0)
        if used + added > limit:
            continue
        output.append(tag)
        seen.add(key)
        used += added
    return output


def _short_tags(settings: Settings, plan: EpisodePlan, cut) -> list[str]:
    configured = list(settings.channel.get("youtube", {}).get("tags", []))
    discovery = [
        plan.episode_title,
        cut.title,
        *plan.primary_subjects,
        *plan.tags,
        *configured,
        "Ringside Rewrite",
        "wrestling shorts",
        "pro wrestling shorts",
        "fantasy booking shorts",
        "wrestling what if",
        "alternate wrestling history",
        "wrestling storyline",
        "wrestling documentary",
        "Shorts",
    ]
    return _fit_youtube_tags(discovery)


def _short_description(plan: EpisodePlan, cut, long_id: str) -> str:
    hashtags = list(
        dict.fromkeys(
            [*plan.hashtags, "#WrestlingShorts", "#FantasyBooking", "#Shorts"]
        )
    )[:5]
    return "\n\n".join(
        [
            cut.caption.strip(),
            f'From the Ringside Rewrite episode: "{plan.episode_title}."',
            f"Watch the full episode: https://youtu.be/{long_id}",
            plan.viewer_question.strip(),
            " ".join(hashtags),
        ]
    )[:5000]


def upload_episode(
    settings: Settings,
    plan: EpisodePlan,
    episode_dir: Path,
    privacy: str = "private",
    publish_at: str | None = None,
    include_shorts: bool = True,
) -> dict[str, Any]:
    if privacy not in {"private", "unlisted", "public"}:
        raise ValueError("privacy must be private, unlisted, or public")
    approval = settings.channel.get("approval", {})
    marker = episode_dir / approval.get("marker_filename", ".approved")
    if privacy != "private" and approval.get("required", True):
        if not settings.auto_publish and not marker.exists():
            raise RuntimeError(
                "Public/unlisted upload requires approval. Run: "
                f"ringside approve --episode-dir {episode_dir}"
            )

    service = youtube_service(settings, interactive=False)
    video_path = episode_dir / "final.mp4"
    thumbnail_path = episode_dir / "thumbnail.png"
    if not video_path.exists():
        raise RuntimeError(f"Missing final video: {video_path}")
    title = plan.title_options[0]
    configured_tags = settings.channel.get("youtube", {}).get("tags", [])
    tags = list(dict.fromkeys(plan.tags + list(configured_tags)))
    long_id = _upload_video(
        service,
        settings,
        video_path,
        title,
        _description(settings, plan),
        tags,
        privacy,
        publish_at,
    )
    if thumbnail_path.exists():
        try:
            from googleapiclient.http import MediaFileUpload
        except ImportError as exc:
            raise RuntimeError("Google API client dependencies are missing.") from exc
        service.thumbnails().set(
            videoId=long_id,
            media_body=MediaFileUpload(str(thumbnail_path), mimetype="image/png"),
        ).execute()

    result: dict[str, Any] = {
        "long_form": {"id": long_id, "url": f"https://youtu.be/{long_id}"},
        "shorts": [],
    }
    if include_shorts:
        for index, cut in enumerate(plan.shorts, start=1):
            short_path = episode_dir / "shorts" / f"short-{index:02d}.mp4"
            if not short_path.exists():
                continue
            short_publish_at = _future_iso(publish_at, index)
            short_id = _upload_video(
                service,
                settings,
                short_path,
                _short_title(plan, cut),
                _short_description(plan, cut, long_id),
                _short_tags(settings, plan, cut),
                privacy,
                short_publish_at,
            )
            result["shorts"].append(
                {"id": short_id, "url": f"https://youtu.be/{short_id}"}
            )
    (episode_dir / "youtube-upload.json").write_text(
        json.dumps(result, indent=2), encoding="utf-8"
    )
    return result


def analytics_snapshot(settings: Settings, max_results: int = 20) -> dict[str, Any]:
    service = youtube_service(settings, interactive=False)
    channel_response = service.channels().list(part="contentDetails", mine=True).execute()
    items = channel_response.get("items", [])
    if not items:
        raise RuntimeError("Authorized account has no YouTube channel.")
    uploads_playlist = items[0]["contentDetails"]["relatedPlaylists"]["uploads"]
    playlist = (
        service.playlistItems()
        .list(part="contentDetails,snippet", playlistId=uploads_playlist, maxResults=max_results)
        .execute()
    )
    ids = [item["contentDetails"]["videoId"] for item in playlist.get("items", [])]
    if not ids:
        return {"videos": []}
    videos = (
        service.videos()
        .list(part="snippet,statistics,status", id=",".join(ids))
        .execute()
    )
    snapshot = {
        "captured_at": datetime.now(timezone.utc).isoformat(),
        "videos": videos.get("items", []),
    }
    destination = settings.output_dir / "analytics-latest.json"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(snapshot, indent=2), encoding="utf-8")
    return snapshot
