# Mac Duo

A classic Macintosh II emulator for iPhone, built for iPhone Duo.

**License:** GNU GPL version 2, because the emulator, [Mini vMac](https://www.gryphel.com/c/minivmac/), is GPL v2 (see `vendor/minivmac/COPYING.txt`). The app's own code is released under the same terms.

- **Emulation:** Mini vMac 36 configured as a **Macintosh II**: 68020 with FPU, 8 MB of RAM, a 640×480 screen in 256 colors, sound, and up to six disks. Runs System 6.0.8 through System 7.5.5.
- **iPhone Duo:** fold it halfway (laptop style) and the Mac's screen sits above the fold with a trackpad, mouse button and keys below it, like a PowerBook. Flat in portrait you get the same stack; in landscape the screen fills the display.
- **Pointer:** slide on the trackpad to move, tap to click, double-tap to double-click, tap then slide to drag, or hold the bar under the pad and slide. Touching the Mac's screen clicks right there; switch it to trackpad mode in ⚙︎ if you'd rather.
- **Keyboard:** the iPhone keyboard, a key bar (esc, tab, ⌘ ⌥ ⌃ ⇧, arrows; tap a modifier for the next key, double-tap to lock) and hardware keyboards.
- **Disks:** add `.dsk`/`.img`/`.hfv` and Disk Copy 4.2 images with **+**, or drop them into Files › On My iPhone › Mac Duo. Tick the disks to insert when the Mac turns on; the first one starts it. More can be inserted from the disk menu while it runs. **+ › New Blank Disk** makes an empty floppy or hard disk the Mac will offer to initialize.
- **Speed:** actual speed, 2×, 4× (default), 8× or as fast as possible.

## What you need

Mac Duo ships **no Apple software**. You add:

1. **A ROM** from a Macintosh II, IIx, IIcx or SE/30 (256 KB) that you own. Mac Plus/SE ROMs (128 KB) won't work with this model. The app checks the size and checksum and says which machine it came from.
2. **System software** on a disk image, e.g. a hard disk image with System 7.

## Getting it on TestFlight

1. Merge the pull request. A Linux machine builds the emulator core and runs `tests/run_core_test.sh`; GitHub's Mac builds the app.
2. One time only: in App Store Connect go to **Apps → + → New App**, name it **Mac Duo** and pick bundle ID `com.ctnetworkstudios.macduo`. (The upload step registers the bundle ID if it isn't listed yet; run it once and it will appear.) Apple may not accept "Mac" in a public App Store name; TestFlight builds are fine.
3. Merging to `main` uploads automatically, or go to **Actions → Mac Duo TestFlight → Run workflow** on `main`.

The upload uses the same `ringside-testflight` signing secrets as the other apps.

## Layout

| Path | What it is |
|---|---|
| `ios/MacDuo/*.swift` | SwiftUI app: library (ROM and disks), the Mac screen, trackpad, keyboard, sound |
| `ios/MacDuo/Core/MVCore.h` | The C interface Swift uses |
| `ios/MacDuo/Core/MVGlue.c` | Mini vMac platform glue: files, ticks, frames, sound ring, input queue |
| `ios/MacDuo/Core/cfg/` | Mini vMac build configuration (Mac II, 640×480×8, 8 MB) |
| `vendor/minivmac/` | Mini vMac emulator sources (from libretro-minivmac `babdf7b`), unmodified, and its license |
| `tests/` | Headless core test: an original 256 KB test ROM (`make_test_rom.py`) runs on the emulated 68020 and draws into video memory |
| `tools/make_project.py` | Regenerates `ios/MacDuo.xcodeproj` after adding or removing source files |

## Simulator launch options

`-MacDuoTestROM` writes the original test ROM and turns the Mac on (striped test picture), `-MacDuoFakeFold` lays the screen out as if half-folded, and `-MacDuoSnapshot` saves screenshots to the app's tmp folder. CI uses these on feature branches.
