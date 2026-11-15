# Ringside Combo art brief

This is the art list for ChatGPT image generation. Generate each image, save it with the
exact file name below, and put it in `games/ring-combo/assets/`. Then run
`python3 games/ring-combo/build.py`. Any image you skip keeps the current look, so you can
add art one piece at a time.

The wrestler portraits are shared with Card Clash and already exist. The arena and belt
fall back to the Card Clash images until you add your own.

## Paste this first

Paste this once at the start of the ChatGPT conversation so every image matches:

> I'm making art for a mobile wrestling match-3 game called Ringside Combo. All characters
> and promotions are fictional. Use one consistent style for every image I ask for: bold,
> glossy, slightly 3D game icons, like premium mobile-game art. Use strong silhouettes,
> thick clean shapes and dramatic arena lighting, with a palette of deep purple, ring-rope
> red, gold and electric blue. No text, letters, logos, watermarks, real people or real
> wrestling company branding unless I ask. Icons must read clearly at 48 pixels on a phone.

## Tile icons

Square PNG with a **transparent background**, 512×512, with the subject centred and
filling about 80% of the frame. The game puts each icon on its own coloured tile, so the
icon itself should not have a tile, frame or background.

| File | Tile colour behind it | Prompt |
|---|---|---|
| `strike.png` | red | A clenched fist punching forward with motion streaks and a small impact burst, wrapped in white athletic tape. Transparent background. |
| `grapple.png` | blue | Two muscular arms locked in a collar-and-elbow tie-up, seen from the side, with a hint of a wrestling singlet strap. Transparent background. |
| `kick.png` | green | A wrestling boot with a knee pad delivering a high kick, with a swoosh arc behind it. Transparent background. |
| `show.png` | gold | A gold star burst with a microphone in the centre and small sparkles around it, showboating energy. Transparent background. |
| `heal.png` | purple | A rolled athletic tape bandage and a water bottle, crossed, with a soft green glow. Transparent background. |

## Special tiles

Same format as the tile icons.

| File | Prompt |
|---|---|
| `fin.png` | A glowing finisher emblem: a fist wrapped in lightning and fire inside a spinning energy ring. Very bright and the most exciting icon of the set. Transparent background. |
| `chair.png` | A dented grey steel folding chair, slightly bent, with a metal glint. Transparent background. |
| `knux.png` | A pair of brass knuckles with a sinister red glow and a small warning spark. Transparent background. |

## Backgrounds

| File | Size | Prompt |
|---|---|---|
| `arena.jpg` | 1080×1920 portrait | A packed wrestling arena at night, seen from ringside. The ring is in the foreground with red ropes, there are spotlights and haze, and the crowd is a soft blur of camera flashes. Dark and moody, with the centre kept quieter because the game board sits on top. No text or logos. |
| `mat.jpg` | 1024×1024 square | A top-down close-up of a wrestling ring canvas: off-white canvas texture with light scuffs and boot marks, lit evenly. No logos or text. It must tile cleanly behind a 7×7 game board. |

## Title and trophy

| File | Size | Prompt |
|---|---|---|
| `logo.png` | 1200×400, transparent | A game logo that reads exactly "RINGSIDE COMBO". "RINGSIDE" is in chunky white letters with a purple outline, and "COMBO" is in metallic gold with a slight bevel. Add a subtle ring-rope swoosh underneath. Transparent background. |
| `belt.png` | 1200×800, transparent | A championship title belt laid flat: a large gold centre plate with a star and a fist emblem, red jewels and black leather straps. Make it fictional, with no real company names or logos. Transparent background. |

## Tips

- If ChatGPT gives you a white background instead of a transparent one, ask: "Make the
  background fully transparent and export as PNG."
- If an icon looks muddy when it's small, ask for "fewer details, thicker shapes, higher
  contrast".
- JPG, PNG and WebP all work. The file name before the dot is what matters (`strike.png`,
  `strike.webp` and so on).
- Keep each image under about 300 KB, because every image is packed into the one game page.
