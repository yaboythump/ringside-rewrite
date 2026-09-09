from pathlib import Path
import json
import subprocess
import urllib.request
import soundfile as sf
from kokoro_onnx import Kokoro

ROOT = Path(__file__).resolve().parent.parent
CFG = json.loads((ROOT / 'gta' / 'episode.json').read_text())
WORK = ROOT / 'gta' / 'work'
OUT = ROOT / 'gta' / 'output'
MODEL_DIR = ROOT / 'gta' / 'models'
WORK.mkdir(parents=True, exist_ok=True)
OUT.mkdir(parents=True, exist_ok=True)
MODEL_DIR.mkdir(parents=True, exist_ok=True)

MODEL = MODEL_DIR / 'kokoro-v1.0.int8.onnx'
VOICES = MODEL_DIR / 'voices-v1.0.bin'
VOICE = 'af_nicole'  # locked Simone zero-credit identity
SPEED = 0.96
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'

MASTER_FILTER = (
    'highpass=f=70,'
    'bass=g=0.4:f=150,'
    'treble=g=-0.3:f=6500,'
    'equalizer=f=2800:t=q:w=1.2:g=1.0,'
    'acompressor=threshold=-18dB:ratio=2.3:attack=15:release=120:makeup=1.4,'
    'loudnorm=I=-16:TP=-1.5:LRA=7,'
    'alimiter=limit=0.95'
)


def run(cmd):
    print('+', ' '.join(map(str, cmd)))
    subprocess.run([str(x) for x in cmd], check=True)


def download(url, dest):
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req, timeout=60) as r, open(dest, 'wb') as f:
        f.write(r.read())


def safe_text_file(name, text):
    p = WORK / name
    p.write_text(text, encoding='utf-8')
    return p


kokoro = Kokoro(str(MODEL), str(VOICES))
full_parts = []
shorts = []

for idx, seg in enumerate(CFG['segments'], start=1):
    image = WORK / f'image_{idx}.jpg'
    raw = WORK / f'simone_{idx}_raw.wav'
    mastered = WORK / f'simone_{idx}.wav'
    video = WORK / f'full_{idx}.mp4'
    short = OUT / f"{CFG['slug']}_short_{idx:02d}.mp4"
    headline_file = safe_text_file(f'headline_{idx}.txt', seg['headline'])

    download(seg['image_url'], image)

    samples, sample_rate = kokoro.create(seg['text'], voice=VOICE, speed=SPEED, lang='en-us')
    sf.write(raw, samples, sample_rate)

    run(['ffmpeg', '-y', '-loglevel', 'error', '-i', raw,
         '-af', MASTER_FILTER, '-ar', '48000', '-ac', '2', mastered])

    vf_full = (
        'scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720,'
        'drawbox=x=0:y=0:w=1280:h=72:color=black@0.68:t=fill,'
        f"drawtext=fontfile={FONT}:text='THE SIX REPORT':fontcolor=white:fontsize=31:x=28:y=18,"
        'drawbox=x=0:y=620:w=1280:h=100:color=black@0.58:t=fill,'
        f"drawtext=fontfile={FONT}:textfile={headline_file}:fontcolor=white:fontsize=34:x=36:y=650"
    )
    run(['ffmpeg', '-y', '-loglevel', 'error', '-loop', '1', '-framerate', '1', '-i', image,
         '-i', mastered, '-vf', vf_full, '-map', '0:v:0', '-map', '1:a:0', '-c:v', 'libx264',
         '-preset', 'ultrafast', '-crf', '26', '-pix_fmt', 'yuv420p', '-r', '12', '-c:a', 'aac',
         '-b:a', '160k', '-shortest', '-movflags', '+faststart', video])
    full_parts.append(video)

    vf_short = (
        'scale=720:1280:force_original_aspect_ratio=increase,crop=720:1280,'
        'drawbox=x=0:y=0:w=720:h=176:color=black@0.72:t=fill,'
        f"drawtext=fontfile={FONT}:text='THE SIX REPORT':fontcolor=white:fontsize=29:x=28:y=26,"
        f"drawtext=fontfile={FONT}:text='GTA':fontcolor=0x00E6FF:fontsize=27:x=28:y=72,"
        f"drawtext=fontfile={FONT}:textfile={headline_file}:fontcolor=white:fontsize=27:x=28:y=118,"
        'drawbox=x=0:y=1150:w=720:h=78:color=black@0.62:t=fill,'
        f"drawtext=fontfile={FONT}:text='FULL EPISODE - THE SIX REPORT':fontcolor=white:fontsize=21:x=86:y=1176"
    )
    run(['ffmpeg', '-y', '-loglevel', 'error', '-loop', '1', '-framerate', '1', '-i', image,
         '-i', mastered, '-vf', vf_short, '-map', '0:v:0', '-map', '1:a:0', '-c:v', 'libx264',
         '-preset', 'ultrafast', '-crf', '26', '-pix_fmt', 'yuv420p', '-r', '12', '-c:a', 'aac',
         '-b:a', '160k', '-shortest', '-movflags', '+faststart', short])
    shorts.append(short)

concat = WORK / 'full-list.txt'
concat.write_text(''.join(f"file '{p.resolve()}'\n" for p in full_parts), encoding='utf-8')
full_out = OUT / f"{CFG['slug']}_full.mp4"
run(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', concat,
     '-c', 'copy', '-movflags', '+faststart', full_out])

thumb_head = safe_text_file('thumb_head.txt', CFG['thumbnail_headline'])
thumb_sub = safe_text_file('thumb_sub.txt', CFG['thumbnail_subhead'])
thumb = OUT / f"{CFG['slug']}_thumbnail.jpg"
thumb_vf = (
    'scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720,'
    'drawbox=x=0:y=0:w=790:h=720:color=black@0.60:t=fill,'
    f"drawtext=fontfile={FONT}:text='THE SIX REPORT':fontcolor=white:fontsize=38:x=42:y=42,"
    f"drawtext=fontfile={FONT}:textfile={thumb_head}:fontcolor=0x00E6FF:fontsize=70:x=42:y=185,"
    f"drawtext=fontfile={FONT}:textfile={thumb_sub}:fontcolor=white:fontsize=34:x=44:y=320"
)
run(['ffmpeg', '-y', '-loglevel', 'error', '-i', WORK / 'image_1.jpg', '-vf', thumb_vf,
     '-frames:v', '1', thumb])

manifest = {
    'show': CFG['show'],
    'narrator': 'Simone',
    'voice_engine': 'Kokoro ONNX',
    'voice': VOICE,
    'speed': SPEED,
    'generation_credits': 0,
    'title': CFG['title'],
    'full_episode': str(full_out.relative_to(ROOT)),
    'shorts': [str(x.relative_to(ROOT)) for x in shorts],
    'thumbnail': str(thumb.relative_to(ROOT)),
    'sources': CFG.get('sources', [])
}
(OUT / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
print(json.dumps(manifest, indent=2))
