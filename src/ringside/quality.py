from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from difflib import SequenceMatcher
from pathlib import Path
from urllib.parse import urlparse

from .models import EpisodePlan


@dataclass
class QualityReport:
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    metrics: dict[str, int | float | str | bool] = field(default_factory=dict)

    @property
    def passed(self) -> bool:
        return not self.errors

    def require_pass(self) -> None:
        if not self.passed:
            joined = "\n- ".join(self.errors)
            raise RuntimeError(f"Quality gate failed:\n- {joined}")

    def save(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "passed": self.passed,
            "errors": self.errors,
            "warnings": self.warnings,
            "metrics": self.metrics,
        }
        path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def _normalize(text: str) -> str:
    return " ".join(re.findall(r"[a-z0-9']+", text.casefold()))


def _script_text(plan: EpisodePlan) -> str:
    return " ".join(shot.spoken_text for shot in plan.shots)


def evaluate_episode(
    plan: EpisodePlan,
    channel_config: dict,
    recent_plans: list[EpisodePlan] | None = None,
) -> QualityReport:
    report = QualityReport()
    quality = channel_config.get("quality", {})
    production = channel_config.get("production", {})
    minimum_words = int(quality.get("min_words", 950))
    maximum_words = int(quality.get("max_words", 1650))
    minimum_shots = int(production.get("min_shots", 24))
    maximum_shots = int(production.get("max_shots", 36))
    minimum_locations = int(quality.get("min_distinct_locations", 4))
    max_similarity = float(quality.get("max_recent_similarity", 0.52))
    minimum_sources = int(quality.get("minimum_source_notes", 2))
    subject_cooldown = int(quality.get("subject_cooldown_episodes", 3))

    word_count = plan.spoken_word_count
    shot_count = len(plan.shots)
    distinct_locations = len({_normalize(shot.location) for shot in plan.shots})
    report.metrics.update(
        word_count=word_count,
        shot_count=shot_count,
        distinct_locations=distinct_locations,
        synthetic_media=plan.contains_synthetic_media,
        original_fiction=plan.original_fiction,
        hypothetical_booking=plan.hypothetical_booking,
        source_count=len(plan.source_notes),
    )

    if word_count < minimum_words:
        report.errors.append(f"Script has {word_count} words; minimum is {minimum_words}.")
    if word_count > maximum_words:
        report.errors.append(f"Script has {word_count} words; maximum is {maximum_words}.")
    if shot_count < minimum_shots:
        report.errors.append(f"Only {shot_count} shots; minimum is {minimum_shots}.")
    if shot_count > maximum_shots:
        report.errors.append(f"{shot_count} shots exceeds the cost cap of {maximum_shots}.")
    if distinct_locations < minimum_locations:
        report.errors.append(
            f"Only {distinct_locations} distinct locations; minimum is {minimum_locations}."
        )
    if quality.get("require_ai_disclosure", True) and not plan.contains_synthetic_media:
        report.errors.append("Realistic synthetic-media disclosure must remain enabled.")
    if quality.get("require_original_story", True) and not plan.original_fiction:
        report.errors.append("Episode must be explicitly marked as original fiction.")
    if quality.get("require_hypothetical_booking", True) and not plan.hypothetical_booking:
        report.errors.append("Episode must be explicitly marked as hypothetical booking.")
    if quality.get("require_factual_baseline", True) and len(plan.factual_baseline) < 3:
        report.errors.append("Episode needs at least three documented baseline facts.")
    if len(plan.source_notes) < minimum_sources:
        report.errors.append(
            f"Episode has {len(plan.source_notes)} source notes; minimum is {minimum_sources}."
        )

    source_urls = [note.source_url.strip() for note in plan.source_notes]
    if len({url.casefold() for url in source_urls}) != len(source_urls):
        report.errors.append("Source URLs must be unique.")
    invalid_sources = [
        url
        for url in source_urls
        if urlparse(url).scheme not in {"http", "https"} or not urlparse(url).netloc
    ]
    if invalid_sources:
        report.errors.append("Every source note must contain a valid HTTP(S) URL.")

    if "what if" not in plan.description.casefold() and "hypothetical" not in plan.description.casefold():
        report.errors.append("Description must clearly identify the episode as a what-if.")
    if any(shot.dialogue for shot in plan.shots):
        report.errors.append(
            "Direct dialogue is disabled for real-person episodes; summarize imagined promos."
        )

    if len(plan.thumbnail_text.split()) > 6:
        report.warnings.append("Thumbnail copy is longer than six words.")
    if any(not hashtag.startswith("#") for hashtag in plan.hashtags):
        report.errors.append("Every hashtag must begin with #.")
    if sum(len(tag) + 1 for tag in plan.tags) > 500:
        report.errors.append("Combined YouTube tag length exceeds 500 characters.")
    if len(plan.description) > 5000:
        report.errors.append("Description exceeds YouTube's 5,000-character limit.")
    if any(len(title) > 100 for title in plan.title_options):
        report.errors.append("A title exceeds YouTube's 100-character limit.")

    normalized_prompts = [_normalize(shot.image_prompt) for shot in plan.shots]
    exact_prompt_duplicates = len(normalized_prompts) - len(set(normalized_prompts))
    if exact_prompt_duplicates:
        report.errors.append(f"{exact_prompt_duplicates} image prompts are exact duplicates.")
    weak_prompts = [
        shot.id
        for shot in plan.shots
        if "no text" not in shot.image_prompt.casefold()
        or "no watermark" not in shot.image_prompt.casefold()
    ]
    if weak_prompts:
        report.warnings.append(
            "Shots missing explicit no-text/no-watermark constraints: "
            + ", ".join(map(str, weak_prompts))
        )

    opening_size = int(quality.get("max_repeated_opening_words", 8))
    openings: list[str] = []
    for shot in plan.shots:
        opening = " ".join(_normalize(shot.spoken_text).split()[:opening_size])
        if opening:
            openings.append(opening)
    repeated_openings = len(openings) - len(set(openings))
    if repeated_openings > 1:
        report.errors.append("Too many shots begin with the same phrasing.")

    current = _normalize(_script_text(plan))
    highest = 0.0
    nearest = ""
    for previous in recent_plans or []:
        score = SequenceMatcher(None, current, _normalize(_script_text(previous))).ratio()
        if score > highest:
            highest = score
            nearest = previous.episode_title
    report.metrics["highest_recent_similarity"] = round(highest, 4)
    if highest > max_similarity:
        report.errors.append(
            f"Script similarity to '{nearest}' is {highest:.1%}; limit is {max_similarity:.1%}."
        )

    current_subjects = {subject.casefold() for subject in plan.primary_subjects}
    recent_subjects: set[str] = set()
    for previous in (recent_plans or [])[:subject_cooldown]:
        recent_subjects.update(subject.casefold() for subject in previous.primary_subjects)
    overlap = sorted(current_subjects & recent_subjects)
    if overlap:
        report.errors.append(
            "Primary subject repeated inside the cooldown window: " + ", ".join(overlap)
        )

    return report


def load_recent_plans(output_dir: Path, exclude_slug: str, limit: int = 12) -> list[EpisodePlan]:
    candidates = sorted(
        output_dir.glob("*/episode.json"),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    plans: list[EpisodePlan] = []
    for path in candidates:
        if path.parent.name == exclude_slug:
            continue
        try:
            plans.append(EpisodePlan.load(path))
        except Exception:
            continue
        if len(plans) >= limit:
            break
    return plans


def evaluate_assets(plan: EpisodePlan, episode_dir: Path) -> QualityReport:
    report = QualityReport()
    missing_images = [
        shot.id for shot in plan.shots if not (episode_dir / "images" / f"shot-{shot.id:03d}.png").exists()
    ]
    missing_audio = [
        shot.id for shot in plan.shots if not (episode_dir / "audio" / f"shot-{shot.id:03d}.wav").exists()
    ]
    final_video = episode_dir / "final.mp4"
    thumbnail = episode_dir / "thumbnail.png"
    if missing_images:
        report.errors.append(f"Missing {len(missing_images)} shot images.")
    if missing_audio:
        report.errors.append(f"Missing {len(missing_audio)} narration files.")
    if not final_video.exists() or final_video.stat().st_size < 100_000:
        report.errors.append("Final video is missing or unexpectedly small.")
    if not thumbnail.exists() or thumbnail.stat().st_size < 10_000:
        report.errors.append("Thumbnail is missing or unexpectedly small.")
    report.metrics.update(
        missing_images=len(missing_images),
        missing_audio=len(missing_audio),
        final_video_exists=final_video.exists(),
        thumbnail_exists=thumbnail.exists(),
    )
    return report
