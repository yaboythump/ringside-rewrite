#!/bin/sh
# Builds the GBA test cart with stock clang + lld (no Nintendo SDK needed).
set -eu
cd "$(dirname "$0")"
(cd ../testcart-ds && python3 font.py)
clang --target=armv4t-none-eabi -marm -O2 -ffreestanding -fno-builtin -nostdlib -fno-pic -Wall -c cart.c -o cart.o
ld.lld -T link.ld -o cart.elf cart.o
llvm-objcopy -O binary cart.elf code.bin
python3 make_gba.py ../ios/RetroDuo/Resources/RetroDuoGBATestCart.gba
rm -f cart.o cart.elf code.bin
