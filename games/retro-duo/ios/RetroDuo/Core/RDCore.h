// Small C interface between Swift and the SameBoy core.
// Swift only sees this header; SameBoy's own headers stay private to RDCore.c.
#ifndef RETRO_DUO_CORE_H
#define RETRO_DUO_CORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct RDCore RDCore;

enum {
    RD_KEY_RIGHT  = 1 << 0,
    RD_KEY_LEFT   = 1 << 1,
    RD_KEY_UP     = 1 << 2,
    RD_KEY_DOWN   = 1 << 3,
    RD_KEY_A      = 1 << 4,
    RD_KEY_B      = 1 << 5,
    RD_KEY_SELECT = 1 << 6,
    RD_KEY_START  = 1 << 7,
};

/// Creates a Game Boy Color with the given boot ROM. Returns NULL on failure.
RDCore *RDCoreCreate(const uint8_t *bootROM, size_t bootROMLength, unsigned sampleRate);
void RDCoreDestroy(RDCore *core);

/// Loads a cartridge and restarts the console. Returns false for files that are not Game Boy ROMs.
bool RDCoreLoadROM(RDCore *core, const uint8_t *rom, size_t length);
void RDCoreReset(RDCore *core);

void RDCoreSetKeys(RDCore *core, uint8_t mask);
void RDCoreRunFrame(RDCore *core);
uint64_t RDCoreFrameCount(const RDCore *core);
/// One byte as the Game Boy's CPU sees it at `address`, without side effects (for the tracker).
uint8_t RDCoreReadMemory(const RDCore *core, uint16_t address);
/// Replaces the cheats: each entry is one cheat, its codes one per line (Game Genie
/// "XXX-YYY-ZZZ" or GameShark "01VVAAAA"). `accepted[i]` says whether every line of entry i was valid.
void RDCoreSetCheats(RDCore *core, const char *const *entries, size_t count, bool *accepted);

/// 160x144 pixels, RGBX byte order (red first), row stride = width * 4.
const uint32_t *RDCorePixels(const RDCore *core);
unsigned RDCoreScreenWidth(const RDCore *core);
unsigned RDCoreScreenHeight(const RDCore *core);

/// Copies up to `frames` stereo frames into the float buffers and zero-fills the rest.
/// Safe to call from the audio thread while the main thread runs frames.
size_t RDCoreReadAudio(RDCore *core, float *left, float *right, size_t frames);
size_t RDCoreBufferedAudioFrames(const RDCore *core);

/// Battery-backed cartridge RAM (in-game saves). Size is 0 for carts without saves.
size_t RDCoreBatterySize(RDCore *core);
size_t RDCoreSaveBattery(RDCore *core, uint8_t *buffer, size_t length);
void RDCoreLoadBattery(RDCore *core, const uint8_t *buffer, size_t length);

/// Full snapshots (save states).
size_t RDCoreStateSize(RDCore *core);
void RDCoreSaveState(RDCore *core, uint8_t *buffer);
bool RDCoreLoadState(RDCore *core, const uint8_t *buffer, size_t length);

/// Writes the cartridge title (up to 16 characters plus NUL) into `title`.
void RDCoreTitle(RDCore *core, char title[17]);
/// Last rumble strength requested by the cartridge, 0...1.
double RDCoreRumble(const RDCore *core);

#ifdef __cplusplus
}
#endif

#endif
