# Ringside Card Clash

A browser wrestling career simulator and collectible-card battler from CTInteractive
and CTNETWORK Studios. All characters and promotions are fictional.

- Live game: https://yaboythump.github.io/ringside-rewrite/
- Playtest: https://yaboythump.github.io/ringside-rewrite/preview/

## Playing

- **Career** includes the Open and Women’s divisions, Create-a-Wrestler, Fight Camp,
  permanent card ownership, training, XP rewards, faction and rivalry choices,
  a four-week event calendar, rankings, and a title journal. Faction allies
  double as tag partners. At every fourth-week special event, wrestle one
  optional tag bout with your Fight Camp deck before your singles main event.
  Two wins with the same partner earn a shot at your division’s tag belts.
  Title changes, successful defenses and vacated titles appear in the career
  journal. Breaking up a championship team vacates the belts.
- **Fight Camp** shows opponent tendencies and lets you adjust a 10–20 card deck
  without spending the weekly segment. Rare cards enter training at level 2 and
  epic cards at level 4. Older decks above the new deck limit remain playable.
- **Quick Match** is the original three-bout ladder. **Exhibition** lets you choose
  the opponent and stipulation. **Championship Cup** runs an eight-wrestler bracket,
  advancing the other bouts locally. It saves the bracket on entry and after
  every result. Reopen Championship Cup to continue the bracket or review
  the finished tournament. An interrupted match restarts from its opening bell.
  **Tag Team** includes a championship with browser-local title holders and a
  title history. When you tag, your partner inherits the legal spot and
  keeps their own deck, stamina, hype and kick-out. The first pin ends the match.
- **Settings** include sound and reduced effects. System reduced-motion settings
  are honored. The match engine and all artwork and audio run locally in the browser.

All 24 authored wrestlers have individual cinematic backstage portraits, including
the original eight. Create-a-Wrestler uses customizable illustrated gear.
The card catalog contains 65 moves, including 16 wrestler signatures introduced
with the expanded roster and four contract rewards. Finishers sit outside the deck.

Career saves and settings are browser-local. Existing careers preserve their
record, booked opponent, deck, position, and title totals. New title history and
detailed match records begin with the upgraded release. The public preview uses
separate storage keys on the same origin.

The **Promoter’s Office** offers four-show contracts with different objectives.
Finish a contract to earn fame and a permanent move. Rivalry contracts book
the named opponent when the title schedule permits it. The Medical Report
tracks injuries and lets you spend a weekly segment on rehab.

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

Add more faction stories, richer divisional stories, and team strategies.
Online multiplayer and cross-device saves would require a separately deployed
service. For multiplayer, keep stable wrestler, card and ruleset IDs in a shared
engine, and have an authoritative server validate each turn, handle reconnects and
own the seeded random state. The current game has no multiplayer service.
