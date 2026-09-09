# Whatever Happened To…? — zero-touch production lane

Permanent operating rule: **Thump touches nothing.**

The final episode must never exist only as a ChatGPT `/mnt/data` render that requires a manual Upload-Post staging window. ChatGPT can research, write, and prepare production instructions, but the final production bundle must be committed into this repository so GitHub Actions performs the final render, QC, publishing, and thumbnail verification.

## Locked production handoff

Before the daily episode is considered ready, automation must write these files in `whatever_happened_to/current/`:

- `build.py` — self-contained episode builder. It must create the final full episode, custom thumbnail, and exactly six Shorts in `current/output/`.
- `job.json` — publishing manifest. **Write/update this file LAST** because changing it triggers `.github/workflows/whatever-happened-zero-touch.yml`.

The build runs on GitHub with ffmpeg, Pillow, NumPy, SciPy, SoundFile, and Kokoro ONNX available. Marcus is locked to `am_fenrir` at speed `0.94`. The shared Kokoro model and voice bank are downloaded automatically.

## Required `job.json` shape

```json
{
  "slug": "myspace",
  "profile": "Whathappen",
  "full": {
    "path": "output/full.mp4",
    "thumbnail": "output/thumbnail.jpg",
    "title": "Whatever Happened To MySpace?",
    "description": "..."
  },
  "shorts": [
    {
      "path": "output/short_01.mp4",
      "title": "...",
      "description": "...",
      "scheduled_date": "2026-09-10T13:00:00-04:00"
    }
  ]
}
```

There must be exactly six Short entries. Every Short must either have a `scheduled_date` or explicitly set `publish_now: true`; the publisher must never silently dump six Shorts at once.

## Hard gates

The workflow fails instead of publishing when any of these are wrong:

- missing `build.py` or `job.json`
- wrong Upload-Post profile (must be `Whathappen`)
- fewer/more than six Shorts
- missing/invalid media
- full episode shorter than four minutes
- Short outside the YouTube Shorts duration range
- decode failure in ffmpeg
- missing custom thumbnail
- Upload-Post failure
- unresolved YouTube video ID
- custom thumbnail patch failure
- visible YouTube thumbnail derivatives do not match the intended custom thumbnail

## Visual standard

The approved flashy MySpace pilot is the baseline: authentic era-specific/archive/official/owned/licensed material first, browser/UI motion, fast cuts, kinetic text, punch-ins, section bumpers, hard stat/money moments, subject-specific music and sound design, no burned captions, and no generic AI-explainer slideshow look.

## End-to-end flow

`topic/research → script → Marcus → episode-specific music → flashy visuals → final render → 6 Shorts → QC → Upload-Post Whathappen → YouTube public → shared thumbnail patch → visible verification`

No manual file picker. No Upload Studio handoff. No user-side staging step.
