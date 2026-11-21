# Clutch Bets V2

**Independent iOS rebuild** for CTInteractive. This is not an update to the older Clutch Bets TestFlight app.

- Display name: **Clutch Bets V2**
- Bundle identifier: **com.ctnetworkstudios.clutchbetsv2**
- Apple team: **J4Y8FY6JNZ**
- iOS: 17+
- Unit default: **$25**
- Built with SwiftUI, no third-party SDKs, with a responsive wide-screen layout.

## Features

- Premium gold / graphite dashboard, adaptive navigation for compact and wide displays.
- Manual straight / parlay slip builder with American-odds validation and stake / return math.
- Persistent ticket ledger, status tracking, realized P/L, win rate and ROI.
- Editable bankroll and unit value, keeping the unit value stored with each old ticket.
- Two-outcome arbitrage check and odds / payout calculator.
- Clear no-data state for picks. **No live odds or verified recommendations are invented.**

## Important limitations

This private beta is **research and tracking only**. It cannot place a bet, take a deposit, connect to sportsbooks, or supply live verified picks. It stores ticket information locally on the installed device using UserDefaults. Cloud sync and licensed data feeds are not yet connected. Mathematical arbitrage does not guarantee executable profit, and the app does not assert that any pick is 90%+ likely to win.

## Build

On a Mac with a current Xcode and XcodeGen:

```sh
python3 scripts/generate_icon.py
xcodegen generate --spec project.yml
xcodebuild -project ClutchBetsV2.xcodeproj -scheme ClutchBetsV2 -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

All commands run from `apps/clutch-bets-v2`.

## Release isolation

The GitHub Actions workflow `.github/workflows/clutch-bets-v2-testflight.yml` builds this app independently. The upload job is manual only and must target the brand-new Apple App ID and App Store Connect app record for **com.ctnetworkstudios.clutchbetsv2**. Do not reuse the old Clutch Bets bundle ID, App Store Connect record, or version numbering. No existing app source needs to be edited.
