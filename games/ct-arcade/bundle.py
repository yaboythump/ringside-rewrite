#!/usr/bin/env python3
"""Copy prepared local assets into the Xcode product for completely offline play."""
from pathlib import Path
import shutil
import sys
root=Path(__file__).resolve().parent
dest=Path(sys.argv[1]);dest.parent.mkdir(parents=True,exist_ok=True)
for name in ("index.html","app.js"):
    shutil.copy2(root/name,dest.parent/name)
core=root/"vendor"/"jsnes.js"
if not core.is_file() or core.stat().st_size<30000:
    raise SystemExit("NES core missing; run python3 games/ct-arcade/prepare.py before Xcode build")
(dest.parent/"vendor").mkdir(exist_ok=True)
shutil.copy2(core,dest.parent/"vendor"/"jsnes.js")
print(f"Bundled CT ARCADE to {dest.parent}")
