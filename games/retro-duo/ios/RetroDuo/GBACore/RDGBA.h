// C interface between Swift and the mGBA Game Boy Advance core (MPL 2.0).
// Single-threaded like the Game Boy core; RDGBAReadAudio is safe from the audio thread.
#ifndef RETRO_DUO_RDGBA_H
#define RETRO_DUO_RDGBA_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct RDGBA RDGBA;

enum {
    GBA_PAD_A      = 1 << 0,
    GBA_PAD_B      = 1 << 1,
    GBA_PAD_SELECT = 1 << 2,
    GBA_PAD_START  = 1 << 3,
    GBA_PAD_RIGHT  = 1 << 4,
    GBA_PAD_LEFT   = 1 << 5,
    GBA_PAD_UP     = 1 << 6,
    GBA_PAD_DOWN   = 1 << 7,
    GBA_PAD_R      = 1 << 8,
    GBA_PAD_L      = 1 << 9,
};

enum { GBA_SCREEN_WIDTH = 240, GBA_SCREEN_HEIGHT = 160 };

RDGBA *RDGBACreate(unsigned sampleRate);
void RDGBADestroy(RDGBA *core);

/// Loads a cartridge (and its save, if any) and starts it. False if it isn't a GBA game.
bool RDGBALoadROM(RDGBA *core, const uint8_t *rom, size_t length, const uint8_t *save, size_t saveLength);
void RDGBAReset(RDGBA *core);

void RDGBASetKeys(RDGBA *core, uint16_t pressed);
void RDGBARunFrame(RDGBA *core);
uint64_t RDGBAFrameCount(const RDGBA *core);
/// One byte from the GBA's address space (work RAM is $02000000 and $03000000), without side effects.
uint8_t RDGBARead8(const RDGBA *core, uint32_t address);

/// RGBX pixels (red byte first), 240x160, stride = width.
const uint32_t *RDGBAPixels(const RDGBA *core);

size_t RDGBAReadAudio(RDGBA *core, float *left, float *right, size_t frames);
size_t RDGBABufferedAudioFrames(const RDGBA *core);

/// Cartridge save data. RDGBACopySave returns a buffer to free with RDGBAFreeBuffer.
uint8_t *RDGBACopySave(RDGBA *core, size_t *length);

uint8_t *RDGBASaveState(RDGBA *core, size_t *length);
bool RDGBALoadState(RDGBA *core, const uint8_t *data, size_t length);
void RDGBAFreeBuffer(uint8_t *buffer);

/// Rumble requested by the cartridge (0 or 1).
double RDGBARumble(const RDGBA *core);

#ifdef __cplusplus
}
#endif

#endif
