#!/usr/bin/env python3
"""Builds the Retro Duo NES Test Cart, an original button and sound tester (NROM, 16 KB + 8 KB).

D-pad moves the star, A and B beep, START changes colours, SELECT recentres.
Usage: python3 make_cart.py OUTPUT.nes
"""
import sys
from pathlib import Path

from asm6502 import Assembler

here = Path(__file__).resolve().parent
glyph_src = (here.parent / "testcart" / "make_tiles.py").read_text().split("def tile_bytes")[0]
scope = {}
exec(glyph_src, scope)
GLYPHS = scope["GLYPHS"]
CHARS = list(GLYPHS)


def text(s):
    return bytes(CHARS.index(c) for c in s) + b"\xFF"


# --- CHR ROM: font in pattern table 0 (colour 3), star sprite (colour 1) -------------
chr_rom = bytearray(8192)
for index, rows in enumerate(GLYPHS.values()):
    bits = [int(r.replace("#", "1").replace(".", "0"), 2) for r in rows]
    plane1 = bits if rows is not GLYPHS["*"] else [0] * 8
    chr_rom[index * 16: index * 16 + 8] = bytes(bits)
    chr_rom[index * 16 + 8: index * 16 + 16] = bytes(plane1)
STAR = CHARS.index("*")

# Zero-page variables
FRAME, PAD, PREV, PRESSED, PALETTE, STAR_Y, STAR_X = 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16
OAM = 0x0200

a = Assembler(0xC000)
a.label("reset")
a.sei(); a.cld()
a.ldx(0x40, "imm"); a.stx(0x4017)
a.ldx(0xFF, "imm"); a.txs()
a.inx(); a.stx(0x2000); a.stx(0x2001); a.stx(0x4010)
a.bit(0x2002)
a.label("vblank1"); a.bit(0x2002); a.bpl("vblank1")
# Clear RAM; park every sprite off screen.
a.lda(0, "imm")
a.label("clear")
for page in (0x000, 0x100, 0x300, 0x400, 0x500, 0x600, 0x700):
    a.sta(page, "x")
a.lda(0xFF, "imm"); a.sta(OAM, "x"); a.lda(0, "imm")
a.inx(); a.bne("clear")
a.label("vblank2"); a.bit(0x2002); a.bpl("vblank2")

# Palettes
a.lda(0x2002); a.lda(0x3F, "imm"); a.sta(0x2006); a.lda(0, "imm"); a.sta(0x2006)
a.ldx(0, "imm")
a.label("palette"); a.lda("palettes", "x"); a.sta(0x2007); a.inx(); a.cpx(32, "imm"); a.bne("palette")

# Clear the first nametable and its attributes (1 KB of tile 0 = space).
a.lda(0x20, "imm"); a.sta(0x2006); a.lda(0, "imm"); a.sta(0x2006)
a.ldy(4, "imm"); a.ldx(0, "imm")
a.label("clearnt"); a.sta(0x2007); a.dex(); a.bne("clearnt"); a.dey(); a.bne("clearnt")

strings = [  # (row, column, label)
    (3, 4, "bar"), (6, 11, "title"), (8, 10, "cart"), (19, 6, "move"), (21, 6, "beep"), (23, 6, "color"), (26, 4, "bar"),
]
for row, col, name in strings:
    address = 0x2000 + row * 32 + col
    a.lda(address >> 8, "imm"); a.sta(0x2006); a.lda(address & 0xFF, "imm"); a.sta(0x2006)
    a.ldx(0, "imm")
    a.label(f"put_{row}")
    a.lda(name, "x"); a.cmp(0xFF, "imm"); a.beq(f"done_{row}"); a.sta(0x2007); a.inx(); a.bne(f"put_{row}")
    a.label(f"done_{row}")

a.jsr("recentre")
a.lda(STAR, "imm"); a.sta(OAM + 1)
a.lda(0, "imm"); a.sta(OAM + 2)
a.lda(0x0F, "imm"); a.sta(0x4015)            # sound channels on
a.lda(0, "imm"); a.sta(0x2005); a.sta(0x2005)
a.lda(0x80, "imm"); a.sta(0x2000)            # NMI on, all tiles from pattern table 0
a.lda(0x1E, "imm"); a.sta(0x2001)            # show background and sprites, no left-edge mask

a.label("main")
a.lda(FRAME, "zp")
a.label("wait"); a.cmp(FRAME, "zp"); a.beq("wait")
a.lda(STAR_Y, "zp"); a.sta(OAM + 0)
a.lda(STAR_X, "zp"); a.sta(OAM + 3)
a.lda(0, "imm"); a.sta(0x2003); a.lda(OAM >> 8, "imm"); a.sta(0x4014)   # sprite DMA
# Read the pad: after 8 shifts, A is bit 7 ... Right is bit 0.
a.lda(1, "imm"); a.sta(0x4016); a.lda(0, "imm"); a.sta(0x4016)
a.ldx(8, "imm")
a.label("readpad"); a.lda(0x4016); a.lsr(); a.rol(PAD, "zp"); a.dex(); a.bne("readpad")
a.lda(PREV, "zp"); a.eor(0xFF, "imm"); a.and_(PAD, "zp")
a.sta(PRESSED, "zp")
a.lda(PAD, "zp"); a.sta(PREV, "zp")

for bit, var, step in ((0x01, STAR_X, "inc"), (0x02, STAR_X, "dec"), (0x04, STAR_Y, "inc"), (0x08, STAR_Y, "dec")):
    a.lda(PAD, "zp"); a.and_(bit, "imm"); a.beq(f"skip{bit}")
    getattr(a, step)(var, "zp")
    a.label(f"skip{bit}")

a.lda(PRESSED, "zp"); a.and_(0x80, "imm"); a.beq("noA")
a.lda(0x9F, "imm"); a.sta(0x4000); a.lda(0, "imm"); a.sta(0x4001)
a.lda(0x7E, "imm"); a.sta(0x4002); a.lda(0x10, "imm"); a.sta(0x4003)     # ~880 Hz, short
a.label("noA")
a.lda(PRESSED, "zp"); a.and_(0x40, "imm"); a.beq("noB")
a.lda(0x9F, "imm"); a.sta(0x4004); a.lda(0, "imm"); a.sta(0x4005)
a.lda(0xFD, "imm"); a.sta(0x4006); a.lda(0x10, "imm"); a.sta(0x4007)     # ~440 Hz, short
a.label("noB")
a.lda(PRESSED, "zp"); a.and_(0x20, "imm"); a.beq("noSelect")
a.jsr("recentre")
a.label("noSelect")
a.lda(PRESSED, "zp"); a.and_(0x10, "imm"); a.beq("noStart")
a.inc(PALETTE, "zp"); a.lda(PALETTE, "zp"); a.and_(3, "imm"); a.sta(PALETTE, "zp")
a.asl(); a.tax()                                    # 2 bytes per colour pair
a.lda(0x3F, "imm"); a.sta(0x2006); a.lda(0x00, "imm"); a.sta(0x2006)
a.lda("bgcolors", "x"); a.sta(0x2007)
a.lda(0x3F, "imm"); a.sta(0x2006); a.lda(0x03, "imm"); a.sta(0x2006)
a.inx(); a.lda("bgcolors", "x"); a.sta(0x2007)
a.label("noStart")
a.lda(0, "imm"); a.sta(0x2005); a.sta(0x2005); a.lda(0x80, "imm"); a.sta(0x2000)
a.jmp("main")

a.label("recentre")
a.lda(116, "imm"); a.sta(STAR_Y, "zp"); a.lda(124, "imm"); a.sta(STAR_X, "zp"); a.rts()

a.label("nmi"); a.inc(FRAME, "zp"); a.rti()
a.label("irq"); a.rti()

a.label("palettes")
a.db(0x01, 0x11, 0x21, 0x30,  0x01, 0x11, 0x21, 0x30,  0x01, 0x11, 0x21, 0x30,  0x01, 0x11, 0x21, 0x30,
     0x01, 0x28, 0x27, 0x16,  0x01, 0x28, 0x27, 0x16,  0x01, 0x28, 0x27, 0x16,  0x01, 0x28, 0x27, 0x16)
a.label("bgcolors")
a.db(0x01, 0x30,  0x09, 0x2A,  0x06, 0x37,  0x04, 0x38)   # navy/white, green, red/cream, purple/gold
a.label("bar"); a.db(*text("=" * 24))
a.label("title"); a.db(*text("RETRO DUO"))
a.label("cart"); a.db(*text("NES TEST CART"))
a.label("move"); a.db(*text("D-PAD  MOVE STAR"))
a.label("beep"); a.db(*text("A  B   BEEP"))
a.label("color"); a.db(*text("START  COLOR"))

code = a.assemble()
prg = bytearray([0xFF] * 16384)
prg[: len(code)] = code
assert len(code) < 16384 - 6
prg[0x3FFA:0x4000] = b"".join(a.labels[n].to_bytes(2, "little") for n in ("nmi", "reset", "irq"))
header = b"NES\x1a" + bytes([1, 1, 0x00, 0x00]) + bytes(8)   # 1x16 KB PRG, 1x8 KB CHR, mapper 0
out = Path(sys.argv[1])
out.write_bytes(header + prg + chr_rom)
print(f"{out.name}: {len(code)} bytes of code")
