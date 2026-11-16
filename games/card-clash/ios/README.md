# Ringside Card Clash for iPhone

This Xcode project builds the same game and portrait assets as the browser
release and bundles them at build time. Play and progress work offline.
The app saves careers, cup brackets, tag results and settings to its own
Application Support directory. Browser saves are separate.

## Simulator

Open `RingsideCardClash.xcodeproj` in Xcode 26 or later. Select an iPhone
simulator and use Run. The shared scheme includes a test that starts a career,
terminates the app, and checks that the career resumes after launch.

## TestFlight

1. On a Mac signed in to the correct Apple Developer team, open Signing &
   Capabilities for the app target and select the team. The proposed identifier
   is `com.ctnetworkstudios.ringsidecardclash`. If the team already has an App
   Store Connect record for the game, use its identifier before the first upload.
2. Register that explicit identifier with Apple and create an iOS app record
   named **Ringside Card Clash** in App Store Connect.
3. Archive the Release build and distribute to App Store Connect. When Apple has
   processed the build, add it to an internal TestFlight group.
4. Verify install, offline play, audio, touch targets and save persistence on an
   iPhone. Complete the store listing, privacy disclosures and age rating before
   submitting for public App Review.

The GitHub simulator work uses no Apple signing credentials and sends no builds
to Apple. Keep signing material out of source control.
