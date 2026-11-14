# Ringside Card Clash

An original wrestling card battler that runs in the browser. All wrestlers are
fictional. Unofficial and fan-made.

Play it: https://yaboythump.github.io/ringside-rewrite/

## Files

| Path | What it is |
|---|---|
| `src.html` | The whole game: styles, markup and code. Edit this. |
| `assets/portraits/<id>.jpg` | One portrait per wrestler |
| `assets/belt.webp` | Championship belt, transparent background |
| `assets/arena.jpg` | Arena photo shown behind every screen |
| `build.py` | Embeds the images into one playable file |
| `../card-clash.html` | The built game. Do not edit by hand. |

## Changing a picture

1. Replace the file in `assets/`, keeping the same name. JPG, PNG and WebP all
   work (`raven.jpg` can become `raven.png`; delete the old one).
2. Portraits: square, face centered, about 320 to 512 px, ideally under 100 KB.
   Wrestler ids: `brick`, `raven`, `dutch`, `kid`, `silas`, `tank`, `jett`, `ox`.
3. Belt: wide image (about 3:1) with a transparent background.
4. Arena: tall image (about 9:16), dark, no text or logos.
5. Commit to `main`. The site rebuilds and redeploys by itself.

A wrestler with no portrait file shows their initials instead.

## Building locally

```
python3 games/card-clash/build.py
```

Then open `games/card-clash.html` in a browser.

## Adding a wrestler or card

Wrestlers are in the `WRESTLERS` object and cards in the `CARDS` object near
the top of the script in `src.html`. Add a portrait named after the wrestler's
id. Keep every character original: no real wrestlers, promotions or logos.
