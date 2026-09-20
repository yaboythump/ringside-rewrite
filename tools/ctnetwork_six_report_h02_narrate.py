#!/usr/bin/env python3
from pathlib import Path
import argparse, gc, re
import numpy as np
import soundfile as sf
import torch
from huggingface_hub import snapshot_download
from qwen_tts import Qwen3TTSModel

ROOT = Path("/workspace/ctnetwork-local")
MODEL = ROOT / "models/qwen3-tts/0.6B-Base"
REPO = "Qwen/Qwen3-TTS-12Hz-0.6B-Base"

def split_sentences(text: str):
    parts=[]
    for para in [p.strip() for p in text.split("\n\n") if p.strip()]:
        sents=[s.strip() for s in re.split(r'(?<=[.!?])\s+', para) if s.strip()]
        parts.extend(sents)
        parts.append("__PARA__")
    if parts and parts[-1]=="__PARA__": parts.pop()
    return parts

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

    if not MODEL.joinpath("config.json").exists():
        MODEL.mkdir(parents=True,exist_ok=True)
        print("DOWNLOADING_0.6B_BASE",flush=True)
        snapshot_download(repo_id=REPO,local_dir=str(MODEL))
        print("MODEL_READY",flush=True)

    text=args.text_file.read_text(encoding="utf-8").strip()
    units=split_sentences(text)
    sentences=[u for u in units if u!="__PARA__"]
    ref_text="This is C T Network. The real story starts where the headline ends. Stay with me."

    print(f"LOAD_MODEL sentences={len(sentences)}",flush=True)
    model=Qwen3TTSModel.from_pretrained(
        str(MODEL),
        device_map="cuda:0",
        dtype=torch.bfloat16,
    )
    prompt=model.create_voice_clone_prompt(
        ref_audio=str(args.ref_audio),
        ref_text=ref_text,
        x_vector_only_mode=False,
    )
    print("H02_PROMPT_READY",flush=True)

    sentence_audio=[]
    sr0=None
    batch_size=4
    for start in range(0,len(sentences),batch_size):
        group=sentences[start:start+batch_size]
        print(f"GENERATING_BATCH={start//batch_size+1}/{(len(sentences)+batch_size-1)//batch_size} sentences={start+1}-{start+len(group)}",flush=True)
        wavs,sr=model.generate_voice_clone(
            text=group,
            language=["English"]*len(group),
            voice_clone_prompt=prompt,
            max_new_tokens=420,
        )
        if sr0 is None: sr0=sr
        if sr!=sr0: raise SystemExit(f"SR_MISMATCH:{sr}:{sr0}")
        for w in wavs:
            sentence_audio.append(np.asarray(w,dtype=np.float32).reshape(-1))
        gc.collect(); torch.cuda.empty_cache()

    waves=[]; si=0
    for unit in units:
        if unit=="__PARA__":
            waves.append(np.zeros(int(sr0*0.55),dtype=np.float32))
        else:
            waves.append(sentence_audio[si]); si+=1
            waves.append(np.zeros(int(sr0*0.12),dtype=np.float32))
    full=np.concatenate(waves)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    sf.write(str(args.output),full,sr0)
    print(f"NARRATION_DONE_SECONDS={len(full)/sr0:.3f}",flush=True)

if __name__=="__main__":
    main()
