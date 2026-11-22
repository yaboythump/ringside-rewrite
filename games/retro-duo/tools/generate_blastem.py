#!/usr/bin/env python3
"""Generates BlastEm's build-time sources into a folder (default: ios/RetroDuo/SegaCore/generated).

BlastEm's 68000, Z80, SH-2 and uPD78K2 interpreters are written in its CPU description
language and turned into C by cpu_dsl.py (the 68000 one alone is ~56 MB of C), so they are
generated before every build instead of being committed. The ROM database and the machine
list are turned into C strings, exactly as BlastEm's Makefile does with sed.
Usage: python3 tools/generate_blastem.py [OUTDIR]
"""
import os
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
vendor = root / "vendor" / "blastem"
out = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else root / "ios" / "RetroDuo" / "SegaCore" / "generated"
out.mkdir(parents=True, exist_ok=True)

# Same dispatch styles as BlastEm's Makefile: computed goto for the Z80, calls for the rest.
for cpu, dispatch in (("m68k", "call"), ("z80", "goto"), ("sh2", "call"), ("upd78k2", "call")):
    target = out / f"{cpu}.c"
    source = vendor / f"{cpu}.cpu"
    if target.exists() and (out / f"{cpu}.h").exists() and target.stat().st_mtime >= max(
            source.stat().st_mtime, (vendor / "cpu_dsl.py").stat().st_mtime):
        continue
    with open(target.with_suffix(".tmp"), "w") as c_file:
        subprocess.run([sys.executable, str(vendor / "cpu_dsl.py"), "-d", dispatch, str(source)],
                       cwd=out, stdout=c_file, check=True,
                       env={**os.environ, "PYTHONHASHSEED": "0"})  # same output every time
    target.with_suffix(".tmp").replace(target)


def c_string(name):
    lines = (vendor / name).read_text().split("\n")
    if lines and lines[-1] == "":
        lines.pop()  # sed sees no line after the final newline
    escaped = ['"' + line.replace('"', '\\"') + '\\n"' for line in lines]
    escaped[0] = f"const char {name.replace('.', '_')}_data[] = " + escaped[0]
    escaped[-1] += ";"
    return "\n".join(escaped) + "\n"


for name in ("rom.db", "systems.cfg"):
    target = out / f"{name}.c"
    text = c_string(name)
    if not target.exists() or target.read_text() != text:
        target.write_text(text)
print(f"BlastEm sources generated in {out}")
