#!/usr/bin/env python3
from __future__ import annotations
import argparse, json
from pathlib import Path
import soundfile as sf
import torch
from qwen_tts import Qwen3TTSModel
ROOT=Path('/workspace/ctnetwork-local')
MODEL=ROOT/'models/qwen3-tts/1.7B-Base'

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--sections-json',type=Path,required=True); ap.add_argument('--ref-audio',type=Path,required=True); ap.add_argument('--ref-text-file',type=Path,required=True); ap.add_argument('--output-dir',type=Path,required=True); ap.add_argument('--language',default='English'); a=ap.parse_args()
    if not torch.cuda.is_available(): raise SystemExit('CUDA_REQUIRED_FOR_QWEN')
    sections=json.loads(a.sections_json.read_text()); ref_text=a.ref_text_file.read_text().strip(); a.output_dir.mkdir(parents=True,exist_ok=True)
    model=Qwen3TTSModel.from_pretrained(str(MODEL),device_map='cuda:0',dtype=torch.bfloat16)
    for i,text in enumerate(sections,1):
        wavs,sr=model.generate_voice_clone(text=text.strip(),language=a.language,ref_audio=str(a.ref_audio),ref_text=ref_text)
        out=a.output_dir/f'section_{i:02d}.wav'; sf.write(str(out),wavs[0],sr); print(f'BATCH_SECTION_WRITTEN={out} sr={sr}',flush=True)
if __name__=='__main__': main()
