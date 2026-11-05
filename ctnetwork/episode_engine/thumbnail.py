#!/usr/bin/env python3
"""Prepare the approved chat-made thumbnail for upload. No generation, no redesign.

Only resamples to the platform size (1280x720 for YouTube masters, 1080x1920
for Shorts covers) and re-encodes under YouTube's 2 MB limit. If the source
aspect differs from the target by more than 3 % it refuses rather than crop
an approved composition.
"""
from __future__ import annotations

import argparse
import io
from pathlib import Path

from PIL import Image


def prepare(src, dst, width=1280, height=720, max_bytes=2 * 1024 * 1024, max_aspect_error=0.03):
    src, dst = Path(src), Path(dst)
    with Image.open(src) as im:
        im = im.convert('RGB')
        r_src, r_dst = im.width / im.height, width / height
        if abs(r_src / r_dst - 1) > max_aspect_error:
            raise ValueError(f'{src.name}: aspect {r_src:.3f} vs {r_dst:.3f}; refusing to crop an approved design')
        im = im.resize((width, height), Image.LANCZOS)
        for q in (95, 92, 90, 87, 84, 80):
            buf = io.BytesIO()
            im.save(buf, 'JPEG', quality=q, optimize=True, progressive=True, subsampling=0 if q >= 90 else 2)
            if buf.tell() <= max_bytes:
                break
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(buf.getvalue())
    return {'source': str(src), 'file': str(dst), 'quality': q, 'bytes': dst.stat().st_size}


if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('src')
    ap.add_argument('dst')
    ap.add_argument('--width', type=int, default=1280)
    ap.add_argument('--height', type=int, default=720)
    a = ap.parse_args()
    print(prepare(a.src, a.dst, a.width, a.height))
