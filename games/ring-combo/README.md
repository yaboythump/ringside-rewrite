# Ringside Combo

A wrestling match-3 prototype. Every match is a move in the bout. The game uses the
Card Clash roster and portraits (`../card-clash/assets/portraits/`). All characters
are fictional.

Open `index.html` in a browser. It needs no build step and no network.

## Rules

- Swap neighbouring tiles to match 3 or more: 👊 Strike, 🤼 Grapple, 🦶 Kick,
  ⭐ Showboat (builds the crowd), 🩹 Recover (heals).
- A cascade gives a combo bonus of +25% damage per chain step.
- Match 4 creates a Clothesline tile, which clears its row or column when matched.
  Match 5 creates a Finisher 🌀. Swap the Finisher with any tile to clear every tile
  of that type and deal big damage. It deals extra damage when the crowd is ON FIRE.
- Pins: landing a Finisher with the opponent under 30% health (40% for Dutch), or
  taking them to 0, starts a cover. Clear the target number of tiles within 3 moves.
  If you miss, they kick out.
- The opponent acts on a visible countdown: attack, raise a guard (only a kick breaks
  it), throw in chairs 🪑, or put on brass knucks 🥊, which explode after 3 moves.
  A match next to a weapon clears it.
- Ladder: Jett Romano → Tank Ferro → Big Ox Duggan → Silas Crowe for the title.

Each playable wrestler has a perk: Brick (grapples), Raven (clotheslines),
Dutch (earlier pins), Kid (crowd).

Balance knobs are in the `HEROES` and `LADDER` tables at the top of the script.
