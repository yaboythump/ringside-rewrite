// C interface between Swift and the melonDS Nintendo DS core (GPLv3).
// The console runs on its own thread; every call here is safe from the main thread,
// and MDCoreReadAudio is safe from the audio thread.
#ifndef RETRO_DUO_MDCORE_H
#define RETRO_DUO_MDCORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct MDCore MDCore;

enum {
    MD_KEY_A      = 1 << 0,
    MD_KEY_B      = 1 << 1,
    MD_KEY_SELECT = 1 << 2,
    MD_KEY_START  = 1 << 3,
    MD_KEY_RIGHT  = 1 << 4,
    MD_KEY_LEFT   = 1 << 5,
    MD_KEY_UP     = 1 << 6,
    MD_KEY_DOWN   = 1 << 7,
    MD_KEY_R      = 1 << 8,
    MD_KEY_L      = 1 << 9,
    MD_KEY_X      = 1 << 10,
    MD_KEY_Y      = 1 << 11,
};

enum { MD_SCREEN_WIDTH = 256, MD_SCREEN_HEIGHT = 192 };

MDCore *MDCoreCreate(unsigned sampleRate);
/// Stops the console thread and frees everything. Stop audio output first.
void MDCoreDestroy(MDCore *core);

/// Loads a cartridge (and its save, if any) and boots it. Returns false for files that aren't DS games.
bool MDCoreLoadROM(MDCore *core, const uint8_t *rom, size_t length,
                   const uint8_t *save, size_t saveLength, const char *name);
/// Starts or resumes the console thread.
void MDCoreSetRunning(MDCore *core, bool running);
void MDCoreReset(MDCore *core);

/// Held buttons, MD_KEY_* bits.
void MDCoreSetKeys(MDCore *core, uint32_t pressed);
/// Touch on the bottom screen in DS pixels (0-255, 0-191).
void MDCoreSetTouch(MDCore *core, bool down, int x, int y);

/// Copies the latest frame (RGBX byte order, 256x192 each). Returns the frame number.
uint64_t MDCoreCopyScreens(MDCore *core, uint32_t *top, uint32_t *bottom);

size_t MDCoreReadAudio(MDCore *core, float *left, float *right, size_t frames);

/// Cartridge save memory. MDCoreSaveChanged reports (and clears) whether the game wrote to it.
size_t MDCoreSaveSize(MDCore *core);
size_t MDCoreCopySave(MDCore *core, uint8_t *buffer, size_t length);
bool MDCoreSaveChanged(MDCore *core);

/// Save states. MDCoreSaveState returns a buffer to free with MDCoreFreeBuffer.
uint8_t *MDCoreSaveState(MDCore *core, size_t *length);
bool MDCoreLoadState(MDCore *core, const uint8_t *data, size_t length);
void MDCoreFreeBuffer(uint8_t *buffer);

void MDCoreTitle(MDCore *core, char title[13]);
/// Frames emulated per second over the last second (for diagnostics).
double MDCoreSpeed(MDCore *core);

#ifdef __cplusplus
}
#endif

#endif
