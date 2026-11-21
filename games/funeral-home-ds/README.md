# Grave Mistakes

A chaotic (not gory) funeral home sim for the Nintendo DS, written in C with [BlocksDS](https://blocksds.skylyrac.net). It ships free inside Retro Duo.

- **Top screen:** the funeral home, live. The family waits in the chapel, the guest of honour lies in the prep room while you work, and during the service the mourners file in, the director reads the eulogy, and then something goes wrong.
- **Touch screen:** the day's bookings, body prep, quick-fix buttons during the service, and the money.

## Story and characters

You've just inherited the funeral home from your Great-Uncle Mort. Scenes play as DS-style talking-head dialogue: animated portraits that blink and talk, typewriter text with a voice blip per character, tap to continue, and SKIP.

- **Great-Uncle Mort**: the founder, now a friendly ghost who floats around the chapel giving advice. He passed last Tuesday (a casket brochure was involved).
- **Kevin**: the intern. On break since 2019. Finds a clue after every disaster.
- **Vivian Vance-Prestige**: owner of Eternal Elegance across the street. She'll buy the place for one dollar unless you hit the day's goal ($7,500 on day 1, then $1,000 more each day). Every disaster turns out to be her sabotage.
- **The families**: a spokesperson for each funeral (eleven in all, each with their own portrait and voice) tells you about the deceased and what they want. They react to the service once it's over.

Scenes happen at the start of each day, when you meet each family, before your first service, after every service, during Vivian's midday visit, and at closing time. That last scene depends on whether you hit the goal.

## A day

1. **Bookings:** three funerals (10 AM, 1 PM, 4 PM), each for a different fictional character with a family who wants a certain makeup look and outfit, and has a casket budget.
2. **Prep, all by touch:**
   - **Embalm:** hold the pump and let go in the green. Too little and there's a smell (and flies). Too much and they look a bit inflated.
   - **Makeup:** pick Natural, Glam or Clown, then rub it on with the stylus until the face is covered.
   - **Outfit:** flip through the rack (Sunday suit, floral dress, Hawaiian shirt, bowling shirt, sequin jumpsuit, superhero cape) and tap Dress.
   - **Casket:** Pine Box ($900), Oak Classic ($2,400) or Gold Deluxe ($5,500). Go over the budget and the family is furious about the bill.
3. **Service:** a random disaster hits every service (no repeats in a day): the lid won't stay shut, a raccoon in the wreath, sprinklers, a power cut, two exes screaming at each other, a phone blasting dance music, everyone sneezing at the lilies, or the casket rolling down the aisle. You have 8 seconds to tap the right quick fix. Wrong fixes cost money and make it worse. Run out of time and the family wants a refund.
4. **Money:** each funeral shows its ledger (fee, casket sale, tip, costs, fixes, refund) and the family's mood. Tips follow the mood.
5. **End of day:** revenue, tips, costs, refunds, profit, a star rating and a review. Then open up tomorrow with three new funerals.

## Building

With BlocksDS installed (or the `skylyrac/blocksds:slim-v1.25.0` Docker image):

```sh
make
```

Without the Wonderful Toolchain, `tools/llvm/build.sh` fetches BlocksDS v1.25.0 at pinned commits, compiles it with stock clang/lld (LLVM 18) and builds the game. `tools/llvm/patch_blocksds.py` lists the handful of GNU-only syntax fixes this needs. This is how `games/retro-duo/ios/RetroDuo/Resources/GraveMistakes.nds` is made. After changing the game, rebuild and commit it:

```sh
tools/llvm/build.sh ../retro-duo/ios/RetroDuo/Resources/GraveMistakes.nds
```

CI checks that the committed ROM matches the source.

## Testing

`tests/run_playthrough.sh [rom] [outdir]` builds Retro Duo's melonDS core and plays a whole day headlessly using only the stylus. It reads both screens with the game's own font, so it checks what a player sees. In 153 checks, it:

- reads every story scene by tapping through it (and checks the families ask for what the prep screen says they want),
- preps all three bodies (including over-pumping once and redoing it),
- matches each family's wishes,
- deliberately goes over budget once,
- tries a wrong quick fix,
- lets one disaster time out,
- confirms every ledger adds up and the day's profit is the sum of the three funerals.

It also writes screenshots (`*.ppm`) of each step. CI runs it on the bundled ROM and on the official BlocksDS build.

## Layout

| Path | What it is |
|---|---|
| `source/main.c` | Fixed 60 Hz loop driven by the vertical blank |
| `source/game.c` | Rules, money, and the touch screen |
| `source/scene.c` | Top screen: chapel, prep room, outside |
| `source/art.c` | Pixel-art characters and props, faces, outfits, caskets |
| `source/data.c` | The deceased, disasters and quick fixes |
| `source/story.c` | Mort, Kevin, Vivian, the families, every scene, and the dialogue box |
| `source/portrait.c` | Talking-head portraits: hair, accessories, six expressions, blinking, talking |
| `source/sfx.c` | PSG sound effects and a slow funeral march (Chopin, public domain) |
| `source/gfx.c` | Software drawing into two 16-bit framebuffers |
| `source/font8.h` | 8x8 font from libnds (zlib license), made by `tools/make_font.py` |

All characters are fictional.
