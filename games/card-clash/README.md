# Ringside Card Clash

A browser wrestling career simulator and collectible-card battler from CTInteractive
and CTNETWORK Studios. All characters and promotions are fictional.

- Live game: https://yaboythump.github.io/ringside-rewrite/
- Playtest: https://yaboythump.github.io/ringside-rewrite/preview/

## Playing

- **Career** includes the Open and Women’s divisions, Create-a-Wrestler, Fight Camp,
  permanent card ownership, training, XP rewards, faction and rivalry choices,
  a four-week event calendar, rankings, and a title journal.
- **Fight Camp** shows opponent tendencies and lets you adjust a 10–20 card deck
  without spending the weekly segment. Rare cards enter training at level 2 and
  epic cards at level 4. Older decks above the new deck limit remain playable.
- **Quick Match** is the original three-bout ladder. **Exhibition** lets you choose
  the opponent and stipulation. **Championship Cup** runs an eight-wrestler bracket,
  advancing the other bouts locally. **Tag Team** includes a championship with
  browser-local title holders. When you tag, your partner inherits the legal spot and
  keeps their own deck, stamina, hype and kick-out. The first pin ends the match.
- **Settings** include sound and reduced effects. System reduced-motion settings
  are honored. The match engine and all artwork and audio run locally in the browser.

There are 24 authored wrestlers. The original eight portraits are embedded. New
wrestlers and created characters use illustrated gear with different colors, skin
tones, hairstyles, masks, and ring gear. Each new wrestler has a named signature,
a finisher, and weighted AI preferences. The card catalog contains 61 moves,
including 16 new wrestler signatures. Finishers are separate from the deck.

Career saves and settings are browser-local. Existing careers preserve their
record, booked opponent, deck, position, and title totals. New title history and
detailed match records begin with the upgraded release. The public preview uses
separate storage keys on the same origin.

## Development and release

```sh
node --test games/card-clash/tests/fight-camp.test.cjs
python3 games/card-clash/build.py /tmp/card-clash.html
```

Open the built HTML in a browser. The build embeds the approved arena, belt and
portrait images, and it has no runtime CDN, AI, or GPU service requirement.
Edit `src.html`; portrait filenames match wrestler IDs. GitHub Pages builds
directly from source.

The Pages workflow publishes from `main`. The preview path builds from an exact
pinned game commit. The pre-upgrade root can be rebuilt from
`archive/card-clash-pre-career-release-20261114`.

## Future work

Add full individual portrait art for the expanded roster, more faction stories,
and richer divisions and tag careers. Cup brackets currently last for the session.
Online multiplayer and cross-device saves would require a separately deployed
service. For multiplayer, keep stable wrestler, card and ruleset IDs in a shared
engine, and have an authoritative server validate each turn, handle reconnects and
own the seeded random state. The current game has no multiplayer service.
