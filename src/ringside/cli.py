from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
from pathlib import Path

from .config import load_settings
from .pipeline import (
    approve_episode,
    create_episode,
    dry_run,
    produce_episode,
    publish_episode,
    scheduled_run,
)
from .youtube import analytics_snapshot, authorize


def _root() -> Path:
    return Path(os.getenv("RINGSIDE_ROOT", Path.cwd())).resolve()


def _path(value: str) -> Path:
    path = Path(value)
    return path if path.is_absolute() else _root() / path


def doctor() -> int:
    settings = load_settings(_root())
    cloud_oauth_client = bool(
        settings.youtube_client_id and settings.youtube_client_secret_value
    )
    cloud_oauth_token = bool(settings.youtube_refresh_token)
    checks = {
        "project_config": (settings.root / "config" / "channel.toml").exists(),
        "research_config": (settings.root / "config" / "research.toml").exists(),
        "brand_assets": all(
            (settings.root / "assets" / name).exists()
            for name in (
                "ringside-rewrite-avatar-youtube.png",
                "ringside-rewrite-banner-youtube.png",
            )
        ),
        "ffmpeg": bool(shutil.which("ffmpeg")),
        "ffprobe": bool(shutil.which("ffprobe")),
        "openai_api_key": settings.openai_api_key_present,
        "youtube_oauth_client": settings.youtube_client_secret.exists()
        or cloud_oauth_client,
        "youtube_authorized": settings.youtube_token.exists() or cloud_oauth_token,
        "youtube_channel_lock": bool(settings.youtube_expected_channel_id),
    }
    print("RINGSIDE REWRITE — system check")
    for name, passed in checks.items():
        print(f"{'PASS' if passed else 'WAIT'}  {name}")
    core = (
        checks["project_config"]
        and checks["research_config"]
        and checks["brand_assets"]
        and checks["ffmpeg"]
        and checks["ffprobe"]
    )
    print("\nCore production system is ready." if core else "\nCore setup is incomplete.")
    return 0 if core else 1


def scheduler() -> None:
    try:
        from apscheduler.schedulers.blocking import BlockingScheduler
        from apscheduler.triggers.cron import CronTrigger
    except ImportError as exc:
        raise RuntimeError("Install the project dependencies with: pip install -e .") from exc

    settings = load_settings(_root())
    schedule = settings.channel.get("schedule", {})
    timezone_name = settings.channel.get("channel", {}).get("timezone", "America/New_York")
    hour, minute = map(int, schedule.get("long_form_time", "12:00").split(":"))
    days = ",".join(schedule.get("long_form_days", ["tue", "thu", "sat"]))
    engine = BlockingScheduler(timezone=timezone_name)
    engine.add_job(
        lambda: scheduled_run(settings),
        CronTrigger(day_of_week=days, hour=hour, minute=minute, timezone=timezone_name),
        id="ringside-long-form",
        coalesce=True,
        max_instances=1,
        misfire_grace_time=3600,
    )
    print(f"RINGSIDE scheduler active: {days} at {hour:02d}:{minute:02d} {timezone_name}")
    engine.start()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="ringside")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("doctor")
    sub.add_parser("youtube-auth")
    sub.add_parser("stats")
    sub.add_parser("scheduler")

    dry = sub.add_parser("dry-run")
    dry.add_argument("--episode", required=True)

    generate = sub.add_parser("generate")
    generate.add_argument("--theme")

    produce = sub.add_parser("produce")
    produce.add_argument("--episode", required=True)
    produce.add_argument("--reuse-images", action="store_true")
    produce.add_argument("--reuse-audio", action="store_true")

    approve = sub.add_parser("approve")
    approve.add_argument("--episode-dir", required=True)

    publish = sub.add_parser("publish")
    publish.add_argument("--episode-dir", required=True)
    publish.add_argument("--privacy", choices=["private", "unlisted", "public"], default="private")
    publish.add_argument("--publish-at", help="ISO 8601 UTC time, for example 2026-08-28T00:30:00Z")
    return parser


def main() -> None:
    args = build_parser().parse_args()
    settings = load_settings(_root())
    if args.command == "doctor":
        raise SystemExit(doctor())
    if args.command == "youtube-auth":
        print(f"Authorized YouTube channel: {authorize(settings)}")
        return
    if args.command == "stats":
        snapshot = analytics_snapshot(settings)
        print(json.dumps({"videos": len(snapshot.get("videos", []))}, indent=2))
        return
    if args.command == "scheduler":
        scheduler()
        return
    if args.command == "dry-run":
        print(f"Quality preflight passed: {dry_run(settings, _path(args.episode))}")
        return
    if args.command == "generate":
        print(f"Generated: {create_episode(settings, args.theme)}")
        return
    if args.command == "produce":
        destination = produce_episode(
            settings,
            _path(args.episode),
            generate_images=not args.reuse_images,
            generate_audio=not args.reuse_audio,
        )
        print(f"Produced: {destination}")
        return
    if args.command == "approve":
        print(f"Approved: {approve_episode(settings, _path(args.episode_dir))}")
        return
    if args.command == "publish":
        result = publish_episode(
            settings,
            _path(args.episode_dir),
            args.privacy,
            args.publish_at,
        )
        print(json.dumps(result, indent=2))
        return
    raise SystemExit(f"Unknown command: {args.command}")


if __name__ == "__main__":
    main()
