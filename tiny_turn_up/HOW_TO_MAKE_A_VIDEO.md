# How to make a Tiny Turn Up video

Each song lives in `tiny_turn_up/episodes/<song>/`. The `episode.json` there already has the
title, description, tags, scene prompts, thumbnail prompt and Shorts.

## 1. Make the song in Suno (you, about 5 minutes)
1. Open the song's lyrics file in `tiny_turn_up/songs/` (e.g. `01-turkey-wobble.md`).
2. In Suno → Custom: paste the **Music style prompt** into Style and the **Lyrics** into Lyrics.
   Delete the *(dance cue)* parts in italics, since those are for the video, not the singer.
3. Generate, pick the best take, download the **MP3**.
4. Save it as `tiny_turn_up/episodes/01-gobble-gobble-wobble/song.mp3`.

## 2. Pictures (automatic, or use ChatGPT)
- **Automatic:** the pipeline makes the 8 scene images and the thumbnail with OpenAI (needs `OPENAI_API_KEY`).
- **Your own from ChatGPT:** save them as `scene_01.png` … `scene_08.png` and `thumbnail.png` in the
  song's folder. Any file you add is kept, and only missing ones get generated.
- **Animated clips (ChatGPT video/Sora):** save a clip as `scene_03.mp4` and it replaces that scene's picture.
  Clips loop to fill their slot.

## 3. Build the videos
```
tinyturnup list                          # what each song still needs
tinyturnup make 01-gobble-gobble-wobble  # images + long video + 2 Shorts + thumbnail
```
Output lands in the song's `build/` folder: `long.mp4`, `short_01.mp4`, `short_02.mp4`, `thumbnail.jpg`.

**Watch the Shorts once.** Their start times in `episode.json` are guesses. If a Short misses
the chorus, change `"start"` (in seconds) and run `make` again. To line a scene up with a part
of the song, add `"start": 42` to that scene in `episode.json`.

## 4. Upload (Made for Kids, private for review)
```
tinyturnup auth                          # one time; choose the TINY TURN UP channel
tinyturnup upload 01-gobble-gobble-wobble
```
- Uploads go up **private** so you can check them in Studio first. Use `--public` or
  `--publish-at 2026-11-10T13:00:00Z` to skip that.
- Every upload is marked **Made for Kids** and **altered/synthetic content**.
- It refuses to upload if you're logged into any channel other than Tiny Turn Up.
- It remembers what it uploaded (`uploaded.json`), so running it twice never makes duplicates.
- Custom thumbnails need a phone-verified channel (YouTube Studio → Settings → Channel → Feature eligibility).

## 5. Compilation
After songs 01–04 are made: `tinyturnup make 05-dance-party-compilation`, then upload it the same way.
