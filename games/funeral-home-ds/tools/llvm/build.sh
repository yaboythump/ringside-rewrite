#!/bin/bash
# Builds Grave Mistakes with BlocksDS v1.25.0 compiled from source by stock clang/lld,
# for machines without the Wonderful Toolchain (BlocksDS' official GCC toolchain).
#
#   tools/llvm/build.sh [output.nds]
#
# Needs: git, clang + lld + llvm-ar/objcopy (tested with LLVM 18), ninja, python3 with Pillow,
# a host C++ compiler and make. Sources are fetched at pinned commits into $WORK
# (default: tools/llvm/work, ignored by git) and built once; later runs only rebuild the game.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
game="$(cd "$here/../.." && pwd)"
out="$(realpath -m "${1:-$game/GraveMistakes.nds}")"
WORK="${WORK:-$here/work}"
mkdir -p "$WORK"
cd "$WORK"

fetch() { # dir url ref
  [ -d "$1/.git" ] && return
  git init -q "$1" && git -C "$1" fetch -q --depth 1 "$2" "$3" && git -C "$1" checkout -q FETCH_HEAD
}
fetch sdk       https://github.com/blocksds/sdk        da93ad5cda6f3aea01769959b3ef7b3c5dd93673  # v1.25.0
fetch libnds    https://github.com/blocksds/libnds     e478cc660a8c7254fbffc54bda3ce0b93ab14c15  # v1.25.0-blocks
fetch fatfs     https://github.com/blocksds/wf-fatfs   2b5c26e2a1eb4cdbbcb57070d49a6ebf7b60c7f9
fetch ndstool   https://github.com/blocksds/ndstool    9435e06a4678abb88da3740c543c83482d16186c
fetch picolibc  https://github.com/picolibc/picolibc   f254ca43dd3c58268ec5759f7a1ad0544c8403f4
fetch meson     https://github.com/mesonbuild/meson    fe8b913b575a421e67b314ea1a1fded91830a40b
if [ ! -d llvm/.git ]; then
  git clone -q --filter=blob:none --no-checkout https://github.com/llvm/llvm-project llvm
  git -C llvm sparse-checkout set compiler-rt/lib/builtins
  git -C llvm checkout -q 689664071b15cdaa463276be0de262e25c69ca40
fi

B="$WORK/build"
if [ ! -f "$B/.done" ]; then
  rm -rf "$B" && mkdir -p "$B"
  git -C libnds checkout -q . && git -C ndstool checkout -q .
  rm -rf libnds/fatfs && ln -s ../fatfs libnds/fatfs
  python3 "$here/patch_blocksds.py" sdk libnds "$B/ld"

  # ndstool: lld can leave a few bytes between segments; pad them instead of stopping.
  python3 - ndstool/source/elf.cpp <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = "\t\telse if(p_headers[i].p_paddr != expected_address) {"
new = ("\t\telse if(p_headers[i].p_paddr > expected_address && p_headers[i].p_paddr - expected_address < 0x100) {\n"
       "\t\t\tunsigned int gap = p_headers[i].p_paddr - expected_address;\n"
       "\t\t\tfor (unsigned int g = 0; g < gap; g++) fputc(0, fNDS);\n"
       "\t\t\t*size += gap;\n\t\t}\n" + old)
assert old in s; open(p, "w").write(s.replace(old, new, 1))
PY
  make -s -C ndstool

  for cpu in arm946e-s arm7tdmi; do
    sys="$B/sysroot-$cpu"
    cat > "$B/cross-$cpu.txt" <<CROSS
[binaries]
c = ['clang', '--target=arm-none-eabi', '-mcpu=$cpu', '-mfloat-abi=soft', '-nostdlib']
ar = 'llvm-ar'
nm = 'llvm-nm'
strip = 'llvm-strip'
[host_machine]
system = 'none'
cpu_family = 'arm'
cpu = 'arm'
endian = 'little'
[properties]
skip_sanity_check = true
CROSS
    python3 meson/meson.py setup "$B/pico-$cpu" picolibc --cross-file "$B/cross-$cpu.txt" \
      -Dmultilib=false -Dtests=false -Dpicocrt=false -Dsemihost=false -Dspecsdir=none \
      -Dprefix="$sys" -Dbuildtype=minsize -Dc_args=-mthumb > "$B/pico-$cpu.log"
    ninja -C "$B/pico-$cpu" install >> "$B/pico-$cpu.log"

    # compiler-rt builtins (division, 64-bit maths, soft float)
    mkdir -p "$B/rt-$cpu"
    for f in llvm/compiler-rt/lib/builtins/*.c llvm/compiler-rt/lib/builtins/arm/*.S llvm/compiler-rt/lib/builtins/arm/aeabi_div0.c; do
      n=$(basename "$f"); case $n in *vfp*|*sync*|*_mutex*|*apple*|*emutls*|*gcc_personality*|*enable_execute_stack*|*clear_cache*|*os_version*|*cpu_model*|*atomic*|*eprintf*|*trampoline*|*chkstk*) continue;; esac
      clang --target=arm-none-eabi -mcpu=$cpu -mfloat-abi=soft -O2 -ffreestanding -nostdlib -I "$sys/include" \
        -c "$f" -o "$B/rt-$cpu/${n%.*}_${f##*.}.o" 2>/dev/null || true
    done
    llvm-ar rcs "$B/libclang_rt-$cpu.a" "$B/rt-$cpu"/*.o
    clang --target=arm-none-eabi -mcpu=$cpu -mfloat-abi=soft -O2 -ffreestanding -fno-builtin -ffunction-sections \
      -Wno-builtin-requires-header -c "$here/compat.c" -o "$B/compat-$cpu.o"
  done

  # libnds (same file lists as libnds' Makefile.arm9 / Makefile.arm7)
  build_libnds() { # cpu arch dirs
    local cpu=$1 arch=$2 sys="$B/sysroot-$1" o="$B/libnds-$2"; mkdir -p "$o"
    local def="-D__NDS__ -D__BLOCKSDS__ -D$(echo "$arch" | tr a-z A-Z) -DNDEBUG"
    local inc="-Ilibnds/include -Ilibnds/source -Ilibnds/source/common/ndsabi -Ilibnds/fatfs/source -Ilibnds/source/arm9/libc/fatfs -I$B -isystem $sys/include"
    local fl="--target=arm-none-eabi -mcpu=$cpu -mfloat-abi=soft -mthumb -O2 -ffunction-sections -fdata-sections -fomit-frame-pointer -ffreestanding -nostdlibinc -w"
    for f in $(cd libnds && find -L $3 -name '*.c' -o -name '*.s' | sort); do
      # The filesystem layer needs BlocksDS' own picolibc build; this game doesn't use it.
      case $f in *arm9/keyboard.c|*fat_device.c|*nitrofs_device.c|*syscalls_filesystem.c) continue;; esac
      case $f in
        *.s) clang $fl -x assembler-with-cpp $def $inc -c "libnds/$f" -o "$o/$(echo "$f" | tr / _).o" ;;
        *.c) clang $fl -std=gnu2x $def $inc -c "libnds/$f" -o "$o/$(echo "$f" | tr / _).o" ;;
      esac
    done
    llvm-ar rcs "$B/libnds-$arch.a" "$o"/*.o
  }
  python3 "$here/font1bpp.py" libnds/graphics/default_font.png "$B"
  clang --target=arm-none-eabi -mcpu=arm946e-s -mthumb -O2 -c "$B/default_font.c" -o "$B/default_font.o"
  build_libnds arm946e-s arm9 "source/arm9 source/common fatfs/source"
  llvm-ar rcs "$B/libnds-arm9.a" "$B/default_font.o"
  build_libnds arm7tdmi arm7 "source/arm7 source/common"

  clang --target=arm-none-eabi -mcpu=arm946e-s -x assembler-with-cpp -D__NDS__ -DARM9 -Ilibnds/include -c "$B/ld/ds_arm9_crt0.s" -o "$B/crt0-arm9.o"
  clang --target=arm-none-eabi -mcpu=arm7tdmi -x assembler-with-cpp -D__NDS__ -DARM7 -Ilibnds/include -c "$B/ld/ds_arm7_crt0.s" -o "$B/crt0-arm7.o"

  # BlocksDS' default ARM7 core without WiFi or Maxmod (arm7_minimal.elf)
  clang --target=arm-none-eabi -mcpu=arm7tdmi -mfloat-abi=soft -mthumb -O2 -ffunction-sections -fdata-sections -ffreestanding -nostdlibinc \
    -D__NDS__ -D__BLOCKSDS__ -DARM7 -Ilibnds/include -isystem "$B/sysroot-arm7tdmi/include" -w \
    -c sdk/sys/arm7/main_core/source/main.c -o "$B/arm7-main.o"
  ld.lld -T "$B/ld/ds_arm7.ld" --gc-sections -z noexecstack --defsym=__sync_synchronize=__sync_synchronize_none \
    -o "$B/arm7_minimal.elf" "$B/crt0-arm7.o" "$B/arm7-main.o" "$B/compat-arm7tdmi.o" \
    --start-group "$B/libnds-arm7.a" "$B/sysroot-arm7tdmi/lib/libc.a" "$B/libclang_rt-arm7tdmi.a" --end-group 2>&1 | grep -v "not a multiple of alignment" || true
  touch "$B/.done"
fi

# The game
o="$B/game"; rm -rf "$o"; mkdir -p "$o"
for f in "$game"/source/*.c; do
  clang --target=arm-none-eabi -mcpu=arm946e-s -mfloat-abi=soft -mthumb -O2 -ffunction-sections -fdata-sections -ffreestanding -nostdlibinc \
    -D__NDS__ -D__BLOCKSDS__ -DARM9 -Ilibnds/include -isystem "$B/sysroot-arm946e-s/include" \
    -Wall -Wextra -Wno-c23-extensions -Wno-unused-parameter -c "$f" -o "$o/$(basename "$f" .c).o"
done
ld.lld -T "$B/ld/ds_arm9.mem" -T "$B/ld/ds_arm9.ld" --gc-sections --no-check-sections -z noexecstack --defsym=__sync_synchronize=__sync_synchronize_none \
  -o "$o/GraveMistakes.elf" "$B/crt0-arm9.o" "$o"/*.o "$B/compat-arm946e-s.o" \
  --start-group "$B/libnds-arm9.a" "$B/sysroot-arm946e-s/lib/libc.a" "$B/libclang_rt-arm946e-s.a" --end-group 2>&1 | grep -v "not a multiple of alignment" || true
ndstool/ndstool -c "$out" -7 "$B/arm7_minimal.elf" -9 "$o/GraveMistakes.elf" \
  -b "$game/icon.bmp" "Grave Mistakes;Funeral Home Sim;Built with BlocksDS" -g GMFH 01 "GRAVEMISTAKE" > /dev/null
echo "built $out"
