#!/bin/sh
# Builds the app's NES sources (vendored Nestopia + NESCore) for this machine and runs the NES checks.
set -eu
cd "$(dirname "$0")/.."
out="${1:-tests/artifacts}"
mkdir -p "$out/nes-obj"
CXX="${CXX:-c++}"
FLAGS="-std=gnu++17 -O2 -w -DNST_NO_ZLIB -DNST_NO_2XSAI -DNST_NO_HQ2X -DNST_NO_SCALEX -DNST_NO_XBR -Ivendor/nestopia/source -Iios/RetroDuo/NESCore"
jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
find vendor/nestopia/source ios/RetroDuo/NESCore -name '*.cpp' | sort | \
  xargs -P "$jobs" -I{} sh -c 'o="'"$out"'/nes-obj/$(echo "{}" | tr / _).o"; '"$CXX $FLAGS"' -c "{}" -o "$o"'
$CXX $FLAGS tests/nes_core_test.cpp "$out"/nes-obj/*.o -o "$out/nes_core_test"
"$out/nes_core_test" ios/RetroDuo/Resources/RetroDuoNESTestCart.nes "$out"
