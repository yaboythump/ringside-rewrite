# Ringside Recap: AEW Fright Night Dynamite (2026-10-28): Operator 2 status

Checked 2026-11-05 (read-only). Server job: `/srv/ctnetwork/jobs/ringside-recap-aew-fright-night-20261028`.
No process was running on the job; it was last modified 2026-10-29 21:42.

| Output | Match | State |
|---|---|---|
| Full episode | full show | PUBLISHED (approved-release-1, 2026-10-29) |
| Short 1 | Queen Aminata vs. Persephone | PUBLISHED |
| Short 2 | The Cut vs. Death Riders | PUBLISHED |
| Short 3 | Kyle Fletcher vs. Jack Perry | **RENDERED, QC PASS, AWAITING THUMP APPROVAL** (never released) |
| Short 4 | Motor City Machine Guns vs. FTR | Narration done (F06, ASR QC pass). **Needs 4 ChatGPT stills** |
| Short 5 | Marina Shafir vs. Rachel Armstrong | Narration done (F06, ASR QC pass). **Needs 4 ChatGPT stills** |
| Short 6 | Darby Allin vs. Josh Alexander | Narration done (F06, ASR QC pass). **Needs 2 ChatGPT stills** |

## Short 3 QC (outputs/v2/short_3.mp4)
- sha256 `d13e9d1a3db551cd0af56b34996d847b1cb7ccb45754d295f3cede3ed6cbb768` (identical copy in review folder)
- 1080x1920, 30 fps, h264 + AAC stereo, 47.24 s (inside the 45-60 s window)
- Same encode spec as the published Shorts 1-2
- Loudness -14.2 LUFS integrated, true peak -1.5 dBFS, LRA 2.2 LU
- Black frames: none. Dead air (<-45 dB for over 1.5 s): none
- 4 stills, each held about 8-12 s (deliberate Recap pacing, per formula)
- Narration ASR QC (job log): similarity 0.9844, pass
- Visual check: art is specific to the match, with accurate on-screen headlines (Fletcher beats Perry, then Full Gear title match set), the Fright Night date and the CTNETWORK watermark
- Planned YouTube title (ledger): `Kyle Fletcher vs. Jack Perry — Fletcher wins; Ospreay next | Ringside Recap`
- Review: https://66-179-191-248.sslip.io/aew-fright-night-20261028/AEW_Fright_Night_2026-10-28_short_3.mp4

## ChatGPT handoff (art only, same approved Fright Night style; 941x1672 vertical, full-frame)
Transfer into the existing art lanes:
- `...-short34-art/graphics/`: `short_4_1.jpg` to `short_4_4.jpg` (MCMG vs. FTR)
- new or existing lane: `short_5_1.jpg` to `short_5_4.jpg` (Shafir vs. Armstrong)
- `...-darby-art/graphics/`: `short_6_3.jpg`, `short_6_4.jpg` (Darby vs. Alexander)

After the art lands, the job's existing `assemble_more.py short_4 short_5 short_6` finishes all three
with the narration already on the server. That costs 0 generation credits.
