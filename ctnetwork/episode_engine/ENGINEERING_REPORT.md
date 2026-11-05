# CTNETWORK Engineering Project 002: Full-Episode Automation Audit

Date: 2026-11-05 · Server: `ubuntu` (IONOS VPS, 8 vCPU, 15 GB RAM, no GPU, ffmpeg 8.0.1) · Scope: Ringside Rewrite, Hip Hop Unscripted (plus HHWI, the closest long-form hip-hop show)

**Result:** I rebuilt the published *What If Raven's Flock Took Over WCW?* package (full episode plus 3 Shorts) in a separate dev sandbox. The rebuild used only the existing chat-made stills, the existing F06 narration, the approved music bed and the approved SFX. All 4 deliverables and all 4 thumbnails passed automated QC. Generation credits spent: **0**. Nothing was published, no service was restarted, and nothing under `/srv/ctnetwork` was modified.

---

## 1. How production actually runs today

| Layer | What exists | State |
|---|---|---|
| Creative | ChatGPT makes the script, every still and the thumbnail, then transfers them to the VPS with a SHA256 manifest (`transfer_status.json`) | Working. Transfer verification is solid. |
| Orchestrator | `production_v2/engine.py` and `worker.py` (systemd `ctnetwork-production-v2`): resumable stages, receipts, bounded retries, final approval gate leading to publish | Used by Recap, News and Rewind. **Not used by Ringside Rewrite** (see F1). |
| Ringside Rewrite renders | Hand-written scripts copied into each job folder (`render_episode.py`, `render_shorts.py`, `narrate_shorts.py`, `prepare_review.py`, `apply_premium_covers.py`) with hard-coded paths and polling loops | Working, but every episode is a code fork. |
| Narration | `qwen_f06_native` CPU voice (`voices/ringside_recap_f06_cpu.bin`) for Recap, Rewrite and Rewind; ElevenLabs via `elevenlabs_adapter.py` for News, Grandma Rose and Hip Hop Unscripted | Working. No cache and no spend gate on the ElevenLabs path (see F6). |
| QC | Per-job checks: decode, blackdetect, ebur128, Whisper transcript match (`quality/narration_qc.py`, which is good) | Misses static picture, color range and loudness shortfall. |
| Publish | `publish_production.py` and `direct_youtube.py`, with routes in `config/social/direct_publish_routes.json`; hash-locked approval | Working. Approval and hash gates are sound. |

## 2. Findings (broken or incomplete)

I measured the published Raven files with the new QC tool (read-only). The same checks were then run on the rebuild.

| # | Finding | Evidence | Impact |
|---|---|---|---|
| **F1** | **Ringside Rewrite plans can't run through the shared engine.** Their `production_plan_v2.json` outputs have no `width`/`height`, so `engine.py` raises `KeyError` in `graphics()`. Each episode is rendered by a fresh copy of job-local scripts instead. | `jobs/ringside-rewrite-{ecw,raven}-*/production_plan_v2.json`; no `work/autonomous/state.json` | Every episode needs manual scripting. Fixes made in one job never reach the next. This is the main cause of manual intervention. |
| **F2** | **Slideshow feel**, which violates `visual.no_slideshow_feel: true`. Stills are joined with the concat demuxer: no motion and hard cuts. | Published master: **60 frozen holds, 492 of 567 s static**. Each Short: 6 holds covering 43–48 s. | The biggest gap between "premium cinematic" and what ships. |
| **F3** | **Color range flagged full-range.** ffmpeg 8 decodes the JPEG stills as `yuvj420p`, and the masters carry that flag. | Published master and all 3 Shorts report `yuvj420p` | Some players and TVs crush blacks or wash out. This is a silent quality defect. |
| **F4** | **Music never ducks, and the bed loop has a hard seam.** The bed sits at a constant -32 dB RMS via `np.tile` (a hard seam every 154 s). The `production_v2/engine.py` path is worse: fixed `volume=0.10` with no ducking. | `render_episode.py` lines 26–29 | Flat mix, an audible loop click on episodes over 2.5 min, and no music lift in pauses or at the outro. |
| **F5** | **Shorts are padded with silent narration** to reach 45 s. | `render_shorts.py`: `np.pad(x,(0,int((45.3-duration)*48000)))` | Dead air at the end of Shorts, which the music bed barely covers. |
| **F6** | **ElevenLabs path has no cache, retry or spend gate.** `narration.py` calls the API every time a receipt is missing. 429/5xx errors are not retried, and nothing estimates cost first. The HHWI pronunciation map (`Ma$e`→`Mace`) is defined in the profile but never applied. | The Hip Hop Unscripted / Grandma Rose Eazy–Papoose episode has **4 paid narration takes in one hour** (`review/GRANDMA_ROSE_EAZY_PAPOOSE_{FINAL,V2_CORRECTED,V4_NARRATION}.mp3` and the original) | Wasted credits on re-renders and QC retries. |
| **F7** | **Hip Hop Unscripted has no show profile.** A route exists (`hip_hop_unscripted`, YouTube only) and the registry lists the show, but `config/show_profiles/hip_hop_unscripted.json` is missing. Its only output, the Grandma Rose reel, is **720×1280, 24 fps, 96 kHz mono AAC**, below the 1080×1920 / 30 fps / 48 kHz stereo network standard. | `review/HIP_HOP_UNSCRIPTED_*.mp4` ffprobe | Can't be produced automatically. The formula isn't written down anywhere. |
| **F8** | **Loudness lands under target with unused headroom.** A single-pass `loudnorm` on a speech mix gives -14.4 LUFS at -4.0 dBTP. | QC on the published master | Minor, but it shows the normaliser isn't in control. |
| **F9** | **Formula assets live inside old job folders.** The music bed is read from `jobs/ringside-rewrite-no-attitude-era-20261021/inputs/audio/music_bed.wav`. The profile's `audio.theme_asset` `Ringside rewrite 2.wav` is a 2-second sting that the recent episodes don't use. | ECW and Raven render scripts | Cleaning up an old job would break every new episode. |
| **F10** | The HHWI locked intro (`Hip_Hop_What_If_Intro_Recent_Episodes_v2.mp4`, 1280×720 / 24 fps) exists only as copies inside three job folders. Nothing in `production_v2` prepends it. | `find` across `/srv` | The required intro depends on someone remembering to add it by hand. |
| F11 | Final encodes use `-preset medium`/`fast` with `-tune stillimage`, against the profile's `preset: slow`. ECW Shorts were cut as a 1080×608 window inside a vertical background, which conflicts with `forbid_inset_panels` (already corrected by the Raven Shorts). | render scripts | Small quality loss and drift from the rules. |
| F12 | Three CTN v7a services are in `failed` state (`ctn-v7a-evidence`, `-readiness`, `-research`). They are unrelated to video production. | `systemctl` | Not touched. Flagged only. |

## 3. What I built (dev copy, reversible)

`ctnetwork/episode_engine/` in this repo, installed on the server at **`/srv/ctnetwork-dev/episode_engine`** (outside `/srv/ctnetwork`, no service points at it). It uses the existing venv read-only, and test-only `pytest` lives in `/srv/ctnetwork-dev/pylib`. **To roll back: `rm -rf /srv/ctnetwork-dev`.**

| Module | What it does | Fixes |
|---|---|---|
| `formulas/ringside_rewrite.json` | The locked Ringside Rewrite formula, copied verbatim from the published ECW/Raven scripts: same F06 narrator runtime, -20 dB speech level, same music bed at -32 dB under narration, same bell/crowd assets and levels, same branding text, positions and opacity, same 4 s thumbnail outro, 3 Shorts, 45–60 s. | F1, F9 |
| `adapters.py` | Reads an existing job read-only. It reuses the **approved picture edit** (`work/edit/timeline.json`: same 61 shots, same order, same cut points) and `shorts_plan.json` (same shots and focus points, same covers). | F1 |
| `render.py` | Ken Burns motion on every still (smoothstep push-in, pull-out and pans, rendered at 2× oversampling so motion is sub-pixel smooth); frame-accurate 0.6 s crossfades that start on the original cut times (zero drift over 61 cuts); bed **ducked** under narration (-32 dB) and lifted in pauses and the outro (-26 dB), looped with equal-power crossfades; the same SFX cues; branding kept off the Shorts' cover frame; optional locked intro prepended with its baked audio untouched; measure, limit if needed, then linear `loudnorm`; BT.709 TV-range output at `preset slow / crf 18`. Clips are cached by content hash, so a re-render is resume-safe. Refuses to write inside the job folder and refuses to run if narration is missing (it never synthesizes). | F2, F3, F4, F5, F8, F10, F11 |
| `qc.py` | A single decode pass checking spec, decode errors, black frames, **frozen picture**, **dead air**, integrated LUFS, true peak, A/V length match and runtime window, plus thumbnail checks against YouTube limits. | F2, F3, F8 detection |
| `thumbnail.py` | Resizes the approved chat thumbnail to 1280×720 (and covers to 1080×1920) under 2 MB. It **refuses to crop** when the aspect is more than 3% off. No generation and no redesign. | Thumbnail delivery |
| `narration_cache.py` | A wrapper around the existing `elevenlabs_adapter.py` (voices and models unchanged): content-addressed cache, pronunciation maps applied before hashing, `estimate()` preflight (cached vs. billable characters), hard `SpendBlocked` gate unless `allow_spend=True` and the budget covers it, retries on 429/5xx only, a JSONL billing ledger, and `seed()` to register audio that's already been paid for. | F6 |
| `run_job.py` | One command from job to deliverables, QC and `delivery_report.json`. `publishing_authorized: false`, always. | End-to-end |

Tests: `tests/test_engine.py` has 10 tests (drift-free frame plan, seamless loop, ducking, episode, Short, intro prepend, static-slideshow detection, thumbnail, spend gate, auth-error fail-fast). **10/10 pass locally (ffmpeg 6.1) and on the server (ffmpeg 8.0.1).** The server run caught F3 before the real render.

## 4. Full rendering test: Raven's Flock (existing assets)

Command, run at `nice 15 / ionice idle`, 3 threads:
```
/srv/ctnetwork-dev/run_raven_test.sh
→ run_job.py /srv/ctnetwork/jobs/ringside-rewrite-raven-flock-20261104 \
    --out /srv/ctnetwork-dev/renders/ringside-rewrite-raven-flock-20261104 \
    --covers-dir /srv/ctnetwork/jobs/ringside-raven-covers-20261104/graphics --subject RAVEN
```

| Deliverable | Published (baseline) | Dev rebuild |
|---|---|---|
| Master 1920×1080 | 567.3 s · -14.4 LUFS · -4.0 dBTP · `yuvj420p` · **60 static holds (492 s)** · FAIL | 567.28 s · **-14.0 LUFS** · -4.5 dBTP · `yuv420p tv bt709` · **0 static holds** · **PASS** |
| Short 1 1080×1920 | 45.4 s · 6 holds (43 s) · silence-padded | 46.0 s · 0 holds · music outro · **PASS** |
| Short 2 | 50.5 s · 6 holds (48 s) | 51.1 s · 0 holds · **PASS** |
| Short 3 | 49.8 s · 6 holds (47 s) | 50.4 s · 0 holds · **PASS** |
| Thumbnails | n/a | 1280×720 (515 KB) and 3× 1080×1920 (≤1.1 MB) · **PASS** |

- Wall time: **27.6 min** for everything (master 21.7 min, Shorts about 1.8 min each). Server load peaked at 6.3 on 8 cores, and production services weren't affected.
- Master bitrate is 5.7 Mb/s (published: 1.7 Mb/s). Motion needs more bits at the same CRF 18. YouTube re-encodes either way.
- Narration offsets, script order and shot order match the approved edit exactly (61/61 shots, sync verified by frame plan; total length matches to 20 ms).
- **Test MP4 (not published, not in the review web root):**
  `/srv/ctnetwork-dev/renders/ringside-rewrite-raven-flock-20261104/Ringside_Rewrite_What_If_Ravens_Flock_Took_Over_WCW.mp4`
  plus `Short_1..3.mp4`, `*_thumbnail.jpg`, `delivery_report.json`, `baseline_*_qc.json`, and a before/after frame check in `review_frames/`.

## 5. Improvements ready for deployment (each needs Thump's approval)

| # | Change | Risk | How to deploy / roll back |
|---|---|---|---|
| D1 | Use `run_job.py` for the **next** Ringside Rewrite episode in place of copying job-local render scripts. Same assets, same formula, better finishing. | Low. Writes only to its `--out` folder. | Point the next job at the engine. Rollback: use the old scripts. |
| D2 | Add `qc.py` checks (`freeze`, `color_range`, LUFS window) to the final review gate, report-only at first. | None (read-only). | Call it from `prepare_review.py`. |
| D3 | Route every ElevenLabs call through `narration_cache.py` with `allow_spend` set from the job's approved budget; seed the cache with existing paid narration. | Low. Same adapter, voices and models. | Wrap the call in `production_v2/narration.py` (one function). Needs a service restart, so **authorization required**. |
| D4 | Move formula assets (music bed, HHWI intro, bell/crowd) into `/srv/ctnetwork/assets/<show>/` and update the formula paths. | None. Copy, don't move. | `cp` plus a formula edit. |
| D5 | Add `width`/`height` to Ringside Rewrite `production_plan_v2.json` outputs, or have `engine.py` read them from the show profile, so `production_v2` can resume Rewrite jobs. | Medium. Touches the live engine. | Patch plus a `production_v2` restart: **authorization required**. |
| D6 | Create `config/show_profiles/hip_hop_unscripted.json` with 1080×1920 / 30 fps / 48 kHz stereo and Grandma Rose's locked ElevenLabs voice (`kawujji4e40AXGJ8Ogbw`, `eleven_v4`). | Low. | Needs Thump to confirm the format (see open questions). |
| D7 | HHWI: render through the engine with `--intro` set to the locked `Hip_Hop_What_If_Intro_Recent_Episodes_v2.mp4` (code path tested; no HHWI full render done yet). | Low. | Formula file `formulas/hhwi.json` still to write from the last approved HHWI render. |

## 6. Open decisions for Thump

1. **Motion style.** The Ken Burns moves are subtle (7% zoom, with eased push, pull and pan alternating) and transitions are 0.6 s dissolves. Please watch the dev master and approve or adjust the strength. Stills-only policy is respected: no generated motion and no GPU.
2. **Theme sting.** The profile lists `Ringside rewrite 2.wav` (a 2 s sting) as the theme asset, but ECW and Raven don't use it. The engine follows the published episodes (no sting) unless you say otherwise.
3. **SFX cue placement** differs per episode (ECW: segments 3/7/15; Raven: 4/11/14). The formula defaults to Raven's cues. Per-episode cues can be passed with `--cues`.
4. **Hip Hop Unscripted format.** Is it the Grandma Rose vertical news-reel series only, or is there a long-form episode formula to lock?
5. I did **not** copy the dev render into `/srv/ctnetwork/review/`, because that's the live review web root. Say the word and I'll stage a private review link.

Rule check: same show (approved edit, narrator, music, branding, covers), same formula (3 Shorts, 45–60 s, stills-only), higher finishing quality, **zero spend**.
