# Dear Tomorrow

Native SwiftUI voice messages, letters and photo capsules for your future self. Bundle identifier: `com.ctnetworkstudios.capsuleduo`.

## Experience

- Cinematic mountain sunrise, separately rendered metallic envelope/clock emblem, champagne serif wordmark, purple glass surfaces and sunset skyline banner.
- Home actions: Record, Write, Seal & Send and My Vault. Bottom navigation reserves safe-area space and never floats over scroll content.
- Upcoming Deliveries remains visible when empty. Real capsule rows update their HH:MM:SS countdown every second. Vault includes a Delivered filter.
- Record up to ten minutes, write a standalone letter, attach up to four photos, or combine them. Choose a date or an existing “Open when…” condition.
- Profile name, delivery notifications and startup sound controls. Signature startup chime respects the silent switch.
- Fold-aware layout retains both panes on iPhone Duo and wide landscape screens. Large accessibility text uses a two-column action grid.

## Privacy and compatibility

The existing Codable capsule schema and Application Support/Capsules paths are unchanged. Voice recordings, notes, photos, delivery dates and opened status remain compatible. No migration, account, server or analytics is introduced.

Date-locked capsules expose only metadata until their date. The store independently checks the lock before opening. A failed seal removes its partial folder and leaves the original draft recording intact. Recordings, manifests and attachments use file protection.

## Production assets

`ios/CapsuleDuo/Assets.xcassets` contains separate EnvelopeEmblem, MountainSunrise, SunsetSkyline, PurpleGlass and AppIcon artwork. No screen is a static mockup. All text, statistics, countdowns and controls are native views. The icon family and illuminated underline are scalable native paths in PremiumDesign.swift.

## Verification and delivery

The existing Capsule Duo TestFlight workflow archives Release, builds and launches the simulator, checks storage/unlock compatibility and captures actual app screens. Only verified changes on main are signed and uploaded through the existing distribution configuration. Public App Store submission is separate.

Simulator-only verification uses a disposable store. `-CapsuleVerify` checks standalone notes, legacy manifest reload, audio/photo byte preservation, blocked early opening, allowed due opening, persisted opening, Open When compatibility, empty-content rejection, failed-seal cleanup, second-by-second countdowns and compiled artwork lookup. It writes `tmp/verification.json`.

Snapshot flags: `-CapsuleSnapshot`, `-CapsuleDemo` (disposable sample capsules), `-CapsuleWrite`, `-CapsuleWriteSnapshot`, `-CapsuleScheduled`, `-CapsuleVault`, `-CapsuleSettings`, `-CapsuleCompose`, `-CapsuleSealedDemo`, `-CapsuleOpenedDemo`, `-CapsuleLandscape`, `-CapsuleFakeFold`.

Production launches use actual on-device data. No sample capsules are seeded on a normal launch.
