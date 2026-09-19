#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import gc
import json
import shutil
import subprocess
import tarfile

import torch
import soundfile as sf
from huggingface_hub import snapshot_download
from qwen_tts import Qwen3TTSModel

ROOT = Path("/workspace/ctnetwork-local")
MODEL = ROOT / "models/qwen3-tts/1.7B-VoiceDesign"
OUT = ROOT / "narrator-auditions/female-urban-10"
PACKAGE = Path("/workspace/CTNETWORK_F01-F10_Female_Auditions.tar.gz")

TEXT = (
    "Look, the headline is only the beginning. "
    "The real story is what happened next, why it mattered, and what everybody missed. "
    "This is C T Network, where the details hit different."
)

VOICES = {
    "F01": "Contemporary American female narrator, warm lower-mid register, confident and grounded, relaxed city-media cadence, natural conversational rhythm, subtle edge, premium documentary delivery, never announcer-like.",
    "F02": "Contemporary American female narrator, youthful and bright, quick conversational rhythm, confident social-media energy, crisp articulation, playful but professional, natural rather than theatrical.",
    "F03": "Contemporary American female narrator, smoky low register, calm and serious, intimate late-night documentary tone, measured pacing, subtle tension, grounded and natural.",
    "F04": "Contemporary American female narrator, warm and empathetic, smooth podcast cadence, emotionally intelligent, easy conversational flow, confident without sounding formal, rich mid register.",
    "F05": "Contemporary American female narrator, bold and punchy, entertainment-news energy, sharp rhythmic delivery, confident attitude, lively but controlled, premium urban-media cadence.",
    "F06": "Contemporary American female narrator, mature and polished, deeper register, calm authority, smooth deliberate pacing, sophisticated documentary presence, natural and modern.",
    "F07": "Contemporary American female narrator, relaxed and witty, conversational city cadence, slightly husky texture, effortless confidence, expressive phrasing, not overly polished.",
    "F08": "Contemporary American female narrator, energetic and focused, sports-and-culture media cadence, clear attack on key words, medium-fast pace, confident and modern, never robotic.",
    "F09": "Contemporary American female narrator, husky and cinematic, lower register, serious emotional weight, slow-burn confidence, restrained intensity, premium true-story delivery.",
    "F10": "Contemporary American female narrator, expressive and versatile, confident medium register, natural modern cadence, strong hooks, smooth transitions between serious and upbeat lines.",
}


def run(cmd: list[str]) -> None:
    subprocess.run(cmd, check=True)


def main() -> None:
    if not torch.cuda.is_available():
        raise SystemExit("CUDA_REQUIRED")

    if not MODEL.joinpath("config.json").exists():
        MODEL.mkdir(parents=True, exist_ok=True)
        print("DOWNLOADING_VOICE_DESIGN_MODEL", flush=True)
        snapshot_download(
            repo_id="Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign",
            local_dir=str(MODEL),
        )
        print("VOICE_DESIGN_MODEL_READY", flush=True)

    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True, exist_ok=True)

    tts = Qwen3TTSModel.from_pretrained(
        str(MODEL),
        device_map="cuda:0",
        dtype=torch.bfloat16,
    )

    manifest = {"sample_text": TEXT, "voices": {}}

    for label, instruct in VOICES.items():
        print(f"GENERATING={label}", flush=True)
        wavs, sr = tts.generate_voice_design(
            text=TEXT,
            language="English",
            instruct=instruct,
            max_new_tokens=2048,
        )
        raw = OUT / f"{label}_raw.wav"
        wav = OUT / f"{label}.wav"
        mp3 = OUT / f"{label}.mp3"
        sf.write(raw, wavs[0], sr)

        run([
            "ffmpeg", "-y", "-loglevel", "error", "-i", str(raw),
            "-af",
            "highpass=f=65,acompressor=threshold=-18dB:ratio=2.2:attack=12:release=100,"
            "loudnorm=I=-16:TP=-1.5:LRA=8,alimiter=limit=0.95",
            "-ar", "48000", "-ac", "1", "-c:a", "pcm_s16le", str(wav),
        ])
        run([
            "ffmpeg", "-y", "-loglevel", "error", "-i", str(wav),
            "-b:a", "192k", str(mp3),
        ])

        dur = float(subprocess.check_output([
            "ffprobe", "-v", "error", "-show_entries", "format=duration",
            "-of", "default=nw=1:nk=1", str(wav),
        ], text=True).strip())

        manifest["voices"][label] = {
            "instruction": instruct,
            "duration_seconds": round(dur, 2),
            "wav": wav.name,
            "mp3": mp3.name,
        }
        raw.unlink(missing_ok=True)
        gc.collect()
        torch.cuda.empty_cache()

    silence = OUT / "silence.wav"
    run([
        "ffmpeg", "-y", "-loglevel", "error",
        "-f", "lavfi", "-i", "anullsrc=r=48000:cl=mono",
        "-t", "0.75", "-c:a", "pcm_s16le", str(silence),
    ])

    concat = OUT / "concat.txt"
    lines: list[str] = []
    labels = list(VOICES)
    for i, label in enumerate(labels):
        lines.append(f"file '{OUT / (label + '.wav')}'")
        if i != len(labels) - 1:
            lines.append(f"file '{silence}'")
    concat.write_text("\n".join(lines) + "\n")

    reel = OUT / "CTNETWORK_F01-F10_Female_Audition_Reel.mp3"
    run([
        "ffmpeg", "-y", "-loglevel", "error",
        "-f", "concat", "-safe", "0", "-i", str(concat),
        "-b:a", "192k", str(reel),
    ])
    silence.unlink(missing_ok=True)
    concat.unlink(missing_ok=True)

    OUT.joinpath("manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

    if PACKAGE.exists():
        PACKAGE.unlink()
    with tarfile.open(PACKAGE, "w:gz") as tf:
        tf.add(OUT, arcname="female-urban-10")

    print(f"AUDITION_PACKAGE_READY={PACKAGE}", flush=True)


if __name__ == "__main__":
    main()
