# Ringside Combo

A wrestling match-3 prototype. Every match is a move in the bout. The game uses the
Card Clash roster and portraits (`../card-clash/assets/portraits/`). All characters
are fictional.

Open `index.html` in a browser. It needs no build step and no network.

All sound effects are synthesized with the Web Audio API, so there are no audio files.
The speaker button in the header mutes them, and the setting is remembered in the browser.

## Rules

- It's turn-based. You make one move, then the opponent makes one on the same board.
  You see the two tiles they pick before they swap them.
- Tile types: 👊 Strike, 🤼 Grapple, 🦶 Kick, ⭐ Showboat (builds your crowd),
  🩹 Recover (heals). When the opponent matches tiles, their strikes, grapples and kicks hurt
  you, their showboats drain your crowd, and their recovers heal them.
- A cascade gives a combo bonus of +25% damage per chain step.
- Match 4 creates a Clothesline tile, which clears its row or column when anyone matches it.
  Match 5 creates a Finisher 🌀 owned by whoever made it. Yours have a gold ring and theirs a red one.
  Swap your Finisher with any tile to clear every tile of that type and deal big damage.
- Pins: landing your Finisher with the opponent under 30% health (40% for Dutch), or taking
  them to 0, starts a cover. Clear the target number of tiles within 3 of your moves. The
  opponent can't move while pinned. If you miss, they kick out.
- If you hit 0 health, they cover you. Clear enough tiles in your next move to kick out,
  and each kick-out makes the next one harder.
- Dirty tricks every few opponent turns: a guard that halves your damage until you match
  kicks, chairs 🪑 that block tiles, and brass knucks 🥊 that explode after 3 turns. A match
  next to a weapon clears it.
- Turn clock: 15s, 13s, 12s, then 10s up the ladder. If it runs out, you lose your turn.
- Ladder: Jett Romano → Tank Ferro → Big Ox Duggan → Silas Crowe for the title. Opponents
  hit harder and pick better moves as you climb.

Each playable wrestler has a perk: Brick (grapples), Raven (clotheslines),
Dutch (earlier pins), Kid (crowd).

Balance settings (`power`, `smart`, `hp`, `tricks`, `clock`) are in the `HEROES` and `LADDER`
tables at the top of the script.
