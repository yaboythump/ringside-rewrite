#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path

import soundfile as sf
import torch
from qwen_tts import Qwen3TTSModel

ROOT = Path('/workspace/ctnetwork-local')
MODEL = ROOT / 'models/qwen3-tts/1.7B-Base'


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--sections-json', type=Path, required=True)
    ap.add_argument('--ref-audio', type=Path, required=True)
    ap.add_argument('--ref-text-file', type=Path, required=True)
    ap.add_argument('--output-dir', type=Path, required=True)
    ap.add_argument('--language', default='English')
    args = ap.parse_args()

    for p in (args.sections_json, args.ref_audio, args.ref_text_file):
        if not p.exists() or p.stat().st_size == 0:
            raise SystemExit(f'missing required input: {p}')
    if not torch.cuda.is_available():
        raise SystemExit('CUDA_REQUIRED_FOR_QWEN')
    if not any(MODEL.rglob('*.safetensors')) and not any(MODEL.rglob('*.bin')):
        raise SystemExit(f'QWEN_MODEL_MISSING:{MODEL}')

    sections = json.loads(args.sections_json.read_text())
    ref_text = args.ref_text_file.read_text().strip()
    args.output_dir.mkdir(parents=True, exist_ok=True)

    missing = []
    for i, text in enumerate(sections, 1):
        out = args.output_dir / f'section_{i:02d}.wav'
        if not out.exists() or out.stat().st_size < 4096:
            missing.append((i, text, out))
        else:
            print(f'SKIP_EXISTING={out}', flush=True)

    if missing:
        model = Qwen3TTSModel.from_pretrained(
            str(MODEL),
            device_map='cuda:0',
            dtype=torch.bfloat16,
        )
        for i, text, out in missing:
            wavs, sr = model.generate_voice_clone(
                text=text,
                language=args.language,
                ref_audio=str(args.ref_audio),
                ref_text=ref_text,
            )
            sf.write(str(out), wavs[0], sr)
            print(f'RESUME_SECTION_WRITTEN={out} sr={sr}', flush=True)

    print('RESUME_ALL_SECTIONS_READY', flush=True)


if __name__ == '__main__':
    main()
