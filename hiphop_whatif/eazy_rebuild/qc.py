"""Fail-closed media validation shared by the renderer and CI."""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import subprocess
from pathlib import Path
from PIL import Image

EXPECTED_DURATION = 350.29775
SHORT_STARTS = (5, 72, 142, 214, 282)

def checked(command):
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode or result.stderr.strip():
        raise RuntimeError(f"Command failed: {command}\n{result.stderr[-4000:]}")
    return result.stdout

def probe(path):
    return json.loads(checked(['ffprobe', '-v', 'error', '-show_streams',
                              '-show_format', '-of', 'json', str(path)]))

def validate_metadata(data, duration, size, audio=True, frames=None):
    streams = data['streams']
    videos = [s for s in streams if s['codec_type'] == 'video']
    audios = [s for s in streams if s['codec_type'] == 'audio']
    assert len(videos) == 1, 'Expected one video stream'
    video = videos[0]
    assert (video['width'], video['height']) == size, 'Wrong dimensions'
    assert video['codec_name'] == 'h264' and video['pix_fmt'] == 'yuv420p'
    assert video['avg_frame_rate'] == '30/1', 'Wrong frame rate'
    for value in (data['format']['duration'], video['duration']):
        assert math.isfinite(float(value)) and abs(float(value)-duration) < .10, 'Wrong duration'
    assert abs(float(video.get('start_time', 0))) < .05, 'Video start offset'
    if frames is not None:
        assert int(video['nb_frames']) == frames, 'Missing video frames'
    if audio:
        assert len(audios) == 1, 'Missing/extra audio stream'
        a = audios[0]
        assert a['codec_name'] == 'aac' and int(a['sample_rate']) == 48000
        assert a['channels'] == 2
        assert abs(float(a['duration'])-duration) < .10, 'Truncated audio'
        assert abs(float(a.get('start_time', 0))) < .05, 'Audio start offset'
    else:
        assert not audios, 'Scene segments must be video-only'

def validate_media(path, duration, size=(1920,1080), audio=True, frames=None):
    assert path.is_file() and path.stat().st_size > 1024, f'Missing/empty media: {path}'
    data = probe(path)
    validate_metadata(data, duration, size, audio, frames)
    checked(['ffmpeg', '-v', 'error', '-xerror', '-i', str(path),
             '-map', '0:v:0', *(['-map', '0:a:0'] if audio else []), '-f', 'null', '-'])
    return data

def loudness(path):
    result = subprocess.run(['ffmpeg','-v','info','-i',str(path),'-vn','-af',
                             'loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json',
                             '-f','null','-'], capture_output=True, text=True, check=True)
    return json.loads(result.stderr[result.stderr.rfind('{'):])

def package(root):
    # Never leave a stale PASS when validation of a newer render fails.
    report = root/'qc-report.json'
    if report.exists():
        report.unlink()
    files = {}
    for name, duration, size in [('full.mp4', EXPECTED_DURATION, (1920,1080))] + [
        (f'short_{i:02d}.mp4',55,(1080,1920)) for i in range(1,6)
    ]:
        path = root/name
        data = validate_media(path, duration, size)
        levels = loudness(path)
        assert -18 <= float(levels['input_i']) <= -14, f'{name}: loudness outside target'
        assert float(levels['input_tp']) <= -1.0, f'{name}: unsafe true peak'
        with path.open('rb') as media:
            digest = hashlib.file_digest(media, 'sha256').hexdigest()
        files[name] = {'sha256':digest,'duration':float(data['format']['duration']),
                       'integrated_lufs':float(levels['input_i']),
                       'true_peak_dbfs':float(levels['input_tp'])}
    for name,size in [('thumbnail.jpg',(1280,720)),('internal_preview.jpg',(1920,1620))]:
        with Image.open(root/name) as im:
            im.load()
            assert im.size == size
    assert (root/'visual-credits.md').stat().st_size > 200
    report.write_text(json.dumps({'technical_qc':'PASS','files':files},indent=2)+'\n')
    print('EAZY_CINEMATIC_QC_PASS', flush=True)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('output', type=Path, nargs='?', default=Path(__file__).parent/'output')
    package(parser.parse_args().output)
