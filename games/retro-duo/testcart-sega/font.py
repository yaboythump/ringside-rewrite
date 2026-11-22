"""The Retro Duo test carts' original 8x8 font, plus the few letters the Sega carts add."""
from pathlib import Path

_root = Path(__file__).resolve().parent.parent
_scope = {}
exec((_root / "testcart" / "make_tiles.py").read_text().split("def tile_bytes")[0], _scope)
_extra = (_root / "testcart-ds" / "font.py").read_text()
exec(_extra[_extra.index("EXTRA = {"):_extra.index("glyphs[\"GLYPHS\"]")], _scope)

GLYPHS = {**_scope["GLYPHS"], **_scope["EXTRA"], **{
    "G": ["..###...", ".#...#..", ".#......", ".#.###..", ".#...#..", ".#...#..", "..####..", "........"],
    "1": ["...#....", "..##....", "...#....", "...#....", "...#....", "...#....", "..###...", "........"],
    "2": ["..###...", ".#...#..", ".....#..", "....#...", "...#....", "..#.....", ".#####..", "........"],
    "X": [".#...#..", ".#...#..", "..#.#...", "...#....", "..#.#...", ".#...#..", ".#...#..", "........"],
    "Z": [".#####..", ".....#..", "....#...", "...#....", "..#.....", ".#......", ".#####..", "........"],
}}
CHARS = list(GLYPHS)  # tile number = index; tile 0 is the blank space


def tiles_4bpp_packed(colour=1):
    """Sega VDP (Genesis) tiles: 4 bits per pixel, packed, 32 bytes per tile."""
    out = bytearray()
    for rows in GLYPHS.values():
        for row in rows:
            value = 0
            for pixel in row:
                value = (value << 4) | (colour if pixel == "#" else 0)
            out += value.to_bytes(4, "big")
    return bytes(out)


def tiles_4bpp_planar(colour=1):
    """Master System / Game Gear tiles: 4 bit planes, one byte per plane per row."""
    out = bytearray()
    for rows in GLYPHS.values():
        for row in rows:
            bits = int(row.replace("#", "1").replace(".", "0"), 2)
            out += bytes(bits if colour >> plane & 1 else 0 for plane in range(4))
    return bytes(out)


def text(s):
    return [CHARS.index(c) for c in s]
