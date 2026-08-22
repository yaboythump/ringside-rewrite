from __future__ import annotations

import base64
import json
import random
import re
import time
from pathlib import Path

from .config import Settings
from .models import EpisodePlan, Shot


def _openai_client():
    try:
        from openai import OpenAI
    except ImportError as exc:
        raise RuntimeError("Install the project dependencies with: pip install -e .") from exc
    return OpenAI()


def _is_retryable_openai_error(exc: Exception) -> bool:
    message = str(exc).casefold()
    retry_words = (
        "connection",
        "timeout",
        "temporarily",
        "server error",
        "service unavailable",
        "rate limit",
        "502",
        "503",
        "504",
    )
    return any(word in message for word in retry_words)


def _openai_retry(label: str, call, attempts: int = 4):
    last_exc: Exception | None = None
    for attempt in range(1, attempts + 1):
        try:
            return call()
        except Exception as exc:
            last_exc = exc
            if attempt == attempts or not _is_retryable_openai_error(exc):
                raise
            wait_seconds = min(60, 8 * attempt)
            print(
                f"[retry {attempt}/{attempts}] {label} hit a temporary OpenAI connection issue; "
                f"waiting {wait_seconds}s before trying again."
            )
            time.sleep(wait_seconds)
    if last_exc is not None:
        raise last_exc
    raise RuntimeError(f"{label} failed without returning a result.")


def _research_brief(settings: Settings) -> str:
    return json.dumps(settings.research, indent=2)


def research_episode(settings: Settings, premise: str) -> str:
    """Build a sourced factual cutoff before any fantasy booking is written."""
    if not settings.openai_api_key_present:
        raise RuntimeError("OPENAI_API_KEY is required to research an episode.")
    research = settings.research.get("research", {})
    if not research.get("web_search_enabled", True):
        raise RuntimeError("Web research is required for real-person fantasy booking.")
    client = _openai_client()
    response = _openai_retry(
        "episode research",
        lambda: client.responses.create(
            model=settings.text_model,
            reasoning={"effort": "medium"},
            tools=[
                {
                    "type": "web_search",
                    "external_web_access": bool(
                        research.get("external_web_access", True)
                    ),
                }
            ],
            tool_choice="required",
            input=(
                "Research the documented professional-wrestling history needed for this "
                f"fantasy-booking premise: {premise}\n\n"
                "Return a compact fact brief with: (1) the exact real-world cutoff, "
                "(2) four to eight verified facts, (3) at least two working source URLs, "
                "and (4) any uncertainty that the writer must avoid presenting as fact. "
                "Prefer official promotion/corporate sources and direct interviews. Do not "
                "invent quotations, contract details, private motives, injuries, or rumors. "
                "Clearly label everything after the cutoff as hypothetical."
            ),
        ),
    )
    brief = response.output_text.strip()
    if not brief:
        raise RuntimeError("Web research returned an empty factual brief.")
    return brief


def generate_episode_plan(
    settings: Settings,
    theme: str | None = None,
    recent_plans: list[EpisodePlan] | None = None,
) -> EpisodePlan:
    if not settings.openai_api_key_present:
        raise RuntimeError("OPENAI_API_KEY is required to generate a new episode.")
    system_prompt = (settings.root / "prompts" / "episode_system.md").read_text(
        encoding="utf-8"
    )
    selected_theme = theme or random.choice(
        (settings.root / "prompts" / "idea_seeds.txt").read_text(encoding="utf-8").splitlines()
    ).strip()
    prior = recent_plans or []
    research_brief = research_episode(settings, selected_theme)
    recent_summary = [
        {
            "title": item.episode_title,
            "subjects": item.primary_subjects,
            "theme": item.theme,
        }
        for item in prior[-12:]
    ]
    user_prompt = f"""
Create the next RINGSIDE REWRITE episode.

What-if premise: {selected_theme}

Documented research brief:
{research_brief}

Recent episodes and subjects to avoid repeating:
{json.dumps(recent_summary, indent=2)}

Research and sourcing rules:
{_research_brief(settings)}

Begin with a short documented setup and audibly announce the exact moment where the
timeline becomes fictional. Then book a coherent multi-event arc with escalating stakes,
payoffs, one major reversal, and lasting consequences. Never fabricate a direct quote or
imitate a real person's voice. Summarize imagined promos instead of writing quotations.
Keep every image prompt 16:9, self-contained, and styled as a premium illustrated
sports-documentary frame rather than a deceptive photograph. Image prompts must have the
same premium cinematic style as the pilot episode: dramatic arena lighting, strong
character framing, documentary tension, rich wrestling props, and story-specific scenes.
Preserve the scene, era, gender presentation, stakes, atmosphere, camera angle, wardrobe
type, and wrestling props. Use fictional/composite wrestlers instead of real-person
likenesses. Never ask for a real wrestler, public figure, celebrity, promoter,
commentator, recognizable likeness, official logo, trademark, costume, tattoo,
typography, or watermark. If the episode centers on women's wrestling, the image prompts
must clearly feature fictional women wrestlers and must not turn them into men or
luchadors.
""".strip()
    client = _openai_client()
    response = _openai_retry(
        "episode plan",
        lambda: client.responses.parse(
            model=settings.text_model,
            reasoning={"effort": "high"},
            input=[
                {"role": "developer", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            text_format=EpisodePlan,
        ),
    )
    if response.output_parsed is None:
        raise RuntimeError("The model did not return a valid episode plan.")
    return response.output_parsed


def _image_result_bytes(result) -> bytes:
    if not result.data or not result.data[0].b64_json:
        raise RuntimeError("The image API returned no image bytes.")
    return base64.b64decode(result.data[0].b64_json)


_FEMALE_HINTS = (
    "sasha",
    "banks",
    "mercedes",
    "bayley",
    "charlotte",
    "becky",
    "bianca",
    "rhea",
    "trish",
    "lita",
    "aj lee",
    "women",
    "woman",
    "female",
    "diva",
    "boss",
)

_EXECUTIVE_HINTS = (
    "vince",
    "mcmahon",
    "bischoff",
    "heyman",
    "triple h",
    "booker",
    "executive",
    "promoter",
)

_BRAND_REPLACEMENTS = {
    r"\bWWE\b": "a major wrestling promotion",
    r"\bWWF\b": "a major wrestling promotion",
    r"\bWCW\b": "a rival wrestling promotion",
    r"\bAEW\b": "a modern wrestling promotion",
    r"\bECW\b": "an extreme wrestling promotion",
    r"\bTNA\b": "a televised wrestling promotion",
    r"\bNXT\b": "a developmental wrestling brand",
    r"\bRAW\b": "a weekly wrestling show",
    r"\bSmackDown\b": "a weekly wrestling show",
    r"\bWrestleMania\b": "a massive stadium wrestling event",
}

_COMMON_PUBLIC_FIGURES = (
    "Sasha Banks",
    "Mercedes MonÃ©",
    "Mercedes Mone",
    "Bayley",
    "Charlotte Flair",
    "Becky Lynch",
    "Bianca Belair",
    "Rhea Ripley",
    "Trish Stratus",
    "Lita",
    "AJ Lee",
    "Vince McMahon",
    "Triple H",
    "Paul Heyman",
    "Eric Bischoff",
    "The Rock",
    "Dwayne Johnson",
    "John Cena",
    "Roman Reigns",
    "CM Punk",
    "Steve Austin",
    "Stone Cold",
    "Hulk Hogan",
    "Sting",
    "Undertaker",
    "Brock Lesnar",
    "Cody Rhodes",
)


def _subject_replacement(subject: str, surrounding_text: str) -> str:
    lower = f"{subject} {surrounding_text}".casefold()
    if any(hint in lower for hint in _FEMALE_HINTS):
        return "a fictional female wrestling star"
    if any(hint in lower for hint in _EXECUTIVE_HINTS):
        return "a fictional wrestling executive"
    return "a fictional wrestling star"


def _presentation_hint(shot: Shot, subjects: list[str]) -> str:
    text = f"{shot.scene_title} {shot.location} {shot.image_prompt} {' '.join(subjects)}".casefold()
    if any(hint in text for hint in _FEMALE_HINTS):
        return (
            "Use fictional women wrestlers only; do not turn this into male wrestlers, "
            "masked luchadors, or generic men unless the prompt explicitly asks for them."
        )
    return (
        "Use fictional wrestlers that match the scene; avoid luchador masks unless the "
        "prompt explicitly asks for lucha libre, masks, or masked wrestlers."
    )


def _hard_sanitize_public_references(text: str, subjects: list[str]) -> str:
    cleaned = text
    for subject in sorted({item.strip() for item in subjects if item.strip()}, key=len, reverse=True):
        if len(subject) >= 3:
            cleaned = re.sub(
                re.escape(subject),
                _subject_replacement(subject, text),
                cleaned,
                flags=re.IGNORECASE,
            )
    for figure in _COMMON_PUBLIC_FIGURES:
        cleaned = re.sub(
            re.escape(figure),
            _subject_replacement(figure, text),
            cleaned,
            flags=re.IGNORECASE,
        )
    for pattern, replacement in _BRAND_REPLACEMENTS.items():
        cleaned = re.sub(pattern, replacement, cleaned, flags=re.IGNORECASE)
    return cleaned


def _safe_wrestling_visual(shot: Shot) -> str:
    text = f"{shot.scene_title} {shot.location} {shot.music_mood}".casefold()
    if any(word in text for word in ("contract", "signing", "desk", "office")):
        return (
            "a contract signing table in a dramatic wrestling arena, championship belt "
            "props, microphone stands with blank plates, tense crowd silhouettes"
        )
    if any(word in text for word in ("backstage", "hallway", "locker", "monitor")):
        return (
            "a smoky backstage corridor with production cases, blank monitors, ring ropes "
            "visible in the distance, tense fictional performers shown only as silhouettes"
        )
    if any(word in text for word in ("entrance", "ramp", "stage", "pyro")):
        return (
            "a dramatic entrance ramp with red and gold arena lights, fog, sparks, and "
            "fictional masked performers seen from behind"
        )
    if any(word in text for word in ("press", "media", "conference", "announcement")):
        return (
            "a sports press conference setup with blank backdrop panels, microphones, "
            "camera flashes, and unidentified fictional wrestling executives in silhouette"
        )
    if any(word in text for word in ("title", "championship", "belt", "main event")):
        return (
            "a championship belt on a pedestal inside a packed fictional wrestling arena, "
            "red ropes, spotlights, smoke, and cheering crowd silhouettes"
        )
    return (
        "a packed fictional wrestling arena with an empty ring under cinematic spotlights, "
        "red ropes, smoke, dramatic shadows, and documentary-style tension"
    )


def _fallback_image_prompt_for_shot(shot: Shot, subjects: list[str]) -> str:
    presentation = _presentation_hint(shot, subjects)
    visual = _safe_wrestling_visual(shot)
    return (
        "Create one 16:9 premium illustrated sports-documentary frame for an unofficial "
        "fictional professional-wrestling alternate-history episode.\n\n"
        f"Scene visual setup: {visual}.\n\n"
        f"{presentation} Use anonymous silhouettes, fictional faces, props, arenas, "
        "crowds, belts, contracts, lights, and atmosphere. Do not depict, name, imitate, "
        "or resemble any real person, public figure, celebrity, real wrestler, promoter, "
        "commentator, or athlete. Do not include official promotion names, logos, "
        "trademarks, team marks, costume replicas, tattoos, captions, typography, borders, "
        "or watermarks. The image must look like stylized editorial illustration, not real "
        "footage or a photo."
    )


def _old_style_image_prompt_for_shot(shot: Shot, subjects: list[str]) -> str:
    cleaned = _hard_sanitize_public_references(shot.image_prompt.strip(), subjects)
    presentation = _presentation_hint(shot, subjects)
    return (
        f"{cleaned}\n\n"
        "Output intent: one clearly stylized 16:9 premium illustrated sports-history "
        "frame for an unofficial fantasy-booking documentary. Keep the same bold, "
        "cinematic, high-detail look as the pilot episode: dramatic arena lighting, "
        "smoke, crowd energy, premium wrestling-poster composition, realistic props, "
        "and emotional documentary tension. "
        f"{presentation} Use fictional/composite performers only. Do not depict, name, "
        "imitate, or resemble any real person, public figure, celebrity, real wrestler, "
        "promoter, commentator, or athlete. Do not include official promotion names, "
        "logos, trademarks, text, captions, typography, borders, or watermarks."
    )


def _empty_ring_fallback_prompt(shot: Shot, subjects: list[str]) -> str:
    presentation = _presentation_hint(shot, subjects)
    return (
        "Create one 16:9 premium illustrated sports-documentary frame of a fictional "
        "wrestling arena. Show an empty ring, red and gold spotlights, smoke, crowd "
        "silhouettes, blank entrance screens, and championship props. "
        f"{presentation} No real people, no recognizable faces, no official logos, no "
        "promotion names, no text, no trademarks, no tattoos, and no watermarks."
    )


def _generate_image(client, settings: Settings, prompt: str):
    return _openai_retry(
        "image generation",
        lambda: client.images.generate(
            model=settings.image_model,
            prompt=prompt,
            size=settings.channel.get("production", {}).get("image_size", "1536x1024"),
            quality=settings.channel.get("production", {}).get("image_quality", "medium"),
            output_format="png",
        ),
    )


def _is_safety_block(exc: Exception) -> bool:
    message = str(exc).casefold()
    return "moderation" in message or "safety" in message or "blocked" in message


def generate_shot_image(
    settings: Settings,
    shot: Shot,
    destination: Path,
    subjects: list[str] | None = None,
) -> None:
    if not settings.openai_api_key_present:
        raise RuntimeError("OPENAI_API_KEY is required to generate images.")
    destination.parent.mkdir(parents=True, exist_ok=True)
    client = _openai_client()
    subjects = subjects or []
    try:
        result = _generate_image(
            client,
            settings,
            _old_style_image_prompt_for_shot(shot, subjects),
        )
    except Exception as exc:
        if not _is_safety_block(exc):
            raise
        try:
            result = _generate_image(
                client,
                settings,
                _fallback_image_prompt_for_shot(shot, subjects),
            )
        except Exception as fallback_exc:
            if not _is_safety_block(fallback_exc):
                raise
            result = _generate_image(
                client,
                settings,
                _empty_ring_fallback_prompt(shot, subjects),
            )
    destination.write_bytes(_image_result_bytes(result))


def generate_shot_audio(settings: Settings, shot: Shot, destination: Path) -> None:
    if not settings.openai_api_key_present:
        raise RuntimeError("OPENAI_API_KEY is required to generate narration.")
    text = shot.spoken_text
    if not text:
        raise RuntimeError(f"Shot {shot.id} has no spoken text.")
    destination.parent.mkdir(parents=True, exist_ok=True)
    client = _openai_client()
    voice_style = settings.channel.get("format", {}).get("voice_style", "grounded and tense")
    instructions = (
        f"Narrate an unofficial fantasy-booking sports documentary. {voice_style}. "
        "Use natural pauses, confident pacing, and controlled excitement. Do not imitate "
        "any real wrestler, promoter, commentator, or public figure. Do not sound like an "
        "advertisement or a parody."
    )
    def _create_audio():
        if destination.exists():
            destination.unlink()
        with client.audio.speech.with_streaming_response.create(
            model=settings.tts_model,
            voice=settings.tts_voice,
            input=text,
            instructions=instructions,
            response_format="wav",
        ) as response:
            response.stream_to_file(destination)
        return destination

    _openai_retry("narration audio", _create_audio)


def generate_episode_assets(
    settings: Settings,
    plan: EpisodePlan,
    episode_dir: Path,
    images: bool = True,
    audio: bool = True,
) -> None:
    image_dir = episode_dir / "images"
    audio_dir = episode_dir / "audio"
    for shot in plan.shots:
        image_path = image_dir / f"shot-{shot.id:03d}.png"
        audio_path = audio_dir / f"shot-{shot.id:03d}.wav"
        if images and not image_path.exists():
            print(f"[image {shot.id:03d}/{len(plan.shots):03d}] {shot.scene_title}")
            generate_shot_image(settings, shot, image_path, plan.primary_subjects)
        if audio and not audio_path.exists():
            print(f"[voice {shot.id:03d}/{len(plan.shots):03d}] {shot.scene_title}")
            generate_shot_audio(settings, shot, audio_path)
