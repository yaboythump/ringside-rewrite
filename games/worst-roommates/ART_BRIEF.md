# Worst Roommates Ever art brief

This is the art list for ChatGPT image generation. Generate each image, save it with the
exact file name below, and put it in `games/worst-roommates/assets/`. The next build packs it in
automatically (`python3 games/worst-roommates/build.py`, the TestFlight workflow and the Pages
deploy all run it). Any image you skip keeps the current look, so you can add art one piece at a time.

From your iPhone: open the repo on github.com → `games/worst-roommates/assets` → **Add file → Upload files**,
pick the images, and commit to `main`. Big images are fine; the build shrinks them.

## Step 1 — Paste this style guide into ChatGPT first

> I'm making art for a mobile game called "Worst Roommates Ever", a chaotic comedy life-sim seen from a top-down, slightly angled (3/4) view. Keep EVERY image in this exact style: bold cartoon look, thick dark outlines (#0b0910), flat saturated colors with one simple shadow tone, chunky slightly chibi proportions (big heads, small bodies), goofy and expressive, PG-13 adult-cartoon humor. No text or letters in any image unless I ask. No photorealism, no gradients-heavy rendering. Unless I say otherwise, use a **transparent background** and center the subject with a little padding. I'll ask for one image at a time — keep the style identical across all of them.

Tip: once you like the first character, upload that image back to ChatGPT with each new prompt and say "same style as this".

## Step 2 — Characters (top-down sprites)
Square PNG, transparent background, **full body seen from slightly above**, facing down/toward the camera, standing. These show up small, so keep the shapes bold and simple.

| File | Prompt |
|---|---|
| `char_dex.png` | Dex, an aspiring DJ in his 20s: hot-pink hoodie, oversized headphones around his neck, backwards cap, smug grin. |
| `char_brenda.png` | Brenda, dramatic woman in her 20s: orange robe, messy bun, mascara-streaked dramatic expression, clutching an oversized gray hoodie. |
| `char_gary.png` | Gary, shifty guy in his 30s: light-blue wrinkled shirt, bad mustache, nervous side-eye, hands in pockets like he's hiding something. |
| `char_priya.png` | Priya, neat freak in her 20s: crisp green cardigan, perfect ponytail, holding a pad of sticky notes, tight passive-aggressive smile. |
| `char_moose.png` | Moose, a huge gentle giant: purple tank top, beard with crumbs in it, holding a drumstick, sweet clueless face. |
| `char_luna.png` | Luna, conspiracy theorist: yellow raincoat, tinfoil hat, wild curly hair, wide paranoid eyes. |
| `char_kyle.png` | Kyle, Brenda's ex: gray clothes, hopeful puppy-dog face, holding his phone. |
| `char_fenwick.png` | Mr. Fenwick, the grumpy landlord: older man, white sweater vest, clipboard, deep scowl. |

## Step 3 — Confessional portraits
Square PNG (1024×1024), **NOT transparent**: head-and-shoulders, character talking straight to camera, on a purple diagonal-striped "reality TV confessional" backdrop. These get cropped to a circle, so keep the face centered.

| File | Prompt |
|---|---|
| `portrait_dex.png` | Dex leaning into camera, smug, explaining why he's not loud. |
| `portrait_brenda.png` | Brenda mid-sob but furious, clutching the hoodie. |
| `portrait_gary.png` | Gary sweating, obviously lying, finger raised to make a point. |
| `portrait_priya.png` | Priya calm and terrifying, holding up a sticky note. |
| `portrait_moose.png` | Moose with food on his face, totally innocent. |
| `portrait_luna.png` | Luna whispering a secret, tinfoil hat crooked. |

## Step 4 — Floors (seamless tiles)
Square PNG, **NOT transparent**, **seamless/tileable**, straight top-down. Keep them dark and low-contrast so the characters stand out.

| File | Prompt |
|---|---|
| `floor_living.png` | Seamless tileable dark muted green carpet texture with subtle stains. |
| `floor_kitchen.png` | Seamless tileable cheap brown-and-tan checkerboard linoleum, scuffed. |
| `floor_bathroom.png` | Seamless tileable teal square bathroom tiles, slightly grimy grout. |
| `floor_bedroom.png` | Seamless tileable dark purple-gray wood floorboards. |

## Step 5 — Furniture & objects (top-down)
Square PNG, transparent background, seen from directly above / slightly angled, same outline style.

| File | Prompt |
|---|---|
| `obj_bed.png` | A single bed from above, rumpled sheets, pillow at the top. Vertical orientation. |
| `obj_toilet.png` | A toilet from above, lid up. |
| `obj_shower.png` | A small square shower stall from above with a drain and shower head. |
| `obj_tub.png` | A bathtub from above, vertical orientation, a rubber duck inside. |
| `obj_fridge.png` | A beat-up fridge from above/front, covered in sticky notes. |
| `obj_stove.png` | A 4-burner stove top from above, one pan on it. |
| `obj_couch.png` | A long saggy 3-seat couch from above, horizontal orientation, maroon fabric, a pizza box on one cushion. |
| `obj_tv.png` | A flat TV on a low stand from above, wide horizontal shape. |
| `obj_speaker.png` | A giant tower speaker with neon lights, from above. |
| `obj_table.png` | A small kitchen table from above with a pizza and two mismatched chairs, horizontal. |
| `obj_plant.png` | A half-dead potted plant from above. |

## Step 6 — Effects

| File | Prompt |
|---|---|
| `fx_fire.png` | A single cartoon flame, transparent background, tall shape. |
| `fx_raccoon.png` | A mischievous cartoon raccoon seen from above, carrying a slice of pizza, transparent background. |
| `fx_note.png` | A single neon-pink music note, transparent background. |

## Step 7 — Logo & app icon

| File | Where it goes | Prompt |
|---|---|---|
| `logo.png` | `games/worst-roommates/assets/` | Title logo text "WORST ROOMMATES EVER" in a chunky cartoon font, yellow letters with a hot-pink drop shadow and black outline, a little fire and a raccoon tail peeking out, transparent background, wide horizontal (3:1). |
| `AppIcon.png` | `games/worst-roommates/ios/WorstRoommates/Assets.xcassets/AppIcon.appiconset/` (replace the placeholder, keep the name `AppIcon.png`) | App icon, 1024×1024, **no transparency, no text**: the six roommates crammed into a tiny doorway, all fighting to get into one bathroom, bold colors on a dark purple background. Fills the whole square. |

## Checklist
- [ ] File names match exactly (lowercase; `.png`, `.jpg` or `.webp`)
- [ ] Sprites and objects have transparent backgrounds
- [ ] Floors are seamless and NOT transparent
- [ ] App icon is 1024×1024 with no transparency (TestFlight rejects transparent icons)
