#!/usr/bin/env python3
"""Publish CTNETWORK TikTok videos through Upload-Post with cover + hashtag rules.

Network rules enforced here:
- TikTok captions contain no more than 5 hashtags.
- Prefer a custom cover image when supplied.
- Fall back to a TikTok cover-frame timestamp when no custom image is supplied.

The Upload-Post API key must be supplied via UPLOAD_POST_API_KEY.
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import os
from pathlib import Path
import re
import sys
from typing import BinaryIO

import requests

API_URL = "https://api.upload-post.com/api/upload"
HASHTAG_RE = re.compile(r"(?<!\w)#[\w]+", flags=re.UNICODE)
ALLOWED_COVER_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp"}
MAX_COVER_BYTES = 20 * 1024 * 1024


def sanitize_caption(caption: str, max_hashtags: int) -> tuple[str, list[str]]:
    """Keep the first unique hashtags up to the TikTok limit and remove the rest."""
    kept: list[str] = []
    seen: set[str] = set()

    def replace(match: re.Match[str]) -> str:
        tag = match.group(0)
        key = tag.casefold()
        if key in seen:
            return ""
        if len(kept) >= max_hashtags:
            return ""
        seen.add(key)
        kept.append(tag)
        return tag

    cleaned = HASHTAG_RE.sub(replace, caption)
    cleaned = re.sub(r"[ \t]{2,}", " ", cleaned)
    cleaned = re.sub(r" +\n", "\n", cleaned)
    cleaned = re.sub(r"\n{3,}", "\n\n", cleaned).strip()
    return cleaned, kept


def validate_cover(path: Path) -> None:
    if path.suffix.lower() not in ALLOWED_COVER_SUFFIXES:
        raise ValueError(
            f"Unsupported TikTok cover type: {path.suffix}. "
            "Use JPG, JPEG, PNG, or WEBP."
        )
    if path.stat().st_size > MAX_COVER_BYTES:
        raise ValueError("TikTok custom cover must be 20 MB or smaller.")


def mime_for(path: Path, fallback: str) -> str:
    return mimetypes.guess_type(path.name)[0] or fallback


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Publish a CTNETWORK TikTok video with a custom cover and max 5 hashtags."
    )
    parser.add_argument(
        "--profile",
        default=os.getenv("UPLOAD_POST_PROFILE", "CTN"),
        help="Upload-Post profile name (default: CTN).",
    )

    video = parser.add_mutually_exclusive_group(required=True)
    video.add_argument("--video", type=Path, help="Local video file to upload.")
    video.add_argument("--video-url", help="Public/signed HTTPS video URL.")

    cover = parser.add_mutually_exclusive_group()
    cover.add_argument("--cover", type=Path, help="Local JPG/JPEG/PNG/WEBP custom cover.")
    cover.add_argument("--cover-url", help="Public HTTPS custom cover URL.")

    parser.add_argument("--caption", required=True, help="TikTok caption. Extra hashtags are removed.")
    parser.add_argument(
        "--cover-timestamp-ms",
        type=int,
        default=int(os.getenv("TIKTOK_DEFAULT_COVER_TIMESTAMP_MS", "1000")),
        help="Fallback cover frame timestamp in milliseconds.",
    )
    parser.add_argument(
        "--max-hashtags",
        type=int,
        default=int(os.getenv("TIKTOK_MAX_HASHTAGS", "5")),
        help="Maximum TikTok hashtags to keep (network default: 5).",
    )
    parser.add_argument(
        "--privacy",
        default="PUBLIC_TO_EVERYONE",
        help="TikTok privacy level.",
    )
    parser.add_argument("--scheduled-date", help="Optional ISO-8601 future publish time.")
    parser.add_argument("--timezone", default="America/New_York", help="IANA timezone.")
    parser.add_argument(
        "--aigc",
        action="store_true",
        help="Declare the TikTok video as AI-generated content.",
    )
    parser.add_argument("--dry-run", action="store_true", help="Validate and print payload without posting.")
    return parser


def main() -> int:
    args = build_parser().parse_args()

    if args.max_hashtags < 0 or args.max_hashtags > 5:
        raise SystemExit("--max-hashtags must be between 0 and 5 for CTNETWORK TikTok.")
    if args.cover_timestamp_ms < 0:
        raise SystemExit("--cover-timestamp-ms cannot be negative.")

    caption, hashtags = sanitize_caption(args.caption, args.max_hashtags)
    if not caption:
        raise SystemExit("Caption is empty after TikTok hashtag cleanup.")

    if args.video is not None and not args.video.is_file():
        raise SystemExit(f"Video file not found: {args.video}")
    if args.video_url and not args.video_url.startswith("https://"):
        raise SystemExit("--video-url must be a public or signed HTTPS URL.")

    if args.cover is not None:
        if not args.cover.is_file():
            raise SystemExit(f"Cover file not found: {args.cover}")
        try:
            validate_cover(args.cover)
        except ValueError as exc:
            raise SystemExit(str(exc)) from exc
    if args.cover_url and not args.cover_url.startswith("https://"):
        raise SystemExit("--cover-url must be a public HTTPS URL.")

    data: dict[str, str] = {
        "user": args.profile,
        "platform[]": "tiktok",
        "title": caption,
        "privacy_level": args.privacy,
        "timezone": args.timezone,
    }
    if args.scheduled_date:
        data["scheduled_date"] = args.scheduled_date
    if args.aigc:
        data["tiktok_is_ai_generated"] = "true"

    # Custom image takes priority. Timestamp is the safe fallback.
    if args.cover_url:
        data["tiktok_cover_image_url"] = args.cover_url
    elif args.cover is None:
        data["cover_timestamp"] = str(args.cover_timestamp_ms)

    if args.video_url:
        data["video_url"] = args.video_url

    preview = {
        "profile": args.profile,
        "caption": caption,
        "hashtags_kept": hashtags,
        "hashtag_count": len(hashtags),
        "video": str(args.video) if args.video else args.video_url,
        "cover": (
            str(args.cover)
            if args.cover
            else args.cover_url
            if args.cover_url
            else f"frame@{args.cover_timestamp_ms}ms"
        ),
        "scheduled_date": args.scheduled_date,
    }

    if args.dry_run:
        print(json.dumps(preview, indent=2, ensure_ascii=False))
        return 0

    api_key = os.getenv("UPLOAD_POST_API_KEY", "").strip()
    if not api_key:
        raise SystemExit("UPLOAD_POST_API_KEY is required. Store it as a GitHub Actions secret.")

    files: dict[str, tuple[str, BinaryIO, str]] = {}
    opened: list[BinaryIO] = []
    try:
        if args.video is not None:
            video_fp = args.video.open("rb")
            opened.append(video_fp)
            files["video"] = (args.video.name, video_fp, mime_for(args.video, "video/mp4"))

        if args.cover is not None:
            cover_fp = args.cover.open("rb")
            opened.append(cover_fp)
            files["tiktok_cover_image"] = (
                args.cover.name,
                cover_fp,
                mime_for(args.cover, "image/jpeg"),
            )

        response = requests.post(
            API_URL,
            headers={"Authorization": f"Apikey {api_key}"},
            data=data,
            files=files or None,
            timeout=600,
        )
        response.raise_for_status()
        payload = response.json()
    except requests.RequestException as exc:
        detail = ""
        if getattr(exc, "response", None) is not None:
            detail = f"\n{exc.response.text}"
        raise SystemExit(f"TikTok upload failed: {exc}{detail}") from exc
    finally:
        for fp in opened:
            fp.close()

    print(json.dumps({"request": preview, "response": payload}, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
