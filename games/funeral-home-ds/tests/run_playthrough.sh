#!/bin/sh
# Builds Retro Duo's melonDS core for this machine and plays a full day of Grave Mistakes on it.
# Usage: tests/run_playthrough.sh [rom] [output dir]
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
rd="$here/../retro-duo"
rom="${1:-$rd/ios/RetroDuo/Resources/GraveMistakes.nds}"
out="${2:-$here/tests/artifacts}"
mkdir -p "$out/ds-obj"
CC="${CC:-cc}"
CXX="${CXX:-c++}"
M="$rd/vendor/melonDS/src"
INC="-I$M -I$M/teakra/include -I$M/teakra/src -I$rd/ios/RetroDuo/DSCore"
jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
# The emulator objects are cached in the output folder between runs.
if [ ! -f "$out/ds-obj/.complete" ]; then
  find "$M" "$rd/ios/RetroDuo/DSCore" -name '*.c' -o -name '*.cpp' | sort | \
    xargs -P "$jobs" -I{} sh -c '
      f="{}"; o="'"$out"'/ds-obj/$(echo "$f" | tr / _).o"
      case "$f" in
        *.c) '"$CC"' -std=gnu11 -O2 -fwrapv -w '"$INC"' -c "$f" -o "$o" ;;
        *) '"$CXX"' -std=gnu++17 -O2 -fwrapv -w '"$INC"' -c "$f" -o "$o" ;;
      esac'
  touch "$out/ds-obj/.complete"
fi
$CC -std=gnu11 -O2 -c "$here/source/data.c" -o "$out/data.o"
$CXX -std=gnu++17 -O2 -fwrapv $INC "$here/tests/playthrough_test.cpp" "$out/data.o" "$out"/ds-obj/*.o -lpthread -o "$out/playthrough_test"
"$out/playthrough_test" "$rom" "$out"
