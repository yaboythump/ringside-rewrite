#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import gc
import json
import subprocess
import time

import numpy as np
import soundfile as sf
import torch
from qwen_tts import Qwen3TTSModel

ROOT = Path("/workspace/ctnetwork-local")
MODEL = ROOT / "models/qwen3-tts/1.7B-Base"
REF = ROOT / "narrator-auditions/female-urban-10/F06.wav"
OUT = ROOT / "narration-jobs/hhwi-ericb-never-met-rakim"
PARTS = OUT / "parts"
MASTER = OUT / "HHWI_What_If_Eric_B_Never_Met_Rakim_F06.wav"
MP3 = OUT / "HHWI_What_If_Eric_B_Never_Met_Rakim_F06.mp3"
PACKAGE = Path("/workspace/HHWI_EricB_Never_Met_Rakim_F06.tar.gz")
STATUS = Path("/workspace/hhwi-ericb-rakim-f06-status.txt")
PROGRESS = Path("/workspace/hhwi-ericb-rakim-f06-progress.json")

REF_TEXT = "This is C T Network. The real story starts where the headline ends. Stay with me."

CHUNKS = [
"""Before Paid in Full became one of the defining records of hip-hop’s golden age, there was a much simpler turning point: Eric B. and Rakim had to meet. In the real timeline, their partnership formed in the mid-1980s, “Eric B. Is President” arrived in 1986, and their debut album Paid in Full followed in 1987. But what if that connection never happened? What if two people who helped reshape rap simply moved through New York on separate tracks? This is Hip Hop What If.""",
"""In this alternate timeline, Eric B. is still chasing the same thing: the right voice to put over his records. He has the records, the DJ instincts, the ambition, and the connections to keep moving. But Rakim never becomes that voice. Maybe a phone call never gets made. Maybe an introduction falls through. Maybe one of them is somewhere else that night. Whatever the reason, the partnership never starts, and hip-hop loses one of those combinations that feels obvious only after history already happened.""",
"""Eric B. probably does not disappear. In New York’s mid-eighties scene, a strong DJ with ambition could still build a name through clubs, parks, tapes, studios, and the right local relationships. So in this timeline, he keeps searching. He might pair with another MC, produce records for somebody else, or become known more for his ear and his turntable presence than for a legendary duo. He could still matter. But without Rakim, the ceiling, the sound, and the legacy are completely different.""",
"""Rakim’s path is even more interesting. The ability is still there. The calm delivery is still there. The internal rhymes, the precision, the way he could make complicated writing sound effortless — none of that depended on meeting Eric B. But talent and timing are two different things. Without that partnership opening the right door at the right moment, Rakim might spend longer in the underground, building reputation through tapes, local performances, and word of mouth before the industry catches up to what other MCs already recognize.""",
"""And that delay changes more than one career. Rakim’s influence was not just about hit records. His style helped push rap toward denser rhyme patterns, smoother control, and a different kind of technical confidence. In this timeline, those ideas probably still emerge, because hip-hop was already evolving fast. But maybe they spread more slowly. Maybe another MC gets credited with moving the form forward first. Maybe the lyrical arms race of the late eighties develops on a different schedule, with different names setting the standard.""",
"""Then there is the missing music itself. Without Eric B. and Rakim as a duo, there is no Paid in Full in the form the culture knows. No exact combination of Rakim’s voice with Eric B.’s identity around those records. No same sequence of singles, album cuts, performances, and images defining that moment. Another record takes some of that space. Another duo gets another magazine cover. Another MC becomes the reference point young rappers study when they are trying to figure out what the next level sounds like.""",
"""That vacuum could create opportunity everywhere. Marley Marl’s orbit, Juice Crew competitors, emerging Long Island artists, and countless New York MC-and-DJ combinations were already fighting for attention. If one of the era’s most important partnerships never happens, somebody else benefits. Maybe a rival gets a longer run. Maybe another technically gifted rapper breaks nationally sooner. Maybe labels spend their money differently. Hip-hop history rarely leaves empty space for long. When one door stays closed, somebody eventually walks through another one.""",
"""But there is another possibility: Rakim eventually finds a different producer or DJ who understands exactly what he is doing. If that happens, he may still become a major figure — just with a different sonic identity. The voice could be the same while the drums, samples, pacing, and image around him change completely. Eric B. could also find another MC and build a respectable catalog. Both men might still become successful. They just would not become Eric B. and Rakim, the name that history remembers as one unit.""",
"""And that is what makes this what-if so big. Sometimes history changes because of a contract, a tragedy, or a battle. Sometimes it changes because two people are simply in the same place at the right time. Take away one meeting in mid-eighties New York, and the golden age still happens. Hip-hop still grows. Great MCs still arrive. But the road there sounds different, the standard changes at a different speed, and one of the culture’s most important partnerships becomes a story that never existed. What if Eric B. never met Rakim?"""
]

def run(cmd):
    print("+", " ".join(map(str, cmd)), flush=True)
    subprocess.run([str(x) for x in cmd], check=True)

def valid_audio(path: Path) -> bool:
    if not path.exists() or path.stat().st_size < 4096:
        return False
    try:
        dur = float(subprocess.check_output([
            "ffprobe","-v","error","-show_entries","format=duration",
            "-of","default=nw=1:nk=1",str(path)
        ], text=True).strip())
        return dur > 2.0
    except Exception:
        return False

def write_progress(done: int, current: int | None = None, state: str = "running"):
    PROGRESS.write_text(json.dumps({
        "state": state,
        "completed_chunks": done,
        "total_chunks": len(CHUNKS),
        "current_chunk": current
    }, indent=2) + "\n")

def main():
    STATUS.unlink(missing_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    PARTS.mkdir(parents=True, exist_ok=True)

    if not torch.cuda.is_available():
        raise SystemExit("CUDA_REQUIRED_FOR_F06")
    if not REF.exists() or REF.stat().st_size < 4096:
        raise SystemExit(f"F06_REFERENCE_MISSING:{REF}")
    if not MODEL.exists():
        raise SystemExit(f"QWEN_MODEL_MISSING:{MODEL}")

    print("LOADING_QWEN_F06", flush=True)
    tts = Qwen3TTSModel.from_pretrained(
        str(MODEL),
        device_map="cuda:0",
        dtype=torch.bfloat16,
    )

    completed = 0
    write_progress(0)

    for i, text in enumerate(CHUNKS, 1):
        clean = PARTS / f"part_{i:02d}.wav"
        raw = PARTS / f"part_{i:02d}_raw.wav"

        if valid_audio(clean):
            completed += 1
            print(f"REUSE_CHUNK {i}/{len(CHUNKS)}", flush=True)
            write_progress(completed, i)
            continue

        last_error = None
        for attempt in range(1, 4):
            try:
                print(f"F06_CHUNK {i}/{len(CHUNKS)} ATTEMPT {attempt}/3 chars={len(text)}", flush=True)
                torch.manual_seed(606)
                wavs, sr = tts.generate_voice_clone(
                    text=text,
                    language="English",
                    ref_audio=str(REF),
                    ref_text=REF_TEXT,
                )
                x = np.asarray(wavs[0], dtype=np.float32).squeeze()
                sf.write(str(raw), x, sr)
                run([
                    "ffmpeg","-y","-loglevel","error","-i",str(raw),
                    "-af",
                    "highpass=f=65,acompressor=threshold=-18dB:ratio=2.2:attack=12:release=100,"
                    "loudnorm=I=-16:TP=-1.5:LRA=8,alimiter=limit=0.95",
                    "-ar","48000","-ac","1","-c:a","pcm_s16le",str(clean)
                ])
                raw.unlink(missing_ok=True)
                if not valid_audio(clean):
                    raise RuntimeError("chunk QC failed")
                completed += 1
                write_progress(completed, i)
                last_error = None
                break
            except Exception as exc:
                last_error = repr(exc)
                print(f"CHUNK_RETRY {i} attempt={attempt} error={last_error}", flush=True)
                raw.unlink(missing_ok=True)
                clean.unlink(missing_ok=True)
                gc.collect()
                torch.cuda.empty_cache()
                time.sleep(3)
        if last_error is not None:
            write_progress(completed, i, "failed")
            raise RuntimeError(f"F06 chunk {i} failed after 3 attempts: {last_error}")

        gc.collect()
        torch.cuda.empty_cache()

    concat = OUT / "concat.txt"
    concat.write_text("\n".join(f"file '{PARTS / f'part_{i:02d}.wav'}'" for i in range(1, len(CHUNKS)+1)) + "\n")
    stitched = OUT / "stitched.wav"
    run([
        "ffmpeg","-y","-loglevel","error","-f","concat","-safe","0","-i",str(concat),
        "-c:a","pcm_s16le","-ar","48000","-ac","1",str(stitched)
    ])
    run([
        "ffmpeg","-y","-loglevel","error","-i",str(stitched),
        "-af","loudnorm=I=-16:TP=-1.5:LRA=8,alimiter=limit=0.95",
        "-ar","48000","-ac","1","-c:a","pcm_s16le",str(MASTER)
    ])
    run(["ffmpeg","-y","-loglevel","error","-i",str(MASTER),"-b:a","192k",str(MP3)])

    dur = float(subprocess.check_output([
        "ffprobe","-v","error","-show_entries","format=duration",
        "-of","default=nw=1:nk=1",str(MASTER)
    ], text=True).strip())
    if dur < 180:
        raise RuntimeError(f"MASTER_TOO_SHORT:{dur}")

    manifest = {
        "show": "Hip Hop What If",
        "episode": "What If Eric B. Never Met Rakim?",
        "narrator": "F06",
        "engine": "Qwen3-TTS 1.7B Base voice clone",
        "chunks": len(CHUNKS),
        "duration_seconds": round(dur, 3),
        "sample_rate": 48000,
        "channels": 1,
        "resume_safe": True,
        "main_ctnetwork_runtime_used": False,
    }
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

    if PACKAGE.exists():
        PACKAGE.unlink()
    run(["tar","-czf",str(PACKAGE),"-C",str(OUT.parent),OUT.name])

    write_progress(len(CHUNKS), len(CHUNKS), "complete")
    STATUS.write_text("0")
    print("F06_NARRATION_READY", json.dumps(manifest), flush=True)

if __name__ == "__main__":
    main()
