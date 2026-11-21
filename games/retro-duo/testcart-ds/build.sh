#!/bin/sh
# Builds the DS test cart with stock clang + lld (no Nintendo SDK needed).
set -eu
cd "$(dirname "$0")"
python3 font.py
FLAGS="-O2 -ffreestanding -fno-builtin -nostdlib -fno-pic -Wall"
clang --target=armv5te-none-eabi -marm $FLAGS -c arm9.c -o arm9.o
clang --target=armv4t-none-eabi -marm $FLAGS -c arm7.c -o arm7.o
ld.lld -T link9.ld -o arm9.elf arm9.o
ld.lld -T link7.ld -o arm7.elf arm7.o
llvm-objcopy -O binary arm9.elf arm9.bin
llvm-objcopy -O binary arm7.elf arm7.bin
python3 make_nds.py ../ios/RetroDuo/Resources/RetroDuoDSTestCart.nds
rm -f arm9.o arm7.o arm9.elf arm7.elf arm9.bin arm7.bin
