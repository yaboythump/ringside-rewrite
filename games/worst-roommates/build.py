#!/usr/bin/env python3
"""Build Worst Roommates Ever as one standalone HTML page with its art embedded.

Usage: python3 build.py [output.html]        (default: ../worst-roommates.html)

Art comes from assets/<name>.(png|jpg|jpeg|webp). See ART_BRIEF.md for the list.
Anything missing keeps the built-in emoji/shape look. Large images are shrunk on the
way in (with macOS `sips`, or Pillow if it is installed) so the page stays light.
"""
import base64
import io
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
MIME = {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".webp": "image/webp"}
MAX_SIZE = {"char_": 192, "portrait_": 512, "floor_": 256, "obj_": 256, "fx_": 128, "logo": 900}


def find(stem):
    for ext in MIME:
        path = HERE / "assets" / f"{stem}{ext}"
        if path.is_file():
            return path
    return None


def data_uri(path, stem):
    """Embed an image without writing undeclared temporary files.

    Xcode's user-script sandbox lets this build step write index.html, not
    scratch files in DerivedSources. Pillow downsizing is optional and is
    done entirely in memory; without Pillow the original image is embedded.
    """
    content = path.read_bytes()
    limit = next((size for prefix, size in MAX_SIZE.items()
                  if stem.startswith(prefix)), 512)
    try:
        from PIL import Image
        with Image.open(io.BytesIO(content)) as image:
            if max(image.size) > limit:
                image.thumbnail((limit, limit))
                resized = io.BytesIO()
                fmt = {".png": "PNG", ".jpg": "JPEG", ".jpeg": "JPEG", ".webp": "WEBP"}
                image.save(resized, format=fmt[path.suffix.lower()])
                if 0 < resized.tell() < len(content):
                    content = resized.getvalue()
    except (ImportError, OSError, ValueError):
        pass
    return f"data:{MIME[path.suffix.lower()]};base64,{base64.b64encode(content).decode()}"


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
    for name in names:
        path = find(name)
        if path:
            art.append(f'{name}:"{data_uri(path, name)}"')
            used.append(name)

    out = src.replace("/*__ART__*/", ",".join(art))
    if "/*__CHARACTERS__*/" not in out:
        sys.exit("src.html is missing the /*__CHARACTERS__*/ marker")
    out = out.replace("/*__CHARACTERS__*/", (HERE / "character-art.js").read_text(encoding="utf-8"))
    for marker, filename in (
        ("/*__GAMEPLAY_CSS__*/", "gameplay.css"),
        ("/*__GAMEPLAY_JS__*/", "gameplay.js"),
        ("/*__DUO_CSS__*/", "duo-layout.css"),
        ("/*__DUO_JS__*/", "duo-layout.js"),
    ):
        if marker not in out:
            sys.exit(f"src.html is missing the {marker} marker")
        out = out.replace(marker, (HERE / filename).read_text(encoding="utf-8"))
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(out, encoding="utf-8")
    print(f"wrote {dest} ({len(out.encode('utf-8')) // 1024} KB)")
    print(f"art: {len(used)}/{len(names)} " + ("(" + ", ".join(used) + ")" if used else "(built-in look)"))


if __name__ == "__main__":
    main()
