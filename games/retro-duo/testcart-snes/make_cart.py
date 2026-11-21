#!/usr/bin/env python3
"""Builds the Retro Duo SNES Test Cart, an original controls tester (32 KB LoROM).

Runs entirely in the 65816's 6502 emulation mode, so the NES cart's tiny assembler builds it.
D-pad moves the star (by scrolling its background layer), A/B/X/Y/L/R light up,
START changes the background colour, SELECT recentres. It has no sound.
Usage: python3 make_cart.py OUTPUT.sfc
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "testcart-nes"))
from asm6502 import Assembler  # noqa: E402

here = Path(__file__).resolve().parent
glyph_src = (here.parent / "testcart" / "make_tiles.py").read_text().split("def tile_bytes")[0]
scope = {}
exec(glyph_src, scope)
extra = (here.parent / "testcart-ds" / "font.py").read_text()
extra = extra[extra.index("EXTRA = {"):extra.index("glyphs[\"GLYPHS\"]")]
exec(extra, scope)
GLYPHS = {**scope["GLYPHS"], **scope["EXTRA"]}
CHARS = list(GLYPHS)


def text(s):
    return bytes(CHARS.index(c) for c in s) + b"\xFF"


def rgb(r, g, b):
    value = r | (g << 5) | (b << 10)
    return [value & 0xFF, value >> 8]


# 2bpp SNES tiles: each row is a word, low byte = plane 0, high byte = plane 1 (colour 3 = both).
font = bytearray()
for rows in GLYPHS.values():
    for row in rows:
        bits = int(row.replace("#", "1").replace(".", "0"), 2)
        font += bytes([bits, bits])
STAR = CHARS.index("*")

FRAME, PADLO, PADHI, PREVHI, PRESSED, SCX, SCY, PALETTE, PTR = 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x20

a = Assembler(0x8000)
a.label("reset")
a.sei(); a.cld()
a.ldx(0xFF, "imm"); a.txs()
a.lda(0x8F, "imm"); a.sta(0x2100)            # forced blank
a.lda(0, "imm"); a.sta(0x4200)
a.ldx(0x01, "imm")
a.label("ppuclear"); a.sta(0x2100, "x"); a.inx(); a.cpx(0x34, "imm"); a.bne("ppuclear")
for zp in (FRAME, PADLO, PADHI, PREVHI, PRESSED, SCX, SCY, PALETTE):
    a.sta(zp, "zp")

# Clear all of VRAM (32K words).
a.lda(0x80, "imm"); a.sta(0x2115)
a.lda(0, "imm"); a.sta(0x2116); a.sta(0x2117)
a.ldy(0x80, "imm"); a.ldx(0, "imm")
a.label("vclear"); a.sta(0x2118); a.sta(0x2119); a.inx(); a.bne("vclear"); a.dey(); a.bne("vclear")

# Font at VRAM word 0, copied through a zero-page pointer.
a.lda(0, "imm"); a.sta(0x2116); a.sta(0x2117)
a.lda("<font", "imm"); a.sta(PTR, "zp"); a.lda(">font", "imm"); a.sta(PTR + 1, "zp")
a.ldx((len(font) + 255) // 256, "imm")
a.ldy(0, "imm")
a.label("fontcopy"); a.lda(PTR, "indy"); a.sta(0x2118); a.iny(); a.lda(PTR, "indy"); a.sta(0x2119); a.iny()
a.bne("fontcopy"); a.inc(PTR + 1, "zp"); a.dex(); a.bne("fontcopy")

# Palettes: BG1 palette 0 (text white), 1 (lit pink), 2 (dim); BG2 palette 0 (gold star).
a.lda(0, "imm"); a.sta(0x2121)
a.ldx(0, "imm")
a.label("cg1"); a.lda("colors", "x"); a.sta(0x2122); a.inx(); a.cpx(24, "imm"); a.bne("cg1")
a.lda(32, "imm"); a.sta(0x2121)
a.ldx(0, "imm")
a.label("cg2"); a.lda("starcolors", "x"); a.sta(0x2122); a.inx(); a.cpx(8, "imm"); a.bne("cg2")

a.lda(0x00, "imm"); a.sta(0x2105)            # mode 0
a.lda(0x04, "imm"); a.sta(0x2107)            # BG1 map at word $0400
a.lda(0x08, "imm"); a.sta(0x2108)            # BG2 map at word $0800
a.lda(0x00, "imm"); a.sta(0x210B)            # both use tiles from word 0

strings = [(2, 4, "bar"), (5, 11, "title"), (7, 9, "cart"), (19, 6, "move"), (21, 6, "color"), (27, 4, "bar")]
for row, col, name in strings:
    address = 0x0400 + row * 32 + col
    a.lda(address & 0xFF, "imm"); a.sta(0x2116); a.lda(address >> 8, "imm"); a.sta(0x2117)
    a.ldx(0, "imm")
    a.label(f"put_{row}")
    a.lda(name, "x"); a.cmp(0xFF, "imm"); a.beq(f"done_{row}")
    a.sta(0x2118); a.lda(0, "imm"); a.sta(0x2119); a.inx(); a.bne(f"put_{row}")
    a.label(f"done_{row}")

star_address = 0x0800 + 13 * 32 + 15
a.lda(star_address & 0xFF, "imm"); a.sta(0x2116); a.lda(star_address >> 8, "imm"); a.sta(0x2117)
a.lda(STAR, "imm"); a.sta(0x2118); a.lda(0, "imm"); a.sta(0x2119)

a.lda(0x03, "imm"); a.sta(0x212C)            # BG1 + BG2 on the main screen
a.lda(0x81, "imm"); a.sta(0x4200)            # NMI + automatic joypad reading
a.lda(0x0F, "imm"); a.sta(0x2100)            # screen on, full brightness

a.label("main")
a.lda(FRAME, "zp")
a.label("wait"); a.cmp(FRAME, "zp"); a.beq("wait")
a.label("padwait"); a.lda(0x4212); a.and_(0x01, "imm"); a.bne("padwait")
a.lda(0x4218); a.sta(PADLO, "zp")
a.lda(0x4219); a.sta(PADHI, "zp")
a.lda(PREVHI, "zp"); a.eor(0xFF, "imm"); a.and_(PADHI, "zp"); a.sta(PRESSED, "zp")
a.lda(PADHI, "zp"); a.sta(PREVHI, "zp")

# Scrolling the star's layer the opposite way moves the star with the D-pad.
for bit, var, step in ((0x01, SCX, "dec"), (0x02, SCX, "inc"), (0x04, SCY, "dec"), (0x08, SCY, "inc")):
    a.lda(PADHI, "zp"); a.and_(bit, "imm"); a.beq(f"skip{bit}")
    getattr(a, step)(var, "zp"); getattr(a, step)(var, "zp")
    a.label(f"skip{bit}")
a.lda(PRESSED, "zp"); a.and_(0x20, "imm"); a.beq("noselect")
a.lda(0, "imm"); a.sta(SCX, "zp"); a.sta(SCY, "zp")
a.label("noselect")
a.lda(SCX, "zp"); a.sta(0x210F); a.lda(0, "imm"); a.sta(0x210F)
a.lda(SCY, "zp"); a.sta(0x2110); a.lda(0, "imm"); a.sta(0x2110)

a.lda(PRESSED, "zp"); a.and_(0x10, "imm"); a.beq("nostart")
a.inc(PALETTE, "zp"); a.lda(PALETTE, "zp"); a.and_(3, "imm"); a.sta(PALETTE, "zp")
a.asl(); a.tax()
a.lda(0, "imm"); a.sta(0x2121)
a.lda("backdrops", "x"); a.sta(0x2122); a.inx(); a.lda("backdrops", "x"); a.sta(0x2122)
a.label("nostart")

# Button lights: A B X Y L R on row 24, pink when held.
lights = [("A", PADLO, 0x80), ("B", PADHI, 0x80), ("X", PADLO, 0x40), ("Y", PADHI, 0x40), ("L", PADLO, 0x20), ("R", PADLO, 0x10)]
address = 0x0400 + 24 * 32 + 10
a.lda(address & 0xFF, "imm"); a.sta(0x2116); a.lda(address >> 8, "imm"); a.sta(0x2117)
for letter, var, bit in lights:
    a.lda(CHARS.index(letter), "imm"); a.sta(0x2118)
    a.lda(var, "zp"); a.and_(bit, "imm"); a.beq(f"dim_{letter}")
    a.lda(0x04, "imm"); a.sta(0x2119); a.jmp(f"next_{letter}")      # palette 1
    a.label(f"dim_{letter}"); a.lda(0x08, "imm"); a.sta(0x2119)       # palette 2
    a.label(f"next_{letter}")
    a.lda(0, "imm"); a.sta(0x2118); a.sta(0x2119)                      # gap
a.jmp("main")

a.label("nmi"); a.pha(); a.lda(0x4210); a.inc(FRAME, "zp"); a.pla(); a.rti()
a.label("irq"); a.rti()

a.label("colors")
a.db(*rgb(2, 3, 9), *rgb(6, 8, 18), *rgb(14, 16, 26), *rgb(31, 31, 31),     # palette 0
     *rgb(2, 3, 9), *rgb(0, 0, 0), *rgb(0, 0, 0), *rgb(31, 9, 13),         # palette 1: lit
     *rgb(2, 3, 9), *rgb(0, 0, 0), *rgb(0, 0, 0), *rgb(8, 10, 18))         # palette 2: dim
a.label("starcolors"); a.db(*rgb(0, 0, 0), *rgb(31, 26, 4), *rgb(31, 20, 4), *rgb(31, 25, 6))
a.label("backdrops"); a.db(*rgb(2, 3, 9), *rgb(3, 9, 4), *rgb(12, 3, 4), *rgb(8, 2, 12))
a.label("bar"); a.db(*text("=" * 24))
a.label("title"); a.db(*text("RETRO DUO"))
a.label("cart"); a.db(*text("SNES TEST CART"))
a.label("move"); a.db(*text("D-PAD  MOVE STAR"))
a.label("color"); a.db(*text("START  COLOR"))
a.label("font")
a.db(*font)

code = a.assemble()

rom = bytearray([0xFF] * 0x8000)
rom[: len(code)] = code
assert len(code) < 0x7FB0, len(code)
title = b"RETRO DUO SNES TEST  "
rom[0x7FC0:0x7FD5] = title
rom[0x7FD5] = 0x20   # LoROM
rom[0x7FD6] = 0x00   # ROM only
rom[0x7FD7] = 0x05   # 32 KB
rom[0x7FD8] = 0x00   # no save RAM
rom[0x7FD9] = 0x01   # North America
rom[0x7FDA] = 0x00
rom[0x7FDB] = 0x00
vectors = {0x7FEA: "nmi", 0x7FEE: "irq", 0x7FFA: "nmi", 0x7FFC: "reset", 0x7FFE: "irq",
           0x7FE4: "irq", 0x7FE6: "irq", 0x7FE8: "irq", 0x7FF4: "irq", 0x7FF8: "irq"}
for offset, name in vectors.items():
    rom[offset:offset + 2] = a.labels[name].to_bytes(2, "little")
rom[0x7FDC:0x7FE0] = b"\xFF\xFF\x00\x00"
checksum = sum(rom) & 0xFFFF
rom[0x7FDC:0x7FDE] = (checksum ^ 0xFFFF).to_bytes(2, "little")
rom[0x7FDE:0x7FE0] = checksum.to_bytes(2, "little")
Path(sys.argv[1]).write_bytes(rom)
print(f"{Path(sys.argv[1]).name}: {len(code)} bytes of code")
