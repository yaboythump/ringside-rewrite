#!/usr/bin/env python3
from __future__ import annotations

import argparse
import subprocess
from pathlib import Path

ROOT = Path('/workspace/ctnetwork-local')
SRC = ROOT / 'src/LTX-2'
PY = SRC / '.venv/bin/python'
MODELS = ROOT / 'models/ltx-2.5'
STATUS = ROOT / 'status'

TRANS = MODELS / 'diffusion_models/ltx-2.5-22b-distilled-transformer-bf16.safetensors'
TEXT = MODELS / 'text_encoders/gemma4-12b-with-proj-ltx-2.5-bf16.safetensors'
VVIDEO = MODELS / 'vae/ltx-2.5-video-vae-bf16.safetensors'
VAUDIO = MODELS / 'vae/ltx-2.5-audio-vae-bf16.safetensors'
UPSCALE = MODELS / 'latent_upscale_models/ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors'
DETAIL = MODELS / 'loras/ltx-2.5-22b-ic-lora-pixel-spatial-upscaler-x2-1.0.safetensors'


def run(cmd: list[str]) -> None:
    print('+', ' '.join(cmd), flush=True)
    subprocess.run(cmd, cwd=SRC, check=True)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--prompt-file', type=Path, required=True)
    ap.add_argument('--output', type=Path, required=True)
    ap.add_argument('--quality', choices=['distilled', 'dfr'], default='dfr')
    ap.add_argument('--width', type=int, default=768)
    ap.add_argument('--height', type=int, default=512)
    ap.add_argument('--frames', type=int, default=121)
    ap.add_argument('--seed', type=int, default=42)
    args = ap.parse_args()

    prompt = args.prompt_file.read_text().strip()
    if not prompt:
        raise SystemExit('EMPTY_VISUAL_PROMPT')
    required = [PY, TRANS, TEXT, VVIDEO, VAUDIO, UPSCALE]
    if args.quality == 'dfr':
        required.append(DETAIL)
        if not (STATUS / 'ltx25_dfr.status').exists():
            raise SystemExit('LTX25_DFR_NOT_CERTIFIED')
    else:
        if not (STATUS / 'ltx25_smoke.status').exists():
            raise SystemExit('LTX25_BASE_NOT_CERTIFIED')
    for p in required:
        if not p.exists() or (p.is_file() and p.stat().st_size == 0):
            raise SystemExit(f'LTX_REQUIRED_FILE_MISSING:{p}')

    args.output.parent.mkdir(parents=True, exist_ok=True)
    common = [
        str(PY), '-m',
        'ltx_pipelines.dfr_pipeline' if args.quality == 'dfr' else 'ltx_pipelines.distilled',
        '--transformer-path', str(TRANS),
        '--text-encoder-path', str(TEXT),
        '--video-vae-path', str(VVIDEO),
        '--audio-vae-path', str(VAUDIO),
        '--spatial-upsampler-path', str(UPSCALE),
        '--width', str(args.width), '--height', str(args.height),
        '--num-frames', str(args.frames), '--seed', str(args.seed),
        '--quantization', 'fp8-cast', '--offload', 'cpu',
        '--output-path', str(args.output), '--prompt', prompt,
    ]
    if args.quality == 'dfr':
        insert_at = common.index('--spatial-upsampler-path')
        common[insert_at:insert_at] = ['--detailing-lora', str(DETAIL)]
    run(common)
    if not args.output.exists() or args.output.stat().st_size < 4096:
        raise SystemExit('LTX_PRODUCTION_OUTPUT_MISSING')
    print(f'LTX_PRODUCTION_WRITTEN={args.output}')


if __name__ == '__main__':
    main()
