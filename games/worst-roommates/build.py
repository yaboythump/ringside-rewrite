#!/usr/bin/env python3
"""Build Worst Roommates Ever as one standalone HTML page with its art embedded.

Usage: python3 build.py [output.html]        (default: ../worst-roommates.html)

Art comes from assets/<name>.(png|jpg|jpeg|webp). See ART_BRIEF.md for the list.
Anything missing keeps the built-in emoji/shape look. Large images are shrunk on the
way in (with macOS `sips`, or Pillow if it is installed) so the page stays light.
"""
import base64
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
MIME = {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".webp": "image/webp"}
MAX_SIZE = {"char_": 192, "portrait_": 512, "floor_": 256, "obj_": 256, "fx_": 128, "logo": 900}


def find(stem):
    for ext in MIME:
        path = HERE / "assets" / f"{stem}{ext}"
        if path.is_file():
            return path
    return None


def shrink(path, stem, scratch):
    """Return a smaller copy of the image when a resizer is available, else the original."""
    limit = next((size for prefix, size in MAX_SIZE.items() if stem.startswith(prefix)), 512)
    out = pathlib.Path(scratch) / path.name
    try:
        if shutil.which("sips"):
            subprocess.run(["sips", "-Z", str(limit), str(path), "--out", str(out)],
                           check=True, capture_output=True, timeout=60)
        else:
            from PIL import Image  # optional
            with Image.open(path) as image:
                image.thumbnail((limit, limit))
                image.save(out)
        if out.is_file() and 0 < out.stat().st_size < path.stat().st_size:
            return out
    except Exception:
        pass
    return path


def data_uri(path):
    return f"data:{MIME[path.suffix.lower()]};base64,{base64.b64encode(path.read_bytes()).decode()}"


def main():
    dest = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else HERE.parent / "worst-roommates.html"
    src = (HERE / "src.html").read_text(encoding="utf-8")
    if "/*__ART__*/" not in src:
        sys.exit("src.html is missing the /*__ART__*/ marker")
    match = re.search(r"const ART_NAMES=\[(.*?)\];", src, re.S)
    if not match:
        sys.exit("src.html is missing the ART_NAMES list")
    names = re.findall(r"'([a-z_]+)'", match.group(1))

    art, used = [], []
    scratch = tempfile.mkdtemp(dir=os.environ.get("DERIVED_FILE_DIR") or None)
    try:
        for name in names:
            path = find(name)
            if path:
                art.append(f'{name}:"{data_uri(shrink(path, name, scratch))}"')
                used.append(name)
    finally:
        shutil.rmtree(scratch, ignore_errors=True)

    out = src.replace("/*__ART__*/", ",".join(art))
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(out, encoding="utf-8")
    print(f"wrote {dest} ({len(out.encode('utf-8')) // 1024} KB)")
    print(f"art: {len(used)}/{len(names)} " + ("(" + ", ".join(used) + ")" if used else "(built-in look)"))


if __name__ == "__main__":
    main()
