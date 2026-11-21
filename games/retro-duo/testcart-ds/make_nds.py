#!/usr/bin/env python3
"""Packs arm9.bin and arm7.bin into a minimal .nds file for direct boot (no Nintendo logo)."""
import struct, sys
from pathlib import Path

def crc16(data, crc=0xFFFF):
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = (crc >> 1) ^ 0xA001 if crc & 1 else crc >> 1
    return crc

here = Path(__file__).resolve().parent
arm9 = (here / "arm9.bin").read_bytes()
arm7 = (here / "arm7.bin").read_bytes()
pad = lambda b: b + bytes((-len(b)) % 0x200)
arm9, arm7 = pad(arm9), pad(arm7)
arm9_off = 0x200  # homebrew layout (below the retail secure area)
arm7_off = arm9_off + len(arm9)
total = arm7_off + len(arm7)
header = bytearray(0x200)
header[0x00:0x0C] = b"RETRODUODS\0\0"
header[0x0C:0x10] = b"HRDT"            # game code (homebrew-style)
header[0x10:0x12] = b"CT"              # maker code
header[0x14] = max(0, (total - 1).bit_length() - 17)  # device capacity
struct.pack_into("<IIII", header, 0x20, arm9_off, 0x02000000, 0x02000000, len(arm9))
struct.pack_into("<IIII", header, 0x30, arm7_off, 0x037F8000, 0x037F8000, len(arm7))
struct.pack_into("<I", header, 0x80, total)
struct.pack_into("<I", header, 0x84, 0x200)
struct.pack_into("<H", header, 0x15E, crc16(header[:0x15E]))
out = Path(sys.argv[1])
out.write_bytes(bytes(header) + arm9 + arm7)
print(f"{out.name}: {total} bytes")
