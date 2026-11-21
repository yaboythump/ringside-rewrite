// C interface between Swift and the Nestopia NES core (GPL v2 or later).
// Single-threaded like the Game Boy core: the main thread runs frames,
// and NESCoreReadAudio is safe from the audio thread.
#ifndef RETRO_DUO_NESCORE_H
#define RETRO_DUO_NESCORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct NESCore NESCore;

enum {
    NES_KEY_A      = 1 << 0,
    NES_KEY_B      = 1 << 1,
    NES_KEY_SELECT = 1 << 2,
    NES_KEY_START  = 1 << 3,
    NES_KEY_UP     = 1 << 4,
    NES_KEY_DOWN   = 1 << 5,
    NES_KEY_LEFT   = 1 << 6,
    NES_KEY_RIGHT  = 1 << 7,
};

/// The picture: 256x224 (the 8 overscan lines at top and bottom that TVs hid are cropped).
enum { NES_SCREEN_WIDTH = 256, NES_SCREEN_HEIGHT = 224 };

NESCore *NESCoreCreate(unsigned sampleRate);
void NESCoreDestroy(NESCore *core);

/// Loads an iNES/NES 2.0 file (plus its battery save, if any) and powers on. False if it isn't a playable NES game.
bool NESCoreLoadROM(NESCore *core, const uint8_t *rom, size_t length, const uint8_t *save, size_t saveLength);
void NESCoreReset(NESCore *core);

void NESCoreSetKeys(NESCore *core, uint8_t pressed);
void NESCoreRunFrame(NESCore *core);
uint64_t NESCoreFrameCount(const NESCore *core);

/// RGBX pixels (red byte first), NES_SCREEN_WIDTH x NES_SCREEN_HEIGHT, stride = width.
const uint32_t *NESCorePixels(const NESCore *core);

size_t NESCoreReadAudio(NESCore *core, float *left, float *right, size_t frames);
size_t NESCoreBufferedAudioFrames(const NESCore *core);

/// Battery-backed cartridge RAM. Size is 0 for games without saves.
size_t NESCoreBatterySize(NESCore *core);
size_t NESCoreCopyBattery(NESCore *core, uint8_t *buffer, size_t length);

/// Save states; free the returned buffer with NESCoreFreeBuffer.
uint8_t *NESCoreSaveState(NESCore *core, size_t *length);
bool NESCoreLoadState(NESCore *core, const uint8_t *data, size_t length);
void NESCoreFreeBuffer(uint8_t *buffer);

#ifdef __cplusplus
}
#endif

#endif
