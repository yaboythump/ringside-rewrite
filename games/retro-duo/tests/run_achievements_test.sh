#!/usr/bin/env bash
# Builds rcheevos and Retro Duo's RetroAchievements layer for Linux and runs tests/achievements.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
out="$(mktemp -d)"
vendor="$here/vendor/rcheevos"
objects=()
for source in $(cat "$vendor/SOURCES.txt"); do
  object="$out/$(echo "$source" | tr / _).o"
  ${CC:-cc} -c -O1 -include "$here/ios/RetroDuo/Achievements/AchievementsConfig.h" -I"$vendor/include" -I"$vendor/src" "$vendor/src/$source" -o "$object"
  objects+=("$object")
done
${CC:-cc} -O1 -Wall -Wextra -I"$here/ios/RetroDuo/Achievements" -I"$vendor/include" \
  "$here/ios/RetroDuo/Achievements/RDAchievements.c" "$here/tests/achievements/achievements_test.c" "${objects[@]}" \
  -lpthread -lm -o "$out/achievements_test"
"$out/achievements_test" "$out/test.gb"
