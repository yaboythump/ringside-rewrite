#!/usr/bin/env python3
"""Small source fixes so BlocksDS v1.25.0 builds with stock clang 18 + ld.lld.

The official BlocksDS toolchain is GCC (Wonderful Toolchain). These patches only
touch syntax that GNU as / GNU ld accept but LLVM does not; the code is the same.

Usage: patch_blocksds.py <sdk dir> <libnds dir> <output dir for linker scripts and crt0s>
"""
import re
import shutil
import sys
from pathlib import Path

sdk, libnds, out = (Path(p) for p in sys.argv[1:4])
out.mkdir(parents=True, exist_ok=True)


def edit(path, fn):
    s = path.read_text()
    t = fn(s)
    if t == s:
        sys.exit(f"patch did not apply: {path}")
    path.write_text(t)


# 1. libnds asm macros compare symbols with `.if \arch == thumb`; LLVM's
#    assembler needs string compares (.ifc), which GNU as also understands.
def asminc(s):
    pat = re.compile(r"    \.if \\arch == thumb\n(.*?)    \.elseif \\arch == arm\n(.*?)"
                     r"    \.elseif \\arch == unset\n(.*?)    \.else\n(.*?)    \.endif\n", re.S)
    return pat.sub(lambda m: "    .ifc \\arch,thumb\n" + m[1] + "    .else\n    .ifc \\arch,arm\n" + m[2]
                   + "    .else\n    .ifc \\arch,unset\n" + m[3] + "    .else\n" + m[4]
                   + "    .endif\n    .endif\n    .endif\n", s)
edit(libnds / "include/nds/asminc.h", asminc)

# 2. __builtin_clzg is clang 19+/GCC 14+.
edit(libnds / "source/arm9/math.c", lambda s: s.replace(
    "__builtin_clzg((uint32_t)(reciprocal64 >> 32), 32)",
    "((uint32_t)(reciprocal64 >> 32) ? __builtin_clz((uint32_t)(reciprocal64 >> 32)) : 32)"))

# 3. `ldr rX, =#imm` is a GNU-ism.
edit(libnds / "source/arm9/system/mpu_setup.s", lambda s: s.replace("=#", "="))

# 4. crt0s and linker scripts are copied so the SDK checkout stays pristine.
crts = sdk / "sys/crts"
for name in ("ds_arm9_crt0.s", "ds_arm7_crt0.s", "ds_arm9.ld", "ds_arm9.mem", "ds_arm7.ld"):
    shutil.copy(crts / name, out / name)

# LLVM can't use a label difference defined later as a mov immediate.
edit(out / "ds_arm7_crt0.s", lambda s: s.replace(
    "mov     r3, #(__sync_end - __sync_start)", "ldr     r3, =(__sync_end - __sync_start)"))


def tls(seg):
    def fn(s):
        # lld needs an explicit PT_TLS program header when PHDRS is used.
        s = re.sub(r"(PHDRS \{.*?)(\n\})", lambda m: m[1] + "\n    tls   PT_TLS;" + m[2], s, count=1, flags=re.S)
        for name in ("tdata", "tbss"):
            pat = re.compile(r"(\n    \." + name + r" ALIGN\(4\)[^\n]*:\n    \{.*?\n    \})([^\n]*)", re.S)
            m = pat.search(s)
            tail = re.sub(r":\w+", "", m[2]).split("=")[0].rstrip() or " >iwram AT>ewram"
            s = s[:m.start()] + m[1] + tail + f" :{seg} :tls" + s[m.end():]
        return s
    return fn
edit(out / "ds_arm7.ld", tls("arm7"))
edit(out / "ds_arm9.ld", tls("main"))

# lld wants a memory region for every section once MEMORY is used.
edit(out / "ds_arm9.mem", lambda s: s.replace(
    "}", "\ttwl_ewram\t: ORIGIN = 0x02000000, LENGTH = 16M /* for lld */\n}", 1))
def twl(s):
    s = s.replace("        __arm9i_end__ = ABSOLUTE(.);\n    } :twl", "        __arm9i_end__ = ABSOLUTE(.);\n    } >twl_ewram :twl")
    s = s.replace("        __twl_bss_end__ = ABSOLUTE(.);\n    } :NONE", "        __twl_bss_end__ = ABSOLUTE(.);\n    } >twl_ewram :NONE")
    s = s.replace("        __twl_end__ = ABSOLUTE(.);\n    } :NONE", "        __twl_end__ = ABSOLUTE(.);\n    } >twl_ewram :NONE")
    return s
edit(out / "ds_arm9.ld", twl)
print("patched", libnds, "and wrote", out)
