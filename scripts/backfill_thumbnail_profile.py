from __future__ import annotations

import os

import backfill_ctnetwork_thumbnails as backfill

profile = os.environ.get("ONLY_PROFILE", "").strip()
if not profile:
    raise SystemExit("ONLY_PROFILE is required")

selected = [show for show in backfill.SHOWS if show.profile == profile]
if not selected:
    raise SystemExit(f"Unknown CTNETWORK Upload-Post profile: {profile}")

backfill.SHOWS = selected
backfill.main()
