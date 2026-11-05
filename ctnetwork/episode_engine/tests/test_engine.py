"""End-to-end tests on synthetic media. No network, no credits, small frames for speed."""
import copy
import json
import subprocess
import sys
from pathlib import Path

import numpy as np
import pytest
import soundfile as sf
from PIL import Image

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
import adapters  # noqa: E402
import narration_cache as nc  # noqa: E402
import qc  # noqa: E402
import render  # noqa: E402
import thumbnail  # noqa: E402

SR = 48000


def speechlike(seconds, seed):
    rng = np.random.default_rng(seed)
    t = np.arange(int(seconds * SR)) / SR
    syll = np.clip(np.sin(2 * np.pi * 4 * t), 0, None)  # 4 Hz "syllables"
    voiced = sum(np.sin(2 * np.pi * f * t + rng.uniform(0, 6)) / k for k, f in enumerate([140, 280, 420, 700, 1100], 1))
    return (0.2 * voiced * syll + 0.01 * rng.standard_normal(len(t)) * syll).astype(np.float32)


def image(p, w, h, seed):
    rng = np.random.default_rng(seed)
    base = np.linspace(0, 255, w)[None, :, None] * np.ones((h, 1, 3))
    noise = rng.integers(0, 80, (h, w, 3))
    Image.fromarray(np.clip(base * 0.6 + noise, 0, 255).astype(np.uint8)).save(p, quality=92)


@pytest.fixture(scope='module')
def job(tmp_path_factory):
    j = tmp_path_factory.mktemp('job')
    for d in ['graphics', 'work/audio', 'work/edit', 'inputs', 'outputs', 'assets']:
        (j / d).mkdir(parents=True, exist_ok=True)
    scenes = []
    for i in range(1, 5):
        image(j / f'graphics/scene_{i:02}.jpg', 836, 470, i)
        sf.write(j / f'work/audio/narration_{i:02}.wav', speechlike(3.0 + i * 0.3, i), SR)
        scenes.append({'text': f'line {i}', 'image': f'graphics/scene_{i:02}.jpg', 'audio': f'work/audio/narration_{i:02}.wav'})
    image(j / 'graphics/thumbnail.jpg', 836, 470, 99)
    image(j / 'graphics/cover.jpg', 540, 960, 77)
    t = np.arange(int(20 * SR)) / SR
    sf.write(j / 'assets/bed.wav', (0.2 * np.sin(2 * np.pi * 110 * t)).astype(np.float32), SR)
    sf.write(j / 'assets/bell.wav', (0.5 * np.sin(2 * np.pi * 900 * t[:SR // 2])).astype(np.float32), SR)
    (j / 'production_plan_v2.json').write_text(json.dumps({'outputs': [{'id': 'episode', 'file': 'outputs/Test.mp4', 'scenes': scenes}]}))
    sf.write(j / 'work/audio/short_1.wav', speechlike(8.0, 50), SR)
    (j / 'inputs/shorts_plan.json').write_text(json.dumps([{'n': 1, 'headline': 'H', 'text': 't', 'shots': [[1, 0.2], [2, 0.8]]}]))
    return j


@pytest.fixture(scope='module')
def formula(job):
    f = copy.deepcopy(adapters.load_formula('ringside_rewrite'))
    f['music']['bed'] = str(job / 'assets/bed.wav')
    f['sfx_assets'] = {'bell': {'file': str(job / 'assets/bell.wav'), 'db': -25}, 'crowd': {'file': str(job / 'assets/bell.wav'), 'db': -34}}
    f['sfx_cues_default'] = [{'sfx': 'bell', 'at': {'t': 0.25}}, {'sfx': 'bell', 'at': {'segment': 3}}]
    f['episode'].update(width=640, height=360, min_seconds=5, max_seconds=60, outro_hold=2.0)
    f['episode']['encode'] = {'preset': 'veryfast', 'crf': 20, 'tune': 'film'}
    f['shorts'].update(width=360, height=640, min_seconds=10, max_seconds=20, cover_seconds=1.0)
    f['shorts']['encode'] = {'preset': 'veryfast', 'crf': 20, 'tune': 'film'}
    return f


def test_frame_plan_is_drift_free():
    tl = [{'duration': 1 / 3}] * 90 + [{'duration': 4}]
    nominal, T = render.frame_plan(tl, 30, 34.0, 0.6)
    assert sum(nominal) == 34 * 30
    assert T == 3  # capped at a third of the shortest 10-frame shot


def test_seamless_loop_has_no_hard_seam():
    t = np.arange(SR) / SR
    m = np.sin(2 * np.pi * 50 * t).astype(np.float32)
    m[-10:] = 1.0  # a click at the loop point
    out = render.seamless_loop(m, 3 * SR, xfade_s=0.2)
    assert len(out) == 3 * SR
    assert np.max(np.abs(np.diff(out))) < 0.1  # no click/discontinuity where the bed repeats


def test_ducking_lowers_bed_under_speech():
    sp = np.concatenate([np.zeros(SR * 2), speechlike(3, 1), np.zeros(SR * 3)]).astype(np.float32)
    g = 20 * np.log10(render.duck_curve(sp, -32, -26))
    assert g[int(3.5 * SR)] < -31 and g[int(7.5 * SR)] > -27


def test_episode_render_qc_and_sandbox(job, formula, tmp_path):
    spec = adapters.rewrite_episode(job, formula)
    rec = render.render(spec, tmp_path)
    out = Path(rec['output'])
    assert out.parent == tmp_path and rec['generation_credits_spent'] == 0
    # the source job is untouched
    assert not (job / 'outputs/Test.mp4').exists()
    r = qc.video_qc(out, width=640, height=360, min_seconds=5, max_seconds=60)
    assert r['pass'], r
    speech_total = sum(float(subprocess.check_output(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', str(job / f'work/audio/narration_{i:02}.wav')])) for i in range(1, 5))
    assert abs(r['duration'] - (speech_total + 2.0)) < 0.1


def test_static_slideshow_is_flagged(job, formula, tmp_path):
    spec = adapters.rewrite_episode(job, formula)
    spec['motion'] = {'enabled': False}
    spec['timeline'] = [{'image': spec['timeline'][0]['image'], 'duration': 20}]
    rec = render.render(spec, tmp_path)
    r = qc.video_qc(rec['output'], width=640, height=360, min_seconds=5, max_seconds=60)
    assert any('slideshow' in e for e in r['errors'])


def test_short_with_intro_cover_clean(job, formula, tmp_path):
    spec = adapters.rewrite_shorts(job, formula, subject='test')[0]
    spec['timeline'][0]['image'] = str(job / 'graphics/cover.jpg')
    rec = render.render(spec, tmp_path)
    r = qc.video_qc(rec['output'], width=360, height=640, min_seconds=10, max_seconds=20)
    assert r['pass'], r
    assert r['duration'] >= 10  # padded with music outro, not dead air


def test_intro_prepend(job, formula, tmp_path):
    intro = tmp_path / 'intro.mp4'
    subprocess.run(['ffmpeg', '-y', '-v', 'error', '-f', 'lavfi', '-i', 'testsrc2=s=320x180:r=24:d=2', '-f', 'lavfi', '-i',
                    'sine=f=440:d=2', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest', str(intro)], check=True)
    spec = adapters.rewrite_episode(job, formula, intro=str(intro))
    rec = render.render(spec, tmp_path / 'o')
    r = qc.video_qc(rec['output'], width=640, height=360, min_seconds=5, max_seconds=60)
    assert r['pass'], r


def test_thumbnail_prepare(job, tmp_path):
    out = tmp_path / 't.jpg'
    thumbnail.prepare(job / 'graphics/thumbnail.jpg', out)
    assert qc.thumbnail_qc(out)['pass']
    with pytest.raises(ValueError):
        thumbnail.prepare(job / 'graphics/cover.jpg', tmp_path / 'bad.jpg')


def test_narration_cache_blocks_spend_and_reuses(tmp_path):
    calls = []

    def fake(text, voice, out, model):
        calls.append(text)
        if len(calls) == 1:
            raise RuntimeError('ElevenLabs error 429: busy')
        Path(out).write_bytes(b'\xff' * 4096)

    c = nc.NarrationCache(tmp_path / 'cache', synth=fake, sleep=lambda s: None)
    with pytest.raises(nc.SpendBlocked):
        c.synthesize('Ma$e came back.', 'v', 'm', tmp_path / 'a.mp3')
    assert calls == []
    budget = {'remaining_chars': 1000}
    r1 = c.synthesize('Ma$e came back.', 'v', 'm', tmp_path / 'a.mp3', allow_spend=True, budget=budget,
                      pronunciations={'Ma$e': 'Mace'})
    assert r1['billed_chars'] == len('Mace came back.') and calls[-1] == 'Mace came back.' and len(calls) == 2
    r2 = c.synthesize('Ma$e came back.', 'v', 'm', tmp_path / 'b.mp3', pronunciations={'Ma$e': 'Mace'})
    assert r2['cached'] and len(calls) == 2
    est = c.estimate(['Ma$e came back.', 'new line'], 'v', 'm', {'Ma$e': 'Mace'})
    assert est['billable_chars'] == len('new line') and est['miss_indexes'] == [1]


def test_narration_cache_auth_error_fails_fast(tmp_path):
    def fake(text, voice, out, model):
        raise RuntimeError('ElevenLabs error 401: bad key')
    c = nc.NarrationCache(tmp_path / 'c', synth=fake, sleep=lambda s: pytest.fail('should not retry'))
    with pytest.raises(RuntimeError):
        c.synthesize('x' * 10, 'v', 'm', tmp_path / 'a.mp3', allow_spend=True)
