#!/usr/bin/env python3
"""Generate an original opaque 1024x1024 Clutch Bets V2 App Store icon using stdlib only."""
from pathlib import Path
import json
import math
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "ios" / "Assets.xcassets" / "AppIcon.appiconset"
DEST.mkdir(parents=True, exist_ok=True)
SIZE = 1024

def inside(x, y, polygon):
    hit = False
    j = len(polygon) - 1
    for i in range(len(polygon)):
        xi, yi = polygon[i]
        xj, yj = polygon[j]
        if (yi > y) != (yj > y):
            bound = (xj - xi) * (y - yi) / (yj - yi) + xi
            if x < bound:
                hit = not hit
        j = i
    return hit

crown = [(210, 370), (350, 474), (512, 260), (674, 474), (814, 370), (765, 695), (259, 695)]
bar = [(254, 712), (770, 712), (787, 770), (237, 770)]
rows = []
for y in range(SIZE):
    row = bytearray([0])
    for x in range(SIZE):
        glow = max(0, 1 - math.hypot(x - 512, y - 420) / 710)
        r = int(8 + 18 * glow)
        g = int(12 + 19 * glow)
        b = int(21 + 24 * glow)
        if inside(x, y, crown) or inside(x, y, bar):
            shimmer = min(1, max(0, (850 - x) / 780))
            r = int(180 + 61 * shimmer)
            g = int(117 + 82 * shimmer)
            b = int(49 + 73 * shimmer)
        row.extend((r, g, b, 255))
    rows.append(bytes(row))
raw = b"".join(rows)

def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)

png = (b"\x89PNG\r\n\x1a\n" +
       chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)) +
       chunk(b"IDAT", zlib.compress(raw, 7)) +
       chunk(b"IEND", b""))
(DEST / "Icon-1024.png").write_bytes(png)
(DEST / "Contents.json").write_text(json.dumps({
    "images": [{"filename": "Icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
    "info": {"author": "xcode", "version": 1}
}, indent=2) + "\n")
print("Generated original Clutch Bets V2 app icon.")
