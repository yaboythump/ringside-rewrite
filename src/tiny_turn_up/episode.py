from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EPISODES_DIR = ROOT / "tiny_turn_up" / "episodes"

STYLE_LINE = (
    "Bright 3D animated kids cartoon style, glossy Pixar-like rendering, saturated "
    "purple/yellow/teal palette, sunny lighting, big expressive eyes, joyful energy, "
    "clean simple background."
)
CAST = (
    "Characters (keep identical every time): JOJO - boy about 6, warm brown skin, big curly "
    "black afro, huge smile, yellow overalls over white T-shirt, teal high-top sneakers with a "
    "star on the sole. KIKI - girl about 5, brown skin, two puffy pigtails with purple flower "
    "clips, lavender overalls over white T-shirt with a yellow flower, pink sneakers. WADDLES - "
    "small fluffy yellow duckling with a teal bow tie and orange feet. Home base: colorful city "
    "playground court with purple floor, graffiti crown murals, basketball hoop, brick buildings."
)


@dataclass
class Scene:
    prompt: str
    start: float | None = None  # seconds into the song; None = spread evenly


@dataclass
class ShortCut:
    start: float
    length: float
    title: str


@dataclass
class Episode:
    slug: str
    folder: Path
    title: str
    description: str
    tags: list[str]
    thumbnail_prompt: str = ""
    scenes: list[Scene] = field(default_factory=list)
    shorts: list[ShortCut] = field(default_factory=list)
    compile_from: list[str] = field(default_factory=list)

    @property
    def song(self) -> Path:
        for name in ("song.mp3", "song.wav", "song.m4a"):
            if (self.folder / name).exists():
                return self.folder / name
        return self.folder / "song.mp3"

    @property
    def build(self) -> Path:
        return self.folder / "build"

    def scene_media(self, index: int) -> Path:
        """A user-supplied clip (scene_01.mp4) wins over a generated/supplied image (scene_01.png)."""
        for ext in (".mp4", ".mov", ".png", ".jpg", ".jpeg", ".webp"):
            path = self.folder / f"scene_{index:02d}{ext}"
            if path.exists():
                return path
        return self.folder / f"scene_{index:02d}.png"

    @property
    def thumbnail_source(self) -> Path:
        for ext in (".png", ".jpg", ".jpeg", ".webp"):
            path = self.folder / f"thumbnail{ext}"
            if path.exists():
                return path
        return self.folder / "thumbnail.png"


def load_episode(slug: str, episodes_dir: Path = EPISODES_DIR) -> Episode:
    folder = episodes_dir / slug
    data = json.loads((folder / "episode.json").read_text(encoding="utf-8"))
    return Episode(
        slug=slug,
        folder=folder,
        title=data["title"],
        description=data["description"],
        tags=list(data.get("tags", [])),
        thumbnail_prompt=data.get("thumbnail_prompt", ""),
        scenes=[Scene(**s) for s in data.get("scenes", [])],
        shorts=[ShortCut(**s) for s in data.get("shorts", [])],
        compile_from=list(data.get("compile_from", [])),
    )


def list_episodes(episodes_dir: Path = EPISODES_DIR) -> list[str]:
    return sorted(p.parent.name for p in episodes_dir.glob("*/episode.json"))


def full_prompt(scene_prompt: str) -> str:
    return f"{STYLE_LINE} {CAST} Scene: {scene_prompt} No text, no logos, no watermarks."


def scene_timings(scenes: list[Scene], duration: float) -> list[tuple[float, float]]:
    """Return (start, length) for each scene, covering the whole song."""
    count = len(scenes)
    if not count:
        raise ValueError("Episode has no scenes.")
    starts: list[float] = []
    for i, scene in enumerate(scenes):
        starts.append(scene.start if scene.start is not None else duration * i / count)
    starts[0] = 0.0
    for i in range(1, count):
        if starts[i] <= starts[i - 1] or starts[i] >= duration:
            raise ValueError(f"Scene {i + 1} start {starts[i]}s is out of order or past the song end.")
    ends = starts[1:] + [duration]
    return [(s, e - s) for s, e in zip(starts, ends)]
