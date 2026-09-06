from __future__ import annotations

import unittest
from pathlib import Path

from ringside import studio
from ringside.length_guard import fit_plan_to_max_words
from ringside.models import EpisodePlan


ROOT = Path(__file__).resolve().parents[1]


class EpisodeLengthGuardTests(unittest.TestCase):
    def setUp(self) -> None:
        self.plan = EpisodePlan.load(ROOT / "content" / "pilot" / "episode.json")

    def test_studio_imports_with_length_guard(self) -> None:
        self.assertTrue(callable(studio.generate_episode_plan))

    def test_overlong_plan_is_trimmed_below_hard_cap(self) -> None:
        overlong = self.plan.model_copy(deep=True)
        for shot in overlong.shots:
            if shot.narration.strip():
                shot.narration = f"{shot.narration} {shot.narration}"

        self.assertGreater(overlong.spoken_word_count, 1200)
        fitted = fit_plan_to_max_words(overlong, 1200)

        self.assertLessEqual(fitted.spoken_word_count, 1200)
        self.assertGreaterEqual(fitted.spoken_word_count, 1100)
        self.assertEqual(fitted.slug, overlong.slug)
        self.assertEqual(len(fitted.shots), len(overlong.shots))
        self.assertTrue(all(shot.spoken_text.strip() for shot in fitted.shots))

    def test_plan_inside_cap_is_unchanged(self) -> None:
        # The legacy pilot is intentionally longer than current normal episodes, so use
        # a ceiling above its real word count to verify the guard is a true no-op.
        fitted = fit_plan_to_max_words(self.plan, 1400)
        self.assertEqual(fitted.spoken_word_count, self.plan.spoken_word_count)
        self.assertEqual(fitted.model_dump(), self.plan.model_dump())


if __name__ == "__main__":
    unittest.main()
