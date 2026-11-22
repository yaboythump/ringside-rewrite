#!/bin/sh
# Builds the app's libretro cores (see build_libretro_cores.sh) and runs the Sega checks.
set -eu
cd "$(dirname "$0")/.."
out="${1:-tests/artifacts}"
CXX="${CXX:-c++}"
tests/build_libretro_cores.sh "$out"
$CXX -std=gnu++17 -O2 -Iios/RetroDuo/Libretro tests/sega_core_test.cpp \
  "$out"/snes-obj/*.o "$out"/sega-obj/*.o "$out"/host-obj/*.o -lpthread -lm -ldl -o "$out/sega_core_test"
"$out/sega_core_test" ios/RetroDuo/Resources "$out"
