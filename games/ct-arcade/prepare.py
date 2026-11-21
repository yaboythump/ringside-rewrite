#!/usr/bin/env python3
"""Prepare pinned Apache-2.0 JSNES and generate an original CT ARCADE app icon.
Run before Xcode archive; the generated core is bundled with the app, never loaded from
a remote network at runtime. No game ROMs or BIOS files are downloaded or bundled.
"""
from pathlib import Path
import struct
import urllib.request
import zlib

ROOT = Path(__file__).resolve().parent
CORE = ROOT / "vendor" / "jsnes.js"
ICON = ROOT / "ios" / "CTArcade" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
CORE_URL = "https://cdn.jsdelivr.net/npm/jsnes@3.0.0/dist/jsnes.js"

def prepare_core():
    CORE.parent.mkdir(parents=True, exist_ok=True)
    if CORE.exists() and CORE.stat().st_size > 30000:
        return
    req = urllib.request.Request(CORE_URL, headers={"User-Agent": "CTArcadeBuild/0.1"})
    with urllib.request.urlopen(req, timeout=50) as stream:
        content = stream.read(3 * 1024 * 1024)
    if len(content) < 30000 or b"NES" not in content:
        raise RuntimeError("The pinned NES emulator bundle could not be verified")
    CORE.write_bytes(content)

def png_chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)

def prepare_icon():
    size = 1024
    def pixel(x,y):
        # Art deco cabinet, subtle brushed midnight/gold colors.
        bg = (10 + y//140, 15 + y//110, 32 + y//90)
        gold = (237, 192, 109)
        if 138 < x < 886 and 110 < y < 920 and 50 < x+y-190 and 50 < 1690-x-y:
            if 175 < x < 849 and 180 < y < 680:
                if 216 < x < 808 and 234 < y < 642:
                    if 252 < x < 770 and 270 < y < 603:
                        return (34, 70 + (x//100)%18, 109)
                    return (210, 179, 116)
                return (36, 47, 69)
            if 350 < x < 675 and 735 < y < 810: return gold
            if 250 < x < 770 and 850 < y < 872: return gold
            return (24, 35, 56)
        return bg
    # Render big pixel-art C T on the cabinet screen.
    bandsC = [(325,370,365,480),(325,375,480,550),(325,485,545,585)]
    bandsT = [(555,705,365,408),(605,658,408,585)]
    rows=[]
    for y in range(size):
        row=bytearray()
        for x in range(size):
            color=pixel(x,y)
            if any(x1<x<x2 and y1<y<y2 for x1,x2,y1,y2 in bandsC+bandsT):
                color=(246,209,133)
            row.extend(color)
        rows.append(bytes([0])+bytes(row))
    raw=zlib.compress(b"".join(rows),level=6)
    body=bytes([137,80,78,71,13,10,26,10])+png_chunk(b"IHDR",struct.pack(">IIBBBBB",size,size,8,2,0,0,0))+png_chunk(b"IDAT",raw)+png_chunk(b"IEND",b"")
    ICON.parent.mkdir(parents=True, exist_ok=True)
    ICON.write_bytes(body)
if __name__=="__main__":
    prepare_core()
    prepare_icon()
    print("CT ARCADE engine and app icon ready")
