/*
	MVCore.h — the small C interface between the Mac Duo app (Swift) and
	the Mini vMac emulator (Macintosh II, 640x480, 256 colors, 8 MB).

	Mini vMac keeps its state in globals, so there is exactly one Mac per
	process. Call MVCoreStart once; afterwards MVCoreReset restarts the
	emulated Mac (like its reset switch) without starting a new one.

	Threading: MVCoreRunTick must always be called from the same thread
	(the emulation thread). Input functions, MVCoreCopyFrame and the
	status getters may be called from any thread. MVCoreReadAudio may be
	called from the real-time audio thread.

	GNU General Public License version 2 (same as Mini vMac).
*/

#ifndef MVCORE_H
#define MVCORE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define MV_SCREEN_WIDTH 640
#define MV_SCREEN_HEIGHT 480
#define MV_ROM_SIZE 0x40000
#define MV_AUDIO_RATE 22255
#define MV_MAX_DISKS 6
#define MV_TICK_HZ 60.14742

typedef enum {
	MVRomOK = 0,          /* a known Mac II-family ROM */
	MVRomUnknown = 1,     /* right size and checksum, but not one we've tested */
	MVRomMissing = 2,     /* file can't be read */
	MVRomWrongSize = 3,   /* not 256 KB (a Mac Plus/SE ROM is 128 KB) */
	MVRomBadChecksum = 4  /* damaged or not a Mac ROM */
} MVRomCheck;

typedef enum {
	MVStateNotStarted = 0,
	MVStateRunning = 1,
	MVStatePoweredOff = 2, /* the Mac chose Shut Down */
	MVStateFailed = 3
} MVState;

/* Looks at a ROM file without starting anything. Fills *checksum. */
MVRomCheck MVCoreCheckROM(const char *path, uint32_t *checksum);

/* Starts the Mac with the ROM at path. Returns 1 on success. */
int MVCoreStart(const char *romPath);

/* Runs one sixtieth of a second of Mac time, plus up to budgetMicros
   of extra time at the chosen speed. Emulation thread only. */
void MVCoreRunTick(int budgetMicros);

MVState MVCoreGetState(void);

/* 0 = 1x (accurate), 1 = 2x, 2 = 4x, 3 = 8x, 4 = 16x, -1 = all out. */
void MVCoreSetSpeed(int speed);

/* Disk images: raw .dsk/.img/.hfv or Disk Copy 4.2. Up to MV_MAX_DISKS.
   Returns 1 if queued; the Mac mounts it on the next tick. A disk that
   can't be opened for writing is inserted locked. */
int MVCoreInsertDisk(const char *path);
/* Number of disks currently inserted in the emulated Mac. */
int MVCoreDiskCount(void);
/* Copies the path of inserted disk i into buf. Returns 0 if none. */
int MVCoreDiskPath(int i, char *buf, int bufSize);

/* Mouse. Coordinates are Mac screen pixels (0..639, 0..479). */
void MVCoreMouseSet(int x, int y);
void MVCoreMouseButton(int down);
/* Current cursor position as the Mac sees it. */
void MVCoreMousePosition(int *x, int *y);

/* Keyboard, using Macintosh virtual key codes (A = 0x00, Return = 0x24). */
void MVCoreKey(int macKey, int down);
/* Releases every key and the mouse button (e.g. when the app goes away). */
void MVCoreReleaseAll(void);

/* Reset switch / interrupt (programmer's) switch. */
void MVCoreReset(void);
void MVCoreInterrupt(void);

/* Copies the latest 640x480 frame as 32-bit BGRA (little-endian 0xAARRGGBB)
   into dst (MV_SCREEN_WIDTH * MV_SCREEN_HEIGHT pixels). Returns the frame
   number; copies nothing and returns the same number if no new frame. */
uint64_t MVCoreCopyFrame(uint32_t *dst, uint64_t lastFrame);

/* Mono sound at MV_AUDIO_RATE, written to both left and right (two separate
   buffers). Fills silence past what's available. Returns the number of
   frames that came from the Mac. Real-time safe (no locks). */
int MVCoreReadAudio(float *left, float *right, int frames);

/* Copies Mini vMac's last message title (e.g. "Unable to locate ROM image")
   into buf and clears it. Returns 0 if there was none. */
int MVCoreTakeMessage(char *buf, int bufSize);

/* Number of ticks emulated so far (for tests and the status line). */
uint64_t MVCoreTickCount(void);

#ifdef __cplusplus
}
#endif

#endif
