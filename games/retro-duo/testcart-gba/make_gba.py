#!/usr/bin/env python3
"""Wraps code.bin (linked at 0x080000C0) in a GBA cartridge header."""
import struct, sys
from pathlib import Path
code = (Path(__file__).resolve().parent / "code.bin").read_bytes()
header = bytearray(0xC0)
struct.pack_into("<I", header, 0, 0xEA000000 | ((0xC0 - 8) // 4))   # b 0x080000C0
header[0xA0:0xAC] = b"RETRODUOGBA\0"
header[0xAC:0xB0] = b"BRDE"
header[0xB0:0xB2] = b"CT"
header[0xB2] = 0x96
header[0xBD] = (-(sum(header[0xA0:0xBD]) + 0x19)) & 0xFF            # header complement
rom = bytes(header) + code
rom += bytes((-len(rom)) % 0x1000)
Path(sys.argv[1]).write_bytes(rom)
print(f"{Path(sys.argv[1]).name}: {len(rom)} bytes")
