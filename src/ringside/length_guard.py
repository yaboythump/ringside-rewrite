from __future__ import annotations

import re

from .models import EpisodePlan

_SENTENCE_SPLIT_RE = re.compile(r"(?<=[.!?])\s+")


def _word_count(text: str) -> int:
    return len(text.split())


def _sentences(text: str) -> list[str]:
    return [part.strip() for part in _SENTENCE_SPLIT_RE.split(text.strip()) if part.strip()]


def _exact_trim(text: str, words_to_remove: int) -> str:
    """Remove an exact number of trailing words without leaving broken punctuation."""
    words = text.strip().split()
    if words_to_remove <= 0 or not words:
        return text.strip()
    keep = max(1, len(words) - words_to_remove)
    clipped = " ".join(words[:keep]).rstrip(" ,;:-")
    if clipped and clipped[-1] not in ".!?":
        clipped += "."
    return clipped


def fit_plan_to_max_words(
    plan: EpisodePlan,
    maximum_words: int,
    *,
    headroom_words: int = 35,
    minimum_words_per_shot: int = 24,
) -> EpisodePlan:
    """Deterministically normalize an overlong plan without aborting production.

    The model still gets the first chance to rewrite naturally. If it ignores the word
    limit, this guard removes the smallest useful amount of narration needed to get back
    under the quality ceiling. Complete trailing sentences are removed first; an exact
    trailing-word trim is used only for the final few words. All non-narration fields,
    shot order, sources, Shorts, image prompts, and metadata stay untouched.
    """
    if maximum_words <= 0 or plan.spoken_word_count <= maximum_words:
        return plan

    fitted = plan.model_copy(deep=True)
    target = max(1, maximum_words - max(0, headroom_words))

    # Prefer clean sentence removal, but never remove a sentence that would take the
    # plan below the target if a smaller edit can finish the job instead.
    while fitted.spoken_word_count > target:
        excess = fitted.spoken_word_count - target
        choices: list[tuple[int, int, object]] = []
        for shot in fitted.shots:
            parts = _sentences(shot.narration)
            if len(parts) <= 1:
                continue
            final_words = _word_count(parts[-1])
            remaining_words = _word_count(" ".join(parts[:-1]))
            if remaining_words < minimum_words_per_shot:
                continue
            if final_words <= excess:
                # Prefer the largest sentence that still fits inside the remaining excess.
                choices.append((final_words, _word_count(shot.narration), shot))

        if not choices:
            break

        _, _, shot = max(choices, key=lambda item: (item[0], item[1]))
        parts = _sentences(shot.narration)
        shot.narration = " ".join(parts[:-1]).strip()

    # Finish precisely. This avoids the old behavior where trimming every shot to a
    # proportional sentence budget could remove hundreds more words than necessary.
    while fitted.spoken_word_count > target:
        excess = fitted.spoken_word_count - target
        candidates = [
            shot
            for shot in fitted.shots
            if _word_count(shot.narration) > minimum_words_per_shot
        ]
        if not candidates:
            break
        shot = max(candidates, key=lambda item: _word_count(item.narration))
        available = _word_count(shot.narration) - minimum_words_per_shot
        remove = min(excess, max(1, available))
        shot.narration = _exact_trim(shot.narration, remove)

    # Absolute hard-cap guarantee. This branch should be effectively unreachable, but it
    # makes the production contract explicit: a model overrun cannot cause this failure
    # mode again.
    if fitted.spoken_word_count > maximum_words:
        for shot in sorted(
            fitted.shots,
            key=lambda item: _word_count(item.narration),
            reverse=True,
        ):
            if fitted.spoken_word_count <= maximum_words:
                break
            words = _word_count(shot.narration)
            removable = min(words - 1, fitted.spoken_word_count - maximum_words)
            if removable > 0:
                shot.narration = _exact_trim(shot.narration, removable)

    return fitted
