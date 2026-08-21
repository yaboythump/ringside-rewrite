from __future__ import annotations

import json
from pathlib import Path
from typing import Literal

from pydantic import BaseModel, Field, field_validator, model_validator


class DialogueLine(BaseModel):
    speaker: str = Field(min_length=1, max_length=40)
    text: str = Field(min_length=1, max_length=500)
    delivery: str = Field(default="grounded", max_length=120)


class Shot(BaseModel):
    id: int = Field(ge=1)
    scene_title: str = Field(min_length=1, max_length=100)
    location: str = Field(min_length=1, max_length=120)
    time_of_day: str = Field(default="night", max_length=40)
    narration: str = Field(default="", max_length=1800)
    dialogue: list[DialogueLine] = Field(default_factory=list)
    image_prompt: str = Field(min_length=40, max_length=3000)
    motion: Literal[
        "slow_push_in",
        "slow_pull_out",
        "pan_left",
        "pan_right",
        "locked",
        "handheld_drift",
    ] = "slow_push_in"
    sfx: list[str] = Field(default_factory=list, max_length=8)
    music_mood: str = Field(default="low cinematic tension", max_length=160)
    duration_hint_seconds: int = Field(default=14, ge=5, le=35)

    @property
    def spoken_text(self) -> str:
        parts: list[str] = []
        if self.narration.strip():
            parts.append(self.narration.strip())
        for line in self.dialogue:
            parts.append(f'{line.speaker}: "{line.text.strip()}"')
        return "\n\n".join(parts).strip()


class ShortCut(BaseModel):
    title: str = Field(min_length=1, max_length=100)
    hook: str = Field(min_length=1, max_length=180)
    start_shot: int = Field(ge=1)
    end_shot: int = Field(ge=1)
    caption: str = Field(min_length=1, max_length=2200)

    @model_validator(mode="after")
    def end_follows_start(self) -> "ShortCut":
        if self.end_shot < self.start_shot:
            raise ValueError("end_shot must be greater than or equal to start_shot")
        return self


class SourceNote(BaseModel):
    claim: str = Field(min_length=20, max_length=500)
    source_title: str = Field(min_length=3, max_length=240)
    source_url: str = Field(pattern=r"^https?://", max_length=1000)


class EpisodePlan(BaseModel):
    slug: str = Field(pattern=r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
    episode_title: str = Field(min_length=1, max_length=100)
    series: str = Field(default="RINGSIDE REWRITE", max_length=100)
    logline: str = Field(min_length=20, max_length=400)
    theme: str = Field(min_length=3, max_length=160)
    primary_subjects: list[str] = Field(min_length=1, max_length=6)
    historical_cutoff: str = Field(min_length=4, max_length=160)
    factual_baseline: list[str] = Field(min_length=3, max_length=10)
    source_notes: list[SourceNote] = Field(min_length=2, max_length=10)
    hypothetical_booking: bool = True
    original_fiction: bool = True
    contains_synthetic_media: bool = True
    title_options: list[str] = Field(min_length=3, max_length=5)
    thumbnail_text: str = Field(min_length=1, max_length=40)
    description: str = Field(min_length=30, max_length=5000)
    tags: list[str] = Field(min_length=5, max_length=15)
    hashtags: list[str] = Field(min_length=3, max_length=5)
    viewer_question: str = Field(min_length=10, max_length=240)
    shots: list[Shot] = Field(min_length=1, max_length=60)
    shorts: list[ShortCut] = Field(default_factory=list, max_length=5)
    thumbnail_source: str | None = None

    @field_validator("title_options")
    @classmethod
    def unique_titles(cls, values: list[str]) -> list[str]:
        clean = [value.strip() for value in values]
        if len({value.casefold() for value in clean}) != len(clean):
            raise ValueError("title options must be unique")
        if any(len(value) > 100 for value in clean):
            raise ValueError("YouTube titles must be 100 characters or fewer")
        return clean

    @field_validator("tags")
    @classmethod
    def unique_tags(cls, values: list[str]) -> list[str]:
        output: list[str] = []
        seen: set[str] = set()
        for value in values:
            tag = value.strip()
            if tag and tag.casefold() not in seen:
                output.append(tag)
                seen.add(tag.casefold())
        return output

    @field_validator("primary_subjects", "factual_baseline", "hashtags")
    @classmethod
    def unique_string_lists(cls, values: list[str]) -> list[str]:
        clean = [value.strip() for value in values if value.strip()]
        if len({value.casefold() for value in clean}) != len(clean):
            raise ValueError("list values must be unique")
        return clean

    @field_validator("hashtags")
    @classmethod
    def normalize_hashtags(cls, values: list[str]) -> list[str]:
        normalized: list[str] = []
        for value in values:
            compact = "".join(value.strip().split())
            normalized.append(compact if compact.startswith("#") else f"#{compact}")
        return normalized

    @model_validator(mode="after")
    def shot_ids_and_short_ranges(self) -> "EpisodePlan":
        ids = [shot.id for shot in self.shots]
        if ids != list(range(1, len(self.shots) + 1)):
            raise ValueError("shot ids must be contiguous and start at 1")
        last = len(self.shots)
        for cut in self.shorts:
            if cut.end_shot > last:
                raise ValueError(f"Short '{cut.title}' exceeds the final shot")
        return self

    @property
    def spoken_word_count(self) -> int:
        return sum(len(shot.spoken_text.split()) for shot in self.shots)

    def save(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(self.model_dump_json(indent=2), encoding="utf-8")

    @classmethod
    def load(cls, path: Path) -> "EpisodePlan":
        return cls.model_validate(json.loads(path.read_text(encoding="utf-8")))
