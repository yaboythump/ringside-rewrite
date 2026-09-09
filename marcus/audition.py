from pathlib import Path
import soundfile as sf
from kokoro_onnx import Kokoro

TEXT = """There was a time when picking your Top 8 could actually start an argument. Before Instagram, before TikTok, before Facebook took over the world, there was MySpace. Your profile had a theme, your favorite song started playing whether anybody wanted it to or not, and somehow, everybody was friends with the same dude named Tom. So how did one of the biggest websites on Earth almost completely disappear?"""

MODEL = "marcus/models/kokoro-v1.0.int8.onnx"
VOICES = "marcus/models/voices-v1.0.bin"
OUT = Path("marcus/output")
OUT.mkdir(parents=True, exist_ok=True)

kokoro = Kokoro(MODEL, VOICES)

candidates = [
    ("Marcus_A_Michael", "am_michael", 0.96),
    ("Marcus_B_Fenrir", "am_fenrir", 0.94),
    ("Marcus_C_Puck", "am_puck", 0.97),
]

for filename, voice, speed in candidates:
    samples, sample_rate = kokoro.create(TEXT, voice=voice, speed=speed, lang="en-us")
    path = OUT / f"{filename}.wav"
    sf.write(path, samples, sample_rate)
    print(f"Created {path} using {voice} at {speed}x")
