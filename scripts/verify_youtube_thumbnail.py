from __future__ import annotations

import argparse
import io
import json
import time
import urllib.request
from pathlib import Path

from PIL import Image, ImageChops, ImageOps, ImageStat


def mean_abs_error(actual: Image.Image, expected: Image.Image) -> float:
    actual = actual.convert("RGB")
    normalized = ImageOps.fit(
        expected.convert("RGB"),
        actual.size,
        method=Image.Resampling.LANCZOS,
        centering=(0.5, 0.5),
    )
    stat = ImageStat.Stat(ImageChops.difference(actual, normalized))
    return sum(stat.mean) / 3.0


def fetch_image(url: str) -> Image.Image:
    with urllib.request.urlopen(url, timeout=20) as response:
        return Image.open(io.BytesIO(response.read())).convert("RGB")


def verify(video_id: str, thumbnail: Path, attempts: int = 8, delay: int = 15) -> None:
    expected = Image.open(thumbnail).convert("RGB")
    variants = ("mqdefault", "hqdefault", "sddefault", "maxresdefault")
    last: dict[str, object] = {}
    for attempt in range(1, attempts + 1):
        passed = True
        last = {}
        for variant in variants:
            url = f"https://i.ytimg.com/vi/{video_id}/{variant}.jpg?verify={time.time_ns()}"
            try:
                score = mean_abs_error(fetch_image(url), expected)
                last[variant] = round(score, 2)
                if score > 20.0:
                    passed = False
            except Exception as exc:
                last[variant] = str(exc)
                passed = False
        print(f"thumbnail verification attempt={attempt}: {last}")
        if passed:
            print(f"THUMBNAIL_GATE_PASS video_id={video_id}")
            return
        time.sleep(delay)
    raise RuntimeError(f"THUMBNAIL_GATE_FAIL video_id={video_id} results={last}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--episode-dir", required=True)
    args = parser.parse_args()
    episode_dir = Path(args.episode_dir)
    upload = json.loads((episode_dir / "youtube-upload.json").read_text(encoding="utf-8"))
    video_id = upload["long_form"]["id"]
    thumbnail = episode_dir / "thumbnail.png"
    if not thumbnail.exists():
        raise RuntimeError(f"Missing required custom thumbnail: {thumbnail}")
    verify(video_id, thumbnail)


if __name__ == "__main__":
    main()
