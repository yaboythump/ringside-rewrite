#!/usr/bin/env python3
"""Build Ringside Combo as one standalone HTML page with images and music embedded.

Usage: python3 build.py [output.html]        (default: ../ring-combo.html)

Images:
  - Portraits come from ../card-clash/assets/portraits/, matched by wrestler ID.
  - Game art comes from assets/<name>.(png|jpg|jpeg|webp). See ART_BRIEF.md for the list.
    Missing tile art falls back to the built-in emoji look. Missing arena or belt
    art falls back to the Card Clash arena and belt.
  - The arena soundtrack comes from assets/arena-loop.mp3.
"""
import base64
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
CLASH = HERE.parent / "card-clash" / "assets"
MIME = {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".webp": "image/webp", ".mp3": "audio/mpeg"}
ART_NAMES = ["strike", "grapple", "kick", "show", "heal", "fin", "chair", "knux", "arena", "mat", "logo", "belt"]


def data_uri(path):
    return f"data:{MIME[path.suffix.lower()]};base64,{base64.b64encode(path.read_bytes()).decode()}"


def find(folder, stem):
    for ext in MIME:
        path = folder / f"{stem}{ext}"
        if path.is_file():
            return path
    return None


def main():
    dest = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else HERE.parent / "ring-combo.html"
    src = (HERE / "src.html").read_text(encoding="utf-8")
    universe = (HERE / "universe.js").read_text(encoding="utf-8")
    for marker in ("/*__PORTRAITS__*/", "/*__ART__*/", "/*__MUSIC__*/"):
        if marker not in src:
            sys.exit(f"src.html is missing the {marker} marker")

    portraits = []
    for wid in sorted(set(re.findall(r"^  ([a-z]+):\{name:.*lore:", universe, re.M))):
        path = find(CLASH / "portraits", wid)
        if not path:
            sys.exit(f"Missing portrait for {wid} in {CLASH / 'portraits'}")
        portraits.append(f'{wid}:"{data_uri(path)}"')

    art, used = [], []
    for name in ART_NAMES:
        path = find(HERE / "assets", name) or (find(CLASH, name) if name in ("arena", "belt") else None)
        if path:
            art.append(f'{name}:"{data_uri(path)}"')
            used.append(f"{name} ({path.relative_to(HERE.parent)})")

    soundtrack = HERE / "assets" / "arena-loop.mp3"
    music = "data:audio/mpeg;base64," + base64.b64encode(soundtrack.read_bytes()).decode()
    voice = ",".join(f'"{i}":"{data_uri(HERE / "assets" / f"count-{i}.mp3")}"' for i in range(1,11))
    for module in ("universe", "progression", "modes", "menus"):
        marker = "/*__" + module.upper() + "__*/"
        if src.count(marker) != 1:
            sys.exit(f"src.html must contain exactly one {marker} marker")
        src = src.replace(marker, (HERE / f"{module}.js").read_text(encoding="utf-8"))
    out = (src.replace("/*__VOICE__*/", voice).replace("/*__PORTRAITS__*/", ",".join(portraits))
           .replace("/*__ART__*/", ",".join(art))
           .replace("/*__MUSIC__*/", music))
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(out, encoding="utf-8")
    print(f"wrote {dest} ({len(out.encode('utf-8')) // 1024} KB)")
    print("art: " + (", ".join(used) if used else "none (built-in look)"))


if __name__ == "__main__":
    main()
