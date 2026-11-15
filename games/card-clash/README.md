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

## Fight Camp (Upgrade 01, pending review)

The game is growing toward a combined wrestling career and strategic card battler.
This development upgrade adds a **Fight Camp** button to the Career hub.

- **Scout**: review an opponent's base strike, grapple, defense and hype tendencies,
  their finisher, and the next match stipulation. These are tendencies, not guaranteed moves.
- **Equip**: manage a match deck of 10 to 20 earned cards without spending the weekly
  promo/training segment. A career's earned move `collection` is separate from the
  equipped `deck`; unequipping does not destroy ownership.
- **Train**: training and the veteran event permanently unlock a move in the
  collection. The move auto-equips only while there is room in the deck.
- **Compatibility**: previously saved careers are migrated from their existing
  equipped deck, keeping existing cards. Legacy decks over 20 remain intact.
- **Safety**: beginning a new career asks before replacing the current local save.

Save data remains **local to the browser/device**. Cloud save, multiplayer, and
cross-device sync are *not* yet implemented.

Run automated checks:

```sh
node --test games/card-clash/tests/fight-camp.test.cjs
python3 games/card-clash/build.py /tmp/ringside-card-clash-preview.html
```

For review, use the `feat/rcc-fight-camp-foundation-20261114` branch. The live
GitHub Pages workflow deploys `main` only. Do not merge without approval.

## Building locally

```
python3 games/card-clash/build.py
```

Then open `games/card-clash.html` in a browser.

## Adding a wrestler or card

Wrestlers are in the `WRESTLERS` object and cards in the `CARDS` object near
the top of the script in `src.html`. Add a portrait named after the wrestler's
id. Keep every character original: no real wrestlers, promotions or logos.
