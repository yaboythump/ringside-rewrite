#!/usr/bin/env python3
"""CTNETWORK Higgsfield/Kling image-to-video helper.

Uses the official Higgsfield Python SDK. Credentials are read only from
server-side environment variables and are never written to project files.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from urllib.parse import urlparse

import requests
import higgsfield_client

PRO_MODEL = "kling-video/v2.5-turbo/pro/image-to-video"
STANDARD_MODEL = "kling-video/v2.5-turbo/std/image-to-video"
DEFAULT_MODEL = STANDARD_MODEL


def normalize_credential_env() -> None:
    """Normalize common RunPod key-name casing without printing secret values."""
    if not os.environ.get("HF_KEY"):
        for alias in ("Hf_key", "hf_key", "HF_Key"):
            value = os.environ.get(alias)
            if value:
                os.environ["HF_KEY"] = value
                break


def credential_present() -> bool:
    normalize_credential_env()
    return bool(
        os.environ.get("HF_KEY")
        or (os.environ.get("HF_API_KEY") and os.environ.get("HF_API_SECRET"))
    )


def video_url_from_result(value):
    if isinstance(value, str):
        p = urlparse(value)
        if p.scheme in {"http", "https"}:
            return value
        return None
    if isinstance(value, dict):
        for key in ("video", "url", "video_url", "output_url"):
            if key in value:
                found = video_url_from_result(value[key])
                if found:
                    return found
        for child in value.values():
            found = video_url_from_result(child)
            if found:
                return found
    if isinstance(value, list):
        for child in value:
            found = video_url_from_result(child)
            if found:
                return found
    return None


def upload_or_url(image: str) -> str:
    if image.startswith("https://") or image.startswith("http://"):
        return image
    path = Path(image)
    if not path.exists() or path.stat().st_size < 512:
        raise SystemExit(f"input image missing or empty: {path}")
    return higgsfield_client.upload_file(str(path))


def render(image: str, prompt: str, duration: int, cfg_scale: float,
           negative_prompt: str, output: Path, model: str = DEFAULT_MODEL) -> Path:
    normalize_credential_env()
    if not credential_present():
        raise SystemExit(
            "Higgsfield API credential missing. Set HF_KEY=KEY_ID:KEY_SECRET "
            "or HF_API_KEY + HF_API_SECRET on the server."
        )
    image_url = upload_or_url(image)
    result = higgsfield_client.subscribe(
        model,
        arguments={
            "prompt": prompt,
            "duration": duration,
            "cfg_scale": cfg_scale,
            "image_url": image_url,
            "negative_prompt": negative_prompt,
        },
    )
    video_url = video_url_from_result(result)
    if not video_url:
        raise RuntimeError("Higgsfield completed without a downloadable video URL")

    output.parent.mkdir(parents=True, exist_ok=True)
    with requests.get(video_url, stream=True, timeout=180) as response:
        response.raise_for_status()
        with output.open("wb") as f:
            for chunk in response.iter_content(1024 * 1024):
                if chunk:
                    f.write(chunk)
    if output.stat().st_size < 4096:
        raise RuntimeError(f"downloaded video is unexpectedly small: {output}")
    print(json.dumps({
        "status": "completed",
        "engine": "higgsfield",
        "model": model,
        "duration": duration,
        "output": str(output),
        "source_url": video_url,
        "bytes": output.stat().st_size,
    }))
    return output


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--image")
    ap.add_argument("--prompt")
    ap.add_argument("--duration", type=int, choices=(5, 10), default=5)
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--cfg-scale", type=float, default=0.5)
    ap.add_argument("--negative-prompt", default="")
    ap.add_argument("--output", type=Path)
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()

    if args.self_test:
        print(json.dumps({
            "status": "ready",
            "model": DEFAULT_MODEL,
            "credential_present": credential_present(),
            "billable_generation_submitted": False,
        }))
        return

    if not args.image or not args.prompt or not args.output:
        ap.error("--image, --prompt and --output are required unless --self-test is used")
    if not 0 <= args.cfg_scale <= 1:
        ap.error("--cfg-scale must be between 0 and 1")
    render(
        args.image, args.prompt, args.duration, args.cfg_scale,
        args.negative_prompt, args.output, args.model
    )


if __name__ == "__main__":
    main()
