# CTNETWORK Engineering Project 003: Premium Cinematic Production Engine

Date: 2026-11-05 · Server: `ubuntu` (IONOS, 8 vCPU, no GPU) · Builds on the Project 002 dev engine (`ctnetwork/episode_engine`) without replacing it.

**SAME SHOW. SAME FORMULA. SAME QUALITY. LESS WASTED SPEND.** Generation credits spent: **0**. Nothing published. No production file, job, service or approval gate was changed. Dev work lives only in `/srv/ctnetwork-dev/project003`, plus one private review folder.

---

## 1. Why imagery repeats (root cause, measured)

| Where | What happens | Evidence |
|---|---|---|
| **Approved Raven edit** (`render_episode.py`, published 2026-11-04) | The hand-written `maps` table spreads 16 images over 61 slots as A‑B‑A‑C per segment. The same still returns after 1–2 shots. The concat demuxer then holds each one frozen. | `work/edit/timeline.json`: 61 slots, 16 unique, `scene_07` ×7, `scene_01/02/05` ×6, reuse gaps `[1, 1, 2, 2, 2, …]` |
| **Project 002 engine** | Adds Ken Burns motion and dissolves but **reuses the approved edit as-is**, so every repeat survives. The motion vocabulary is a fixed 4-move cycle and every boundary is the same 0.6 s fade. | `adapters.rewrite_episode()` copies `timeline.json` verbatim; `MOVES[i % 4]` |
| **Storyboard supply** | Each segment of about 37 s gets 2–3 stills. Without reframing, 9–10 min of narration over 15 stills *must* repeat whole frames. | `production_plan_v2.json`: 15 scenes for 567 s |
| **Hip Hop Rewind E001** | Footage edit reuses source ranges (e.g. `freestyle` 38.5–49.5 s and again 38.65–41.12 s) and photo plates (#1 ×5, #4 ×6). | `episode_edit.json`, flagged by `visual_qc.ledger_reuse` |
| **QC blind spot** | Existing QC (decode, blackdetect, ebur128, transcript, freezedetect) never looks at *what* is on screen, so repetition and slideshow pacing ship unflagged. | `quality/`, job `media_qc.json` |

## 2. What I built (dev, reversible)

All of this is in `ctnetwork/episode_engine/` on branch `claude/cinematic-production-engine-pj9ghg`, installed on the server at `/srv/ctnetwork-dev/project003/src/…`. Project 002's install at `/srv/ctnetwork-dev/episode_engine` is untouched.

| Module | What it does |
|---|---|
| `coverage.py` (new) | **Virtual-coverage shot planner.** It finds points of interest in each approved still (spectral-residual saliency plus local contrast plus a centre prior) and derives distinct **wide / medium / close / alternate-close** framings, never cropping below a source-pixel quality floor (1040 px for Ringside Rewrite). Each segment uses **only the stills the approved edit gave it**. It **cuts on the narrator's natural pauses**, detected from the narration audio with no API calls, and picks the hold lengths by dynamic programming (Rewrite: 4–9.5 s, target 6.5 s). It never shows the same still back-to-back. An identical framing may return only after 90 s, at most 3 times, and always with a different move. Shared stills are split fairly across upcoming segments (lookahead), so no segment starves. When the storyboard is too thin, the planner emits an **asset request** ("segment 7 needs 1 more still") instead of padding with repeats. |
| `render.py` (extended) | **Rect-to-rect camera moves**: push into the subject, lateral drift, tilt reveal, settle and pull-out, eased, with speed capped in px/s and a light unsharp only on punch-ins. **Per-cut transitions**: frame-exact hard cuts (concat), dissolves, and dip-to-black at act breaks. Narration sync stays exact. The Project 002 behaviour is unchanged when a timeline has no planner fields. |
| `visual_qc.py` (new) | **Automated visual QC**, read-only. **Repetition**: perceptual hash plus alignment-tolerant correlation, so a Ken Burns move on the same still is "the same picture" while different title cards on a shared background are not; it reports every repeat, its gap and its appearance count. **Static sequences**: frozen-picture runs. **Pacing**: holds longer than the show allows. **Missing media**: black or flat frames and unfitted pillarbox. **Preflight**: missing, undecodable, under-resolution and duplicate stills, plus missing or silent narration, music, SFX and intro, checked *before* any render time is spent. **Archive ledger**: reused footage ranges. It also writes a **contact sheet** with repeats outlined in red. |
| `adapters.py`, `run_job.py` | `--planner coverage`, `--excerpt 60-90` (proof-of-concept renders), `--plan-only` (full-episode plan and report in seconds, no render), `--compare` (QC an existing master over the same window). Every run writes `delivery_report.json` with `publishing_authorized: false`. |
| `formulas/ringside_rewrite.json` | Adds `coverage`, `visual_qc` and `visual_qc_shorts` blocks. Narrator, music, SFX, watermark, outro and Shorts are unchanged. |
| `formulas/hhwi.json`, `formulas/hip_hop_rewind.json` (drafts) | Same engine and QC for the other two shows. HHWI is limited to gentle wide/medium reframes (its profile says *preserve approved storyboard framing*) and keeps its locked intro prepended with its baked audio. Hip Hop Rewind is footage-first: QC plus ledger checks now, with photo-plate coverage available. |
| `project003/` | Server runbook, summary and private review staging script. |

Tests: **24/24 pass** locally (ffmpeg 6.1), 14 of them new. Server results: see §4.

RESULTS_PLACEHOLDER
