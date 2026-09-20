#!/usr/bin/env python3
from pathlib import Path
import argparse, gc
import numpy as np
import soundfile as sf
import torch
from qwen_tts import Qwen3TTSModel

ROOT = Path("/workspace/ctnetwork-local")
MODEL = ROOT / "models/qwen3-tts/1.7B-Base"

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--text-file",type=Path,required=True)
    ap.add_argument("--ref-audio",type=Path,required=True)
    ap.add_argument("--output",type=Path,required=True)
    args=ap.parse_args()

    if not torch.cuda.is_available():
        raise SystemExit("CUDA_REQUIRED_FOR_QWEN")
    for p in (args.text_file,args.ref_audio):
        if not p.exists() or p.stat().st_size==0:
            raise SystemExit(f"MISSING:{p}")
    text=args.text_file.read_text(encoding="utf-8").strip()
    parts=[p.strip() for p in text.split("\n\n") if p.strip()]
    if not parts: raise SystemExit("EMPTY_TEXT")

    ref_text="This is C T Network. The real story starts where the headline ends. Stay with me."
    model=Qwen3TTSModel.from_pretrained(str(MODEL),device_map="cuda:0",dtype=torch.bfloat16)
    waves=[]; sr0=None
    for i,part in enumerate(parts,1):
        print(f"GENERATING_SECTION={i}/{len(parts)}",flush=True)
        wavs,sr=model.generate_voice_clone(
            text=part,
            language="English",
            ref_audio=str(args.ref_audio),
            ref_text=ref_text,
        )
        w=np.asarray(wavs[0],dtype=np.float32).reshape(-1)
        if sr0 is None: sr0=sr
        if sr != sr0: raise SystemExit(f"SR_MISMATCH:{sr}:{sr0}")
        waves.append(w)
        if i != len(parts):
            waves.append(np.zeros(int(sr0*0.38),dtype=np.float32))
        gc.collect()
        torch.cuda.empty_cache()
    full=np.concatenate(waves)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    sf.write(str(args.output),full,sr0)
    print(f"NARRATION_DONE_SECONDS={len(full)/sr0:.3f}",flush=True)

if __name__=="__main__":
    main()
