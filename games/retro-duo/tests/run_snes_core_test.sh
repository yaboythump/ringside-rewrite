#!/bin/sh
# Builds the app's SNES sources (vendored bsnes via its units + the libretro host) for this machine and runs the SNES checks.
# Every file gets the app's prefix header (SameBoyConfig.h), exactly as in Xcode.
set -eu
cd "$(dirname "$0")/.."
out="${1:-tests/artifacts}"
mkdir -p "$out/snes-obj"
CC="${CC:-cc}"
CXX="${CXX:-c++}"
INC="-Ivendor/bsnes -Ivendor/bsnes/bsnes -Ivendor/bsnes/bsnes/gb -Ivendor/bsnes/bsnes/sfc -Iios/RetroDuo/SNESCore -Iios/RetroDuo/Libretro"
jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
ls ios/RetroDuo/SNESCore/units/*.c ios/RetroDuo/SNESCore/units/*.cpp ios/RetroDuo/SNESCore/RDLibco.c \
   ios/RetroDuo/SNESCore/SNESCoreTable.c ios/RetroDuo/Libretro/RDLibretro.c | \
  xargs -P "$jobs" -I{} sh -c 'f="{}"; o="'"$out"'/snes-obj/$(basename "$f").o"; [ "$o" -nt "$f" ] && exit 0;
    case "$f" in
      *.cpp) '"$CXX"' -include ios/RetroDuo/Core/SameBoyConfig.h -std=gnu++17 -O2 -w -fno-strict-aliasing -fwrapv '"$INC"' -c "$f" -o "$o" ;;
      *) '"$CC"' -include ios/RetroDuo/Core/SameBoyConfig.h -std=gnu11 -O2 -w -D_GNU_SOURCE '"$INC"' -c "$f" -o "$o" ;;
    esac'
# No libretro or bundled Game Boy symbol may escape un-renamed (they would clash with SameBoy and other cores).
if nm -g --defined-only "$out"/snes-obj/*.o | awk '{print $3}' | grep -E '^_?(retro_|GB_)'; then
  echo "FAIL un-renamed bsnes symbols above"; exit 1
fi
$CXX -std=gnu++17 -O2 $INC tests/snes_core_test.cpp "$out"/snes-obj/*.o -lpthread -lm -ldl -o "$out/snes_core_test"
"$out/snes_core_test" ios/RetroDuo/Resources/RetroDuoSNESTestCart.sfc "$out"
