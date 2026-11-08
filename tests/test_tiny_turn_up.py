import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from PIL import Image

from ringside.render import probe_duration
from tiny_turn_up.episode import EPISODES_DIR, Scene, list_episodes, load_episode, scene_timings
from tiny_turn_up.produce import render_compilation, render_long, render_shorts, render_thumbnail


def _make_episode(root: Path, slug: str, seconds: int, use_clip: bool) -> None:
    folder = root / slug
    folder.mkdir(parents=True)
    spec = {
        "title": "Test", "description": "Test", "tags": ["x"],
        "scenes": [{"prompt": "a"}, {"prompt": "b"}, {"prompt": "c"}],
        "shorts": [{"start": 2, "length": 4, "title": "Short"}],
    }
    (folder / "episode.json").write_text(json.dumps(spec))
    subprocess.run(["ffmpeg", "-y", "-f", "lavfi", "-i", f"sine=frequency=440:duration={seconds}",
                    str(folder / "song.mp3")], check=True, capture_output=True)
    for i, color in enumerate(["purple", "yellow", "teal"], start=1):
        Image.new("RGB", (1536, 1024), color).save(folder / f"scene_{i:02d}.png")
    if use_clip:  # a ChatGPT/Sora clip should replace the still for that scene
        subprocess.run(["ffmpeg", "-y", "-f", "lavfi", "-i", "testsrc=size=1280x720:rate=24:duration=1",
                        str(folder / "scene_02.mp4")], check=True, capture_output=True)
    Image.new("RGB", (1536, 1024), "orange").save(folder / "thumbnail.png")


class TinyTurnUpTests(unittest.TestCase):
    def test_bundled_episodes_load(self):
        slugs = list_episodes()
        self.assertIn("01-gobble-gobble-wobble", slugs)
        for slug in slugs:
            ep = load_episode(slug)
            self.assertLessEqual(len(ep.title), 100, slug)
            self.assertTrue(ep.scenes or ep.compile_from)
            for cut in ep.shorts:
                self.assertLessEqual(len(cut.title), 100)
            for part in ep.compile_from:
                self.assertTrue((EPISODES_DIR / part / "episode.json").exists())

    def test_scene_timings(self):
        even = scene_timings([Scene("a"), Scene("b"), Scene("c"), Scene("d")], 120)
        self.assertEqual(even, [(0.0, 30.0), (30.0, 30.0), (60.0, 30.0), (90.0, 30.0)])
        self.assertEqual(scene_timings([Scene("a"), Scene("b", start=10)], 40), [(0.0, 10.0), (10, 30)])
        with self.assertRaises(ValueError):
            scene_timings([Scene("a"), Scene("b", start=50)], 40)

    @unittest.skipUnless(shutil.which("ffmpeg"), "ffmpeg not installed")
    def test_render_pipeline(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _make_episode(root, "a", 9, use_clip=True)
            _make_episode(root, "b", 6, use_clip=False)
            a = load_episode("a", root)
            self.assertAlmostEqual(probe_duration(render_long(a)), 9, delta=0.5)
            shorts = render_shorts(a)
            self.assertEqual(len(shorts), 1)
            self.assertAlmostEqual(probe_duration(shorts[0]), 4, delta=0.5)
            self.assertEqual(Image.open(render_thumbnail(a)).size, (1280, 720))
            render_long(load_episode("b", root))
            comp = root / "comp"
            comp.mkdir()
            (comp / "episode.json").write_text(json.dumps(
                {"title": "C", "description": "C", "tags": [], "compile_from": ["a", "b"]}))
            out = render_compilation(load_episode("comp", root), root)
            self.assertAlmostEqual(probe_duration(out), 15, delta=1.0)


if __name__ == "__main__":
    unittest.main()
