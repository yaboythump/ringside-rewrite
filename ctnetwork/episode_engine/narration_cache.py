#!/usr/bin/env python3
"""Spend-safe wrapper around the existing /srv/ctnetwork/elevenlabs_adapter.py.

It does not replace the adapter or change any voice/model: it only adds
  * a content-addressed cache (text + voice_id + model_id + settings rev) so a
    re-render, retry or QC rerun never pays for the same line twice;
  * show pronunciation maps (e.g. HHWI "Ma$e" -> "Mace") applied before hashing,
    which production_v2/narration.py currently ignores;
  * a preflight estimate: characters that are cached vs. would be billed;
  * a hard spend gate: misses raise SpendBlocked unless allow_spend=True and the
    job's character budget covers them;
  * bounded retries with backoff for 429/5xx only (4xx auth/quota errors fail fast);
  * a JSONL ledger of every billed request.
"""
from __future__ import annotations

import hashlib
import json
import re
import shutil
import subprocess
import time
from pathlib import Path

SETTINGS_REV = 'adapter-2026-10-12'  # bump if elevenlabs_adapter voice_settings change


class SpendBlocked(RuntimeError):
    pass


def apply_pronunciations(text: str, mapping: dict | None) -> str:
    for src, dst in (mapping or {}).items():
        text = re.sub(re.escape(src), dst, text)
    return text


def cache_key(text, voice_id, model_id):
    norm = ' '.join(text.split())
    return hashlib.sha256(json.dumps([norm, voice_id, model_id, SETTINGS_REV]).encode()).hexdigest()


class NarrationCache:
    def __init__(self, cache_dir, ledger=None, synth=None, sleep=time.sleep):
        self.dir = Path(cache_dir)
        self.dir.mkdir(parents=True, exist_ok=True)
        self.ledger = Path(ledger) if ledger else self.dir / 'ledger.jsonl'
        self._synth = synth
        self._sleep = sleep

    def _adapter(self):
        if self._synth is None:
            import sys
            sys.path.insert(0, '/srv/ctnetwork')
            from elevenlabs_adapter import synthesize
            self._synth = synthesize
        return self._synth

    def path_for(self, text, voice_id, model_id):
        return self.dir / f'{cache_key(text, voice_id, model_id)}.mp3'

    def estimate(self, lines, voice_id, model_id, pronunciations=None):
        cached = billed = 0
        misses = []
        for i, t in enumerate(lines):
            t = apply_pronunciations(t, pronunciations)
            if self.path_for(t, voice_id, model_id).is_file():
                cached += len(t)
            else:
                billed += len(t)
                misses.append(i)
        return {'lines': len(lines), 'cached_chars': cached, 'billable_chars': billed, 'miss_indexes': misses}

    def synthesize(self, text, voice_id, model_id, out, *, allow_spend=False, budget=None,
                   pronunciations=None, retries=4):
        text = apply_pronunciations(text, pronunciations)
        hit = self.path_for(text, voice_id, model_id)
        out = Path(out)
        if hit.is_file() and hit.stat().st_size > 1024:
            shutil.copyfile(hit, out)
            return {'cached': True, 'billed_chars': 0, 'path': str(out)}
        if not allow_spend:
            raise SpendBlocked(f'{len(text)} characters not cached; spending requires allow_spend=True')
        if budget is not None:
            if budget.get('remaining_chars', 0) < len(text):
                raise SpendBlocked(f'character budget exhausted ({budget.get("remaining_chars")} left, need {len(text)})')
        tmp = hit.with_suffix('.part.mp3')
        delay = 2.0
        for attempt in range(retries + 1):
            try:
                self._adapter()(text, voice_id, str(tmp), model_id)
                break
            except RuntimeError as e:
                m = re.search(r'ElevenLabs error (\d+)', str(e))
                code = int(m.group(1)) if m else 0
                retryable = code == 429 or code >= 500 or code == 0
                if not retryable or attempt == retries:
                    tmp.unlink(missing_ok=True)
                    raise
                self._sleep(delay)
                delay = min(delay * 2, 60)
        if not tmp.is_file() or tmp.stat().st_size < 1024:
            tmp.unlink(missing_ok=True)
            raise RuntimeError('ElevenLabs returned empty audio; not cached')
        tmp.replace(hit)
        shutil.copyfile(hit, out)
        if budget is not None:
            budget['remaining_chars'] -= len(text)
        with self.ledger.open('a') as f:
            f.write(json.dumps({'t': time.time(), 'voice_id': voice_id, 'model_id': model_id,
                                'chars': len(text), 'key': hit.stem}) + '\n')
        return {'cached': False, 'billed_chars': len(text), 'path': str(out)}

    def seed(self, text, voice_id, model_id, existing_audio, pronunciations=None):
        """Register already-paid-for audio so future renders reuse it at zero cost."""
        text = apply_pronunciations(text, pronunciations)
        dst = self.path_for(text, voice_id, model_id)
        if not dst.exists():
            src = Path(existing_audio)
            if src.suffix.lower() == '.mp3':
                shutil.copyfile(src, dst)
            else:
                subprocess.run(['ffmpeg', '-y', '-v', 'error', '-i', str(src), '-b:a', '192k', str(dst)], check=True)
        return dst
