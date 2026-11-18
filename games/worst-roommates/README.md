# Worst Roommates Ever

A chaotic comedy life-sim. Six AI roommates, one bathroom, and you're the director. The
roommates live on their own, with needs, grudges, food theft, bathroom standoffs and revenge
pranks. A chaos meter sets how often big events hit: kitchen fire, raccoon, blackout, flood,
Brenda's ex, the landlord, Dex's party. A director cam zooms in on the drama and cuts to
confessionals. Type a prompt and Claude writes a full episode that the cast acts out, and
grudges carry into the next episode. All characters are fictional.

- Live game (after merging to `main`): https://yaboythump.github.io/ringside-rewrite/worst-roommates/

## Building

```sh
python3 games/worst-roommates/build.py            # writes games/worst-roommates.html
```

Edit `src.html`. The build packs any art in `assets/` into one HTML file with no network
requirement. Open the built file in a browser to play. On the web build the episode writer
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
