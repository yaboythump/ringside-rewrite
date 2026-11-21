#!/bin/sh
# Rebuilds the bundled test cart. Needs RGBDS 0.9 (rgbasm, rgblink, rgbfix) on PATH.
set -eu
cd "$(dirname "$0")"
python3 make_tiles.py
rgbasm -o testcart.o testcart.asm
rgblink -o testcart.gbc testcart.o
rgbfix -v -c -t "RETRO DUO" -l 0x33 -k "CT" -m 0x00 -r 0x00 -p 0xFF testcart.gbc
rm -f testcart.o
mv testcart.gbc ../ios/RetroDuo/Resources/RetroDuoTestCart.gbc
