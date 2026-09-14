#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

import soundfile as sf
import torch
from qwen_tts import Qwen3TTSModel

ROOT = Path('/workspace/ctnetwork-local')
MODEL = ROOT / 'models/qwen3-tts/1.7B-Base'


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--text-file', type=Path, required=True)
    ap.add_argument('--ref-audio', type=Path, required=True)
    ap.add_argument('--ref-text-file', type=Path, required=True)
    ap.add_argument('--output', type=Path, required=True)
    ap.add_argument('--language', default='English')
    args = ap.parse_args()

    for p in (args.text_file, args.ref_audio, args.ref_text_file):
        if not p.exists() or p.stat().st_size == 0:
            raise SystemExit(f'missing required narration input: {p}')
    if not torch.cuda.is_available():
        raise SystemExit('CUDA_REQUIRED_FOR_QWEN')
    if not any(MODEL.rglob('*.safetensors')) and not any(MODEL.rglob('*.bin')):
        raise SystemExit(f'QWEN_MODEL_MISSING:{MODEL}')

    text = args.text_file.read_text().strip()
    ref_text = args.ref_text_file.read_text().strip()
    if not text:
        raise SystemExit('EMPTY_NARRATION_TEXT')
    if not ref_text:
        raise SystemExit('EMPTY_REFERENCE_TRANSCRIPT')

    args.output.parent.mkdir(parents=True, exist_ok=True)
    model = Qwen3TTSModel.from_pretrained(
        str(MODEL),
        device_map='cuda:0',
        dtype=torch.bfloat16,
    )
    wavs, sr = model.generate_voice_clone(
        text=text,
        language=args.language,
        ref_audio=str(args.ref_audio),
        ref_text=ref_text,
    )
    sf.write(str(args.output), wavs[0], sr)
    print(f'QWEN_NARRATION_WRITTEN={args.output} sr={sr}')


if __name__ == '__main__':
    main()
