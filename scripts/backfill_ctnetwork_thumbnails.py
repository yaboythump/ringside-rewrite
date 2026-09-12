from __future__ import annotations

import io
import json
import os
import re
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

import requests
from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageFont, ImageOps, ImageStat

API = "https://api.upload-post.com/api"
OUT = Path("thumbnail-backfill-report")
OUT.mkdir(parents=True, exist_ok=True)


@dataclass(frozen=True)
class Show:
    profile: str
    name: str
    cutoff: str
    accent: tuple[int, int, int]
    accent2: tuple[int, int, int]


SHOWS = [
    Show("YouTube", "JOHNNY FACTS", "2026-08-28T00:00:00Z", (247, 197, 45), (42, 103, 188)),
    Show("HipHopWhatIf", "HIP HOP WHAT IF", "2026-08-28T00:00:00Z", (212, 175, 55), (166, 26, 36)),
    Show("Tcwt", "TRUE CRIME WITH THUMP", "2026-09-01T00:00:00Z", (217, 40, 46), (235, 235, 235)),
    Show("GTA", "THE SIX REPORT", "2026-09-02T00:00:00Z", (130, 255, 120), (178, 80, 255)),
    Show("Breakingconversations", "BIGGER CONVERSATIONS", "2026-09-07T00:00:00Z", (221, 180, 68), (238, 238, 238)),
    Show("Ringsiderewrite", "RINGSIDE REWRITE", "2026-09-01T00:00:00Z", (221, 35, 35), (245, 245, 245)),
    Show("Whathappen", "WHATEVER HAPPENED TO...?", "2026-09-09T00:00:00Z", (229, 157, 55), (238, 238, 238)),
    Show("Case", "THE CASE AGAINST...", "2026-09-10T00:00:00Z", (212, 175, 55), (170, 31, 42)),
]

FONT_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf"
FONT_REG = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"


def dt(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def auth_headers() -> dict[str, str]:
    key = os.environ.get("UPLOAD_POST_API_KEY", "").strip()
    if not key:
        raise RuntimeError("UPLOAD_POST_API_KEY is missing")
    return {"Authorization": f"Apikey {key}"}


def api_json(method: str, path: str, *, params=None, data=None, files=None, timeout=120) -> dict:
    response = requests.request(
        method,
        API + path,
        headers=auth_headers(),
        params=params,
        data=data,
        files=files,
        timeout=timeout,
    )
    if response.status_code >= 400:
        raise RuntimeError(f"{method} {path} HTTP {response.status_code}: {response.text[:800]}")
    payload = response.json()
    if payload.get("success") is False:
        raise RuntimeError(f"{method} {path} rejected: {payload}")
    return payload


def list_media(profile: str) -> list[dict]:
    items: list[dict] = []
    cursor = None
    seen = set()
    for _ in range(20):
        params = {"platform": "youtube", "user": profile, "limit": 100}
        if cursor:
            params["cursor"] = cursor
        payload = api_json("GET", "/uploadposts/media", params=params, timeout=90)
        batch = payload.get("media", [])
        for item in batch:
            vid = item.get("id")
            if vid and vid not in seen:
                seen.add(vid)
                items.append(item)
        page = payload.get("pagination", {})
        if not page.get("has_more"):
            break
        cursor = page.get("next_cursor")
        if not cursor:
            break
    return items


def fetch_image(url: str) -> Image.Image:
    response = requests.get(url, timeout=30, headers={"User-Agent": "Mozilla/5.0"})
    response.raise_for_status()
    return Image.open(io.BytesIO(response.content)).convert("RGB")


def youtube_image(video_id: str, name: str) -> Image.Image:
    return fetch_image(f"https://i.ytimg.com/vi/{video_id}/{name}.jpg?ctn={time.time_ns()}")


def mae(a: Image.Image, b: Image.Image) -> float:
    b = b.resize(a.size, Image.Resampling.LANCZOS)
    stat = ImageStat.Stat(ImageChops.difference(a.convert("RGB"), b.convert("RGB")))
    return sum(stat.mean) / 3.0


def ahash(image: Image.Image) -> tuple[int, ...]:
    gray = image.convert("L").resize((16, 16), Image.Resampling.LANCZOS)
    px = list(gray.getdata())
    avg = sum(px) / len(px)
    return tuple(1 if p >= avg else 0 for p in px)


def hamming(a: Iterable[int], b: Iterable[int]) -> int:
    return sum(x != y for x, y in zip(a, b))


def looks_auto_generated(video_id: str) -> tuple[bool, dict]:
    hq = youtube_image(video_id, "hqdefault")
    h = ahash(hq)
    scores = []
    for candidate in ("1", "2", "3"):
        try:
            frame = youtube_image(video_id, candidate)
            scores.append(
                {
                    "candidate": candidate,
                    "mae": round(mae(hq, frame), 2),
                    "hash_distance": hamming(h, ahash(frame)),
                }
            )
        except Exception as exc:
            scores.append({"candidate": candidate, "error": str(exc)})
    usable = [x for x in scores if "mae" in x]
    if not usable:
        raise RuntimeError("No YouTube auto-frame candidates were readable")
    best = min(usable, key=lambda x: (x["hash_distance"], x["mae"]))
    # Calibrated against known CTNETWORK gate-passed custom thumbnails and known raw-auto examples.
    is_auto = best["hash_distance"] <= 12 and best["mae"] <= 25.0
    return is_auto, {"best": best, "all": scores}


def clean_title(caption: str) -> str:
    text = re.sub(r"#Shorts\b", "", caption, flags=re.I).strip(" |—-")
    for suffix in (
        " | Hip Hop What If",
        " | Ringside Rewrite",
        " | True Crime With Thump",
        " | The Six Report",
        " | Bigger Conversations",
        " | Johnny Facts Full Episode",
    ):
        if text.endswith(suffix):
            text = text[: -len(suffix)]
    text = re.sub(r"\s+", " ", text).strip()
    return text[:120]


def wrap(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont, max_width: int, max_lines: int = 3) -> list[str]:
    words = text.split()
    lines: list[str] = []
    cur = ""
    for word in words:
        trial = (cur + " " + word).strip()
        if draw.textbbox((0, 0), trial, font=font, stroke_width=2)[2] <= max_width:
            cur = trial
        else:
            if cur:
                lines.append(cur)
            cur = word
            if len(lines) == max_lines - 1:
                break
    if cur and len(lines) < max_lines:
        lines.append(cur)
    consumed = " ".join(lines)
    if consumed != text and lines:
        while draw.textbbox((0, 0), lines[-1] + "…", font=font, stroke_width=2)[2] > max_width and len(lines[-1]) > 5:
            lines[-1] = lines[-1][:-1]
        lines[-1] = lines[-1].rstrip(" ,.-") + "…"
    return lines


def cover_frame(source: Image.Image, size=(1280, 720)) -> Image.Image:
    img = ImageOps.fit(source.convert("RGB"), size, method=Image.Resampling.LANCZOS, centering=(0.5, 0.45))
    img = ImageEnhance.Contrast(img).enhance(1.08)
    img = ImageEnhance.Color(img).enhance(0.92)
    return img


def make_thumbnail(show: Show, video_id: str, caption: str) -> Path:
    try:
        source = youtube_image(video_id, "maxresdefault")
    except Exception:
        source = youtube_image(video_id, "hqdefault")
    base = cover_frame(source).convert("RGBA")
    blurred = base.filter(ImageFilter.GaussianBlur(radius=2.2))
    base = Image.blend(base, blurred, 0.14)

    overlay = Image.new("RGBA", base.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    # cinematic left-to-right darkening plus bottom readability shelf
    for x in range(0, 900, 6):
        alpha = int(205 * (1 - x / 1000)) + 20
        d.rectangle((x, 0, x + 6, 720), fill=(0, 0, 0, max(20, min(alpha, 215))))
    d.rectangle((0, 525, 1280, 720), fill=(0, 0, 0, 145))
    d.rectangle((0, 0, 1280, 16), fill=show.accent + (255,))
    d.rectangle((0, 704, 1280, 720), fill=show.accent2 + (230,))

    show_font = ImageFont.truetype(FONT_BOLD, 43)
    ctn_font = ImageFont.truetype(FONT_BOLD, 28)
    title_font = ImageFont.truetype(FONT_BOLD, 70)
    small_font = ImageFont.truetype(FONT_REG, 25)

    d.rounded_rectangle((48, 42, 520, 112), radius=12, fill=(0, 0, 0, 185), outline=show.accent + (245,), width=3)
    d.text((70, 55), show.name, font=show_font, fill=show.accent + (255,), stroke_width=2, stroke_fill=(0, 0, 0, 255))
    d.text((1030, 55), "CTNETWORK", font=ctn_font, fill=(245, 245, 245, 255), stroke_width=2, stroke_fill=(0, 0, 0, 255))

    title = clean_title(caption)
    lines = wrap(d, title.upper(), title_font, 865, 3)
    y = 250
    for i, line in enumerate(lines):
        fill = (248, 248, 248, 255) if i == 0 else show.accent + (255,)
        d.text((62, y), line, font=title_font, fill=fill, stroke_width=5, stroke_fill=(0, 0, 0, 245))
        y += 82

    kind = "SHORT" if "#shorts" in caption.casefold() else "FULL EPISODE"
    d.rounded_rectangle((60, 620, 310, 671), radius=9, fill=show.accent2 + (230,))
    d.text((78, 629), kind, font=small_font, fill=(255, 255, 255, 255), stroke_width=1, stroke_fill=(0, 0, 0, 170))

    finished = Image.alpha_composite(base, overlay).convert("RGB")
    dest = OUT / f"{show.profile}_{video_id}.jpg"
    finished.save(dest, quality=92, optimize=True)
    # stay under YouTube/Upload-Post's 2 MB API limit
    if dest.stat().st_size > 1_900_000:
        finished.save(dest, quality=84, optimize=True)
    return dest


def set_thumbnail(show: Show, video_id: str, thumbnail: Path) -> dict:
    with thumbnail.open("rb") as fh:
        payload = api_json(
            "POST",
            "/uploadposts/youtube/thumbnail",
            data={"user": show.profile, "video_id": video_id},
            files={"thumbnail": (thumbnail.name, fh, "image/jpeg")},
            timeout=180,
        )
    if payload.get("video_id") != video_id:
        raise RuntimeError(f"thumbnail endpoint returned wrong video id: {payload}")
    return payload


def youtube_geometry(source: Image.Image, target_size: tuple[int, int]) -> Image.Image:
    contained = ImageOps.contain(source.convert("RGB"), target_size, method=Image.Resampling.LANCZOS)
    canvas = Image.new("RGB", target_size, (0, 0, 0))
    canvas.paste(contained, ((target_size[0] - contained.width) // 2, (target_size[1] - contained.height) // 2))
    return canvas


def verify(video_id: str, thumbnail: Path, attempts: int = 8, delay: int = 10) -> dict:
    expected = Image.open(thumbnail).convert("RGB")
    variants = ("mqdefault", "hqdefault", "sddefault", "maxresdefault")
    last = {}
    for attempt in range(1, attempts + 1):
        good = True
        last = {}
        for variant in variants:
            try:
                actual = youtube_image(video_id, variant)
                normalized = youtube_geometry(expected, actual.size)
                score = mae(actual, normalized)
                last[variant] = round(score, 2)
                if score > 20.0:
                    good = False
            except Exception as exc:
                last[variant] = f"unavailable:{exc}"
                # mq/hq are required; sd/maxres may legitimately be unavailable on older/low-res uploads.
                if variant in ("mqdefault", "hqdefault"):
                    good = False
        print(f"VERIFY video={video_id} attempt={attempt} {last}", flush=True)
        if good:
            return last
        time.sleep(delay)
    raise RuntimeError(f"visible thumbnail verification failed: {last}")


def main() -> None:
    report: list[dict] = []
    for show in SHOWS:
        cutoff = dt(show.cutoff)
        print(f"\n===== {show.name} / {show.profile} =====", flush=True)
        try:
            media = list_media(show.profile)
        except Exception as exc:
            report.append({"profile": show.profile, "show": show.name, "status": "profile_error", "error": str(exc)})
            print(f"PROFILE_ERROR {show.profile}: {exc}", flush=True)
            continue
        scoped = []
        for item in media:
            stamp = item.get("timestamp")
            if not stamp or dt(stamp) < cutoff:
                continue
            if not item.get("id") or not item.get("thumbnail_url") or item.get("caption") == "Deleted video":
                continue
            scoped.append(item)
        print(f"CATALOG items_since_cutoff={len(scoped)}", flush=True)

        for item in scoped:
            video_id = item["id"]
            caption = item.get("caption", "")
            row = {"profile": show.profile, "show": show.name, "video_id": video_id, "title": caption}
            try:
                auto, signature = looks_auto_generated(video_id)
                row["signature"] = signature
                if not auto:
                    row["status"] = "existing_custom_preserved"
                    print(f"KEEP {video_id} {caption}", flush=True)
                    report.append(row)
                    continue
                print(f"BACKFILL {video_id} {caption} signature={signature['best']}", flush=True)
                thumbnail = make_thumbnail(show, video_id, caption)
                response = set_thumbnail(show, video_id, thumbnail)
                row["set_response"] = {k: response.get(k) for k in ("success", "video_id", "width", "height")}
                row["verification"] = verify(video_id, thumbnail)
                row["status"] = "custom_thumbnail_added_and_verified"
                print(f"THUMBNAIL_GATE_PASS video_id={video_id} profile={show.profile}", flush=True)
            except Exception as exc:
                row["status"] = "error"
                row["error"] = str(exc)
                print(f"ERROR {video_id} {caption}: {exc}", flush=True)
            report.append(row)

    path = OUT / "report.json"
    path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    counts: dict[str, int] = {}
    for row in report:
        counts[row["status"]] = counts.get(row["status"], 0) + 1
    print("\n===== CTNETWORK THUMBNAIL BACKFILL SUMMARY =====")
    print(json.dumps(counts, indent=2))
    print(f"REPORT={path}")
    # Fail only if a profile itself could not be audited. Individual thumbnail failures remain in report
    # so one YouTube rate-limit does not prevent the rest of the network from being checked.
    if counts.get("profile_error"):
        raise SystemExit(2)


if __name__ == "__main__":
    main()
