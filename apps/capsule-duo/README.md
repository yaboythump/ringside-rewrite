# Capsule Duo

Voice messages to your future self, made for iPhone Duo.

- **Record:** tap the wax-red mic and talk for up to 10 minutes. Listen back and re-record as often as you like before sealing.
- **Seal it:** pick when it unlocks, either **on a date** (1 month, 6 months, 1 year, 5 years or any date and time) or **"Open when…"** (a moment like *I'm having a hard day* or *I reach my goal*).
- **Sealed means sealed:** a sealed capsule shows only its envelope, a countdown and what's inside (length, note, photo count). There's no way to listen early. A date capsule sends a notification the moment it unseals. An "Open when…" capsule asks "Is it time?" before it opens.
- **Add a note and photos:** up to 4 photos and a written note travel with the recording and appear only once it's opened.
- **Fold-aware:** on the open iPhone Duo the home screen puts recording on one side of the fold and your capsules on the other. While composing, the recorder and the note/lock options each get a side. An opened capsule plays on one side with the note and photos on the other. On a regular phone the two halves stack in one scroll.
- **Private:** everything lives in the app's Application Support folder with file protection on. No account, no server, no upload.

## How it works

| Path | What it is |
|---|---|
| `ios/CapsuleDuo/CapsuleStore.swift` | Capsule model, on-device storage, unlock rules and reminders |
| `ios/CapsuleDuo/Audio.swift` | Recorder (AAC, live levels) and player |
| `ios/CapsuleDuo/DuoLayout.swift` | `DuoSplit`, which lays two panes around the fold, plus the shared look |
| `ios/CapsuleDuo/ShelfView.swift` | Home screen |
| `ios/CapsuleDuo/ComposeView.swift` | Record, label, lock, note, photos, seal |
| `ios/CapsuleDuo/CapsuleView.swift` | Sealed envelope, breaking the seal, playback |

The fold comes from `GeometryProxy.reservedRegions(kind: .division)` (iOS 27.1), the same as Quilune.

Simulator flags used by the workflow: `-CapsuleDemo` (example capsules in a throwaway folder), `-CapsuleSealedDemo`, `-CapsuleOpenedDemo`, `-CapsuleCompose`, `-CapsuleLandscape`, `-CapsuleFakeFold` and `-CapsuleSnapshot`.

## Getting it on TestFlight

1. Merge the pull request. GitHub's Mac builds the app and uploads it.
2. One time only: in App Store Connect go to **Apps → + → New App**, name it **Capsule Duo** and pick bundle ID `com.ctnetworkstudios.capsuleduo`. (The upload step registers the bundle ID if it isn't listed yet; run it once and it will appear.)
3. If the first upload stopped because the app record didn't exist yet, go to **Actions → Capsule Duo TestFlight → Run workflow** on `main`. The build appears in TestFlight a few minutes later.

The upload uses the same `ringside-testflight` signing secrets as the other apps.

## Later

Capsules sent to someone else (a parent recording for a child's 18th birthday, say) need a server to hold them, so they're a second phase.
