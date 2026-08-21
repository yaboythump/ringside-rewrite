from __future__ import annotations

import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

from PIL import Image

from ringside.config import load_settings
from ringside.models import DialogueLine, EpisodePlan
from ringside.quality import evaluate_episode
from ringside.render import _render_shot, probe_duration
from ringside.youtube import _future_iso


ROOT = Path(__file__).resolve().parents[1]


class PilotTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.settings = load_settings(ROOT)
        cls.plan = EpisodePlan.load(ROOT / "content" / "pilot" / "episode.json")

    def test_pilot_passes_quality_gate(self) -> None:
        report = evaluate_episode(self.plan, self.settings.channel)
        self.assertTrue(report.passed, report.errors)
        self.assertGreaterEqual(self.plan.spoken_word_count, 1050)
        self.assertEqual(len(self.plan.shots), 24)
        self.assertTrue(self.plan.contains_synthetic_media)
        self.assertTrue(self.plan.original_fiction)
        self.assertTrue(self.plan.hypothetical_booking)
        self.assertGreaterEqual(len(self.plan.source_notes), 2)
        self.assertGreaterEqual(len(self.plan.factual_baseline), 3)
        self.assertIn("#RingsideRewrite", self.plan.hashtags)
        self.assertEqual(self.plan.slug, "sting-leads-the-invasion")

    def test_duplicate_visuals_fail(self) -> None:
        mutated = self.plan.model_copy(deep=True)
        mutated.shots[1].image_prompt = mutated.shots[0].image_prompt
        report = evaluate_episode(mutated, self.settings.channel)
        self.assertFalse(report.passed)
        self.assertTrue(any("exact duplicates" in error for error in report.errors))

    def test_missing_disclosure_fails(self) -> None:
        mutated = self.plan.model_copy(deep=True)
        mutated.contains_synthetic_media = False
        report = evaluate_episode(mutated, self.settings.channel)
        self.assertFalse(report.passed)
        self.assertTrue(any("disclosure" in error for error in report.errors))

    def test_direct_dialogue_fails(self) -> None:
        mutated = self.plan.model_copy(deep=True)
        mutated.shots[0].dialogue = [
            DialogueLine(speaker="Real Wrestler", text="This invented quote should fail.")
        ]
        report = evaluate_episode(mutated, self.settings.channel)
        self.assertFalse(report.passed)
        self.assertTrue(any("Direct dialogue" in error for error in report.errors))

    def test_subject_cooldown_fails(self) -> None:
        previous = self.plan.model_copy(deep=True)
        previous.slug = "prior-sting-episode"
        previous.episode_title = "Prior Sting Episode"
        report = evaluate_episode(self.plan, self.settings.channel, [previous])
        self.assertFalse(report.passed)
        self.assertTrue(any("cooldown" in error for error in report.errors))

    def test_scheduled_short_offset(self) -> None:
        self.assertEqual(
            _future_iso("2026-08-21T20:30:00Z", 2), "2026-08-23T20:30:00Z"
        )

    def test_cloud_oauth_values_load_from_environment(self) -> None:
        values = {
            "YOUTUBE_CLIENT_ID": "mobile-client-id",
            "YOUTUBE_CLIENT_SECRET_VALUE": "mobile-client-secret",
            "YOUTUBE_REFRESH_TOKEN": "mobile-refresh-token",
        }
        with patch.dict("os.environ", values, clear=False):
            settings = load_settings(ROOT)
        self.assertEqual(settings.youtube_client_id, values["YOUTUBE_CLIENT_ID"])
        self.assertEqual(
            settings.youtube_client_secret_value,
            values["YOUTUBE_CLIENT_SECRET_VALUE"],
        )
        self.assertEqual(
            settings.youtube_refresh_token, values["YOUTUBE_REFRESH_TOKEN"]
        )

    def test_research_config_loads(self) -> None:
        self.assertTrue(self.settings.research["research"]["web_search_enabled"])
        self.assertGreaterEqual(
            self.settings.research["research"]["minimum_sources"], 2
        )


@unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "FFmpeg unavailable")
class RenderSmokeTest(unittest.TestCase):
    def test_single_shot_render(self) -> None:
        with tempfile.TemporaryDirectory() as raw_dir:
            directory = Path(raw_dir)
            image = directory / "image.png"
            audio = directory / "audio.wav"
            video = directory / "shot.mp4"
            Image.new("RGB", (1536, 1024), (8, 18, 28)).save(image)
            subprocess.run(
                [
                    "ffmpeg",
                    "-y",
                    "-f",
                    "lavfi",
                    "-i",
                    "anullsrc=r=44100:cl=stereo",
                    "-t",
                    "1.0",
                    str(audio),
                ],
                check=True,
                capture_output=True,
            )
            _render_shot(image, audio, video, 1.0, "slow_push_in", 640, 360, 15)
            self.assertTrue(video.exists())
            self.assertGreater(video.stat().st_size, 1_000)
            self.assertGreater(probe_duration(video), 0.8)


if __name__ == "__main__":
    unittest.main()
