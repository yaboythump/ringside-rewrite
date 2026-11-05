"""Project 003 tests: coverage planner, per-boundary transitions, visual QC, preflight. Synthetic media only."""
import copy
import json
import subprocess
import sys
from pathlib import Path

import numpy as np
import pytest
import soundfile as sf
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
import adapters  # noqa: E402
import coverage  # noqa: E402
import qc  # noqa: E402
import render  # noqa: E402
import visual_qc  # noqa: E402

SR = 48000


def scene(p, w, h, seed):
    """A distinct 'photo': gradient sky, a few bold shapes, fine texture."""
    rng = np.random.default_rng(seed)
    base = np.zeros((h, w, 3), np.float32)
    c0, c1 = rng.uniform(0, 255, 3), rng.uniform(0, 255, 3)
    t = np.linspace(0, 1, h)[:, None, None]
    base[:] = c0 * (1 - t) + c1 * t
    im = Image.fromarray(base.astype(np.uint8))
    d = ImageDraw.Draw(im)
    for _ in range(7):
        x, y = rng.integers(0, w), rng.integers(0, h)
        r = int(rng.integers(h // 12, h // 4))
        col = tuple(int(v) for v in rng.integers(0, 255, 3))
        (d.ellipse if rng.random() < 0.5 else d.rectangle)([x - r, y - r, x + r, y + r], fill=col)
    a = np.asarray(im, np.float32) + rng.normal(0, 6, (h, w, 3))
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(p, quality=92)


def speech_with_pauses(seconds, seed, every=2.3, gap=0.4):
    rng = np.random.default_rng(seed)
    t = np.arange(int(seconds * SR)) / SR
    x = (0.2 * np.sin(2 * np.pi * 180 * t) * np.clip(np.sin(2 * np.pi * 4 * t), 0, None)
         + 0.01 * rng.standard_normal(len(t))).astype(np.float32)
    k = every
    while k < seconds - 0.5:
        x[int(k * SR):int((k + gap) * SR)] = 0
        k += every + gap
    return x


@pytest.fixture(scope='module')
def job(tmp_path_factory):
    j = tmp_path_factory.mktemp('job3')
    for d in ['graphics', 'work/audio', 'work/edit', 'inputs', 'outputs', 'assets']:
        (j / d).mkdir(parents=True, exist_ok=True)
    scenes = []
    for i in range(1, 5):
        scene(j / f'graphics/scene_{i:02}.jpg', 1672, 941, i)
        sf.write(j / f'work/audio/narration_{i:02}.wav', speech_with_pauses(9.0 + i, i), SR)
        scenes.append({'text': f'line {i}', 'image': f'graphics/scene_{i:02}.jpg', 'audio': f'work/audio/narration_{i:02}.wav'})
    scene(j / 'graphics/thumbnail.jpg', 1672, 941, 99)
    t = np.arange(int(30 * SR)) / SR
    sf.write(j / 'assets/bed.wav', (0.2 * np.sin(2 * np.pi * 110 * t)).astype(np.float32), SR)
    sf.write(j / 'assets/bell.wav', (0.5 * np.sin(2 * np.pi * 900 * t[:SR // 2])).astype(np.float32), SR)
    (j / 'production_plan_v2.json').write_text(json.dumps({'outputs': [{'id': 'episode', 'file': 'outputs/Test.mp4', 'scenes': scenes}]}))
    # Approved edit in the Raven style: interleaved A-B-A per segment (the repetition we are fixing).
    g = lambda k: str(j / f'graphics/scene_{k:02}.jpg')  # noqa: E731
    maps = [[1, 2, 1], [2, 3, 2], [3, 4, 3], [4, 1, 4]]
    tl = []
    for s, seq in enumerate(maps, 1):
        d = (9.0 + s) / len(seq)
        tl += [{'image': g(k), 'duration': d, 'segment': s} for k in seq]
    tl.append({'image': str(j / 'graphics/thumbnail.jpg'), 'duration': 2.0, 'segment': 'outro'})
    (j / 'work/edit/timeline.json').write_text(json.dumps(tl))
    return j


@pytest.fixture(scope='module')
def formula(job):
    f = copy.deepcopy(adapters.load_formula('ringside_rewrite'))
    f['music']['bed'] = str(job / 'assets/bed.wav')
    f['sfx_assets'] = {'bell': {'file': str(job / 'assets/bell.wav'), 'db': -25}, 'crowd': {'file': str(job / 'assets/bell.wav'), 'db': -34}}
    f['sfx_cues_default'] = [{'sfx': 'bell', 'at': {'t': 0.25}}, {'sfx': 'bell', 'at': {'segment': 3}}]
    f['episode'].update(width=640, height=360, min_seconds=5, max_seconds=90, outro_hold=2.0)
    f['episode']['encode'] = {'preset': 'veryfast', 'crf': 20, 'tune': 'film'}
    f['coverage'].update(shot_min=2.0, shot_target=3.2, shot_max=5.0, min_source_px=500)
    return f


# ------------------------------------------------------------------ planner
def test_framings_are_distinct_and_respect_quality_floor(job):
    P = {**coverage.DEFAULT_POLICY, 'min_source_px': 1040}
    frs = coverage.framings_for(job / 'graphics/scene_01.jpg', 1920, 1080, P)
    assert len(frs) >= 3 and frs[0].name == 'wide'
    for a in range(len(frs)):
        x, y, w = frs[a].rect
        assert 0 <= x <= 1 - w + 1e-6 and 0 <= y <= 1 - w + 1e-6
        assert w * 1672 >= 1040 - 1  # never crops below the source-pixel floor
        for b in range(a + 1, len(frs)):
            assert not coverage._too_similar(frs[a].rect, frs[b].rect)


def test_pauses_detected_from_narration():
    x = speech_with_pauses(10, 1, every=2.3, gap=0.4)
    p = coverage.speech_pauses(x, SR)
    expected = [2.5, 5.2, 7.9]
    assert all(any(abs(q - e) < 0.15 for q in p) for e in expected), p


def test_cuts_land_on_pauses_within_hold_limits():
    P = {**coverage.DEFAULT_POLICY, 'shot_min': 4.0, 'shot_target': 6.5, 'shot_max': 9.5}
    pauses = [2.1, 5.0, 6.8, 11.9, 13.0, 19.4, 25.2, 31.0]
    cuts = coverage.choose_cuts(36.0, pauses, 3, P)
    assert set(cuts) <= set(pauses)
    b = [0] + cuts + [36.0]
    holds = [b[i + 1] - b[i] for i in range(len(b) - 1)]
    assert len(holds) >= 3 and min(holds) >= 4.0 * 0.75 and max(holds) <= 9.5 * 1.35, holds


def test_plan_removes_repetition_vs_approved_interleave(job, formula):
    approved = adapters.rewrite_episode(job, formula)
    planned = adapters.rewrite_episode(job, formula, planner='coverage')
    a, p = approved['plan_report'], planned['plan_report']
    assert a['identical_shot_repeats'] >= 4  # the A-B-A pattern re-shows the identical frame
    assert p['back_to_back_same_still'] == 0
    assert p['identical_shot_repeats'] == 0  # every reuse of a still is a different framing
    assert p['min_reuse_gap_shots'] >= 2
    # storyboard preserved: each shot uses a still the approved edit gave that segment
    pools = adapters.approved_pools(job, 4)
    for t in planned['timeline']:
        if isinstance(t['segment'], int):
            assert t['image'] in pools[t['segment'] - 1]
    # picture length matches narration + outro exactly
    speech = sum(len(render.load_audio(Path(s['audio']))) / SR for s in planned['segments'])
    assert abs(sum(t['duration'] for t in planned['timeline']) - (speech + 2.0)) < 1e-3
    kinds = p['transitions']
    assert kinds.get('cut', 0) > 0 and kinds.get('fadeblack', 0) == 1 and kinds.get('fade', 0) >= 2


def test_moves_vary_and_stay_in_frame(job, formula):
    planned = adapters.rewrite_episode(job, formula, planner='coverage')
    moves = [t['move'] for t in planned['timeline'][:-1]]
    assert all(moves[i] != moves[i + 1] for i in range(len(moves) - 1))
    assert len(set(moves)) >= 3
    for t in planned['timeline']:
        for r in (t['rect0'], t['rect1']):
            x, y, w = r
            assert 0 <= x <= 1 - w + 1e-4 and 0 <= y <= 1 - w + 1e-4 and 0 < w <= 1


def test_short_pool_never_overholds_and_requests_stills(job, formula):
    """One approved still for 40 s: keep holds within limits, never repeat a framing back-to-back,
    vary the move on any returning framing, and tell the producer how many stills to add."""
    pools = [[str(job / 'graphics/scene_01.jpg')]]
    x = speech_with_pauses(40, 3)
    seg = coverage.Segment(duration=len(x) / SR, pool=pools[0], pauses=coverage.speech_pauses(x, SR))
    P = {**formula['coverage'], 'shot_min': 2.0, 'shot_target': 3.0, 'shot_max': 5.0, 'min_source_px': 500}
    plan = coverage.plan_timeline([seg], 640, 360, P)
    r, tl = plan['report'], plan['timeline']
    assert r['shot_seconds_range'][1] <= 5.0 * 1.6  # pause-snapped cuts may run a little past the max
    keys = [(t['framing']) for t in tl]
    assert all(keys[i] != keys[i + 1] for i in range(len(keys) - 1))
    seen = {}
    for t in tl:
        assert t['move'] not in seen.get(t['framing'], [])
        seen.setdefault(t['framing'], []).append(t['move'])
    assert any('framings_short' in w for w in r['warnings'])
    assert r['asset_requests'] and r['asset_requests'][0]['additional_stills_recommended'] >= 1


# ------------------------------------------------------------------ render
def test_xfade_graph_mixed_boundaries_frame_exact(tmp_path):
    fps, W, H = 30, 160, 90
    nominal = [30, 45, 40]
    bounds = [None, ('cut', 0), ('fadeblack', 9)]
    tails = [0, 9, 0]
    inputs = []
    for i, n in enumerate(nominal):
        p = tmp_path / f'c{i}.mp4'
        subprocess.run(['ffmpeg', '-y', '-v', 'error', '-f', 'lavfi', '-i', f'color=c=0x{(i + 3) * 30:02x}4060:s={W}x{H}:r={fps}',
                        '-frames:v', str(n + tails[i]), '-pix_fmt', 'yuv420p', '-c:v', 'libx264', str(p)], check=True)
        inputs += ['-i', str(p)]
    graph, last = render.xfade_graph(3, nominal, 0, fps, 'fade', bounds=bounds)
    out = tmp_path / 'o.mp4'
    subprocess.run(['ffmpeg', '-y', '-v', 'error', *inputs, '-filter_complex', graph, '-map', last, '-c:v', 'libx264', str(out)], check=True)
    assert int(round(render.duration(out) * fps)) == sum(nominal)


def test_coverage_render_passes_delivery_and_visual_qc(job, formula, tmp_path):
    spec = adapters.rewrite_episode(job, formula, planner='coverage')
    assert visual_qc.preflight(spec)['pass']
    rec = render.render(spec, tmp_path)
    r = qc.video_qc(rec['output'], width=640, height=360, min_seconds=5, max_seconds=90)
    assert r['pass'], r
    v = visual_qc.analyze_video(rec['output'], {**formula['visual_qc'], 'max_hold_seconds': 8},
                                contact_sheet=tmp_path / 'c.jpg')
    assert v['static_fraction'] < 0.05, v
    assert v['longest_static_seconds'] < 3, v
    assert (tmp_path / 'c.jpg').exists()


def test_excerpt_window_and_cue_rebase(job, formula):
    durs = adapters.segment_durations(job)
    a, b = adapters.choose_excerpt(durs, 20, 30, 2.0)
    assert a == 1 and 20 <= sum(durs[a - 1:b]) + 2 <= 30
    spec = adapters.rewrite_episode(job, formula, planner='coverage', segment_range=(2, 3))
    assert len(spec['segments']) == 2 and spec['id'] == 'excerpt_s02-s03'
    assert [c['at'] for c in spec['sfx']] == [{'segment': 2}]  # segment 3 -> 2nd segment of the excerpt; t-cue dropped


# --------------------------------------------------------------- visual QC
def _slideshow(tmp_path, seq, seconds=4):
    paths = []
    for i, k in enumerate(seq):
        p = tmp_path / f's{i}.mp4'
        subprocess.run(['ffmpeg', '-y', '-v', 'error', '-loop', '1', '-i', str(k), '-t', str(seconds), '-r', '30',
                        '-vf', 'scale=640:360,format=yuv420p', '-c:v', 'libx264', str(p)], check=True)
        paths.append(p)
    lst = tmp_path / 'l.txt'
    lst.write_text(''.join(f"file '{p}'\n" for p in paths))
    out = tmp_path / 'slideshow.mp4'
    subprocess.run(['ffmpeg', '-y', '-v', 'error', '-f', 'concat', '-safe', '0', '-i', str(lst), '-c', 'copy', str(out)], check=True)
    return out


def test_visual_qc_flags_interleaved_static_repetition(job, tmp_path):
    g = lambda k: job / f'graphics/scene_{k:02}.jpg'  # noqa: E731
    out = _slideshow(tmp_path, [g(1), g(2), g(1), g(3), g(1), g(2)], seconds=7)
    v = visual_qc.analyze_video(out, {'max_static_seconds': 6.0})
    assert v['unique_visuals'] == 3 and v['repeats_total'] == 3 and v['max_appearances_one_visual'] == 3
    assert any('excessive_repetition' in e for e in v['errors'])
    assert any('static_sequences' in e for e in v['errors'])


def test_visual_qc_distinct_stills_no_false_repeats(job, tmp_path):
    out = _slideshow(tmp_path, [job / f'graphics/scene_{k:02}.jpg' for k in (1, 2, 3, 4)] + [job / 'graphics/thumbnail.jpg'], seconds=3)
    v = visual_qc.analyze_video(out)
    assert v['repeats_total'] == 0 and v['unique_visuals'] == 5, v


def test_visual_qc_flags_missing_media_black(tmp_path):
    out = tmp_path / 'b.mp4'
    subprocess.run(['ffmpeg', '-y', '-v', 'error', '-f', 'lavfi', '-i', 'testsrc2=s=320x180:r=30:d=3', '-f', 'lavfi', '-i',
                    'color=c=black:s=320x180:r=30:d=2', '-filter_complex', '[0:v][1:v]concat=n=2:v=1[v]', '-map', '[v]',
                    '-pix_fmt', 'yuv420p', str(out)], check=True)
    v = visual_qc.analyze_video(out)
    assert any('missing_media' in e for e in v['errors'])


def test_preflight_catches_missing_and_duplicate_assets(job, formula, tmp_path):
    spec = adapters.rewrite_episode(job, formula, planner='coverage')
    dup = tmp_path / 'copy_of_scene_01.jpg'
    dup.write_bytes((job / 'graphics/scene_01.jpg').read_bytes())
    spec['timeline'].append({'image': str(dup), 'duration': 1})
    spec['timeline'].append({'image': str(tmp_path / 'nope.jpg'), 'duration': 1})
    spec['segments'].append({'audio': str(tmp_path / 'missing.wav')})
    r = visual_qc.preflight(spec, min_width=640, min_height=360)
    assert not r['pass']
    joined = ' '.join(r['errors'])
    assert 'missing_image' in joined and 'byte_identical_stills' in joined and 'missing_narration' in joined


def test_ledger_reuse_finds_repeated_archive_ranges():
    rows = [{'kind': 'archive', 'source': 'freestyle', 'source_in': 38.5, 'duration': 11, 'sequence_start': 200},
            {'kind': 'archive', 'source': 'freestyle', 'source_in': 38.65, 'duration': 2.47, 'sequence_start': 230},
            {'kind': 'archive', 'source': 'riot', 'source_in': 20, 'duration': 14, 'sequence_start': 10},
            {'kind': 'archive', 'source': 'temper', 'source_in': 70, 'duration': 3},
            {'kind': 'photo', 'photo': 1, 'duration': 4}, {'kind': 'photo', 'photo': 1, 'duration': 4}]
    r = visual_qc.ledger_reuse(rows)
    assert not r['pass'] and len(r['reused_ranges']) == 1 and r['reused_ranges'][0]['overlap_seconds'] == 2.47
    assert r['photo_uses'] == {1: 2}


def test_outro_image_not_reshown_just_before_outro(job, formula):
    thumb = str(job / 'graphics/thumbnail.jpg')
    x = speech_with_pauses(20, 5)
    segs = [coverage.Segment(len(x) / SR, [str(job / 'graphics/scene_01.jpg'), thumb], coverage.speech_pauses(x, SR))]
    P = {**formula['coverage'], 'shot_min': 2.0, 'shot_target': 3.0, 'shot_max': 5.0, 'min_source_px': 500}
    plan = coverage.plan_timeline(segs, 640, 360, P, outro={'image': thumb, 'duration': 2.0})
    assert [t['image'] for t in plan['timeline']].count(thumb) == 1  # only the outro hold
    assert plan['report']['identical_repeats_within_90s'] == 0


def test_planned_dip_to_black_is_not_missing_media(tmp_path):
    out = tmp_path / 'dip.mp4'
    subprocess.run(['ffmpeg', '-y', '-v', 'error', '-f', 'lavfi', '-i', 'testsrc2=s=320x180:r=30:d=3', '-f', 'lavfi', '-i',
                    'testsrc2=s=320x180:r=30:d=3', '-f', 'lavfi', '-i', 'sine=f=300:d=5:sample_rate=48000',
                    '-filter_complex', '[0:v][1:v]xfade=transition=fadeblack:duration=1:offset=2[v];[2:a]aformat=channel_layouts=stereo[a]',
                    '-map', '[v]', '-map', '[a]', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest', str(out)], check=True)
    loose = dict(width=320, height=180, lufs=-20, lufs_tolerance=50, true_peak_max=10)
    assert any('black_frames' in e for e in qc.video_qc(out, **loose)['errors'])
    r = qc.video_qc(out, allowed_black=[[1.9, 3.1]], **loose)
    assert not any('black_frames' in e for e in r['errors']) and any('planned_dip' in w for w in r['warnings'])
