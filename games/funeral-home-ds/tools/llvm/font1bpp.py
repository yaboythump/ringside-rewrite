#!/usr/bin/env python3
"""Turns libnds' default_font.png into the 1bpp tiles grit would make (for libnds' console.c)."""
import sys
from PIL import Image

img = Image.open(sys.argv[1]).convert("RGB")
w, h = img.size
data = bytearray()
for ty in range(h // 8):
    for tx in range(w // 8):
        for y in range(8):
            b = 0
            for x in range(8):
                if img.getpixel((tx * 8 + x, ty * 8 + y)) != (0, 0, 0):
                    b |= 1 << x
            data.append(b)
words = [int.from_bytes(data[i:i + 4], "little") for i in range(0, len(data), 4)]
with open(sys.argv[2] + "/default_font.h", "w") as f:
    f.write("#pragma once\n#define default_fontTilesLen %d\nextern const unsigned int default_fontTiles[%d];\n" % (len(data), len(words)))
with open(sys.argv[2] + "/default_font.c", "w") as f:
    f.write("const unsigned int default_fontTiles[%d] __attribute__((aligned(4))) = {\n" % len(words))
    f.write(",\n".join("0x%08X" % v for v in words) + "\n};\n")
