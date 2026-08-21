from __future__ import annotations

import os
import tomllib
from dataclasses import dataclass
from pathlib import Path
from typing import Any


def _load_dotenv(path: Path) -> None:
    try:
        from dotenv import load_dotenv
    except ImportError:
        return
    load_dotenv(path)


def load_toml(path: Path) -> dict[str, Any]:
    with path.open("rb") as handle:
        return tomllib.load(handle)


@dataclass(frozen=True)
class Settings:
    root: Path
    channel: dict[str, Any]
    research: dict[str, Any]
    text_model: str
    image_model: str
    tts_model: str
    tts_voice: str
    auto_publish: bool
    youtube_client_secret: Path
    youtube_token: Path
    youtube_client_id: str
    youtube_client_secret_value: str
    youtube_refresh_token: str
    youtube_expected_channel_id: str

    @property
    def output_dir(self) -> Path:
        return self.root / "output"

    @property
    def openai_api_key_present(self) -> bool:
        return bool(os.getenv("OPENAI_API_KEY", "").strip())

    def resolve(self, value: str | Path) -> Path:
        path = Path(value)
        return path if path.is_absolute() else self.root / path


def load_settings(root: Path | None = None) -> Settings:
    project_root = (root or Path.cwd()).resolve()
    _load_dotenv(project_root / ".env")
    channel = load_toml(project_root / "config" / "channel.toml")
    research = load_toml(project_root / "config" / "research.toml")
    return Settings(
        root=project_root,
        channel=channel,
        research=research,
        text_model=os.getenv("RINGSIDE_TEXT_MODEL", "gpt-5.6"),
        image_model=os.getenv("RINGSIDE_IMAGE_MODEL", "gpt-image-2"),
        tts_model=os.getenv("RINGSIDE_TTS_MODEL", "gpt-4o-mini-tts"),
        tts_voice=os.getenv("RINGSIDE_TTS_VOICE", "cedar"),
        auto_publish=os.getenv("RINGSIDE_AUTO_PUBLISH", "false").casefold()
        in {"1", "true", "yes", "on"},
        youtube_client_secret=project_root
        / os.getenv("YOUTUBE_CLIENT_SECRET", "secrets/client_secret.json"),
        youtube_token=project_root
        / os.getenv("YOUTUBE_TOKEN", "secrets/youtube_token.json"),
        youtube_client_id=os.getenv("YOUTUBE_CLIENT_ID", "").strip(),
        youtube_client_secret_value=os.getenv(
            "YOUTUBE_CLIENT_SECRET_VALUE", ""
        ).strip(),
        youtube_refresh_token=os.getenv("YOUTUBE_REFRESH_TOKEN", "").strip(),
        youtube_expected_channel_id=os.getenv(
            "YOUTUBE_EXPECTED_CHANNEL_ID", ""
        ).strip(),
    )
