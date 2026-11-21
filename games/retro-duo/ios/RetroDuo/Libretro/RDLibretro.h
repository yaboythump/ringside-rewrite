// A small libretro host: runs one libretro emulator core (SNES today; Sega and PC Engine
// cores plug in the same way) for Swift. Single-threaded like the Game Boy core:
// the main thread runs frames, RDLRReadAudio is safe from the audio thread.
#ifndef RETRO_DUO_LIBRETRO_HOST_H
#define RETRO_DUO_LIBRETRO_HOST_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct RDLRHost RDLRHost;

/// Which emulator core to run.
enum {
    RDLR_SYSTEM_SNES = 1,
};

/// Buttons in RetroPad order (RETRO_DEVICE_ID_JOYPAD_* bit positions).
enum {
    RDLR_PAD_B      = 1 << 0,
    RDLR_PAD_Y      = 1 << 1,
    RDLR_PAD_SELECT = 1 << 2,
    RDLR_PAD_START  = 1 << 3,
    RDLR_PAD_UP     = 1 << 4,
    RDLR_PAD_DOWN   = 1 << 5,
    RDLR_PAD_LEFT   = 1 << 6,
    RDLR_PAD_RIGHT  = 1 << 7,
    RDLR_PAD_A      = 1 << 8,
    RDLR_PAD_X      = 1 << 9,
    RDLR_PAD_L      = 1 << 10,
    RDLR_PAD_R      = 1 << 11,
};

/// Only one host can run at a time (libretro cores keep global state). Returns NULL if
/// another host is alive or the system isn't built in.
RDLRHost *RDLRCreate(int system, const char *workDirectory);
void RDLRDestroy(RDLRHost *host);

/// Loads a game (and its battery save, if any). `fileName` is a plain name with the
/// right extension, e.g. "game.sfc"; some cores read the file from the work directory.
bool RDLRLoadROM(RDLRHost *host, const uint8_t *rom, size_t length,
                 const uint8_t *save, size_t saveLength, const char *fileName);
void RDLRReset(RDLRHost *host);

void RDLRSetKeys(RDLRHost *host, uint32_t pressed);
void RDLRRunFrame(RDLRHost *host);
uint64_t RDLRFrameCount(const RDLRHost *host);

/// Latest picture: RGBX (red byte first), RDLRWidth x RDLRHeight, stride = width.
const uint32_t *RDLRPixels(const RDLRHost *host);
unsigned RDLRWidth(const RDLRHost *host);
unsigned RDLRHeight(const RDLRHost *host);
/// Display height / width the core asks for (accounts for non-square pixels).
double RDLRDisplayAspect(const RDLRHost *host);
double RDLRFrameRate(const RDLRHost *host);
double RDLRSampleRate(const RDLRHost *host);

size_t RDLRReadAudio(RDLRHost *host, float *left, float *right, size_t frames);
size_t RDLRBufferedAudioFrames(const RDLRHost *host);

/// Battery save RAM; free with RDLRFreeBuffer. NULL when the game has none.
uint8_t *RDLRCopySave(RDLRHost *host, size_t *length);
uint8_t *RDLRSaveState(RDLRHost *host, size_t *length);
bool RDLRLoadState(RDLRHost *host, const uint8_t *data, size_t length);
void RDLRFreeBuffer(uint8_t *buffer);

#ifdef __cplusplus
}
#endif

#endif
