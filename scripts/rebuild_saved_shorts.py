#!/usr/bin/env python3
from __future__ import annotations

import argparse
import math
import re
from pathlib import Path

from ringside.config import load_settings
from ringside.models import EpisodePlan
from ringside.render import ShotTiming, render_shorts


TIME_RE = re.compile(
    r"(?P<sh>\d{2}):(?P<sm>\d{2}):(?P<ss>\d{2}),(?P<sms>\d{3})\s+-->\s+"
    r"(?P<eh>\d{2}):(?P<em>\d{2}):(?P<es>\d{2}),(?P<ems>\d{3})"
)


def seconds(hours: str, minutes: str, secs: str, millis: str) -> float:
    return int(hours) * 3600 + int(minutes) * 60 + int(secs) + int(millis) / 1000


def caption_ranges(path: Path) -> list[tuple[float, float]]:
    ranges: list[tuple[float, float]] = []
    for match in TIME_RE.finditer(path.read_text(encoding="utf-8")):
        ranges.append(
            (
                seconds(match["sh"], match["sm"], match["ss"], match["sms"]),
                seconds(match["eh"], match["em"], match["es"], match["ems"]),
            )
        )
    return ranges


def recover_timings(plan: EpisodePlan, captions: Path) -> list[ShotTiming]:
    entries = caption_ranges(captions)
    cursor = 0
    timings: list[ShotTiming] = []
    for shot in plan.shots:
        chunks = max(1, math.ceil(len(shot.spoken_text.replace("\n", " ").split()) / 10))
        group = entries[cursor : cursor + chunks]
        if len(group) != chunks:
            raise RuntimeError("Captions do not contain enough timing entries to rebuild Shorts.")
        timings.append(ShotTiming(shot.id, group[0][0], group[-1][1]))
        cursor += chunks
    return timings


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--episode-dir", required=True)
    args = parser.parse_args()
    episode_dir = Path(args.episode_dir).resolve()
    plan = EpisodePlan.load(episode_dir / "episode.json")
    timings = recover_timings(plan, episode_dir / "captions.srt")
    settings = load_settings(Path.cwd())
    render_shorts(settings, plan, episode_dir, timings)
    print(f"Rebuilt {len(plan.shorts)} correctly fitted Shorts in {episode_dir / 'shorts'}")


if __name__ == "__main__":
    main()
