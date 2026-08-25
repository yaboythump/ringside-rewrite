#!/usr/bin/env python3
import os
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from ringside.config import load_settings
from ringside.pipeline import scheduled_run


def scheduled_day_is_enabled(settings) -> bool:
    if os.getenv("GITHUB_EVENT_NAME", "").casefold() != "schedule":
        return True
    timezone_name = settings.channel.get("channel", {}).get(
        "timezone", "America/New_York"
    )
    today = datetime.now(ZoneInfo(timezone_name)).strftime("%a").casefold()
    enabled = {
        str(day).strip().casefold()[:3]
        for day in settings.channel.get("schedule", {}).get("long_form_days", [])
    }
    return today in enabled


if __name__ == "__main__":
    settings = load_settings(Path.cwd())
    if scheduled_day_is_enabled(settings):
        print(scheduled_run(settings))
    else:
        print("Skipped: today is not one of the configured two production days.")
