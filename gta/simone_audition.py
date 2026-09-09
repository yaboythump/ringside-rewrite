from pathlib import Path
import subprocess
import soundfile as sf
from kokoro_onnx import Kokoro

ROOT = Path(__file__).resolve().parent.parent
MODEL = ROOT / 'gta/models/kokoro-v1.0.int8.onnx'
VOICES = ROOT / 'gta/models/voices-v1.0.bin'
OUT = ROOT / 'gta/auditions'
OUT.mkdir(parents=True, exist_ok=True)

TEXT = """Rockstar just confirmed another major GTA Six detail, and this one matters. Forget the rumors for a second. Here is exactly what we know, what Rockstar actually said, and what it means for the game when it launches."""

CANDIDATES = {
    'Simone_Bella': 'af_bella',
    'Simone_Heart': 'af_heart',
    'Simone_Sarah': 'af_sarah',
}
SPEED = 0.98

# More authority than the first test: stronger low-mid body, more presence, tighter compression,
# and less airy top end. This is designed for a confident GTA news host, not a whispery narrator.
FILTER = (
    'highpass=f=65,'
    'bass=g=1.8:f=150,'
    'equalizer=f=650:t=q:w=1.0:g=1.0,'
    'equalizer=f=1900:t=q:w=1.1:g=1.8,'
    'equalizer=f=3200:t=q:w=1.0:g=2.5,'
    'treble=g=-0.8:f=7000,'
    'acompressor=threshold=-20dB:ratio=3.2:attack=8:release=90:makeup=2.2,'
    'loudnorm=I=-14.5:TP=-1.2:LRA=5,'
    'alimiter=limit=0.95'
)

kokoro = Kokoro(str(MODEL), str(VOICES))
for label, voice in CANDIDATES.items():
    raw = OUT / f'{label}_RAW.wav'
    wav = OUT / f'{label}_MASTERED.wav'
    mp3 = OUT / f'{label}_MASTERED.mp3'
    samples, sr = kokoro.create(TEXT, voice=voice, speed=SPEED, lang='en-us')
    sf.write(raw, samples, sr)
    subprocess.run(['ffmpeg','-y','-loglevel','error','-i',str(raw),'-af',FILTER,'-ar','48000','-ac','2',str(wav)], check=True)
    subprocess.run(['ffmpeg','-y','-loglevel','error','-i',str(wav),'-codec:a','libmp3lame','-b:a','192k',str(mp3)], check=True)
    print(f'{label}: {voice} -> {mp3}')
