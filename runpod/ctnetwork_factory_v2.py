#!/usr/bin/env python3
"""Generation-capable CTNETWORK local production controller.

A manifest can provide already-approved media or ask the local factory to create
narration with Qwen3-TTS and visuals with LTX-2.5 DFR. All paths converge on the
same deterministic assembly/QC/approval gate. This module intentionally has no
publisher implementation.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path

try:
    import yaml
except Exception:
    yaml = None

ROOT = Path(os.environ.get('CTN_ROOT', '/workspace/ctnetwork-local'))
READY = ROOT / 'ready_for_approval'
JOBS = ROOT / 'jobs'
STATUS = ROOT / 'status'
CONTROLLER = ROOT / 'controller'
RECIPES = ROOT / 'recipes'


def utcnow() -> str:
    return datetime.now(timezone.utc).isoformat()


def sh(cmd: list[str], *, capture: bool = False) -> subprocess.CompletedProcess:
    print('+', ' '.join(map(str, cmd)), flush=True)
    return subprocess.run(cmd, check=True, text=True, capture_output=capture)


def write_json(path: Path, obj: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, indent=2, sort_keys=True) + '\n')


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(4 * 1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def ffprobe(path: Path) -> dict:
    p = sh(['ffprobe', '-v', 'error', '-show_streams', '-show_format', '-of', 'json', str(path)], capture=True)
    return json.loads(p.stdout)


def media_summary(path: Path) -> dict:
    d = ffprobe(path)
    streams = d.get('streams', [])
    fmt = d.get('format', {})
    v = [s for s in streams if s.get('codec_type') == 'video']
    a = [s for s in streams if s.get('codec_type') == 'audio']
    out = {
        'path': str(path), 'bytes': path.stat().st_size if path.exists() else 0,
        'duration': float(fmt.get('duration') or 0),
        'video_streams': len(v), 'audio_streams': len(a),
    }
    if v:
        out.update(width=int(v[0].get('width') or 0), height=int(v[0].get('height') or 0), video_codec=v[0].get('codec_name'))
    if a:
        out.update(sample_rate=int(a[0].get('sample_rate') or 0), audio_codec=a[0].get('codec_name'))
    return out


class Job:
    def __init__(self, job_id: str, show: str, title: str):
        self.job_id = job_id
        self.show = show
        self.title = title
        self.work = JOBS / job_id
        self.out = READY / job_id
        self.state_path = self.work / 'state.json'
        self.work.mkdir(parents=True, exist_ok=True)
        self.out.mkdir(parents=True, exist_ok=True)
        self.state = {
            'job_id': job_id, 'show': show, 'title': title, 'state': 'PLANNED',
            'history': [{'state': 'PLANNED', 'at': utcnow()}],
            'retryable_failures': [], 'blocked_failures': [],
            'approved': False, 'publish_allowed': False,
        }
        if self.state_path.exists():
            try:
                self.state = json.loads(self.state_path.read_text())
            except Exception:
                pass
        self.save()

    def save(self):
        write_json(self.state_path, self.state)

    def stage(self, state: str, detail: str = ''):
        self.state['state'] = state
        self.state.setdefault('history', []).append({'state': state, 'at': utcnow(), 'detail': detail})
        self.save()
        print(f'STATE {state}: {detail}', flush=True)

    def retryable(self, state: str, error: str):
        self.state.setdefault('retryable_failures', []).append({'stage': state, 'error': error, 'at': utcnow()})
        self.save()

    def block(self, state: str, error: str):
        self.state['state'] = 'FAILED_BLOCKED'
        self.state.setdefault('blocked_failures', []).append({'stage': state, 'error': error, 'at': utcnow()})
        self.save()
        raise RuntimeError(f'BLOCKED {state}: {error}')


def require_file(path: Path, stage: str, job: Job, min_bytes: int = 1024):
    if not path.exists() or path.stat().st_size < min_bytes:
        job.block(stage, f'missing/empty file: {path}')


def load_manifest(path: Path) -> dict:
    if path.suffix.lower() == '.json':
        return json.loads(path.read_text())
    if yaml is None:
        raise RuntimeError('PyYAML required for YAML manifests')
    return yaml.safe_load(path.read_text())


def stage_text(job: Job, name: str, text: str) -> Path:
    p = job.work / name
    p.write_text(text.strip() + '\n')
    return p


def resolve_narration(m: dict, job: Job) -> Path:
    inputs = m.get('inputs', {})
    if inputs.get('narration'):
        p = Path(inputs['narration'])
        require_file(p, 'NARRATION', job)
        job.stage('NARRATION', f'use supplied narration {p}')
        return p

    n = m.get('narration', {})
    script = n.get('text') or m.get('script')
    ref_audio = n.get('voice_reference')
    ref_text = n.get('voice_reference_text')
    if not script or not ref_audio or not ref_text:
        job.block('NARRATION', 'local Qwen generation requires script, voice_reference, and voice_reference_text')
    if (STATUS / 'qwen_smoke.status').read_text().strip() != 'PASS':
        job.block('NARRATION', 'Qwen engine is not certified PASS')
    ref = Path(ref_audio)
    require_file(ref, 'NARRATION', job)
    script_file = stage_text(job, 'script.txt', script)
    ref_text_file = stage_text(job, 'voice_reference.txt', ref_text)
    out = job.work / 'narration.raw.wav'
    job.stage('NARRATION', 'generate authorized show narration locally with Qwen3-TTS')
    qwen_py = ROOT / 'envs/qwen3-tts/bin/python'
    helper = CONTROLLER / 'ctnetwork_qwen_narrate.py'
    require_file(helper, 'NARRATION', job, 100)
    try:
        sh([str(qwen_py), str(helper), '--text-file', str(script_file), '--ref-audio', str(ref), '--ref-text-file', str(ref_text_file), '--output', str(out), '--language', n.get('language', 'English')])
    except Exception as exc:
        job.retryable('NARRATION', repr(exc))
        # one targeted retry; model/reference assets are unchanged
        sh([str(qwen_py), str(helper), '--text-file', str(script_file), '--ref-audio', str(ref), '--ref-text-file', str(ref_text_file), '--output', str(out), '--language', n.get('language', 'English')])
    require_file(out, 'NARRATION', job)
    return out


def resolve_visual(m: dict, job: Job) -> Path:
    inputs = m.get('inputs', {})
    if inputs.get('visual'):
        p = Path(inputs['visual'])
        require_file(p, 'VISUALS', job)
        job.stage('VISUALS', f'use supplied visual master {p}')
        return p

    v = m.get('visuals', {})
    prompt = v.get('prompt') or m.get('visual_prompt')
    if not prompt:
        job.block('VISUALS', 'local LTX generation requires visuals.prompt')
    quality = v.get('quality', 'dfr')
    status_name = 'ltx25_dfr.status' if quality == 'dfr' else 'ltx25_smoke.status'
    status_path = STATUS / status_name
    if not status_path.exists() or status_path.read_text().strip() != 'PASS':
        job.block('VISUALS', f'LTX engine is not certified PASS: {status_name}')
    prompt_file = stage_text(job, 'visual_prompt.txt', prompt)
    out = job.work / 'visual.raw.mp4'
    helper = CONTROLLER / 'ctnetwork_ltx_generate.py'
    require_file(helper, 'VISUALS', job, 100)
    job.stage('VISUALS', f'generate local LTX-2.5 {quality} visual')
    cmd = [
        str(ROOT / 'envs/core/bin/python'), str(helper), '--prompt-file', str(prompt_file),
        '--output', str(out), '--quality', quality,
        '--width', str(int(v.get('width', 768))), '--height', str(int(v.get('height', 512))),
        '--frames', str(int(v.get('frames', 121))), '--seed', str(int(v.get('seed', 42))),
    ]
    try:
        sh(cmd)
    except Exception as exc:
        job.retryable('VISUALS', repr(exc))
        sh(cmd)
    require_file(out, 'VISUALS', job, 4096)
    return out


def assemble(video: Path, audio: Path, out: Path, job: Job):
    job.stage('ASSEMBLY', 'assemble generated/supplied visuals with narration')
    cmd = [
        'ffmpeg', '-y', '-stream_loop', '-1', '-i', str(video), '-i', str(audio),
        '-map', '0:v:0', '-map', '1:a:0', '-vf', 'format=yuv420p',
        '-af', 'loudnorm=I=-16:TP=-1.5:LRA=11',
        '-c:v', 'libx264', '-preset', 'medium', '-crf', '18',
        '-c:a', 'aac', '-b:a', '192k', '-ar', '48000', '-shortest', '-movflags', '+faststart', str(out),
    ]
    try:
        sh(cmd)
    except Exception as exc:
        job.retryable('ASSEMBLY', repr(exc))
        cmd[cmd.index('medium')] = 'fast'
        cmd[cmd.index('18')] = '20'
        sh(cmd)
    require_file(out, 'ASSEMBLY', job, 4096)
    job.stage('AUDIO', 'normalized narration master; AAC 48 kHz')


def make_short(master: Path, out: Path, seconds: float):
    sh([
        'ffmpeg', '-y', '-i', str(master), '-t', f'{seconds:.2f}',
        '-vf', 'scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,format=yuv420p',
        '-c:v', 'libx264', '-preset', 'fast', '-crf', '19', '-c:a', 'aac', '-b:a', '160k', '-ar', '48000',
        '-movflags', '+faststart', str(out),
    ])


def make_thumbnail(master: Path, out: Path):
    sh(['ffmpeg', '-y', '-ss', '0.5', '-i', str(master), '-frames:v', '1', '-vf', 'scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720', '-q:v', '2', str(out)])


def black_ratio(path: Path) -> float:
    p = subprocess.run(['ffmpeg', '-hide_banner', '-i', str(path), '-vf', 'blackdetect=d=1:pix_th=0.98', '-an', '-f', 'null', '-'], text=True, capture_output=True)
    import re
    total = sum(float(x) for x in re.findall(r'black_duration:([0-9.]+)', p.stderr))
    d = media_summary(path)['duration']
    return total / d if d else 1.0


def qc_media(path: Path, *, vertical: bool = False) -> dict:
    s = media_summary(path)
    checks = {
        'nonempty': s['bytes'] > 4096,
        'duration': s['duration'] > 0.5,
        'video': s['video_streams'] >= 1,
        'audio': s['audio_streams'] >= 1,
        'not_mostly_black': black_ratio(path) < 0.80,
    }
    if vertical:
        checks['vertical'] = s.get('height', 0) > s.get('width', 0)
    return {'summary': s, 'checks': checks, 'pass': all(checks.values())}


def package_manifest(m: dict, job: Job, narration: Path, visual: Path) -> Path:
    master = job.out / 'master.mp4'
    assemble(visual, narration, master, job)

    shorts_cfg = m.get('shorts', {})
    count = int(shorts_cfg.get('count', 1))
    seconds = float(shorts_cfg.get('seconds', 12))
    job.stage('SHORTS', f'count={count}')
    shorts = []
    for i in range(count):
        p = job.out / f'short_{i+1:02d}_9x16.mp4'
        make_short(master, p, seconds)
        shorts.append(p)

    job.stage('THUMBNAIL', 'prepare custom-thumbnail review asset')
    supplied_thumb = m.get('inputs', {}).get('thumbnail')
    thumb = job.out / 'thumbnail.jpg'
    if supplied_thumb:
        src = Path(supplied_thumb)
        require_file(src, 'THUMBNAIL', job)
        shutil.copy2(src, thumb)
    else:
        make_thumbnail(master, thumb)

    metadata = {
        'show': job.show,
        'title': job.title,
        'description': m.get('description', ''),
        'tags': m.get('tags', []),
        'burned_in_captions': False,
        'thumbnail': thumb.name,
        'shorts': [p.name for p in shorts],
        'publish': False,
    }
    write_json(job.out / 'metadata.json', metadata)

    job.stage('QC', 'media integrity, streams, aspect, black-frame ratio, checksums')
    qc = {'master': qc_media(master)}
    for i, p in enumerate(shorts, 1):
        qc[f'short_{i:02d}'] = qc_media(p, vertical=True)
    qc['thumbnail'] = {'bytes': thumb.stat().st_size if thumb.exists() else 0, 'pass': thumb.exists() and thumb.stat().st_size > 4096}
    qc['pass'] = all(v.get('pass', False) for v in qc.values() if isinstance(v, dict))
    write_json(job.out / 'qc.json', qc)
    if not qc['pass']:
        job.block('QC', 'one or more package QC checks failed')

    files = [master, *shorts, thumb, job.out / 'metadata.json', job.out / 'qc.json']
    write_json(job.out / 'checksums.json', {p.name: sha256(p) for p in files})
    write_json(job.out / 'approval.json', {
        'job_id': job.job_id, 'state': 'READY_FOR_APPROVAL',
        'requires_manual_approval': True, 'approved': False,
        'publish_allowed': False, 'publishing_implemented': False,
        'created_at': utcnow(), 'note': 'Factory production complete. No external publishing is permitted without a separate explicit approval/publisher action.'
    })
    job.state['approved'] = False
    job.state['publish_allowed'] = False
    job.stage('READY_FOR_APPROVAL', str(job.out))
    return job.out


def run_manifest(path: Path) -> Path:
    m = load_manifest(path)
    job_id = m.get('job_id') or datetime.now().strftime('ctn-%Y%m%d-%H%M%S')
    job = Job(job_id, m.get('show', 'CTNETWORK'), m.get('title', job_id))
    narration = resolve_narration(m, job)
    visual = resolve_visual(m, job)
    return package_manifest(m, job, narration, visual)


def status(job_id: str | None):
    if job_id:
        p = JOBS / job_id / 'state.json'
        print(p.read_text() if p.exists() else json.dumps({'job_id': job_id, 'state': 'UNKNOWN'}))
        return
    data = []
    for p in sorted(JOBS.glob('*/state.json')):
        try: data.append(json.loads(p.read_text()))
        except Exception: pass
    print(json.dumps(data, indent=2))


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd', required=True)
    r = sub.add_parser('run-manifest'); r.add_argument('manifest', type=Path)
    s = sub.add_parser('status'); s.add_argument('--job-id')
    args = ap.parse_args()
    if args.cmd == 'run-manifest': run_manifest(args.manifest)
    elif args.cmd == 'status': status(args.job_id)


if __name__ == '__main__':
    main()
