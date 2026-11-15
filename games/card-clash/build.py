#!/usr/bin/env python3
"""Build Ringside Card Clash as a standalone HTML page.

Usage: python3 build.py [output.html]
Default output: ../card-clash.html
"""
import base64
import io
import pathlib
import re
import subprocess
import sys
import tarfile

HERE = pathlib.Path(__file__).resolve().parent
MIME = {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".webp": "image/webp"}


def data_uri(name, contents):
    mime = MIME[pathlib.PurePosixPath(name).suffix.lower()]
    return f"data:{mime};base64,{base64.b64encode(contents).decode()}"


def find_image(stem, assets):
    for name, contents in sorted(assets.items()):
        path = pathlib.PurePosixPath(name)
        if path.parent == pathlib.PurePosixPath(".") and path.stem == stem and path.suffix.lower() in MIME:
            return data_uri(name, contents)
    sys.exit(f"Missing image: assets/{stem}.(jpg|png|webp)")


def build_page(src, dest, assets):
    portraits = []
    for name, contents in sorted(assets.items()):
        path = pathlib.PurePosixPath(name)
        if path.parent == pathlib.PurePosixPath("portraits") and path.suffix.lower() in MIME and path.stem.isidentifier():
            portraits.append(f'{path.stem}:"{data_uri(name, contents)}"')

    for marker in ("/*__PORTRAITS__*/", "__BELT__", "__ARENA__"):
        if marker not in src:
            sys.exit(f"src.html is missing the {marker} marker")
    out = (
        src.replace("/*__PORTRAITS__*/", ",".join(portraits))
        .replace("__BELT__", find_image("belt", assets))
        .replace("__ARENA__", find_image("arena", assets))
    )
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(out, encoding="utf-8")
    print(f"wrote {dest} ({len(out.encode('utf-8')) // 1024} KB)")


def publish_preview(dest):
    pin = (HERE / "pages-preview-ref.txt").read_text().strip()
    if not re.fullmatch(r"[a-f0-9]{40}", pin):
        sys.exit("Preview ref must be a full Git commit SHA")
    git = ["git", "-C", str(HERE.parents[1])]
    subprocess.run([*git, "fetch", "--no-tags", "--depth=1", "origin", pin], check=True)
    root = "games/card-clash"
    prefix = f"{root}/assets/"
    snapshot = subprocess.check_output([*git, "archive", pin, f"{root}/src.html", f"{root}/assets"])
    with tarfile.open(fileobj=io.BytesIO(snapshot)) as archive:
        source = archive.extractfile(f"{root}/src.html").read().decode("utf-8")
        assets = {
            member.name.removeprefix(prefix): archive.extractfile(member).read()
            for member in archive
            if member.isfile() and member.name.startswith(prefix)
        }
    build_page(source, dest.parent / "preview" / "index.html", assets)


if __name__ == "__main__":
    dest = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else HERE.parent / "card-clash.html"
    asset_dir = HERE / "assets"
    local_assets = {p.relative_to(asset_dir).as_posix(): p.read_bytes() for p in asset_dir.rglob("*") if p.is_file()}
    build_page((HERE / "src.html").read_text(encoding="utf-8"), dest, local_assets)
    if dest.parent.name == "_site" and dest.name == "index.html":
        publish_preview(dest)
