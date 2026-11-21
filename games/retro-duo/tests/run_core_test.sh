#!/bin/sh
# Builds the app's C sources (SameBoy core + RDCore) for this machine and runs the core checks.
set -eu
cd "$(dirname "$0")/.."
out="${1:-tests/artifacts}"
mkdir -p "$out"
CC="${CC:-cc}"
$CC -std=gnu11 -O2 -w -include ios/RetroDuo/Core/SameBoyConfig.h \
  -Ivendor/SameBoy -Iios/RetroDuo/Core \
  vendor/SameBoy/Core/*.c ios/RetroDuo/Core/RDCore.c tests/core_test.c -lm -o "$out/core_test"
"$out/core_test" ios/RetroDuo/Resources/cgb_boot.bin ios/RetroDuo/Resources/RetroDuoTestCart.gbc "$out"
