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

Tests: **26/26 pass** locally (ffmpeg 6.1), 16 of them new; **24/24** passed on the server (ffmpeg 8) before the final two fixes.

## 3. Proof of concept: Raven's Flock, cold open + "the real timeline" (73.1 s)

Rendered on the server from the **existing** Raven assets only: the approved stills for segments 1–2, the existing narration, the approved music bed, the bell cue and the thumbnail outro. Render time 2.8 min at idle priority. It passed preflight, delivery QC and visual QC.

- Proof of concept: `/srv/ctnetwork-dev/project003/renders/raven-poc/Ringside_Rewrite_Raven_POC_Cinematic.mp4` (1920×1080, -13.9 LUFS, -4.6 dBTP)
- Before/after side-by-side: `…/raven-poc/Raven_POC_Before_After.mp4`
- Private review page (unlisted, DEV, same mechanism as Project 002): the URL is in `/srv/ctnetwork-dev/project003/review_url.txt`. It is kept out of the repo because the link itself grants access. Rollback: delete the `dev-project003-cinematic-*` folder under `/srv/ctnetwork/review/`.

Same 73 s window, measured by the same visual QC:

| | Published 2026-11-04 | Project 002 dev | **Project 003** |
|---|---|---|---|
| Distinct visuals on screen | 4 | 8 | **11** |
| Repeats within 90 s | 5 | 4 | **0** |
| Static (frozen) picture | 73.2 s (100 %) | 0 s | **0 s** |
| Shots / transitions | 9 shots, hard holds | 15 shots, all 0.6 s fades | **11 shots: 9 pause-timed cuts, 1 dip-to-black (act break), 1 dissolve to outro** |
| Delivery QC | FAIL (static, repetition) | FAIL (repetition) | **PASS** |

## 4. Full-episode comparison (Raven, 567 s)

The plan for the full episode was built with `--plan-only` against the real job (no render). The published and Project 002 masters were measured with `visual_qc.py`.

| Metric | Published | Project 002 | **Project 003 plan** |
|---|---|---|---|
| Shots | 61 | 61 (same edit) | **82** |
| Same still back-to-back | 2 | 2 | **0** |
| Identical frame re-shown within 90 s | 37 | 37 | **0** |
| Shot length | flat ~9.3 s | flat ~9.3 s | **4–10 s on narration pauses** (one 14.1 s where segment 7 is short of stills) |
| Transitions | hard holds | 61 identical fades | **67 cuts / 14 dissolves / 1 dip-to-black** |
| Visual QC (measured) | FAIL: 35 repeats < 90 s, one visual ×7, 58 static runs, 567 s static | FAIL: 33 repeats < 90 s, one visual ×7 | full render not run (POC passes) |

The planner also files **asset requests**: segments 3, 6 and 7 would each benefit from **one more approved still** to reach the target pacing. That is 3 extra chat-made images, at no generation credits, requested *before* production instead of fixed after.

**Other shows (measured, read-only):**
- Published Raven Shorts: all 3 have 6 frozen holds of 3 s or more. Short 2 shows one image twice.
- Hip Hop Rewind E001: 11 repeats within 120 s and one visual ×7. The ledger finds **76.9 s of reused archive ranges** (e.g. `riot` 20–23 s used three times) and photo plates #1 ×5 and #4 ×5. These go to the producer as findings; the published episode was not touched.

Server test run: **24/24 passed** (ffmpeg 8). Locally after the final fixes: **26/26**.

## 5. Rule check

- Same show and formula: the same narration files at native speed, the same music bed and levels, the same bell cue, the same CTNETWORK watermark and the same thumbnail outro. Only the approved stills each segment already had are used. Shorts formula unchanged.
- Yesterday's Raven episode, its job folder and its review page were read, never written.
- Credits spent: **0**. Nothing published. No service, cron, profile or approval gate changed. `publishing_authorized: false` in every report.
- Dev isolation: code runs from `/srv/ctnetwork-dev/project003/src/<commit>/` and outputs go to `/srv/ctnetwork-dev/project003/`. Project 002's install is untouched. Rollback: `rm -rf /srv/ctnetwork-dev/project003` plus the review folder above.
- iPhone prompts: about 15 device calls in total, by batching each inventory, install-and-run and readback into one call.

## 6. Ready to deploy (each needs Thump's approval)

| # | Change | Risk |
|---|---|---|
| D1 | Next Ringside Rewrite episode: `run_job.py <job> --planner coverage` in place of job-local scripts (with `--plan-only` first, so asset requests reach the chat-image step). | Low. Writes only to `--out`. |
| D2 | Add `visual_qc.py` to the final review gate, report-only at first, with the contact sheet attached to the review page. | None (read-only). |
| D3 | Hip Hop Rewind: run `visual_qc.py --ledger` before approval, to catch reused archive ranges. | None. |
| D4 | HHWI: confirm the music bed and intro paths in `formulas/hhwi.json` (draft), then render the next episode with gentle reframes only. | Low. |

**Decisions for Thump:**
1. **Punch-in strength.** Close-ups crop to about 62 % of frame width on the 1672 px stills, which adds visible softening. Approve, or ask for medium-only.
2. **Act breaks.** The cold open dips to black into "the real timeline". Should there be a second dip where the rewrite begins (pass `--act-breaks 2,<n>`)?
3. **HHWI close-ups.** They stay off unless approved.
