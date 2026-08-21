# Ringside Rewrite

**Wrestling History. Booked Differently.**

Ringside Rewrite is an automated YouTube production kit for sourced wrestling “What If?” fantasy booking. Each episode researches the real-world starting point first, clearly announces where the fictional timeline begins, then generates a cinematic long-form episode, Shorts cutdowns, metadata, captions, thumbnails, and YouTube upload drafts.

The pilot is **What If Sting Led the WCW Invasion?**

## What this kit includes

- Ringside Rewrite avatar and banner assets
- Pilot episode package with sourced baseline and 24-shot script
- Automated research-first fantasy-booking pipeline
- Scene image generation and narrated audio generation
- FFmpeg video render with captions, thumbnail, and Shorts
- YouTube private upload support
- Wrong-channel safety check for **RINGSIDE REWRITE**
- GitHub Actions preflight and scheduled production workflows

## Quick local setup

1. Create a Python 3.11+ environment.
2. Install FFmpeg.
3. Install the project:

   ```bash
   pip install -e .
   ```

4. Copy `.env.example` to `.env` and fill in your keys.
5. Run the system check:

   ```bash
   ringside doctor
   ```

6. Run the pilot quality check:

   ```bash
   ringside dry-run --episode content/pilot/episode.json
   ```

7. Produce the pilot:

   ```bash
   ringside produce --episode content/pilot/episode.json
   ```

8. Upload privately after YouTube is authorized:

   ```bash
   ringside publish --episode-dir output/sting-leads-the-invasion --privacy private
   ```

## Cloud/iPhone path

If you are setting this up from an iPhone, use `IPHONE_CLOUD_SETUP.md`. The GitHub workflow can run the pilot and scheduled episodes without keeping a computer on.

## Core command map

```bash
ringside doctor
ringside youtube-auth
ringside dry-run --episode content/pilot/episode.json
ringside produce --episode content/pilot/episode.json
ringside generate --theme "What if The Rock never left for Hollywood?"
ringside scheduler
```

## Safety rules baked in

- Every new episode must have source notes and a factual baseline.
- The description must identify the video as a what-if/hypothetical rewrite.
- Direct invented dialogue from real wrestlers is blocked.
- Recent primary subjects are cooled down to avoid repetitive uploads.
- Uploads are checked against the configured YouTube channel title before publishing.
- Public or unlisted uploads require approval unless automation is deliberately enabled.

## Important disclaimer

Ringside Rewrite is an unofficial fan-made fantasy-booking channel. It is not affiliated with WWE, AEW, TNA, NJPW, or any wrestling promotion.
