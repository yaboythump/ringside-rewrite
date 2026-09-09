from pathlib import Path
import soundfile as sf
from kokoro_onnx import Kokoro

TEXT = """There was a time when picking your Top 8 could actually start an argument. Before Instagram, before TikTok, before Facebook took over the world, there was MySpace. Your profile had a theme, your favorite song started playing whether anybody wanted it to or not, and somehow, everybody was friends with the same dude named Tom. So how did one of the biggest websites on Earth almost completely disappear?"""

MODEL = "marcus/models/kokoro-v1.0.int8.onnx"
VOICES = "marcus/models/voices-v1.0.bin"
OUT = Path("marcus/output")
OUT.mkdir(parents=True, exist_ok=True)

# LOCKED SHOW VOICE: Marcus = Kokoro am_fenrir
# Keep this identity and speed consistent across Whatever Happened To...? episodes.
VOICE = "am_fenrir"
SPEED = 0.94

kokoro = Kokoro(MODEL, VOICES)
samples, sample_rate = kokoro.create(TEXT, voice=VOICE, speed=SPEED, lang="en-us")
raw_path = OUT / "Marcus_Fenrir_RAW.wav"
sf.write(raw_path, samples, sample_rate)
print(f"Created {raw_path} using locked voice {VOICE} at {SPEED}x")
