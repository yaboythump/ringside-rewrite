#!/usr/bin/env python3
"""Builds a tiny original 256 KB "ROM" for the headless core test.

It is not Apple code: just a valid Mac II-style ROM header (checksum and
reset vector) and a few 68020 instructions that fill the video card's
memory with a known pattern, so the test can see the CPU, the memory map
and the picture path all working without a real Macintosh ROM.
"""
import struct
import sys

SIZE = 0x40000
BASE = 0x40800000  # where a Mac II maps its ROM
START = 0x100

rom = bytearray(SIZE)
code = bytes.fromhex(
    "41F9F9900000"  # lea     $F9900000,a0   (video card RAM, slot 9)
    "203C12345678"  # move.l  #$12345678,d0
    "20C0"          # loop: move.l d0,(a0)+
    "B1FCF9910000"  # cmpa.l  #$F9910000,a0
    "66F6"          # bne.s   loop
    "60FE"          # bra.s   *               (park)
)
rom[START:START + len(code)] = code
struct.pack_into(">I", rom, 4, BASE + START)  # reset PC
rom[0x1000:0x1010] = b"MacDuoTestROM\0\0\0"

checksum = 0
for i in range(4, SIZE, 2):
    checksum = (checksum + (rom[i] << 8 | rom[i + 1])) & 0xFFFFFFFF
struct.pack_into(">I", rom, 0, checksum)  # also the initial stack pointer

with open(sys.argv[1], "wb") as f:
    f.write(rom)
print(f"test ROM checksum {checksum:08X}")
