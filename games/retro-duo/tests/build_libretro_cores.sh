#!/bin/sh
# Builds the app's libretro cores for this machine, exactly as Xcode compiles them (same units,
# same prefix header): bsnes (SNES) into OUT/snes-obj, BlastEm (Sega) into OUT/sega-obj, and the
# host into OUT/host-obj. Objects newer than their source are reused.
set -eu
cd "$(dirname "$0")/.."
out="$1"
mkdir -p "$out/snes-obj" "$out/sega-obj" "$out/host-obj"
CC="${CC:-cc}"
CXX="${CXX:-c++}"
jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
PREFIX="-include ios/RetroDuo/Core/SameBoyConfig.h"
SNES_INC="-Ivendor/bsnes -Ivendor/bsnes/bsnes -Ivendor/bsnes/bsnes/gb -Ivendor/bsnes/bsnes/sfc -Iios/RetroDuo/SNESCore -Iios/RetroDuo/Libretro"
SEGA_INC="-Iios/RetroDuo/SegaCore -Iios/RetroDuo/SegaCore/generated -Ivendor/blastem -Ivendor/blastem/zlib -Ivendor/blastem/libchdr/include -Ivendor/blastem/libchdr -Ivendor/blastem/lzma -Iios/RetroDuo/Libretro"

python3 tools/generate_blastem.py

list="$out/compile-list.txt"
: > "$list"
add() { # objdir source [also-depends-on]
  o="$out/$1/$(basename "$2").o"
  case "$1" in sega-obj) config=ios/RetroDuo/SegaCore/SegaConfig.h;; snes-obj) config=ios/RetroDuo/SNESCore/SNESConfig.h;; *) config="$2";; esac
  # A unit is just two #includes: it is out of date when the real source it pulls in changes.
  real="${3:-}"
  if [ -z "$real" ]; then
    inc=$(sed -n 's/^#include "\(\.\..*\)"$/\1/p' "$2")
    real="${inc:+$(dirname "$2")/$inc}"
    real="${real:-$2}"
  fi
  if [ -f "$o" ] && [ "$o" -nt "$2" ] && [ "$o" -nt "$real" ] && [ "$o" -nt "$config" ]; then return 0; fi
  case "$1:$2" in
    snes-obj:*.cpp) echo "$CXX $PREFIX -std=gnu++17 -O2 -w -fno-strict-aliasing -fwrapv $SNES_INC -c $2 -o $o" ;;
    snes-obj:*) echo "$CC $PREFIX -std=gnu11 -O2 -w -D_GNU_SOURCE $SNES_INC -c $2 -o $o" ;;
    sega-obj:*) echo "$CC $PREFIX -std=gnu11 -O2 -w -fwrapv $SEGA_INC -c $2 -o $o" ;;
    host-obj:*) echo "$CC $PREFIX -std=gnu11 -O2 -w $SNES_INC -c $2 -o $o" ;;
  esac >> "$list"
}
gen=ios/RetroDuo/SegaCore/generated
units=ios/RetroDuo/SegaCore/units
# Biggest first: the generated 68000 core alone takes minutes. Generated cores are included by
# their units, so a unit is rebuilt when its generated file changes.
for cpu in m68k sh2 z80 upd78k2; do add sega-obj "$units/blastem_generated_$cpu.c" "$gen/$cpu.c"; done
for f in ios/RetroDuo/SNESCore/units/*.c ios/RetroDuo/SNESCore/units/*.cpp ios/RetroDuo/SNESCore/RDLibco.c ios/RetroDuo/SNESCore/SNESCoreTable.c; do add snes-obj "$f"; done
for f in "$units"/*.c ios/RetroDuo/SegaCore/SegaCoreTable.c; do
  case "$f" in *_generated_m68k.c|*_generated_sh2.c|*_generated_z80.c|*_generated_upd78k2.c) ;; *) add sega-obj "$f";; esac
done
add host-obj ios/RetroDuo/Libretro/RDLibretro.c
echo "compiling $(wc -l < "$list") files"
tr '\n' '\0' < "$list" | xargs -0 -r -P "$jobs" -n 1 sh -c

# Nothing may escape un-renamed: libretro functions, bsnes's Game Boy core, or any BlastEm global.
bad=$(nm -g --defined-only "$out"/snes-obj/*.o "$out"/sega-obj/*.o | awk 'NF==3 {print $3}' | \
  grep -E '^_?(retro_|GB_)' || true)
if [ -n "$bad" ]; then echo "$bad"; echo "FAIL un-renamed core symbols above"; exit 1; fi
# (zlib's gzgetc is #undef'd by zlib itself, so no rename macro can reach it; nothing else defines it.)
bad=$(nm -g --defined-only "$out"/sega-obj/*.o | awk 'NF==3 {print $3}' | grep -vE '^_?(blastem_|RDLRSegaCore$|gzgetc$)' || true)
if [ -n "$bad" ]; then echo "$bad"; echo "FAIL BlastEm symbols above are missing from SegaConfig.h's renames"; exit 1; fi
