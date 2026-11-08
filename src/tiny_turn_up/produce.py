from __future__ import annotations

import shutil
from pathlib import Path

from PIL import Image

from ringside.render import _run, probe_duration, require_ffmpeg

from .episode import EPISODES_DIR, Episode, full_prompt, load_episode, scene_timings

WIDTH, HEIGHT, FPS = 1920, 1080, 30
VIDEO_EXTS = {".mp4", ".mov"}


# ---------- images (OpenAI) ----------

def generate_images(episode: Episode, force: bool = False) -> list[Path]:
    """Create any missing scene images and the thumbnail. Files you drop in yourself are kept."""
    from ringside.studio import _image_result_bytes, _openai_client, _openai_retry

    client = _openai_client()
    import os

    model = os.getenv("TTU_IMAGE_MODEL", os.getenv("RINGSIDE_IMAGE_MODEL", "gpt-image-2"))
    made: list[Path] = []

    def make(prompt: str, destination: Path) -> None:
        result = _openai_retry(
            f"image {destination.name}",
            lambda: client.images.generate(
                model=model, prompt=prompt, size="1536x1024", quality="high", output_format="png"
            ),
        )
        destination.write_bytes(_image_result_bytes(result))
        made.append(destination)
        print(f"  made {destination.name}")

    for index, scene in enumerate(episode.scenes, start=1):
        target = episode.scene_media(index)
        if force or not target.exists():
            make(full_prompt(scene.prompt), episode.folder / f"scene_{index:02d}.png")
    if episode.thumbnail_prompt and (force or not episode.thumbnail_source.exists()):
        make(
            f"{full_prompt(episode.thumbnail_prompt)}".replace(
                "No text, no logos, no watermarks.",
                "Render the requested title text exactly, spelled correctly, huge and readable on a phone.",
            ),
            episode.folder / "thumbnail.png",
        )
    return made


# ---------- render ----------

def _scene_clip(source: Path, destination: Path, length: float, index: int) -> None:
    frames = max(round(length * FPS), 1)
    fit = f"scale={WIDTH}:{HEIGHT}:force_original_aspect_ratio=increase,crop={WIDTH}:{HEIGHT}"
    if source.suffix.lower() in VIDEO_EXTS:
        inputs = ["-stream_loop", "-1", "-i", str(source)]
        vf = f"{fit},fps={FPS},format=yuv420p"
    else:
        # Gentle alternating zoom in/out so still images feel alive.
        zoom = "min(zoom+0.0007,1.10)" if index % 2 else "if(eq(on,1),1.10,max(1.0,zoom-0.0007))"
        inputs = ["-loop", "1", "-i", str(source)]
        vf = (
            f"scale={WIDTH * 2}:{HEIGHT * 2}:force_original_aspect_ratio=increase,"
            f"crop={WIDTH * 2}:{HEIGHT * 2},"
            f"zoompan=z='{zoom}':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d={frames}"
            f":s={WIDTH}x{HEIGHT}:fps={FPS},format=yuv420p"
        )
    _run(
        ["ffmpeg", "-y", *inputs, "-vf", vf, "-frames:v", str(frames), "-an",
         "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-r", str(FPS), str(destination)]
    )


def render_long(episode: Episode) -> Path:
    require_ffmpeg()
    if not episode.song.exists():
        raise RuntimeError(
            f"No song yet. Export it from Suno and save it as {episode.folder / 'song.mp3'}"
        )
    missing = [episode.scene_media(i).name for i in range(1, len(episode.scenes) + 1)
               if not episode.scene_media(i).exists()]
    if missing:
        raise RuntimeError(f"Missing scene files: {', '.join(missing)}. Run the 'images' step first.")
    duration = probe_duration(episode.song)
    build = episode.build
    build.mkdir(exist_ok=True)
    clips: list[Path] = []
    for index, (_, length) in enumerate(scene_timings(episode.scenes, duration), start=1):
        clip = build / f"clip_{index:02d}.mp4"
        _scene_clip(episode.scene_media(index), clip, length, index)
        clips.append(clip)
    concat_list = build / "clips.txt"
    concat_list.write_text("".join(f"file '{c.name}'\n" for c in clips), encoding="utf-8")
    final = build / "long.mp4"
    _run(
        ["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", str(concat_list), "-i", str(episode.song),
         "-map", "0:v", "-map", "1:a", "-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
         "-t", f"{duration:.3f}", "-movflags", "+faststart", str(final)]
    )
    print(f"  long video -> {final}")
    return final


def render_shorts(episode: Episode) -> list[Path]:
    long_video = episode.build / "long.mp4"
    if not long_video.exists():
        raise RuntimeError("Render the long video first.")
    duration = probe_duration(long_video)
    outputs: list[Path] = []
    # Full 16:9 picture stays visible; a blurred copy fills the 9:16 frame.
    vertical = (
        "[0:v]split=2[bg][fg];"
        "[bg]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,gblur=sigma=30[b];"
        "[fg]scale=1080:-2[f];"
        "[b][f]overlay=(W-w)/2:(H-h)/2-120,format=yuv420p[v]"
    )
    for index, cut in enumerate(episode.shorts, start=1):
        start = min(max(cut.start, 0.0), max(duration - 5, 0.0))
        length = min(cut.length, 59.0, duration - start)
        out = episode.build / f"short_{index:02d}.mp4"
        _run(
            ["ffmpeg", "-y", "-ss", f"{start:.3f}", "-i", str(long_video), "-t", f"{length:.3f}",
             "-filter_complex", vertical, "-map", "[v]", "-map", "0:a",
             "-af", f"afade=t=out:st={max(length - 1.0, 0):.3f}:d=1",
             "-c:v", "libx264", "-crf", "20", "-c:a", "aac", "-movflags", "+faststart", str(out)]
        )
        outputs.append(out)
        print(f"  short -> {out}")
    return outputs


def render_thumbnail(episode: Episode) -> Path | None:
    source = episode.thumbnail_source
    if not source.exists():
        print("  no thumbnail image yet (skipped)")
        return None
    image = Image.open(source).convert("RGB")
    ratio = 16 / 9
    if image.width / image.height > ratio:
        w = round(image.height * ratio)
        image = image.crop(((image.width - w) // 2, 0, (image.width - w) // 2 + w, image.height))
    else:
        h = round(image.width / ratio)
        image = image.crop((0, (image.height - h) // 2, image.width, (image.height - h) // 2 + h))
    out = episode.build / "thumbnail.jpg"
    episode.build.mkdir(exist_ok=True)
    image.resize((1280, 720), Image.Resampling.LANCZOS).save(out, quality=92)
    print(f"  thumbnail -> {out}")
    return out


def render_compilation(episode: Episode, episodes_dir: Path = EPISODES_DIR) -> Path:
    require_ffmpeg()
    parts: list[Path] = []
    for item in episode.compile_from:
        path = episodes_dir / item / "build" / "long.mp4"
        if not path.exists():
            path = (episodes_dir / item).resolve()
        if not path.exists() or path.is_dir():
            raise RuntimeError(f"Compilation part not rendered yet: {item}")
        parts.append(path)
    build = episode.build
    build.mkdir(exist_ok=True)
    inputs: list[str] = []
    for part in parts:
        inputs += ["-i", str(part)]
    norm = "".join(
        f"[{i}:v]scale={WIDTH}:{HEIGHT}:force_original_aspect_ratio=decrease,"
        f"pad={WIDTH}:{HEIGHT}:(ow-iw)/2:(oh-ih)/2,fps={FPS},setsar=1,format=yuv420p[v{i}];"
        f"[{i}:a]aresample=48000,aformat=channel_layouts=stereo[a{i}];"
        for i in range(len(parts))
    )
    joined = "".join(f"[v{i}][a{i}]" for i in range(len(parts)))
    out = build / "long.mp4"
    _run(
        ["ffmpeg", "-y", *inputs, "-filter_complex", f"{norm}{joined}concat=n={len(parts)}:v=1:a=1[v][a]",
         "-map", "[v]", "-map", "[a]", "-c:v", "libx264", "-crf", "20", "-preset", "medium",
         "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", str(out)]
    )
    print(f"  compilation -> {out}")
    return out


def produce(slug: str, images: bool = True) -> Episode:
    episode = load_episode(slug)
    print(f"== {episode.title}")
    if episode.compile_from:
        render_compilation(episode)
    else:
        if images:
            generate_images(episode)
        render_long(episode)
    render_shorts(episode)
    render_thumbnail(episode)
    return episode


def clean(slug: str) -> None:
    shutil.rmtree(load_episode(slug).build, ignore_errors=True)
