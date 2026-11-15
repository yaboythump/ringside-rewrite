#!/usr/bin/env python3
"""Build Ringside Card Clash into one self-contained HTML file.

Reads src.html and the images in assets/, embeds the images, and writes the
playable page. Usage: python3 build.py [output.html]
Default output: ../card-clash.html
"""
import base64, pathlib, sys

HERE = pathlib.Path(__file__).resolve().parent
MIME = {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".webp": "image/webp"}


def data_uri(path):
    return "data:%s;base64,%s" % (MIME[path.suffix.lower()], base64.b64encode(path.read_bytes()).decode())


def find(stem, folder):
    for p in sorted(folder.iterdir()):
        if p.stem == stem and p.suffix.lower() in MIME:
            return p
    sys.exit("missing image: %s/%s.(jpg|png|webp)" % (folder, stem))


src = (HERE / "src.html").read_text()
portraits = ",".join(
    '%s:"%s"' % (p.stem, data_uri(p))
    for p in sorted((HERE / "assets" / "portraits").iterdir())
    if p.suffix.lower() in MIME and p.stem.isidentifier()
)
for marker in ("/*__PORTRAITS__*/", "__BELT__", "__ARENA__"):
    if marker not in src:
        sys.exit("src.html is missing the %s marker" % marker)
out = (
    src.replace("/*__PORTRAITS__*/", portraits)
    .replace("__BELT__", data_uri(find("belt", HERE / "assets")))
    .replace("__ARENA__", data_uri(find("arena", HERE / "assets")))
)
dest = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else HERE.parent / "card-clash.html"
dest.parent.mkdir(parents=True, exist_ok=True)
dest.write_text(out)
print("wrote %s (%d KB)" % (dest, len(out) // 1024))
