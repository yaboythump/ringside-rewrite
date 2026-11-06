# Ringside News — Production Test 001: Jeff Hardy / syX

Status: **BLOCKED BEFORE ASSEMBLY. No MP4 or cover was produced. Nothing was published.**
Job folder on the VPS: `/srv/ctnetwork/jobs/ringside-news-jeff-hardy-syx-20261106`

## Fact check (primary source: TNA results page for Nov 5, 2026, fetched 2026-11-06)
- TNA Injury Report (on air): "Jeff Hardy is being held out of action indefinitely due to the severity of his injuries from the syX Slaughterhouse Match."
- Moose called out syX, they attacked him, and Matt Hardy made the save with a steel pipe.
- Backstage, Matt Hardy said he "will not forget or forgive" what syX did to Jeff. Matt announced that he and Moose will face syX in tag team action at Destination X.
- Destination X: **Sunday, November 15, 2026, Edmonton, Alberta** (TNA's date. Wrestling Inc. reports Nov 14; TNA's date is used.)
- Next week: Moose vs. Samuel Shaw.
- **Storyline vs. medical:** the injury report is an on-screen angle. TNA has released no independent medical details and no return date. Wrestling Inc. reports that Matt Hardy has said on his podcast that Jeff has bulging neck discs, and that a busy schedule could be another reason for the absence. That reporting was not independently verified, so it is left out of the narration.
- Newer developments: nothing newer than the Nov 5 episode was found.

## Duplicate check
No Hardy, Moose or syX jobs, transfers, publish receipts or database rows exist on the VPS. The most recent Ringside News job is Flair, Oct 23.

## What is ready
- `script.txt`: 142 words, about 45 s with the 2 s intro and tail used in the Flair formula.
- `metadata.json`: title, description, source and hashtags (marked not approved).
- `render.py`: the Oct 23 Flair Short formula (1080x1920, approved `Ringside news.mp3` bed at 0.07, CTNETWORK bug). It runs once `work/narration.mp3` and `graphics/main.jpg` plus `support1.jpg` to `support3.jpg` exist.
- `research/`: archived copy of the TNA source page.

## Blockers
1. **Visuals.** The locked workflow requires ChatGPT-created stills. The template lock and production rules forbid server-invented visuals and substitutions. No approved images of Jeff Hardy, Matt Hardy, Moose or syX exist on the VPS. The only free generator is the CPU-only tiny-SD test (no GPU on the VPS). It produced a generic, low-quality wrestler with no likeness, so it doesn't meet the standard. TNA press photos are not cleared for reuse. GPU work (RunPod) or image credits would be extra spend.
2. **Narrator.** ElevenLabs returned `401 ivc_not_permitted` for the approved voice `Z32A1FOtMGZSvBZZYHWE`: "Instantly cloned voices are not available on your current plan." Fixing this needs a plan upgrade. No substitute voice was used.

## Cost
USD 0.00. No ElevenLabs characters were billed (the request was refused). There were no ChatGPT, image-generation, RunPod or other paid calls.

## To finish
Restore the ElevenLabs plan tier that includes the cloned voice, supply 4 approved 9:16 stills (main plus 3 supports, in the Ringside News header template), then run `render.py`.
