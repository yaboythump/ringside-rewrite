#!/usr/bin/env python3
from pathlib import Path

from ringside.config import load_settings
from ringside.pipeline import scheduled_run


if __name__ == "__main__":
    print(scheduled_run(load_settings(Path.cwd())))

