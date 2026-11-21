#!/bin/sh
# Builds the app's GBA sources (vendored mGBA via its units + RDGBA) for this machine and runs the GBA checks.
set -eu
cd "$(dirname "$0")/.."
out="${1:-tests/artifacts}"
mkdir -p "$out/gba-obj"
CC="${CC:-cc}"
CXX="${CXX:-c++}"
INC="-Iios/RetroDuo/GBACore -Ivendor/mgba/include -Ivendor/mgba/include-generated -Ivendor/mgba/src"
jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
ls ios/RetroDuo/GBACore/units/*.c ios/RetroDuo/GBACore/RDGBA.c | \
  xargs -P "$jobs" -I{} sh -c 'o="'"$out"'/gba-obj/$(basename {}).o"; '"$CC"' -std=gnu11 -O2 -w -D_GNU_SOURCE '"$INC"' -c "{}" -o "$o"'
$CXX -std=gnu++17 -O2 $INC tests/gba_core_test.cpp "$out"/gba-obj/*.o -lpthread -lm -o "$out/gba_core_test"
"$out/gba_core_test" ios/RetroDuo/Resources/RetroDuoGBATestCart.gba "$out"
