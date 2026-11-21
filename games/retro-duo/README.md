# Retro Duo

A Game Boy, Game Boy Color and Nintendo DS player for iPhone, built for iPhone Duo.

**License:** GNU GPL v3 or later (see `LICENSE`), because the DS engine, melonDS, is GPL. SameBoy is Expat (MIT); teakra is MIT.

- **Emulation:** the [SameBoy](https://github.com/LIJI32/SameBoy) core (Expat/MIT license), compiled straight into the app. Every game runs on an emulated Game Boy Color, so original Game Boy games get color palettes.
- **iPhone Duo:** fold it halfway (laptop style) and the picture sits on the top half with the controls on the bottom half. Flat landscape puts the D-pad and buttons on either side. Portrait works like the original handheld.
- **Library:** tap **+** to import `.gb` / `.gbc` files, or drop them into Files › On My iPhone › Retro Duo. Swipe to delete.
- **Saves:** in-game saves are written automatically (Files › Retro Duo › Saves). The game also resumes where you left off, and the ☰ menu has a quick save slot.
- **Extras:** haptics, rumble carts, sound, and Bluetooth controllers (right face button = A, bottom = B, Menu = START, Options = SELECT).
- **Nintendo DS:** [melonDS](https://melonds.kuribo64.net) 1.1 with its free replacement BIOS (no Nintendo files needed), running on its own thread. Half-folded, the top screen sits above the fold and the touch screen below it, between the D-pad and A/B/X/Y. L/R are on screen and on controllers' shoulder buttons. Saves, resume and quick save work like Game Boy.
- **Built-in Test Cart:** an original mini ROM for checking controls, sound and colors on first launch.

The app ships no commercial games. Players add games they own or that are shared freely.

## Getting it on TestFlight

1. Merge the pull request. GitHub's Mac builds the app and a Linux machine plays the test cart to check the emulator.
2. One time only: in App Store Connect go to **Apps → + → New App**, name it **Retro Duo** and pick bundle ID `com.ctnetworkstudios.retroduo`. (The upload step registers the bundle ID for you if it isn't listed yet. Run it once and it will appear.)
3. Go to **Actions → Retro Duo TestFlight → Run workflow** on `main`. The build appears in TestFlight a few minutes later.

The upload uses the same `ringside-testflight` signing secrets as the other games.

## Layout

| Path | What it is |
|---|---|
| `ios/RetroDuo/*.swift` | SwiftUI app: library, play screen, controls, audio, saves |
| `ios/RetroDuo/Core/RDCore.c/.h` | Small C layer between Swift and SameBoy |
| `ios/RetroDuo/Core/SameBoyConfig.h` | SameBoy build options (prefix header) |
| `ios/RetroDuo/Resources/` | Game Boy Color start-up ROM (built from SameBoy source), test cart, license |
| `ios/RetroDuo/DSCore/` | C bridge and platform layer for melonDS (`MDCore`) |
| `vendor/melonDS/` | melonDS 1.1 core sources (no frontend, JIT or OpenGL) |
| `testcart-ds/` | Original DS test cart (C, built with stock clang + lld) |
| `vendor/SameBoy/` | SameBoy v1.0.5 `Core/`, unmodified |
| `testcart/` | Test cart source (RGBDS assembly) and `build.sh` |
| `tests/` | Headless core test run on every push |

## Updating SameBoy

Replace `vendor/SameBoy/Core` with the new release's `Core` folder (minus `debugger.c`, `sm83_disassembler.c`, `symbol_hash.c`, `cheats.c`, `cheat_search.c`, `rewind.c`), update `GB_VERSION` in `SameBoyConfig.h`, rebuild `cgb_boot.bin` with `make bootroms`, and run `tests/run_core_test.sh`.
