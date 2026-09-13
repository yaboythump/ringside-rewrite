#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path

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


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--video-id', default='O4DB032Y22U')
    args = ap.parse_args()

    out = Path('dlo-rebuilt-shorts')
    out.mkdir(exist_ok=True)
    master = out / 'dlo-master.mp4'

    run([
        'yt-dlp',
        '--no-playlist',
        '-f', 'bv*[height<=1080]+ba/b[height<=1080]',
        '--merge-output-format', 'mp4',
        '-o', str(master),
        f'https://www.youtube.com/watch?v={args.video_id}',
    ])
    if not master.exists():
        # yt-dlp may append an extension despite merge-output-format.
        matches = sorted(out.glob('dlo-master*.mp4'))
        if not matches:
            raise RuntimeError('Could not recover the published DLo master.')
        master = matches[0]

    full = probe(master)
    full_duration = float(full['format']['duration'])
    print(f'Master duration: {full_duration:.3f}s')
    if full_duration < 300:
        raise RuntimeError('Downloaded master is unexpectedly short; refusing repair.')

    # Three story beats spread across the 5:33 master: opening consequence/hook,
    # alternate-career middle, and legacy/payoff section. Each stays safely below 60s.
    cuts = [
        (0.0, 58.8),
        (122.0, 58.8),
        (244.0, 58.8),
    ]
    titles = [
        "What If D’Lo Brown Never Injured Droz? | Ringside Rewrite #Shorts",
        "Droz’s Career Continues — Then Everything Changes | Ringside Rewrite #Shorts",
        "The D’Lo Brown Future We Never Saw | Ringside Rewrite #Shorts",
    ]
    hooks = [
        "One move changed two careers. What if that night ended differently?",
        "If Droz keeps wrestling, the entire Attitude Era gets another timeline.",
        "D’Lo Brown carried that night for years. What changes if the injury never happens?",
    ]

    shorts: list[Path] = []
    vf = (
        '[0:v]split=2[background][foreground];'
        '[background]scale=1080:1920:force_original_aspect_ratio=increase,'
        'crop=1080:1920,gblur=sigma=32,eq=brightness=-0.12[bg];'
        '[foreground]scale=1080:1920:force_original_aspect_ratio=decrease[fg];'
        '[bg][fg]overlay=(W-w)/2:(H-h)/2-120,format=yuv420p[video]'
    )
    for i, (start, duration) in enumerate(cuts, 1):
        dest = out / f'DLo_Droz_Short_{i:02d}.mp4'
        run([
            'ffmpeg','-y','-ss',f'{start:.3f}','-i',str(master),
            '-t',f'{duration:.3f}',
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

    # Recheck immediately before upload. The only DLo/Droz video is allowed to be
    # the protected full episode. If another matching child appears, stop rather
    # than creating duplicates.
    search = service.search().list(
        part='id,snippet', forMine=True, type='video', order='date', maxResults=50
    ).execute()
    matching = []
    for item in search.get('items', []):
        vid = item.get('id', {}).get('videoId', '')
        title = item.get('snippet', {}).get('title', '')
        t = title.replace('’', "'").casefold()
        if vid != args.video_id and ("d'lo" in t or 'droz' in t):
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
            f'From: “What If D’Lo Brown Never Injured Droz?”\n'
            f'Watch the full Ringside Rewrite episode: https://youtu.be/{args.video_id}\n\n'
            '#RingsideRewrite #WrestlingShorts #WWE #DLoBrown #Droz'
        )
        video_id = _upload_video(
            service, settings, path, titles[i], description, base_tags,
            'public', None
        )
        uploaded.append({'index': i+1, 'id': video_id, 'url': f'https://youtu.be/{video_id}', 'title': titles[i]})
        print(f'UPLOADED SHORT {i+1}: {video_id}')

    receipt = {
        'protected_full_episode': args.video_id,
        'old_child_uploads_found': 0,
        'new_shorts': uploaded,
    }
    (out / 'repair-receipt.json').write_text(json.dumps(receipt, indent=2), encoding='utf-8')
    print(json.dumps(receipt, indent=2))


if __name__ == '__main__':
    main()
