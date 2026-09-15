#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

import requests

MEDIA_API = 'https://api.upload-post.com/api/uploadposts/media'
SOURCE_IDS = [
    '363068784190156_122288036642062695',
    '363068784190156_122288051144062695',
    '363068784190156_122288070266062695',
]
CAPTIONS = [
    "What if D’Lo Brown’s powerbomb landed safely and Droz got back up? #RingsideRewrite #DLoBrown #Droz #WWE #WrestlingShorts",
    "If Droz keeps wrestling, he and Prince Albert enter the WWF tag-team war. #RingsideRewrite #Droz #WWE #AttitudeEra #WrestlingShorts",
    "One move changed two careers. Here’s the future Droz and D’Lo never got. #RingsideRewrite #DLoBrown #Droz #WWE #WrestlingShorts",
]


def probe(path: Path) -> tuple[int, int, float]:
    raw = subprocess.check_output([
        'ffprobe','-v','error','-select_streams','v:0',
        '-show_entries','stream=width,height:format=duration','-of','json',str(path)
    ], text=True)
    data = json.loads(raw)
    stream = data['streams'][0]
    return int(stream['width']), int(stream['height']), float(data['format']['duration'])


def main() -> None:
    key = os.environ.get('UPLOAD_POST_API_KEY', '').strip()
    if not key:
        raise SystemExit('UPLOAD_POST_API_KEY is required')

    response = requests.get(
        MEDIA_API,
        headers={'Authorization': f'Apikey {key}'},
        params={'platform':'facebook','user':'Ringsiderewrite','limit':50},
        timeout=60,
    )
    response.raise_for_status()
    media = {item.get('id'): item for item in response.json().get('media', [])}

    out = Path('dlo-tiktok-repair')
    out.mkdir(exist_ok=True)
    vf = (
        '[0:v]split=2[background][foreground];'
        '[background]scale=1080:1920:force_original_aspect_ratio=increase,'
        'crop=1080:1920,gblur=sigma=32,eq=brightness=-0.12[bg];'
        '[foreground]scale=1080:1920:force_original_aspect_ratio=decrease[fg];'
        '[bg][fg]overlay=(W-w)/2:(H-h)/2,format=yuv420p[video]'
    )

    receipt = []
    for i, source_id in enumerate(SOURCE_IDS, 1):
        item = media.get(source_id)
        if not item or not item.get('media_url'):
            raise RuntimeError(f'Facebook source unavailable: {source_id}')
        source = out / f'source-{i:02d}.mp4'
        with requests.get(item['media_url'], stream=True, timeout=120) as download:
            download.raise_for_status()
            with source.open('wb') as fh:
                for chunk in download.iter_content(1024 * 1024):
                    if chunk:
                        fh.write(chunk)

        dest = out / f'DLo_Droz_TikTok_{i:02d}.mp4'
        subprocess.run([
            'ffmpeg','-y','-i',str(source),'-filter_complex',vf,
            '-map','[video]','-map','0:a?','-c:v','libx264','-preset','veryfast','-crf','20',
            '-c:a','aac','-b:a','192k','-movflags','+faststart',str(dest)
        ], check=True)
        width, height, duration = probe(dest)
        print(f'TIKTOK QC {i}: {width}x{height}, {duration:.3f}s')
        if (width, height) != (1080, 1920) or duration > 59.2:
            raise RuntimeError(f'TikTok short {i} failed QC')

        subprocess.run([
            'python','scripts/publish_tiktok.py',
            '--profile','Ringsiderewrite',
            '--video',str(dest),
            '--caption',CAPTIONS[i-1],
            '--privacy','PUBLIC_TO_EVERYONE',
        ], check=True)
        receipt.append({'index':i,'source_id':source_id,'width':width,'height':height,'duration':duration})

    (out / 'receipt.json').write_text(json.dumps(receipt, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
