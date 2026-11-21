#!/usr/bin/env python3
"""Build a single, fully offline HTML resource for the native iPhone app.

Xcode's user script sandbox only permits declared outputs. Keep the engine and
UI inside index.html, not additional sidecar files in the .app.
"""
from pathlib import Path
import sys

root = Path(__file__).resolve().parent
dest = Path(sys.argv[1])
core_path = root / "vendor" / "jsnes.js"
if not core_path.is_file() or core_path.stat().st_size < 30000:
    raise SystemExit("Pinned JSNES core missing; run prepare.py before archiving")
source = (root / "index.html").read_text(encoding="utf-8")
start = source.index('<script src="vendor/jsnes.js"')
end_marker = '<script src="app.js"></script>'
end = source.index(end_marker, start) + len(end_marker)
core = core_path.read_text(encoding="utf-8").replace("</script", "<\\/script")
ui = (root / "app.js").read_text(encoding="utf-8").replace("</script", "<\\/script")
replacement = "<script>\n" + core + "\n</script><script>\n" + ui + "\n</script>"
source = source[:start] + replacement + source[end:]
dest.parent.mkdir(parents=True, exist_ok=True)
dest.write_text(source, encoding="utf-8")
print(f"CT Arcade offline bundle: {dest.stat().st_size // 1024} KB -> {dest}")
