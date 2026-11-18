# CTInteractive | Detective Duo

**Playable Case 001: The Last Call at Meridian.** Original offline-first missing-person mystery for iPhone Duo. Investigate the disappearance of reporter Lena Vale from the fictional Meridian Hotel. All characters, locations, and artwork are original.

## Game features

- Four illustrated interactive rooms with **16 tap-to-collect clues**.
- Four witnesses/suspects with contextual questions (some unlocked by evidence).
- **Four evidence-pair deductions** with clear positive and negative feedback.
- Final three-part reconstruction, reversible incorrect answers, complete win state.
- On-device autosave, haptic feedback in the iOS app, restart and help.
- Folded iPhone: compact scene with a fixed, tabbed evidence desk, no page scroll to reach actions.
- Unfolded/landscape iPhone Duo: the interactive scene and the live evidence board run **side by side** with no reload.
- No external services, accounts, API keys, generated suspects, subscriptions, or network needed to play.

## Run as a website

Open `games/detective-duo/index.html`. The game is self-contained.

## iPhone app

Xcode project: `games/detective-duo/ios/DetectiveDuo.xcodeproj`.
Bundle identifier: `com.ctnetworkstudios.detectiveduo`.
Apple Team: `J4Y8FY6JNZ`.
Native code loads the offline game with WKWebView, keeps the player's save in UserDefaults, and supplies native haptic feedback. All gameplay works without a network.

## Test

```sh
npm install --no-save playwright
npx playwright install chromium
node games/detective-duo/tests/smoke.mjs
```

The dedicated Actions workflow also verifies the iOS archive and browser gameplay before attempting distribution to TestFlight. It uses the repository's existing `ringside-testflight` environment. If Apple will not allow the app record or bundle registration, verification will still complete, but the upload step will report that Apple authorization is needed. The workflow must not change other CTInteractive games.

**Game art:** Original, vector-style nighttime hotel scenes are drawn in HTML SVG; no unlicensed character imagery.
