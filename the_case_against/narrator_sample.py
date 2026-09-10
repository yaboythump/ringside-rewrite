from pathlib import Path
import soundfile as sf
from kokoro_onnx import Kokoro

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "published-assets" / "the-case-against" / "narrator-audition"
OUT.mkdir(parents=True, exist_ok=True)

MODEL = ROOT / "kokoro-v1.0.int8.onnx"
VOICES = ROOT / "voices-v1.0.bin"

# Malik candidate: distinct from Marcus (am_fenrir).
VOICE = "am_onyx"
SPEED = 0.93

TEXT = (
    "LeBron James has one of the greatest resumes basketball has ever seen. "
    "But greatest resume and greatest player are not automatically the same thing. "
    "Tonight, we put the GOAT case on trial. Finals record. Team construction. Peak versus longevity. "
    "No hate. No fan fiction. Just the strongest case the other side can make. "
    "Case made. You decide."
)

kokoro = Kokoro(str(MODEL), str(VOICES))
samples, sr = kokoro.create(TEXT, voice=VOICE, speed=SPEED, lang="en-us")

wav = OUT / "malik_am_onyx_raw.wav"
sf.write(wav, samples, sr)
print(f"Wrote {wav} at {sr} Hz")
