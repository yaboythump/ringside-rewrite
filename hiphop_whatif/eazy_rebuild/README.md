# Eazy-E release pipeline

`build_v6.py` is the production entrypoint. It downloads the eight locked narrator WAVs and seven archival visual sources. It does not need `previous/full.mp4`, paid generation, or a v4 render. Existing helpers supply visual treatment and the original synthesized music.

The 350.29775-second narration and 24-scene pacing are locked. Video-only scenes are frame-counted and decoded before concatenation. Continuous PCM narration/music is normalized in two passes to -16 LUFS / -1.5 dBTP and encoded once in the full master. All five 55-second Shorts retain starts 5, 72, 142, 214 and 282 seconds. Portrait layouts preserve the full subject/title composition over a blurred background. There are no burned speech captions.

Run `python hiphop_whatif/eazy_rebuild/build_v6.py`. Requirements: FFmpeg, ffprobe, DejaVu fonts, requests, numpy, Pillow. `qc.py` validates every complete package and records durations, loudness, true peaks and SHA-256 hashes. `test_qc.py` and `test_publish.py` exercise failure handling. Temporary files are isolated, and only a validated package is promoted to `output/`.

The rebuild workflow runs on any source change and retains the package for 14 days. It does not publish to social platforms. Preview commits are idempotent.

## Release

Listen to the full master, inspect the 24-scene contact sheet and Shorts, and approve source rights for the intended territories before release. Technical QC does not certify spoken factual accuracy or legal clearance. The N.W.A. press photo has a US public-domain rationale, not a worldwide public-domain guarantee.

Dispatch **Eazy-E verified release** with the approved rebuild run ID, `approved=true`, and a timezone-qualified release time at least two hours ahead. The script revalidates the downloaded media, includes source credits in every description, uploads to the locked HipHopWhatIf YouTube profile and Facebook page 1305726102625399, and spaces Shorts one hour apart. Old dates in job.json are historical and are deliberately not silently reused.

YouTube is uploaded privately with native scheduled release so the full thumbnail can be patched and visually verified before release. Facebook returns scheduling job IDs; these are not claims of completed publication. Receipts are saved after every accepted request and retained even on failure. Stable per-episode/platform idempotency keys prevent blind duplicate uploads. If a release partially fails, inspect its receipts and existing remote jobs before changing the schedule. A failed later step does not cancel already scheduled posts.

API references: https://docs.upload-post.com/api/upload-video/ , https://docs.upload-post.com/api/upload-status/ , https://docs.upload-post.com/api/youtube-thumbnail/
