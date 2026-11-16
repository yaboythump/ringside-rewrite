# Ringside Combo

Ringside Combo is CTInteractive’s offline wrestling match-3 game. It keeps the original roster, turn-based board, finishers, crowd meter, dirty tricks, and four-opponent Championship Ladder. Road to Gold and Exhibition are available from the same game.

## Build and play

```sh
python3 games/ring-combo/build.py
```

Open `games/ring-combo.html` in a browser. Portraits, approved arena art, game music, referee counts and crowd samples are embedded. GitHub Pages and the iOS Xcode target call the same build script. Character identities, lore, portrait paths and title definitions are in `games/ringside-universe.json`. Combo applies its own combat stats and maintains its own saves.

## Controls and progression

- **Play** offers the original Championship Ladder and seven exhibition rulesets. Pick a wrestler, press **Start Match**, and the entrance advances to the opening bell. Tap neighboring tiles or swipe to swap them.
- Match three tiles to attack, recover, play to the crowd, or set a counter. Match four to create a Clothesline. Match five to create a wrestler-owned Finisher. Board matches also charge the four moves on the wrestler’s loadout.
- **Career** starts with a rookie debut. Singles and tag wins unlock title challenges. Results build rivalry heat and unlock a cage rematch, a Hardcore ambush, and title defenses. Match earnings fund development and cosmetic unlocks.
- **Wrestlers** lets players equip compatible move cards, train attributes with cash when eligible, and wear their unlocked cosmetics. **Shop** sells and upgrades cards and unlocks cosmetics. Cash is earned through play.
- Daily rewards are claimed once per period. The weekly tournament is a three-stage single-elimination bracket. Periods use a forward-only UTC calendar and require 20 minutes of accumulated match time before another daily event can open and 60 minutes before another weekly bracket can open. These local checks limit clock changes and duplicate claims. A wholly offline save has no trusted server time.
- A previous build’s mute choice migrates into the versioned profile. Browser saves use the same origin as before. Native saves use the app-owned file bridge and retain a previous valid profile as a recovery copy. A save from an unsupported version stays on disk.

| Match | Finish |
| --- | --- |
| Singles / Hardcore | Score a pinfall. Hardcore adds matchable weapons and disables rope breaks. |
| Steel Cage | Build 100% climb progress with Showboat matches and escape once your opponent is below half health. |
| Submission | Use Grapples and submission cards to apply pressure. Break a hold with Recover, Reversal or Kick matches. |
| Iron Man | Score the most falls in two minutes. Both wrestlers recover after a fall. |
| Last Man Standing | Reduce the opponent to zero and keep them down through ten. Clear tiles to recover when downed. |
| Tag Team | Win by pinfall. Swap to a rested partner and spend team momentum on double-team attacks and finishers. |

## Verification and TestFlight

```sh
python3 -m pip install playwright
python3 -m playwright install chromium
python3 games/ring-combo/test_game.py
```

The browser suite runs the unmodified offline build for touch layout and navigation. A separate instrumented build runs deterministic scenario tests for combat, rewards and save recovery. It also plays a full singles match using legal swaps. Tablet and physical-device experience, native haptics, the iPhone silent switch and `WKWebView` audio interruptions require device checks.

The TestFlight workflow runs browser tests and an unsigned Release archive on pull requests. Its upload job requires an explicit manual workflow run with `upload` enabled. It uses the existing protected Apple environment and iPhone app ID `com.ctnetworkstudios.ringsidecombo`. The Xcode target supports iOS 17 and later in portrait orientation and packages the approved icon, system launch screen and privacy manifest. TestFlight status must be confirmed in App Store Connect after processing.

For public release, validate the signed candidate on iPhone, finish the age-rating and privacy disclosures, provide a public privacy-policy URL, and complete the App Store Connect listing and screenshots. The pull request and CI do not publish the live game.
