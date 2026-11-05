#!/usr/bin/env python3
"""Stage the Project 003 proof-of-concept on a private, unlisted review link (same mechanism as
Project 002's dev-raven-cinematic page). Copies files only; touches nothing else in production.
Rollback: delete the printed folder."""
import json
import secrets
import shutil
import sys
import urllib.request
from pathlib import Path

P = Path(sys.argv[1])
POC = P / 'renders/raven-poc'
tok = 'dev-project003-cinematic-' + secrets.token_urlsafe(18)
R = Path('/srv/ctnetwork/review') / tok
R.mkdir(mode=0o755)
files = [('Ringside_Rewrite_Raven_POC_Cinematic.mp4', 'Proof of concept (Project 003 engine)'),
         ('Raven_POC_Before_After.mp4', 'Before / after: published 2026-11-04 vs Project 003')]
imgs = sorted(p.name for p in POC.glob('*_contact.jpg'))
cards = []
for f, title in files:
    if (POC / f).exists():
        shutil.copyfile(POC / f, R / f)
        cards.append(f'<section><h2>{title}</h2><video controls playsinline preload="metadata" src="{f}"></video><p><a href="{f}">Open / download</a></p></section>')
for i in imgs:
    shutil.copyfile(POC / i, R / i)
    cards.append(f'<section><h3>{i.replace("_", " ")}</h3><a href="{i}"><img src="{i}" style="width:100%"></a></section>')
(R / 'index.html').write_text('<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><title>DEV Project 003 cinematic engine</title>'
    '<style>body{max-width:1100px;margin:auto;padding:24px;background:#09090d;color:#fafafa;font:17px system-ui}video{width:100%;max-height:80vh;background:#050505}section{margin:32px 0;border-top:2px solid #af1931}a{color:#eb9aa7}</style>'
    '<h1>DEV TEST: Project 003 premium cinematic engine</h1><p>Engineering proof of concept from existing Raven assets. Not published. Not for upload. Red-outlined tiles in contact sheets are repeated imagery.</p>' + ''.join(cards))
for p in R.iterdir():
    p.chmod(0o644)
base = 'https://66-179-191-248.sslip.io/' + tok + '/'
for n in ['index.html'] + [f for f, _ in files if (R / f).exists()]:
    with urllib.request.urlopen(urllib.request.Request(base + n, headers={'Range': 'bytes=0-1023'}), timeout=30) as r:
        print(r.status, base + n)
(P / 'review_url.txt').write_text(base + 'index.html\n' + str(R) + '\n')
