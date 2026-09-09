from pathlib import Path
import json
import subprocess
import urllib.request
import numpy as np
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

# LOCKED GTA SHOW VOICE: Simone Heart.
VOICE = 'af_heart'
SPEED = 0.98
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'

# Clean-up pass for the static/hiss heard in the first Heart audition, followed by
# a present broadcast-style EQ/compression chain. Keep the top end controlled.
MASTER_FILTER = (
    'highpass=f=72,'
    'lowpass=f=11800,'
    'afftdn=nr=11:nf=-38,'
    'bass=g=1.3:f=150,'
    'equalizer=f=650:t=q:w=1.0:g=0.8,'
    'equalizer=f=2100:t=q:w=1.1:g=1.7,'
    'equalizer=f=3400:t=q:w=1.0:g=1.4,'
    'equalizer=f=7200:t=q:w=1.2:g=-1.4,'
    'acompressor=threshold=-19dB:ratio=2.8:attack=9:release=105:makeup=1.8,'
    'loudnorm=I=-15:TP=-1.2:LRA=5,'
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


def audio_duration(path):
    out = subprocess.check_output([
        'ffprobe', '-v', 'error', '-show_entries', 'format=duration',
        '-of', 'default=nw=1:nk=1', str(path)
    ], text=True).strip()
    return float(out)


def make_music_bed(duration, path, seed=6):
    """Generate a subtle original electronic/news bed locally: no generation credits."""
    sr = 48000
    n = max(1, int(duration * sr))
    t = np.arange(n, dtype=np.float32) / sr
    rng = np.random.default_rng(seed)

    # Dark Vice-City/newsroom pad.
    pad = (
        0.030 * np.sin(2 * np.pi * 55.00 * t) +
        0.016 * np.sin(2 * np.pi * 82.41 * t) +
        0.012 * np.sin(2 * np.pi * 110.00 * t)
    )

    # Soft 100-BPM pulse so the video has movement without fighting narration.
    beat = 60.0 / 100.0
    pulse = np.zeros(n, dtype=np.float32)
    pulse_len = int(0.22 * sr)
    env = np.exp(-np.linspace(0, 5.2, pulse_len, dtype=np.float32))
    tone_t = np.arange(pulse_len, dtype=np.float32) / sr
    kick = 0.055 * np.sin(2 * np.pi * 62.0 * tone_t) * env
    for start_s in np.arange(0, duration, beat):
        start = int(start_s * sr)
        end = min(n, start + pulse_len)
        pulse[start:end] += kick[:end-start]

    # Very restrained hat texture.
    hats = np.zeros(n, dtype=np.float32)
    hat_len = int(0.055 * sr)
    hat_env = np.exp(-np.linspace(0, 7.0, hat_len, dtype=np.float32))
    for start_s in np.arange(beat / 2.0, duration, beat):
        start = int(start_s * sr)
        end = min(n, start + hat_len)
        noise = rng.normal(0, 1, end-start).astype(np.float32)
        hats[start:end] += 0.006 * noise * hat_env[:end-start]

    music = pad + pulse + hats
    # Gentle fade at each segment edge.
    fade_n = min(int(0.6 * sr), n // 2)
    if fade_n > 1:
        fade = np.linspace(0, 1, fade_n, dtype=np.float32)
        music[:fade_n] *= fade
        music[-fade_n:] *= fade[::-1]

    stereo = np.stack([music, music], axis=1)
    sf.write(path, stereo, sr, subtype='PCM_16')


kokoro = Kokoro(str(MODEL), str(VOICES))
full_parts = []
shorts = []

for idx, seg in enumerate(CFG['segments'], start=1):
    image = WORK / f'image_{idx}.jpg'
    raw = WORK / f'simone_{idx}_raw.wav'
    mastered = WORK / f'simone_{idx}_clean.wav'
    music = WORK / f'gta_music_{idx}.wav'
    video = WORK / f'full_{idx}.mp4'
    short = OUT / f"{CFG['slug']}_short_{idx:02d}.mp4"
    headline_file = safe_text_file(f'headline_{idx}.txt', seg['headline'])

    download(seg['image_url'], image)

    samples, sample_rate = kokoro.create(seg['text'], voice=VOICE, speed=SPEED, lang='en-us')
    sf.write(raw, samples, sample_rate)

    run(['ffmpeg', '-y', '-loglevel', 'error', '-i', raw,
         '-af', MASTER_FILTER, '-ar', '48000', '-ac', '2', mastered])

    make_music_bed(audio_duration(mastered) + 0.5, music, seed=600 + idx)

    vf_full = (
        'scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720,'
        'drawbox=x=0:y=0:w=1280:h=72:color=black@0.68:t=fill,'
        f"drawtext=fontfile={FONT}:text='THE SIX REPORT':fontcolor=white:fontsize=31:x=28:y=18,"
        'drawbox=x=0:y=620:w=1280:h=100:color=black@0.58:t=fill,'
        f"drawtext=fontfile={FONT}:textfile={headline_file}:fontcolor=white:fontsize=34:x=36:y=650"
    )
    audio_mix = (
        '[1:a]volume=1.0[voice];'
        '[2:a]volume=0.32[music];'
        '[voice][music]amix=inputs=2:duration=first:dropout_transition=1.5,'
        'alimiter=limit=0.95[aout]'
    )
    run(['ffmpeg', '-y', '-loglevel', 'error', '-loop', '1', '-framerate', '1', '-i', image,
         '-i', mastered, '-i', music, '-vf', vf_full, '-filter_complex', audio_mix,
         '-map', '0:v:0', '-map', '[aout]', '-c:v', 'libx264', '-preset', 'ultrafast',
         '-crf', '26', '-pix_fmt', 'yuv420p', '-r', '12', '-c:a', 'aac', '-b:a', '192k',
         '-shortest', '-movflags', '+faststart', video])
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
         '-i', mastered, '-i', music, '-vf', vf_short, '-filter_complex', audio_mix,
         '-map', '0:v:0', '-map', '[aout]', '-c:v', 'libx264', '-preset', 'ultrafast',
         '-crf', '26', '-pix_fmt', 'yuv420p', '-r', '12', '-c:a', 'aac', '-b:a', '192k',
         '-shortest', '-movflags', '+faststart', short])
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
    'narrator': 'Simone Heart',
    'voice_engine': 'Kokoro ONNX',
    'voice': VOICE,
    'speed': SPEED,
    'generation_credits': 0,
    'audio_cleanup': 'denoise + controlled top end + broadcast EQ/compression',
    'background_music': 'original locally synthesized GTA news bed',
    'title': CFG['title'],
    'full_episode': str(full_out.relative_to(ROOT)),
    'shorts': [str(x.relative_to(ROOT)) for x in shorts],
    'thumbnail': str(thumb.relative_to(ROOT)),
    'sources': CFG.get('sources', [])
}
(OUT / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
print(json.dumps(manifest, indent=2))
