#!/bin/sh
# Builds the app's DS sources (vendored melonDS + MDCore) for this machine and runs the DS checks.
set -eu
cd "$(dirname "$0")/.."
out="${1:-tests/artifacts}"
mkdir -p "$out/ds-obj"
CC="${CC:-cc}"
CXX="${CXX:-c++}"
M=vendor/melonDS/src
INC="-I$M -I$M/teakra/include -I$M/teakra/src -Iios/RetroDuo/DSCore"
jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
find $M ios/RetroDuo/DSCore -name '*.c' -o -name '*.cpp' | sort | \
  xargs -P "$jobs" -I{} sh -c '
    f="{}"; o="'"$out"'/ds-obj/$(echo "$f" | tr / _).o"
    case "$f" in
      *.c) '"$CC"' -std=gnu11 -O2 -fwrapv -w '"$INC"' -c "$f" -o "$o" ;;
      *) '"$CXX"' -std=gnu++17 -O2 -fwrapv -w '"$INC"' -c "$f" -o "$o" ;;
    esac'
$CXX -std=gnu++17 -O2 -fwrapv $INC tests/ds_core_test.cpp "$out"/ds-obj/*.o -lpthread -o "$out/ds_core_test"
"$out/ds_core_test" ios/RetroDuo/Resources/RetroDuoDSTestCart.nds "$out"
