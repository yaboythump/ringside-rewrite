# Worst Roommates Ever

A playable offline-first comedy life-sim about six fictional roommates sharing one
bathroom. The original self-running apartment, personalities, grudges, dramatic
events and AI episode director all remain intact.

**Three modes**

- **Story: Survive the Lease.** A seven-day challenge with side-hustle cash,
  cleaning, mediation, repairs, missions, house peace and rent. Pay $180 on
  Day 4 and $240 on Day 7. Avoid eviction and keep the roommates from revolting.
- **Chaos: Make Everything Worse.** A 120-second high-score challenge. Pick a
  roommate, launch pranks, start feuds and trigger disasters. Chain trouble
  within nine seconds to earn up to a 5x multiplier.
- **Director: Create the Drama.** The existing episode generator, confessionals
  and persistent grudges, with the native Claude option and an offline fallback.

Tap a roommate on the stage or in the cast grid to select them for actions.
SFX can be toggled. Story progress, Chaos high scores and director episode
saves survive app restarts separately.

- Live preview after publishing: https://yaboythump.github.io/ringside-rewrite/worst-roommates/

## Building

```sh
python3 games/worst-roommates/build.py            # writes games/worst-roommates.html
```

Edit `src.html` for the apartment, `gameplay.js` for the modes, and `gameplay.css`
for mobile controls. The build embeds these and the images in `assets/` into one
HTML file with no network requirement. Open the built file in a browser to play. On the web build the episode writer
uses the offline gag generator.

## Art

`ART_BRIEF.md` lists every image the game can use, with ready-to-paste ChatGPT prompts and
file names. Put the files in `assets/` and rebuild. Missing art keeps the built-in look.

## iPhone app (TestFlight)

`ios/` is the native wrapper. It runs the built page offline and adds:

- **Claude episode writer.** Tap ⚙️ in the app and paste a Claude API key. It's stored only
  in that phone's Keychain. Without a key, the offline gag writer is used.
- Haptics for big moments, and on-device voices with a different pitch and speed per
  roommate (🔊 Voices).
- Saves kept by the app (episode number, grudges), so they survive WebKit storage resets.
- iPhone Duo layout: one column folded, and stage beside controls when unfolded or in landscape.

Bundle ID `com.ctnetworkstudios.worstroommates`, team `J4Y8FY6JNZ`. It uses the same
`ringside-testflight` environment secrets as Ringside Combo.

**First time only:** in App Store Connect, create the app record (**Apps → + → New App**,
iOS, name "Worst Roommates", bundle ID `com.ctnetworkstudios.worstroommates`, any SKU).
The workflow registers the bundle ID and provisioning profile itself, but Apple requires the
app record before an upload.

**To ship a build:** go to **Actions → Worst Roommates TestFlight → Run workflow** on `main`
with "upload" checked. Pushes to `main` that touch this game only run the unsigned build check.

## Tuning

- Cast, traits, needs and dialogue are in the `CAST` table near the top of the script.
- Big events are in `triggerEvent()`, and small drama is in `INCIDENTS`.
- The episode writer prompt is in `writeEpisode()`.

## Gameplay QA

`tests/smoke.mjs` runs an automated mobile-browser check for Story, Chaos,
Director, roommate selection, scoring, restart, and horizontal overflow.
The dedicated GitHub workflow builds and tests this offline game.
