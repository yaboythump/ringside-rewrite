# CT ARCADE · CTInteractive
Native iPhone Duo retro arcade application. **This is a playable NES v0.1 alpha**, not a claim that SNES, N64, PS1, PSP, and DS emulation already work.

## What is implemented
- Native iOS app (SwiftUI + offline WKWebView), adaptive folded/unfolded and portrait/landscape UI.
- NES emulation using the Apache 2.0 licensed JSNES 3.0.0 engine; 256x240 pixel-correct framebuffer.
- On-screen D-pad, A/B, Start/Select; connected Xbox/PlayStation gamepad support through GameController.
- NES ROM import from the iOS Files picker, local cartridge library and per-game save states.
- Local Web Audio, pause/resume and reset.
- Original built-in Star Runner mini-game runs even with an empty library, no commercial ROMs bundled.
- Xcode 27.1 native project and CI build checks.

## Build
Run `python3 games/ct-arcade/prepare.py` to download and locally prepare the pinned JSNES open-source engine and generate the original app icon. Then build `games/ct-arcade/ios/CTArcade.xcodeproj` (scheme `CTArcade`). The Xcode build phase embeds the engine and UI JavaScript into one index.html resource so no CDN is needed on the iPhone. This also satisfies Xcode's user-script sandbox.

Browser development preview: `games/ct-arcade/index.html`; if the local engine is missing, browser preview falls back to the pinned CDN. Native binary always includes the local engine.

## Legal / release
No Nintendo games or BIOS are distributed. Users must provide games they have a right to use. JSNES copyright and license: https://github.com/bfirsh/jsnes/blob/main/LICENSE (Apache-2.0). Release uses bundle `com.ctnetworkstudios.ctarcade`, Apple team `J4Y8FY6JNZ`; Apple App Store Connect requires an app record before TestFlight upload.

## Next
QA on actual Duo half-open poses, performance and audio latency. Then add additional emulator cores with reviewed licenses and proven iOS compatibility.
