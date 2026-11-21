#!/usr/bin/env python3
"""Builds the built-in sample book from the Standard Ebooks source (CC0 public domain).

    git clone --depth 1 https://github.com/standardebooks/lewis-carroll_alices-adventures-in-wonderland_john-tenniel se-alice
    python3 build_sample.py se-alice ../ios/BookDuo/Resources/Alice.epub

Tenniel's illustrations are shrunk from the 30 MB of SVG in the source to small
PNGs on white, and a plain typographic cover replaces the 1 MB SVG cover.
"""
import io, re, sys, zipfile
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

src, out = Path(sys.argv[1]), Path(sys.argv[2])
epub = src / "src" / "epub"
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf"
FONT_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"


def illustration(n):
    im = Image.open(src / "images" / f"illustration-{n}.png").convert("RGBA")
    im.thumbnail((640, 900), Image.LANCZOS)
    flat = Image.new("RGB", im.size, "white")
    flat.paste(im, mask=im.split()[3])
    buf = io.BytesIO()
    flat.convert("L").save(buf, "JPEG", quality=62, optimize=True, progressive=True)
    return buf.getvalue()


def cover():
    w, h = 800, 1200
    art = Image.open(src / "images" / "cover.jpg").convert("RGB")
    scale = max(w / art.width, h / art.height)
    art = art.resize((round(art.width * scale), round(art.height * scale)), Image.LANCZOS)
    left, top = (art.width - w) // 2, (art.height - h) // 2
    im = art.crop((left, top, left + w, top + h))
    d = ImageDraw.Draw(im, "RGBA")
    d.rectangle((0, 832, w, 1120), fill=(18, 16, 14, 225))
    title = ImageFont.truetype(FONT_BOLD, 52)
    small = ImageFont.truetype(FONT, 32)
    for text, font, y in [("Alice’s Adventures", title, 872), ("in Wonderland", title, 936), ("LEWIS CARROLL", small, 1036)]:
        d.text((w / 2, y), text, font=font, fill=(244, 236, 216), anchor="ma")
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=74, optimize=True, progressive=True)
    return buf.getvalue()


def fix_refs(text):
    return re.sub(r"illustration-(\d+)\.svg", r"illustration-\1.jpg", text)


with zipfile.ZipFile(out, "w") as z:
    z.writestr(zipfile.ZipInfo("mimetype"), "application/epub+zip", compress_type=zipfile.ZIP_STORED)
    z.write(src / "src" / "META-INF" / "container.xml", "META-INF/container.xml", zipfile.ZIP_DEFLATED)
    for path in sorted(epub.rglob("*")):
        if path.is_dir():
            continue
        rel = path.relative_to(epub).as_posix()
        if rel.startswith("images/illustration-") or rel == "images/cover.svg":
            continue
        data = path.read_bytes()
        if rel == "content.opf":
            text = fix_refs(data.decode())
            text = re.sub(r'(href="images/illustration-\d+\.jpg" id="illustration-\d+\.jpg") media-type="image/svg\+xml"',
                          r'\1 media-type="image/jpeg"', text)
            text = text.replace('<item href="images/cover.svg" id="cover.svg" media-type="image/svg+xml" properties="cover-image"/>',
                                '<item href="images/cover.jpg" id="cover.jpg" media-type="image/jpeg" properties="cover-image"/>')
            text = text.replace('content="cover.svg"', 'content="cover.jpg"')
            data = text.encode()
        elif rel.endswith(".xhtml"):
            data = fix_refs(data.decode()).encode()
        z.writestr(rel, data, zipfile.ZIP_DEFLATED)
    for n in range(1, 43):
        z.writestr(f"images/illustration-{n}.jpg", illustration(n), zipfile.ZIP_STORED)
    z.writestr("images/cover.jpg", cover(), zipfile.ZIP_STORED)
print(out, out.stat().st_size)
