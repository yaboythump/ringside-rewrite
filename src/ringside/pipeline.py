from __future__ import annotations

import json
import shutil
from datetime import datetime, timedelta, timezone
from pathlib import Path

from .config import Settings
from .models import EpisodePlan
from .quality import evaluate_assets, evaluate_episode, load_recent_plans
from .render import render_episode
from .studio import generate_episode_assets, generate_episode_plan
from .youtube import upload_episode


def dry_run(settings: Settings, episode_path: Path) -> Path:
    plan = EpisodePlan.load(episode_path)
    recent = load_recent_plans(settings.output_dir, plan.slug)
    report = evaluate_episode(plan, settings.channel, recent)
    destination = settings.output_dir / plan.slug / "quality-preflight.json"
    report.save(destination)
    report.require_pass()
    return destination


def create_episode(settings: Settings, theme: str | None = None) -> Path:
    recent = load_recent_plans(settings.output_dir, exclude_slug="")
    plan = generate_episode_plan(
        settings,
        theme=theme,
        recent_plans=recent,
    )
    report = evaluate_episode(plan, settings.channel, recent)
    episode_dir = settings.output_dir / plan.slug
    episode_dir.mkdir(parents=True, exist_ok=True)
    plan_path = episode_dir / "episode.json"
    plan.save(plan_path)
    report.save(episode_dir / "quality-preflight.json")
    report.require_pass()
    return plan_path


def produce_episode(
    settings: Settings,
    episode_path: Path,
    generate_images: bool = True,
    generate_audio: bool = True,
) -> Path:
    plan = EpisodePlan.load(episode_path)
    recent = load_recent_plans(settings.output_dir, plan.slug)
    preflight = evaluate_episode(plan, settings.channel, recent)
    preflight.require_pass()
    episode_dir = settings.output_dir / plan.slug
    episode_dir.mkdir(parents=True, exist_ok=True)
    plan.save(episode_dir / "episode.json")
    preflight.save(episode_dir / "quality-preflight.json")

    generate_episode_assets(
        settings,
        plan,
        episode_dir,
        images=generate_images,
        audio=generate_audio,
    )
    render_episode(settings, plan, episode_dir)
    postflight = evaluate_assets(plan, episode_dir)
    postflight.save(episode_dir / "quality-assets.json")
    postflight.require_pass()

    manifest = {
        "channel": settings.channel.get("channel", {}).get("name"),
        "episode": plan.episode_title,
        "slug": plan.slug,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "synthetic_media_disclosed": plan.contains_synthetic_media,
        "hypothetical_booking": plan.hypothetical_booking,
        "historical_cutoff": plan.historical_cutoff,
        "sources": [note.source_url for note in plan.source_notes],
        "files": {
            "video": "final.mp4",
            "thumbnail": "thumbnail.png",
            "captions": "captions.srt",
            "shorts": [f"shorts/short-{index:02d}.mp4" for index in range(1, len(plan.shorts) + 1)],
        },
    }
    (episode_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2), encoding="utf-8"
    )
    return episode_dir


def approve_episode(settings: Settings, episode_dir: Path) -> Path:
    plan = EpisodePlan.load(episode_dir / "episode.json")
    report = evaluate_assets(plan, episode_dir)
    report.require_pass()
    marker_name = settings.channel.get("approval", {}).get("marker_filename", ".approved")
    marker = episode_dir / marker_name
    marker.write_text(
        f"Approved {datetime.now(timezone.utc).isoformat()}\n", encoding="utf-8"
    )
    return marker


def publish_episode(
    settings: Settings,
    episode_dir: Path,
    privacy: str,
    publish_at: str | None = None,
) -> dict:
    plan = EpisodePlan.load(episode_dir / "episode.json")
    evaluate_assets(plan, episode_dir).require_pass()
    return upload_episode(
        settings,
        plan,
        episode_dir,
        privacy=privacy,
        publish_at=publish_at,
        include_shorts=True,
    )


def scheduled_run(settings: Settings) -> dict:
    episode_path = create_episode(settings)
    episode_dir = produce_episode(settings, episode_path)
    if settings.auto_publish:
        publish_time = datetime.now(timezone.utc) + timedelta(hours=2)
        privacy = "public"
        publish_at = publish_time.isoformat().replace("+00:00", "Z")
    else:
        privacy = "private"
        publish_at = None
    return publish_episode(settings, episode_dir, privacy, publish_at)


def seed_pilot_assets(settings: Settings) -> Path:
    """Copy the supplied visual launch assets beside the pilot output."""
    plan = EpisodePlan.load(settings.root / "content" / "pilot" / "episode.json")
    episode_dir = settings.output_dir / plan.slug
    episode_dir.mkdir(parents=True, exist_ok=True)
    for source, target in [
        (
            settings.root / "assets" / "pilot-thumbnail-youtube.png",
            episode_dir / "thumbnail-source.png",
        ),
        (
            settings.root / "assets" / "ringside-rewrite-logo-master.png",
            episode_dir / "brand-reference.png",
        ),
    ]:
        if source.exists() and not target.exists():
            shutil.copy2(source, target)
    return episode_dir
