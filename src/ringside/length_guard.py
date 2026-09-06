from __future__ import annotations

import re

from .models import EpisodePlan

_SENTENCE_SPLIT_RE = re.compile(r"(?<=[.!?])\s+")


def _word_count(text: str) -> int:
    return len(text.split())


def _trim_to_word_budget(text: str, budget: int) -> str:
    """Trim text to a word budget while preferring complete sentences."""
    text = text.strip()
    if not text or budget <= 0:
        return ""
    if _word_count(text) <= budget:
        return text

    sentences = [part.strip() for part in _SENTENCE_SPLIT_RE.split(text) if part.strip()]
    if len(sentences) > 1:
        kept: list[str] = []
        used = 0
        for sentence in sentences:
            words = _word_count(sentence)
            if kept and used + words > budget:
                break
            if not kept and words > budget:
                break
            kept.append(sentence)
            used += words
        if kept:
            return " ".join(kept).strip()

    words = text.split()
    clipped = " ".join(words[:budget]).rstrip(" ,;:-")
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
    """Deterministically bring an overlong plan below the configured maximum.

    Model-based repair remains the first choice because it preserves prose quality. This
    guard exists so a harmless overrun can never abort an otherwise valid production run.
    It trims narration proportionally across shots, preferring sentence boundaries, and
    leaves a little headroom below the hard quality-gate ceiling.
    """
    if maximum_words <= 0 or plan.spoken_word_count <= maximum_words:
        return plan

    fitted = plan.model_copy(deep=True)
    target = max(1, maximum_words - max(0, headroom_words))
    current = fitted.spoken_word_count
    scale = min(1.0, target / max(current, 1))

    for shot in fitted.shots:
        if not shot.narration.strip():
            continue
        current_words = _word_count(shot.narration)
        budget = max(minimum_words_per_shot, int(current_words * scale))
        shot.narration = _trim_to_word_budget(shot.narration, budget)

    # Sentence-aware proportional trimming can still land a little high. Remove one
    # trailing sentence at a time from the longest narration until the hard cap is met.
    while fitted.spoken_word_count > maximum_words:
        candidates = [
            shot
            for shot in fitted.shots
            if _word_count(shot.narration) > minimum_words_per_shot
        ]
        if not candidates:
            break
        shot = max(candidates, key=lambda item: _word_count(item.narration))
        sentences = [
            part.strip()
            for part in _SENTENCE_SPLIT_RE.split(shot.narration.strip())
            if part.strip()
        ]
        if len(sentences) > 1:
            shot.narration = " ".join(sentences[:-1]).strip()
        else:
            budget = max(minimum_words_per_shot, _word_count(shot.narration) - 12)
            shot.narration = _trim_to_word_budget(shot.narration, budget)

    # Last-resort exact cap. This should be rare, but it guarantees this class of
    # workflow failure cannot recur just because the model ignored the requested length.
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
                shot.narration = _trim_to_word_budget(shot.narration, words - removable)

    return fitted
