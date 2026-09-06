from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Iterable

from ringside.config import Settings


_GENERATED_TARGET = 80
_MAX_HISTORY_TITLES = 120

# These are only an emergency floor. On normal scheduled runs the OpenAI refill
# adds a much larger batch that is filtered again by the existing selector.
_FALLBACK_PREMISES = (
    "What if Hulk Hogan never left WWF in 1993?",
    "What if Randy Savage stayed in WWF through the Monday Night War?",
    "What if Razor Ramon won the WWF Championship in 1994?",
    "What if Owen Hart won the WWF Championship in 1994?",
    "What if British Bulldog defeated Bret Hart for the WWF Championship at SummerSlam 1992?",
    "What if Mr. Perfect became WWF Champion in 1990?",
    "What if Lex Luger defeated Yokozuna for the WWF Championship at SummerSlam 1993?",
    "What if Vader won the WWF Championship in 1996?",
    "What if Sid defeated The Undertaker at WrestleMania 13?",
    "What if Kane kept the WWF Championship after King of the Ring 1998?",
    "What if Mick Foley defeated Triple H at No Way Out 2000 and stayed active?",
    "What if Chris Jericho remained Undisputed Champion through WrestleMania X8?",
    "What if Eddie Guerrero stayed WWE Champion through the end of 2004?",
    "What if Rey Mysterio had a dominant World Heavyweight Championship reign in 2006?",
    "What if Batista never left WWE in 2010?",
    "What if Edge never had to retire in 2011?",
    "What if Jeff Hardy stayed with WWE after SummerSlam 2009?",
    "What if Christian became WWE's top world champion after 2011?",
    "What if Shelton Benjamin became a world champion during the Ruthless Aggression era?",
    "What if MVP won a world championship during his first WWE run?",
    "What if Umaga defeated John Cena for the WWE Championship in 2007?",
    "What if Mr. Kennedy successfully cashed in Money in the Bank in 2007?",
    "What if Wade Barrett won the WWE Championship during the Nexus era?",
    "What if Bray Wyatt defeated John Cena at WrestleMania 30?",
    "What if Rusev defeated John Cena at WrestleMania 31?",
    "What if Cesaro received a full main-event push after WrestleMania 30?",
    "What if Dolph Ziggler's 2013 World Heavyweight Championship reign lasted a full year?",
    "What if Dean Ambrose won the 2016 Royal Rumble?",
    "What if Seth Rollins never betrayed The Shield in 2014?",
    "What if Roman Reigns turned heel immediately after WrestleMania 33?",
    "What if AJ Lee stayed in WWE through the Women's Revolution?",
    "What if Paige never had to retire in 2018?",
    "What if Trish Stratus stayed full-time after 2006?",
    "What if Lita won her final WWE match in 2006 and continued wrestling?",
    "What if Kharma had a full WWE run beginning in 2011?",
    "What if Gail Kim stayed in WWE after 2011?",
    "What if Beth Phoenix became the centerpiece of WWE's women's division in 2010?",
    "What if Mickie James became WWE's long-term top women's star after WrestleMania 22?",
    "What if Bayley won the NXT Women's Championship earlier and entered WWE as an undefeated star?",
    "What if Ronda Rousey stayed undefeated through WrestleMania 35?",
    "What if Ric Flair never left WCW in 1991?",
    "What if Sting defeated Hulk Hogan clean at Starrcade 1997?",
    "What if Diamond Dallas Page defeated Goldberg at Halloween Havoc 1998?",
    "What if Bret Hart became WCW's centerpiece immediately after Starrcade 1997?",
    "What if Goldberg's undefeated streak continued through 1999?",
    "What if the nWo never split into Hollywood and Wolfpac?",
    "What if WCW never ended Goldberg versus Hogan with the Fingerpoke of Doom?",
    "What if Booker T remained WCW Champion throughout the 2001 Invasion?",
    "What if Scott Steiner won the WCW Championship in 1999 instead of 2000?",
    "What if Eddie Guerrero never left WCW in 2000?",
    "What if Chris Jericho never left WCW in 1999?",
    "What if Rey Mysterio never lost his mask in WCW?",
    "What if Eric Bischoff and Fusient successfully purchased WCW in 2001?",
    "What if WWF delayed the WCW Invasion until the biggest contracts became available?",
    "What if ECW entered the 2001 Invasion as a true independent third side?",
    "What if ECW secured a stable national television deal in 2000?",
    "What if Taz stayed in ECW through 2001?",
    "What if Rob Van Dam became ECW World Champion during his 1998 television-title run?",
    "What if Mike Awesome stayed with ECW in 2000?",
    "What if Raven never left ECW for WCW in 1997?",
    "What if AJ Styles never left TNA in 2014?",
    "What if Samoa Joe's TNA World Championship reign lasted through Bound for Glory 2008?",
    "What if Bobby Roode defeated Kurt Angle at Bound for Glory 2011?",
    "What if James Storm had a long TNA World Championship reign in 2011?",
    "What if Monty Brown became NWA World Heavyweight Champion in TNA?",
    "What if Christian Cage stayed with TNA after 2008?",
    "What if CM Punk remained with AEW after All In 2023?",
    "What if Kenny Omega defeated Jon Moxley at Full Gear 2019?",
    "What if Hangman Page stayed AEW World Champion through the end of 2022?",
    "What if MJF lost the AEW World Championship to Wardlow?",
    "What if Jade Cargill stayed with AEW?",
    "What if Britt Baker remained AEW Women's World Champion through 2022?",
    "What if The Elite never split during AEW's early years?",
    "What if Shinsuke Nakamura stayed with NJPW in 2016?",
    "What if Tetsuya Naito defeated Kazuchika Okada at Wrestle Kingdom 12?",
    "What if Kota Ibushi never left NJPW?",
    "What if Bullet Club never turned on AJ Styles in 2016?",
    "What if D-Generation X never split in 1998?",
    "What if Evolution never turned on Randy Orton in 2004?",
    "What if The Wyatt Family never split up?",
    "What if The New Day turned heel again after becoming WWE's longest-reigning tag champions?",
    "What if The Hardy Boyz stayed together through the entire Ruthless Aggression era?",
    "What if Edge and Christian never split in 2001?",
    "What if the Dudley Boyz became WWE's dominant tag team for the entire 2000s?",
    "What if the WWE brand split never happened in 2002?",
    "What if King of the Ring remained a major annual pay-per-view after 2002?",
    "What if Money in the Bank stayed exclusive to WrestleMania?",
    "What if WWE never introduced the Universal Championship in 2016?",
    "What if the World Heavyweight Championship never left Raw in 2005?",
)


def _normalize(text: str) -> str:
    return " ".join(re.findall(r"[a-z0-9]+", text.casefold()))


def _clean_premises(lines: Iterable[str]) -> list[str]:
    cleaned: list[str] = []
    seen: set[str] = set()
    for raw in lines:
        line = re.sub(r"^\s*(?:[-*•]|\d+[.)])\s*", "", str(raw)).strip()
        if not line.casefold().startswith("what if "):
            continue
        if not line.endswith("?"):
            line += "?"
        if len(line) < 30 or len(line) > 220:
            continue
        key = _normalize(line)
        if key and key not in seen:
            seen.add(key)
            cleaned.append(line)
    return cleaned


def _history_titles(settings: Settings) -> list[str]:
    try:
        from ringside.youtube import analytics_snapshot

        snapshot = analytics_snapshot(settings, max_results=200)
    except Exception as exc:
        print(f"Topic refill: YouTube history unavailable ({exc}); continuing with local history.")
        return []

    titles: list[str] = []
    seen: set[str] = set()
    for item in snapshot.get("videos", []) or []:
        snippet = item.get("snippet", {}) or {}
        title = str(snippet.get("title") or "").strip()
        if not title:
            continue
        key = _normalize(title)
        if key and key not in seen:
            seen.add(key)
            titles.append(title)
        if len(titles) >= _MAX_HISTORY_TITLES:
            break
    return titles


def _parse_model_output(text: str) -> list[str]:
    raw = text.strip()
    if not raw:
        return []

    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        payload = None

    if isinstance(payload, list):
        return _clean_premises(str(item) for item in payload)
    if isinstance(payload, dict):
        for key in ("premises", "topics", "ideas"):
            value = payload.get(key)
            if isinstance(value, list):
                return _clean_premises(str(item) for item in value)

    return _clean_premises(raw.splitlines())


def _generate_premises(
    settings: Settings,
    existing: list[str],
    history_titles: list[str],
) -> list[str]:
    if not settings.openai_api_key_present:
        return []

    try:
        from openai import OpenAI

        client = OpenAI()
        prompt = f"""
Create {_GENERATED_TARGET} fresh episode premises for RINGSIDE REWRITE, an alternate-history
professional-wrestling series.

Return one premise per line with NO numbering or commentary. Every line must begin exactly
with "What if" and end with "?".

Rules:
- Use real, well-documented wrestling history from the 1980s through the present as the
  divergence point; later episode research will verify the factual setup.
- Do not rely on rumors, private motives, invented injuries, or fabricated quotations.
- Avoid repeating the same wrestler, faction, promotion, event, or storyline too often.
- Use at most two ideas centered on the same primary wrestler.
- Mix WWF/WWE, WCW, ECW, TNA/Impact, AEW, NJPW, women's wrestling, tag teams, factions,
  title changes, career crossroads, and promotion-level alternate histories.
- Do not repeat or closely paraphrase any existing seed or prior upload below.

Existing seeds:
{json.dumps(existing[-120:], indent=2)}

Prior upload titles:
{json.dumps(history_titles, indent=2)}
""".strip()
        response = client.responses.create(
            model=settings.text_model,
            reasoning={"effort": "low"},
            input=prompt,
        )
        premises = _parse_model_output(response.output_text)
        print(f"Topic refill: model generated {len(premises)} usable fresh premise(s).")
        return premises
    except Exception as exc:
        print(f"Topic refill: model generation failed ({exc}); using emergency premise pool.")
        return []


def refill_topic_seeds(settings: Settings) -> int:
    """Expand the in-run topic pool before the normal selector ranks candidates."""

    path = settings.root / "prompts" / "idea_seeds.txt"
    existing = _clean_premises(path.read_text(encoding="utf-8").splitlines())
    existing_keys = {_normalize(item) for item in existing}

    history_titles = _history_titles(settings)
    generated = _generate_premises(settings, existing, history_titles)
    additions: list[str] = []

    for premise in [*generated, *_FALLBACK_PREMISES]:
        key = _normalize(premise)
        if key and key not in existing_keys:
            existing_keys.add(key)
            additions.append(premise)

    if not additions:
        print("Topic refill: no additions were needed.")
        return 0

    path.write_text(
        "\n".join([*existing, *additions]).rstrip() + "\n",
        encoding="utf-8",
    )
    print(
        f"Topic refill: added {len(additions)} premise(s) for this run; "
        f"{len(existing) + len(additions)} total candidates are now available."
    )
    return len(additions)


if __name__ == "__main__":
    from ringside.config import load_settings

    refill_topic_seeds(load_settings(Path.cwd()))
