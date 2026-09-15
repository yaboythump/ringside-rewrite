#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import subprocess
from pathlib import Path

import requests

from ringside.config import load_settings
from ringside.youtube import _upload_video, youtube_service


def run(cmd: list[str]) -> None:
    print('+', ' '.join(cmd))
    subprocess.run(cmd, check=True)


def probe(path: Path) -> dict:
    return json.loads(subprocess.check_output([
        'ffprobe','-v','error','-select_streams','v:0',
        '-show_entries','stream=width,height:format=duration',
        '-of','json',str(path)
    ], text=True))


def download(url: str, path: Path) -> None:
    with requests.get(url, stream=True, timeout=120) as response:
        response.raise_for_status()
        with path.open('wb') as fh:
            for chunk in response.iter_content(chunk_size=1024 * 1024):
                if chunk:
                    fh.write(chunk)


def fetch_approved_facebook_sources(out: Path) -> list[Path]:
    key = os.environ.get('UPLOAD_POST_API_KEY', '').strip()
    if not key:
        raise RuntimeError('UPLOAD_POST_API_KEY is required to recover the approved Facebook short cuts.')

    target_ids = [
        '363068784190156_122288036642062695',
        '363068784190156_122288051144062695',
        '363068784190156_122288070266062695',
    ]
    response = requests.get(
        'https://api.upload-post.com/api/uploadposts/media',
        headers={'Authorization': f'Apikey {key}'},
        params={'platform': 'facebook', 'user': 'Ringsiderewrite', 'limit': 50},
        timeout=60,
    )
    response.raise_for_status()
    data = response.json()
    media = {item.get('id'): item for item in data.get('media', [])}

    sources: list[Path] = []
    for index, media_id in enumerate(target_ids, 1):
        item = media.get(media_id)
        if not item:
            raise RuntimeError(f'Approved Facebook source {media_id} was not found.')
        media_url = item.get('media_url')
        if not media_url:
            raise RuntimeError(f'Approved Facebook source {media_id} has no downloadable media_url.')
        src = out / f'DLo_Droz_Approved_Source_{index:02d}.mp4'
        download(media_url, src)
        info = probe(src)
        stream = info['streams'][0]
        duration = float(info['format']['duration'])
        print(f'SOURCE {index}: {stream["width"]}x{stream["height"]}, {duration:.3f}s, Facebook ID {media_id}')
        if duration < 20 or duration > 59.2:
            raise RuntimeError(f'Approved source {index} has unsafe duration {duration:.3f}s.')
        sources.append(src)
    return sources


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--video-id', default='O4DB032Y22U')
    args = ap.parse_args()

    out = Path('dlo-rebuilt-shorts')
    out.mkdir(exist_ok=True)
    sources = fetch_approved_facebook_sources(out)

    titles = [
        "What If The Move Landed Safely? | Ringside Rewrite #Shorts",
        "Droz & Prince Albert Enter The Tag War | Ringside Rewrite #Shorts",
        "One Move Changed Two Careers | Ringside Rewrite #Shorts",
    ]
    hooks = [
        "October 5, 1999 changes completely if D’Lo Brown’s running powerbomb lands safely and Droz gets back up.",
        "If Droz’s career continues, he and Prince Albert become a wrecking crew in the WWF tag-team era.",
        "In this alternate timeline, Droz gets years of matches and D’Lo keeps moving forward without that night defining his career.",
    ]

    shorts: list[Path] = []
    vf = (
        '[0:v]split=2[background][foreground];'
        '[background]scale=1080:1920:force_original_aspect_ratio=increase,'
        'crop=1080:1920,gblur=sigma=32,eq=brightness=-0.12[bg];'
        '[foreground]scale=1080:1920:force_original_aspect_ratio=decrease[fg];'
        '[bg][fg]overlay=(W-w)/2:(H-h)/2,format=yuv420p[video]'
    )
    for i, source in enumerate(sources, 1):
        dest = out / f'DLo_Droz_Short_{i:02d}.mp4'
        run([
            'ffmpeg','-y','-i',str(source),
            '-filter_complex',vf,
            '-map','[video]','-map','0:a?',
            '-c:v','libx264','-preset','medium','-crf','19',
            '-c:a','aac','-b:a','192k','-movflags','+faststart',str(dest)
        ])
        data = probe(dest)
        s = data['streams'][0]
        dur = float(data['format']['duration'])
        print(f'QC short {i}: {s["width"]}x{s["height"]}, {dur:.3f}s')
        if (int(s['width']), int(s['height'])) != (1080, 1920):
            raise RuntimeError(f'Short {i} failed vertical QC.')
        if dur > 59.2:
            raise RuntimeError(f'Short {i} failed duration QC: {dur:.3f}s')
        shorts.append(dest)

    settings = load_settings(Path.cwd())
    service = youtube_service(settings, interactive=False)

    known_failed_ids = {
        '8rau0GIKiv8', 'T9Y7Cgp-3Bc', 'BgX-u8PKAeo',
        'fFlMFMGQmho', 'FSBWD4YQf_Y', 'znMlDBzizDY',
    }

    search = service.search().list(
        part='id,snippet', forMine=True, type='video', order='date', maxResults=50
    ).execute()
    matching = []
    for item in search.get('items', []):
        vid = item.get('id', {}).get('videoId', '')
        title = item.get('snippet', {}).get('title', '')
        t = title.replace('’', "'").casefold()
        if vid == args.video_id or vid in known_failed_ids:
            continue
        if "d'lo" in t or 'droz' in t:
            matching.append({'id': vid, 'title': title})
    if matching:
        raise RuntimeError(f'Safety stop: unexpected existing DLo/Droz child uploads appeared: {matching}')

    uploaded = []
    base_tags = [
        'Ringside Rewrite','DLo Brown','Droz','WWE','WWF','wrestling what if',
        'fantasy booking','wrestling history','wrestling shorts','Shorts'
    ]
    for i, path in enumerate(shorts):
        description = (
            f'{hooks[i]}\n\n'
            f'Full episode: What If D’Lo Brown Never Injured Droz?\n'
            f'https://youtu.be/{args.video_id}\n\n'
            '#RingsideRewrite #WrestlingShorts #WWE #DLoBrown #Droz #Shorts'
        )
        video_id = _upload_video(
            service, settings, path, titles[i], description, base_tags,
            'public', None
        )
        uploaded.append({'index': i+1, 'id': video_id, 'url': f'https://youtu.be/{video_id}', 'title': titles[i]})
        print(f'UPLOADED SHORT {i+1}: {video_id}')

    receipt = {
        'protected_full_episode': args.video_id,
        'source': 'approved Facebook DLo/Droz short cuts',
        'facebook_source_ids': [
            '363068784190156_122288036642062695',
            '363068784190156_122288051144062695',
            '363068784190156_122288070266062695',
        ],
        'known_failed_horizontal_ids_ignored': sorted(known_failed_ids),
        'new_shorts': uploaded,
    }
    (out / 'repair-receipt.json').write_text(json.dumps(receipt, indent=2), encoding='utf-8')
    print(json.dumps(receipt, indent=2))


if __name__ == '__main__':
    main()
