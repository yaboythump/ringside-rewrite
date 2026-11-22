#!/usr/bin/env python3
"""Builds the Retro Duo Master System and Game Gear Test Carts (original, 32 KB each).

One Z80 program for both: the D-pad moves the star (a sprite), buttons 1 and 2 light up,
PAUSE (Master System) or START (Game Gear) changes the background colour.
Usage: python3 make_sms.py OUTPUT.sms   or   python3 make_sms.py --gg OUTPUT.gg
"""
import sys
from pathlib import Path

here = Path(__file__).resolve().parent
sys.path.insert(0, str(here))
import font  # noqa: E402
from z80asm import Z80  # noqa: E402

gg = "--gg" in sys.argv
output = Path([arg for arg in sys.argv[1:] if not arg.startswith("--")][0])

COPY_B = len(font.CHARS)  # second font copy, drawn in colour 2 (button lights)
STAR = font.CHARS.index("*")
PAD, PREV, PAUSED, STARX, STARY, COLOUR = 0xC000, 0xC001, 0xC002, 0xC003, 0xC004, 0xC005
VDP_DATA, VDP_CTRL = 0xBE, 0xBF


def rgb(r, g, b):
    """Colour from 0..15 per channel: GG has 4 bits per channel, the Master System 2."""
    if gg:
        value = r | g << 4 | b << 8
        return [value & 0xFF, value >> 8]
    return [r >> 2 | (g >> 2) << 2 | (b >> 2) << 4]


BACKGROUNDS = [rgb(1, 2, 6), rgb(1, 6, 2), rgb(7, 1, 1), rgb(5, 1, 7)]
palette = []
palette += BACKGROUNDS[0] + rgb(15, 15, 15) + rgb(5, 6, 10) + rgb(0, 0, 0)   # tiles: bg, white, dim
palette += rgb(0, 0, 0) * 12
palette += rgb(0, 0, 0) + rgb(15, 13, 2) + rgb(15, 5, 7) + rgb(0, 0, 0)      # sprites: -, gold, pink
palette += rgb(0, 0, 0) * 12

# GG shows only the middle 20x18 tiles (columns 6-25, rows 3-20) of the 32x24 screen.
if gg:
    strings = [(4, 6, "=" * 20), (6, 11, "RETRO DUO"), (8, 11, "GAME GEAR"), (14, 7, "D-PAD  MOVE"),
               (16, 7, "START  COLOR"), (19, 6, "=" * 20)]
    lights_at = (18, 14)
    centre = (124, 92)
else:
    strings = [(2, 4, "=" * 24), (5, 11, "RETRO DUO"), (7, 9, "MASTER SYSTEM"), (17, 6, "D-PAD  MOVE STAR"),
               (19, 6, "PAUSE  COLOR"), (22, 4, "=" * 24)]
    lights_at = (21, 14)
    centre = (124, 92)


def vram_address(a, address, write=True):
    a.ld_a_n(address & 0xFF); a.out_n_a(VDP_CTRL)
    a.ld_a_n((address >> 8) | (0x40 if write else 0)); a.out_n_a(VDP_CTRL)


a = Z80(0)
a.di(); a.im1(); a.jp("main")
a.org(0x38); a.reti()                                   # interrupts stay off
a.org(0x66)                                             # NMI = the Master System's PAUSE button
a.push_af(); a.ld_a_n(1); a.ld_mem_a(PAUSED); a.pop_af(); a.retn()

a.label("main")
a.ld_sp_nn(0xDFF0)
a.in_a_n(VDP_CTRL)                                      # clear a pending status
a.ld_hl_nn("vdp_registers"); a.ld_b_n(22); a.ld_c_n(VDP_CTRL); a.otir()

vram_address(a, 0)                                      # clear all 16 KB of VRAM
a.ld_bc_nn(0x4000)
a.label("clear"); a.xor_a(); a.out_n_a(VDP_DATA); a.dec_bc(); a.ld_a_b(); a.or_c(); a.jr_nz("clear")

vram_address(a, 0)                                      # both font copies
a.ld_hl_nn("font"); a.ld_bc_nn(len(font.CHARS) * 64)
a.label("fontcopy"); a.ld_a_hl(); a.out_n_a(VDP_DATA); a.inc_hl(); a.dec_bc(); a.ld_a_b(); a.or_c(); a.jr_nz("fontcopy")

a.xor_a(); a.out_n_a(VDP_CTRL); a.ld_a_n(0xC0); a.out_n_a(VDP_CTRL)   # palette
a.ld_hl_nn("palette"); a.ld_b_n(len(palette)); a.ld_c_n(VDP_DATA); a.otir()

# Text: each entry is a VRAM address (2 bytes) then tile numbers, ending in 0xFF; address 0 ends it.
a.ld_hl_nn("texts")
a.label("nexttext")
a.ld_a_hl(); a.ld_e_a(); a.inc_hl(); a.ld_a_hl(); a.ld_d_a(); a.inc_hl()
a.ld_a_d(); a.cp_n(0); a.jr_z("textsdone")
a.ld_a_e(); a.out_n_a(VDP_CTRL); a.ld_a_d(); a.out_n_a(VDP_CTRL)
a.label("textchar")
a.ld_a_hl(); a.inc_hl(); a.cp_n(0xFF); a.jr_z("nexttext")
a.out_n_a(VDP_DATA); a.xor_a(); a.out_n_a(VDP_DATA); a.jr("textchar")
a.label("textsdone")

a.ld_a_n(centre[0]); a.ld_mem_a(STARX); a.ld_a_n(centre[1]); a.ld_mem_a(STARY)
a.xor_a(); a.ld_mem_a(PAD); a.ld_mem_a(PREV); a.ld_mem_a(PAUSED); a.ld_mem_a(COLOUR)
a.ld_a_n(0xC0); a.out_n_a(VDP_CTRL); a.ld_a_n(0x81); a.out_n_a(VDP_CTRL)  # display on

a.label("frame")
a.label("vblank"); a.in_a_n(VDP_CTRL); a.and_n(0x80); a.jr_z("vblank")

# Sprite 0 = the star, then the end-of-list marker.
vram_address(a, 0x3F00)
a.ld_a_mem(STARY); a.out_n_a(VDP_DATA); a.ld_a_n(0xD0); a.out_n_a(VDP_DATA)
vram_address(a, 0x3F80)
a.ld_a_mem(STARX); a.out_n_a(VDP_DATA); a.ld_a_n(STAR); a.out_n_a(VDP_DATA)

# Button lights "1" and "2": the dim font copy, in the sprite palette (pink) while held.
vram_address(a, 0x3800 + (lights_at[0] * 32 + lights_at[1]) * 2)
for bit, char in ((0x10, "1"), (0x20, "2")):
    a.ld_a_n(COPY_B + font.CHARS.index(char)); a.out_n_a(VDP_DATA)
    a.ld_a_mem(PAD); a.and_n(bit); a.jr_z(f"dim{char}")
    a.ld_a_n(0x08); a.jr(f"attr{char}")
    a.label(f"dim{char}"); a.xor_a()
    a.label(f"attr{char}"); a.out_n_a(VDP_DATA)
    a.xor_a(); a.out_n_a(VDP_DATA); a.out_n_a(VDP_DATA)  # gap

# Read the pad (active low): bit 0 up, 1 down, 2 left, 3 right, 4 button 1, 5 button 2.
a.ld_a_mem(PAD); a.ld_mem_a(PREV)
a.in_a_n(0xDC); a.cpl(); a.and_n(0x3F); a.ld_b_a()
if gg:
    a.in_a_n(0x00); a.cpl(); a.and_n(0x80); a.ld_c_a(); a.ld_a_b(); a.or_c(); a.ld_b_a()  # START = bit 7
a.ld_a_b(); a.ld_mem_a(PAD)

for bit, var, step in ((0x08, STARX, 2), (0x04, STARX, -2), (0x02, STARY, 2), (0x01, STARY, -2)):
    a.ld_a_mem(PAD); a.and_n(bit); a.jr_z(f"nomove{bit}")
    a.ld_a_mem(var); a.add_a_n(step & 0xFF); a.ld_mem_a(var)
    a.label(f"nomove{bit}")

# Background colour: on a START press (GG) or after PAUSE (Master System NMI).
if gg:
    a.ld_a_mem(PREV); a.cpl(); a.ld_c_a(); a.ld_a_mem(PAD); a.and_c(); a.and_n(0x80); a.jr_z("nocolour")
else:
    a.ld_a_mem(PAUSED); a.cp_n(0); a.jr_z("nocolour")
    a.xor_a(); a.ld_mem_a(PAUSED)
a.ld_a_mem(COLOUR); a.inc_a(); a.and_n(3); a.ld_mem_a(COLOUR)
a.xor_a(); a.out_n_a(VDP_CTRL); a.ld_a_n(0xC0); a.out_n_a(VDP_CTRL)
a.ld_a_mem(COLOUR)
if gg:
    a.rlca()  # two bytes per colour
a.ld_c_a(); a.ld_b_n(0); a.ld_hl_nn("backgrounds")
# hl += bc
a.ld_a_c(); a.cp_n(0); a.jr_z("bgready")
a.label("bgstep"); a.inc_hl(); a.dec_bc(); a.ld_a_b(); a.or_c(); a.jr_nz("bgstep")
a.label("bgready")
a.ld_b_n(2 if gg else 1); a.ld_c_n(VDP_DATA); a.otir()
a.label("nocolour")
a.jp("frame")

# Data -----------------------------------------------------------------------------------------
regs = [0x04, 0x80, 0x80, 0x81, 0xFF, 0x82, 0xFF, 0x83, 0xFF, 0x84, 0xFF, 0x85, 0xFB, 0x86,
        0x00, 0x87, 0x00, 0x88, 0x00, 0x89, 0xFF, 0x8A]
a.label("vdp_registers"); a.db(*regs)
a.label("palette"); a.db(*palette)
a.label("backgrounds"); a.db(*[byte for colour in BACKGROUNDS for byte in colour])
a.label("texts")
for row, column, s in strings:
    address = 0x3800 + (row * 32 + column) * 2
    a.db(address & 0xFF, (address >> 8) | 0x40, *font.text(s), 0xFF)
a.db(0, 0)
a.label("font"); a.db(*font.tiles_4bpp_planar(1), *font.tiles_4bpp_planar(2))

code = a.assemble()
assert len(code) < 0x7FF0, len(code)
rom = bytearray(0x8000)
rom[:len(code)] = code
rom[0x7FF0:0x7FF8] = b"TMR SEGA"
checksum = sum(rom[:0x7FF0]) & 0xFFFF
rom[0x7FFA:0x7FFC] = checksum.to_bytes(2, "little")
rom[0x7FFC:0x7FFF] = bytes([0x26, 0x70, 0x00])  # product code / version
rom[0x7FFF] = (0x70 if gg else 0x40) | 0x0C     # region (GG export / SMS export), 32 KB
output.write_bytes(rom)
print(f"{output.name}: {len(code)} bytes of code")
