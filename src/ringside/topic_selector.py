from __future__ import annotations

import hashlib
import json
import math
import re
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from statistics import median
from typing import Any

from .config import Settings
from .models import EpisodePlan


_TOKEN_RE = re.compile(r"[a-z0-9]+")

_STOPWORDS = {
    "a",
    "about",
    "after",
    "all",
    "and",
    "as",
    "at",
    "became",
    "been",
    "be",
    "by",
    "during",
    "for",
    "from",
    "had",
    "has",
    "if",
    "in",
    "into",
    "it",
    "never",
    "of",
    "on",
    "or",
    "the",
    "then",
    "through",
    "to",
    "was",
    "were",
    "what",
    "when",
    "with",
    "without",
}

_SUBJECT_STOPWORDS = _STOPWORDS | {
    "absorbed",
    "active",
    "alliance",
    "became",
    "break",
    "broke",
    "called",
    "champion",
    "championship",
    "chosen",
    "continued",
    "defeated",
    "ended",
    "faced",
    "first",
    "final",
    "joined",
    "left",
    "main",
    "match",
    "national",
    "outside",
    "program",
    "promotion",
    "relinquish",
    "remaining",
    "returned",
    "rivalry",
    "signed",
    "standing",
    "stayed",
    "streak",
    "survived",
    "tall",
    "true",
    "turned",
    "undefeated",
    "won",
}

_RARE_SUBJECT_TOKENS = {
    "aj",
    "angle",
    "asuka",
    "austin",
    "balor",
    "banks",
    "booker",
    "bret",
    "brock",
    "bryan",
    "cena",
    "chyna",
    "cm",
    "cody",
    "cold",
    "dam",
    "daniel",
    "drew",
    "finn",
    "goldberg",
    "hart",
    "john",
    "joe",
    "kenny",
    "kurt",
    "lesnar",
    "mcintyre",
    "michaels",
    "omega",
    "punk",
    "randy",
    "reigns",
    "rhoades",
    "rhodes",
    "rob",
    "rock",
    "roman",
    "samoa",
    "sasha",
    "savage",
    "shawn",
    "shield",
    "steve",
    "sting",
    "stone",
    "styles",
    "undertaker",
    "van",
}

_POPULARITY_WEIGHTS = {
    "rock": 14.0,
    "cena": 13.5,
    "undertaker": 13.0,
    "austin": 13.0,
    "stone": 9.0,
    "cold": 9.0,
    "punk": 12.0,
    "roman": 11.5,
    "reigns": 11.5,
    "cody": 11.0,
    "rhodes": 11.0,
    "sasha": 10.5,
    "banks": 10.5,
    "sting": 10.0,
    "daniel": 9.5,
    "bryan": 9.5,
    "goldberg": 9.0,
    "brock": 9.0,
    "lesnar": 9.0,
    "bret": 8.5,
    "hart": 8.5,
    "shawn": 8.5,
    "michaels": 8.5,
    "angle": 8.0,
    "kurt": 8.0,
    "omega": 8.0,
    "kenny": 8.0,
    "asuka": 7.5,
    "chyna": 7.5,
    "booker": 7.0,
    "joe": 7.0,
    "finn": 7.0,
    "balor": 7.0,
}

_STORYLINE_WEIGHTS = {
    "wrestlemania": 9.0,
    "streak": 10.0,
    "nwo": 9.0,
    "invasion": 10.0,
    "monday": 7.0,
    "war": 8.0,
    "rumble": 7.0,
    "survivor": 7.0,
    "summerslam": 6.0,
    "shield": 8.0,
    "nexus": 7.0,
    "championship": 6.0,
    "champion": 6.0,
    "heel": 8.0,
    "betrayal": 8.0,
    "wins": 6.0,
    "won": 6.0,
    "defeated": 6.0,
    "never": 5.0,
    "signed": 5.0,
    "survived": 5.0,
    "broke": 5.0,
}

_CURIOSITY_PHRASES = {
    "turned heel": 11.0,
    "never ended": 10.0,
    "never left": 9.0,
    "never broke up": 9.0,
    "signed with": 8.0,
    "joined the": 8.0,
    "won the": 8.0,
    "defeated": 7.0,
    "stayed active": 7.0,
    "survived": 6.0,
    "standing tall": 6.0,
}


@dataclass(frozen=True)
class TopicChoice:
    premise: str
    score: float
    reason: str
    analytics_used: bool
    report: dict[str, Any]


@dataclass(frozen=True)
class _Candidate:
    premise: str
    index: int
    core_tokens: frozenset[str]
    subject_tokens: frozenset[str]
    story_tags: frozenset[str]
    intrinsic_score: float


def select_episode_topic(
    settings: Settings,
    recent_plans: list[EpisodePlan] | None = None,
    analytics: dict[str, Any] | None = None,
    *,
    now: datetime | None = None,
    save_report: bool = True,
) -> TopicChoice:
    """Pick the next episode premise without changing the generation pipeline.

    The selector uses the existing idea seed file as the contract: it returns one
    normal what-if premise string, exactly like the previous random selector did.
    When YouTube data is available it ranks seeds by recent channel performance.
    When it is not available, it safely falls back to intrinsic topic strength and
    the same local cooldown rules.
    """

    now = now or datetime.now(timezone.utc)
    candidates = _load_candidates(settings.root / "prompts" / "idea_seeds.txt")
    prior = recent_plans or []
    analytics_error: str | None = None
    analytics_source = "provided"

    if analytics is None:
        try:
            from .youtube import analytics_snapshot

            # Read enough upload history to make "already used" a channel-wide
            # rule instead of a short recent-window guess.
            analytics = analytics_snapshot(settings, max_results=200)
            analytics_source = "youtube_data_api"
        except Exception as exc:  # selector should never kill an episode
            analytics = None
            analytics_error = str(exc)
            analytics_source = "fallback"

    videos = _videos_from_snapshot(analytics or {}, now)
    recent_groups = _recent_episode_groups(videos, _cooldown_count(settings))
    used_groups = _used_episode_groups(videos)
    ranked = _rank_candidates(candidates, videos, recent_groups, used_groups, prior, now)
    chosen = _first_eligible(ranked)

    report = {
        "captured_at": now.isoformat(),
        "selector": "analytics_driven_topic_selector_v2",
        "analytics_used": bool(videos),
        "analytics_source": analytics_source,
        "analytics_error": analytics_error,
        "selected": {
            "premise": chosen["premise"],
            "score": round(chosen["score"], 3),
            "reason": chosen["reason"],
        },
        "rules": {
            "keeps_existing_pipeline": True,
            "output_contract": "single idea_seeds premise string",
            "blocks_recent_near_duplicates": True,
            "uses_channel_video_stats_when_available": True,
            "uses_small_stable_randomness": True,
        },
        "top_candidates": [
            {
                "premise": item["premise"],
                "score": round(item["score"], 3),
                "eligible": item["eligible"],
                "reason": item["reason"],
            }
            for item in ranked[:10]
        ],
        "blocked_candidates": [
            {
                "premise": item["premise"],
                "reason": item["reason"],
            }
            for item in ranked
            if not item["eligible"]
        ][:10],
    }

    if save_report:
        _save_report(settings.output_dir / "topic-selection-latest.json", report)

    return TopicChoice(
        premise=chosen["premise"],
        score=float(chosen["score"]),
        reason=str(chosen["reason"]),
        analytics_used=bool(videos),
        report=report,
    )


def _load_candidates(path: Path) -> list[_Candidate]:
    lines = [
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]
    if not lines:
        raise RuntimeError(f"No topic seeds were found in {path}.")
    return [_candidate(line, index) for index, line in enumerate(lines)]


def _candidate(premise: str, index: int) -> _Candidate:
    core = frozenset(_core_tokens(premise))
    subjects = frozenset(_subject_tokens(premise))
    return _Candidate(
        premise=premise,
        index=index,
        core_tokens=core,
        subject_tokens=subjects,
        story_tags=frozenset(_story_tags(premise)),
        intrinsic_score=_intrinsic_score(premise, core),
    )


def _cooldown_count(settings: Settings) -> int:
    selector_config = settings.channel.get("topic_selector", {})
    if isinstance(selector_config, dict) and "subject_cooldown_episodes" in selector_config:
        try:
            return max(0, int(selector_config["subject_cooldown_episodes"]))
        except (TypeError, ValueError):
            pass
    generation = settings.channel.get("generation", {})
    try:
        return max(0, int(generation.get("subject_cooldown_episodes", 3)))
    except (AttributeError, TypeError, ValueError):
        return 3


def _tokens(text: str) -> list[str]:
    return _TOKEN_RE.findall(text.casefold())


def _core_tokens(text: str) -> set[str]:
    tokens = set(_tokens(text))
    return {token for token in tokens if token not in _STOPWORDS and len(token) > 1}


def _subject_tokens(text: str) -> set[str]:
    core = _core_tokens(text)
    rare = core & _RARE_SUBJECT_TOKENS
    if rare:
        return rare
    fallback = {token for token in core if token not in _SUBJECT_STOPWORDS}
    return fallback or core


def _story_tags(text: str) -> set[str]:
    lower = text.casefold()
    tokens = _core_tokens(text)
    tags: set[str] = set()
    if {"wrestlemania", "summerslam", "survivor", "rumble"} & tokens:
        tags.add("major_event")
    if {"won", "wins", "defeated", "champion", "championship"} & tokens:
        tags.add("title_change")
    if "heel" in tokens or "betrayal" in lower or "joined the nwo" in lower:
        tags.add("betrayal_turn")
    if {"invasion", "war", "alliance", "nwo", "nexus"} & tokens:
        tags.add("promotion_or_faction_war")
    if "streak" in tokens or "never ended" in lower:
        tags.add("legacy_streak")
    if {"signed", "returned", "left", "survived", "active"} & tokens:
        tags.add("career_crossroads")
    if "shield" in tokens or "broke up" in lower:
        tags.add("faction_breakup")
    if {"women", "women's", "sasha", "banks", "asuka", "chyna"} & tokens:
        tags.add("women_focus")
    return tags or {"general_what_if"}


def _intrinsic_score(premise: str, tokens: set[str]) -> float:
    popularity = sum(_POPULARITY_WEIGHTS.get(token, 0.0) for token in tokens)
    storyline = sum(_STORYLINE_WEIGHTS.get(token, 0.0) for token in tokens)
    curiosity = sum(weight for phrase, weight in _CURIOSITY_PHRASES.items() if phrase in premise.casefold())

    # Cap each bucket so one name cannot drown out a stronger complete premise.
    return (
        44.0
        + min(popularity, 22.0)
        + min(storyline, 18.0)
        + min(curiosity, 14.0)
    )


def _videos_from_snapshot(snapshot: dict[str, Any], now: datetime) -> list[dict[str, Any]]:
    output: list[dict[str, Any]] = []
    for item in snapshot.get("videos", []) or []:
        snippet = item.get("snippet", {}) or {}
        stats = item.get("statistics", {}) or {}
        text = _video_text(snippet)
        published_at = _parse_datetime(snippet.get("publishedAt")) or now
        age_days = max((now - published_at).total_seconds() / 86_400, 1.0)
        views = _safe_int(stats.get("viewCount"))
        likes = _safe_int(stats.get("likeCount"))
        comments = _safe_int(stats.get("commentCount"))
        engagement = (likes + comments * 2) / max(views, 1)
        raw_score = math.log1p(views / math.sqrt(age_days)) + min(2.5, engagement * 18)
        output.append(
            {
                "id": item.get("id"),
                "title": str(snippet.get("title") or ""),
                "text": text,
                "tokens": _core_tokens(text),
                "subject_tokens": _subject_tokens(text),
                "story_tags": _story_tags(text),
                "published_at": published_at,
                "views": views,
                "likes": likes,
                "comments": comments,
                "raw_score": raw_score,
                "episode_key": _episode_key(str(snippet.get("title") or "")),
            }
        )
    scores = [video["raw_score"] for video in output]
    if scores:
        center = median(scores)
        spread = max(0.75, median([abs(score - center) for score in scores]) * 1.4826)
        for video in output:
            video["normalized_score"] = max(
                -1.5, min(3.0, (video["raw_score"] - center) / spread)
            )
    return sorted(output, key=lambda video: video["published_at"], reverse=True)


def _video_text(snippet: dict[str, Any]) -> str:
    parts = [
        str(snippet.get("title") or ""),
        str(snippet.get("description") or ""),
    ]
    tags = snippet.get("tags")
    if isinstance(tags, list):
        parts.extend(str(tag) for tag in tags)
    return " ".join(parts)


def _episode_key(title: str) -> str:
    clean = re.sub(r"#\s*shorts?", "", title, flags=re.IGNORECASE)
    clean = clean.split(" — ", 1)[0].split(" - ", 1)[0]
    return _normalize_text(clean)


def _normalize_text(text: str) -> str:
    return " ".join(_tokens(text))


def _parse_datetime(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def _safe_int(value: Any) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def _recent_episode_groups(videos: list[dict[str, Any]], limit: int) -> list[dict[str, Any]]:
    if limit <= 0:
        return []
    groups: dict[str, dict[str, Any]] = {}
    ordered: list[str] = []
    for video in videos:
        key = video["episode_key"] or str(video.get("id") or len(ordered))
        if key not in groups:
            ordered.append(key)
            groups[key] = {
                "key": key,
                "text": "",
                "tokens": set(),
                "subject_tokens": set(),
                "story_tags": set(),
                "published_at": video["published_at"],
            }
        group = groups[key]
        group["text"] = f"{group['text']} {video['text']}".strip()
        group["tokens"].update(video["tokens"])
        group["subject_tokens"].update(video["subject_tokens"])
        group["story_tags"].update(video["story_tags"])
    return [groups[key] for key in ordered[:limit]]


def _used_episode_groups(videos: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return _recent_episode_groups(videos, limit=max(len(videos), 1))


def _rank_candidates(
    candidates: list[_Candidate],
    videos: list[dict[str, Any]],
    recent_groups: list[dict[str, Any]],
    used_groups: list[dict[str, Any]],
    prior: list[EpisodePlan],
    now: datetime,
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for candidate in candidates:
        reason_parts: list[str] = []
        eligible = True

        if _blocked_by_local_history(candidate, prior):
            eligible = False
            reason_parts.append("blocked by local subject cooldown")
        elif _blocked_by_recent_analytics(candidate, recent_groups):
            eligible = False
            reason_parts.append("blocked by recent YouTube topic cooldown")
        elif _same_story_used_before(candidate, used_groups):
            eligible = False
            reason_parts.append("hard blocked as an already-used wrestler/storyline")

        analytics_score, analytics_reason = _analytics_score(candidate, videos)
        diversity_score = _diversity_bonus(candidate, used_groups)
        jitter = _stable_jitter(candidate.premise, now)
        score = candidate.intrinsic_score + analytics_score + diversity_score + jitter

        if analytics_reason:
            reason_parts.append(analytics_reason)
        reason_parts.append(f"intrinsic {candidate.intrinsic_score:.1f}")
        if diversity_score:
            reason_parts.append(f"diversity +{diversity_score:.1f}")
        if abs(jitter) >= 0.1:
            reason_parts.append(f"variety {jitter:+.1f}")

        rows.append(
            {
                "premise": candidate.premise,
                "score": score,
                "eligible": eligible,
                "reason": "; ".join(reason_parts),
                "index": candidate.index,
            }
        )
    return sorted(rows, key=lambda row: (row["eligible"], row["score"], -row["index"]), reverse=True)


def _blocked_by_local_history(candidate: _Candidate, prior: list[EpisodePlan]) -> bool:
    for plan in prior[-12:]:
        text = " ".join([plan.theme, plan.episode_title, *plan.primary_subjects])
        if _near_duplicate(candidate, _core_tokens(text), _subject_tokens(text), text):
            return True
    return False


def _blocked_by_recent_analytics(candidate: _Candidate, recent_groups: list[dict[str, Any]]) -> bool:
    return any(
        _near_duplicate(candidate, group["tokens"], group["subject_tokens"], group["text"])
        for group in recent_groups
    )


def _same_story_used_before(candidate: _Candidate, groups: list[dict[str, Any]]) -> bool:
    """Block the same episode concept even when YouTube uses a creative title.

    Exact wording is not reliable because upload titles are optimized separately
    from the seed premise. A repeated primary subject plus a distinctive storyline
    fingerprint (for example Undertaker + legacy_streak) is a used episode.
    """
    normalized_premise = _normalize_text(candidate.premise)
    for group in groups:
        normalized_group = _normalize_text(group["text"])
        if normalized_premise and normalized_premise in normalized_group:
            return True
        subject_overlap = candidate.subject_tokens & group["subject_tokens"]
        shared_story_tags = candidate.story_tags & group["story_tags"]
        distinctive_tags = shared_story_tags - {"general_what_if", "major_event"}
        if subject_overlap and distinctive_tags:
            return True
        if candidate.core_tokens:
            coverage = len(candidate.core_tokens & group["tokens"]) / len(candidate.core_tokens)
            if coverage >= 0.55 and subject_overlap:
                return True
    return False


def _near_duplicate(
    candidate: _Candidate,
    other_tokens: set[str],
    other_subjects: set[str],
    other_text: str,
) -> bool:
    if not other_tokens:
        return False

    subject_overlap = candidate.subject_tokens & other_subjects
    if candidate.subject_tokens and subject_overlap:
        required = 1 if len(candidate.subject_tokens) == 1 else 2
        if len(subject_overlap) >= required:
            return True

    normalized_premise = _normalize_text(candidate.premise)
    if normalized_premise and normalized_premise in _normalize_text(other_text):
        return True

    if candidate.core_tokens:
        overlap = len(candidate.core_tokens & other_tokens)
        small_side = max(1, min(len(candidate.core_tokens), len(other_tokens)))
        if overlap / small_side >= 0.42 and overlap >= 3:
            return True
    return False


def _analytics_score(candidate: _Candidate, videos: list[dict[str, Any]]) -> tuple[float, str]:
    if not videos:
        return 0.0, "no analytics available; using fallback ranking"

    weighted_total = 0.0
    weight_sum = 0.0
    topic_hits = 0
    format_weighted_total = 0.0
    format_weight_sum = 0.0

    for video in videos:
        topic_affinity = _topic_affinity(candidate, video)
        if topic_affinity >= 0.12:
            weighted_total += topic_affinity * video["normalized_score"]
            weight_sum += topic_affinity
            topic_hits += 1

        shared_tags = candidate.story_tags & video["story_tags"]
        if shared_tags:
            format_weight = min(1.0, len(shared_tags) / max(1, len(candidate.story_tags)))
            format_weighted_total += format_weight * video["normalized_score"]
            format_weight_sum += format_weight

    score = 0.0
    reason_bits: list[str] = []
    if weight_sum:
        topic_signal = weighted_total / weight_sum
        score += topic_signal * 12.0
        reason_bits.append(f"topic analytics {topic_signal:+.2f} from {topic_hits} upload(s)")
    if format_weight_sum:
        format_signal = format_weighted_total / format_weight_sum
        score += format_signal * 7.0
        reason_bits.append(f"format analytics {format_signal:+.2f}")

    if not reason_bits:
        reason_bits.append("analytics found no close match")
    return score, ", ".join(reason_bits)


def _topic_affinity(candidate: _Candidate, video: dict[str, Any]) -> float:
    video_tokens = video["tokens"]
    if not candidate.core_tokens or not video_tokens:
        return 0.0
    subject_overlap = len(candidate.subject_tokens & video["subject_tokens"])
    core_overlap = len(candidate.core_tokens & video_tokens)
    subject_score = subject_overlap / max(1, len(candidate.subject_tokens))
    core_score = core_overlap / max(4, len(candidate.core_tokens))
    tag_score = len(candidate.story_tags & video["story_tags"]) / max(1, len(candidate.story_tags))
    return min(1.0, subject_score * 0.55 + core_score * 0.30 + tag_score * 0.15)


def _diversity_bonus(candidate: _Candidate, used_groups: list[dict[str, Any]]) -> float:
    if not used_groups:
        return 0.0
    recent_story_tags: set[str] = set()
    for group in used_groups[:6]:
        recent_story_tags.update(group["story_tags"])
    if not recent_story_tags:
        return 0.0
    new_tags = candidate.story_tags - recent_story_tags
    return min(4.0, len(new_tags) * 1.25)


def _stable_jitter(premise: str, now: datetime) -> float:
    day = now.date().isoformat()
    digest = hashlib.sha256(f"{day}|{premise}".encode("utf-8")).digest()
    value = int.from_bytes(digest[:2], "big") / 65535
    return (value - 0.5) * 3.0


def _first_eligible(ranked: list[dict[str, Any]]) -> dict[str, Any]:
    for row in ranked:
        if row["eligible"]:
            return row
    if not ranked:
        raise RuntimeError("No topic candidates were available.")
    # Never spend production credits on a known repeat. Expanding the seed list is
    # safer than silently relaxing the duplicate rule.
    raise RuntimeError(
        "Every topic seed is blocked by channel history or the recent-subject cooldown. "
        "Add fresh premises to prompts/idea_seeds.txt before producing another episode."
    )


def _save_report(path: Path, report: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2), encoding="utf-8")
