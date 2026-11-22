#!/usr/bin/env bash
# Builds the Mac Duo core (Mini vMac + MVGlue.c) for the host and runs the headless test.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
app="$here/.."
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
cc="${CC:-cc}"
flags=(-O2 -D__LIBRETRO__ -w -I"$app/ios/MacDuo/Core/cfg" -I"$app/ios/MacDuo/Core" -I"$app/vendor/minivmac/src")
objs=()
for src in "$app"/vendor/minivmac/src/*.c "$app/ios/MacDuo/Core/MVGlue.c" "$here/mv_core_test.c"; do
  obj="$out/$(basename "$src" .c).o"
  "$cc" "${flags[@]}" -c "$src" -o "$obj"
  objs+=("$obj")
done
"$cc" "${objs[@]}" -o "$out/mv_core_test" -lpthread
python3 "$here/make_test_rom.py" "$out/test.rom"
"$out/mv_core_test" "$out/test.rom" "$out"
