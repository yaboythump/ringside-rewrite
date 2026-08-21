from __future__ import annotations

import json
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFont

from .config import Settings
from .models import EpisodePlan


@dataclass
class ShotTiming:
    shot_id: int
    start: float
    end: float


def require_ffmpeg() -> None:
    if not shutil.which("ffmpeg") or not shutil.which("ffprobe"):
        raise RuntimeError("FFmpeg and ffprobe must be installed and available on PATH.")


def _run(command: list[str], cwd: Path | None = None) -> None:
    result = subprocess.run(command, cwd=cwd, text=True, capture_output=True)
    if result.returncode:
        tail = "\n".join(result.stderr.splitlines()[-25:])
        raise RuntimeError(f"Command failed ({result.returncode}):\n{tail}")


def probe_duration(path: Path) -> float:
    result = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "default=noprint_wrappers=1:nokey=1",
            str(path),
        ],
        text=True,
        capture_output=True,
        check=True,
    )
    return max(float(result.stdout.strip()), 0.1)


def _srt_time(seconds: float) -> str:
    milliseconds = round(seconds * 1000)
    hours, milliseconds = divmod(milliseconds, 3_600_000)
    minutes, milliseconds = divmod(milliseconds, 60_000)
    secs, milliseconds = divmod(milliseconds, 1000)
    return f"{hours:02d}:{minutes:02d}:{secs:02d},{milliseconds:03d}"


def _caption_text(text: str, words_per_caption: int = 10) -> list[str]:
    words = text.replace("\n", " ").split()
    return [
        " ".join(words[index : index + words_per_caption])
        for index in range(0, len(words), words_per_caption)
    ]


def write_captions(plan: EpisodePlan, timings: list[ShotTiming], destination: Path) -> None:
    entries: list[str] = []
    counter = 1
    for shot, timing in zip(plan.shots, timings, strict=True):
        chunks = _caption_text(shot.spoken_text)
        if not chunks:
            continue
        span = (timing.end - timing.start) / len(chunks)
        for index, chunk in enumerate(chunks):
            start = timing.start + index * span
            end = min(timing.end, start + span)
            entries.extend(
                [
                    str(counter),
                    f"{_srt_time(start)} --> {_srt_time(end)}",
                    chunk,
                    "",
                ]
            )
            counter += 1
    destination.write_text("\n".join(entries), encoding="utf-8")


def _zoom_expression(motion: str) -> tuple[str, str, str]:
    if motion == "slow_pull_out":
        return ("if(eq(on,1),1.08,max(1.0,zoom-0.0005))", "iw/2-(iw/zoom/2)", "ih/2-(ih/zoom/2)")
    if motion == "pan_left":
        return ("1.05", "max(0,iw-iw/zoom-on*0.8)", "ih/2-(ih/zoom/2)")
    if motion == "pan_right":
        return ("1.05", "min(iw-iw/zoom,on*0.8)", "ih/2-(ih/zoom/2)")
    if motion == "locked":
        return ("1.0", "0", "0")
    if motion == "handheld_drift":
        return ("min(zoom+0.00035,1.05)", "iw/2-(iw/zoom/2)+sin(on/17)*3", "ih/2-(ih/zoom/2)+cos(on/19)*3")
    return ("min(zoom+0.0005,1.08)", "iw/2-(iw/zoom/2)", "ih/2-(ih/zoom/2)")


def _render_shot(
    image_path: Path,
    audio_path: Path,
    destination: Path,
    duration: float,
    motion: str,
    width: int,
    height: int,
    fps: int,
) -> None:
    frames = max(round(duration * fps), 1)
    zoom, x_pos, y_pos = _zoom_expression(motion)
    video_filter = (
        f"scale={width}:{height}:force_original_aspect_ratio=increase,"
        f"crop={width}:{height},"
        f"zoompan=z='{zoom}':x='{x_pos}':y='{y_pos}':d={frames}:s={width}x{height}:fps={fps},"
        "format=yuv420p"
    )
    _run(
        [
            "ffmpeg",
            "-y",
            "-loop",
            "1",
            "-i",
            str(image_path),
            "-i",
            str(audio_path),
            "-vf",
            video_filter,
            "-t",
            f"{duration:.3f}",
            "-r",
            str(fps),
            "-c:v",
            "libx264",
            "-preset",
            "medium",
            "-crf",
            "18",
            "-c:a",
            "aac",
            "-b:a",
            "192k",
            "-shortest",
            str(destination),
        ]
    )


def render_thumbnail(source: Path, text: str, destination: Path) -> None:
    image = Image.open(source).convert("RGB")
    target_ratio = 16 / 9
    if image.width / image.height > target_ratio:
        new_width = round(image.height * target_ratio)
        left = (image.width - new_width) // 2
        image = image.crop((left, 0, left + new_width, image.height))
    else:
        new_height = round(image.width / target_ratio)
        top = (image.height - new_height) // 2
        image = image.crop((0, top, image.width, top + new_height))
    image = image.resize((1280, 720), Image.Resampling.LANCZOS)
    image = ImageEnhance.Contrast(image).enhance(1.08)
    overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    draw.rectangle((0, 0, 680, 720), fill=(0, 0, 0, 155))
    font_path = Path("/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf")
    font_size = 108
    font = ImageFont.truetype(str(font_path), font_size)
    words = text.upper().split()
    lines: list[str] = []
    current = ""
    for word in words:
        candidate = f"{current} {word}".strip()
        if draw.textbbox((0, 0), candidate, font=font)[2] > 590 and current:
            lines.append(current)
            current = word
        else:
            current = candidate
    if current:
        lines.append(current)
    total_height = len(lines) * 130
    y_pos = (720 - total_height) // 2
    for line in lines:
        draw.text(
            (58, y_pos),
            line,
            font=font,
            fill=(215, 170, 76, 255),
            stroke_width=5,
            stroke_fill=(0, 0, 0, 255),
        )
        y_pos += 130
    Image.alpha_composite(image.convert("RGBA"), overlay).convert("RGB").save(
        destination, quality=95
    )


def render_episode(settings: Settings, plan: EpisodePlan, episode_dir: Path) -> list[ShotTiming]:
    require_ffmpeg()
    production = settings.channel.get("production", {})
    width = int(production.get("video_width", 1920))
    height = int(production.get("video_height", 1080))
    fps = int(production.get("fps", 30))
    clip_dir = episode_dir / "clips"
    clip_dir.mkdir(parents=True, exist_ok=True)
    timings: list[ShotTiming] = []
    cursor = 0.0
    clip_paths: list[Path] = []

    for shot in plan.shots:
        image_path = episode_dir / "images" / f"shot-{shot.id:03d}.png"
        audio_path = episode_dir / "audio" / f"shot-{shot.id:03d}.wav"
        if not image_path.exists() or not audio_path.exists():
            raise RuntimeError(f"Shot {shot.id} is missing an image or narration file.")
        duration = probe_duration(audio_path) + 0.18
        clip_path = clip_dir / f"shot-{shot.id:03d}.mp4"
        print(f"[render {shot.id:03d}/{len(plan.shots):03d}] {duration:.1f}s")
        _render_shot(
            image_path,
            audio_path,
            clip_path,
            duration,
            shot.motion,
            width,
            height,
            fps,
        )
        clip_paths.append(clip_path)
        timings.append(ShotTiming(shot.id, cursor, cursor + duration))
        cursor += duration

    concat_file = episode_dir / "concat.txt"
    concat_file.write_text(
        "\n".join(f"file '{path.resolve()}'" for path in clip_paths), encoding="utf-8"
    )
    base_video = episode_dir / "base.mp4"
    _run(
        [
            "ffmpeg",
            "-y",
            "-f",
            "concat",
            "-safe",
            "0",
            "-i",
            str(concat_file),
            "-c",
            "copy",
            str(base_video),
        ]
    )
    captions = episode_dir / "captions.srt"
    write_captions(plan, timings, captions)
    final_video = episode_dir / "final.mp4"
    subtitle_filter = (
        "subtitles=captions.srt:force_style='FontName=DejaVu Sans,FontSize=18,"
        "PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,BorderStyle=1,"
        "Outline=2,Shadow=0,Alignment=2,MarginV=42'"
    )
    music = settings.root / "assets" / "music-bed.mp3"
    if music.exists():
        volume = float(production.get("music_volume", 0.10))
        _run(
            [
                "ffmpeg",
                "-y",
                "-i",
                str(base_video),
                "-stream_loop",
                "-1",
                "-i",
                str(music),
                "-vf",
                subtitle_filter,
                "-filter_complex",
                f"[0:a]volume=1.0[voice];[1:a]volume={volume}[bed];[voice][bed]amix=inputs=2:duration=first[a]",
                "-map",
                "0:v",
                "-map",
                "[a]",
                "-c:v",
                "libx264",
                "-crf",
                "18",
                "-c:a",
                "aac",
                "-shortest",
                str(final_video),
            ],
            cwd=episode_dir,
        )
    else:
        _run(
            [
                "ffmpeg",
                "-y",
                "-i",
                str(base_video),
                "-vf",
                subtitle_filter,
                "-c:v",
                "libx264",
                "-crf",
                "18",
                "-c:a",
                "copy",
                str(final_video),
            ],
            cwd=episode_dir,
        )

    thumbnail_source = (
        settings.resolve(plan.thumbnail_source)
        if plan.thumbnail_source
        else episode_dir / "images" / "shot-001.png"
    )
    if not thumbnail_source.exists():
        thumbnail_source = episode_dir / "images" / "shot-001.png"
    render_thumbnail(thumbnail_source, plan.thumbnail_text, episode_dir / "thumbnail.png")
    (episode_dir / "shot-timings.json").write_text(
        json.dumps([timing.__dict__ for timing in timings], indent=2), encoding="utf-8"
    )
    render_shorts(settings, plan, episode_dir, timings)
    return timings


def render_shorts(
    settings: Settings,
    plan: EpisodePlan,
    episode_dir: Path,
    timings: list[ShotTiming],
) -> None:
    final_video = episode_dir / "final.mp4"
    shorts_dir = episode_dir / "shorts"
    shorts_dir.mkdir(exist_ok=True)
    by_id = {timing.shot_id: timing for timing in timings}
    for index, cut in enumerate(plan.shorts, start=1):
        start = by_id[cut.start_shot].start
        end = by_id[cut.end_shot].end
        duration = min(end - start, 59.0)
        destination = shorts_dir / f"short-{index:02d}.mp4"
        crop_filter = (
            "scale=1920:1080:force_original_aspect_ratio=increase,"
            "crop=608:1080:(in_w-608)/2:0,scale=1080:1920"
        )
        _run(
            [
                "ffmpeg",
                "-y",
                "-ss",
                f"{start:.3f}",
                "-i",
                str(final_video),
                "-t",
                f"{duration:.3f}",
                "-vf",
                crop_filter,
                "-c:v",
                "libx264",
                "-crf",
                "20",
                "-c:a",
                "aac",
                str(destination),
            ]
        )

