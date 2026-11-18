# Worst Roommates Ever

A chaotic comedy life-sim. Six AI roommates, one bathroom, and you're the director. The
roommates live on their own, with needs, grudges, food theft, bathroom standoffs and revenge
pranks. A chaos meter sets how often big events hit: kitchen fire, raccoon, blackout, flood,
Brenda's ex, the landlord, Dex's party. A director cam zooms in on the drama and cuts to
confessionals. Type a prompt and Claude writes a full episode that the cast acts out, and
grudges carry into the next episode. All characters are fictional.

- Live game (after merging to `main`): https://yaboythump.github.io/ringside-rewrite/worst-roommates/


## Gameplay quality check

A GitHub Actions smoke test builds the game, checks JavaScript syntax, and runs
mobile-sized Chromium tests that tap through Story, Chaos and Director modes.
See `tests/smoke.mjs` and `.github/workflows/worst-roommates-gameplay-qa.yml`.
