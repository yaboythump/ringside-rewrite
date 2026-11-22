/*
	Headless test for the Mac Duo core (Mini vMac + MVGlue.c).
	Usage: mv_core_test test.rom scratch-dir
*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#include "MVCore.h"

extern uint8_t *VidMem; /* Mini vMac's video card memory */

static int failures = 0;
#define CHECK(cond, ...) do { if (!(cond)) { ++failures; printf("FAIL: " __VA_ARGS__); printf("\n"); } else { printf("ok: " __VA_ARGS__); printf("\n"); } } while (0)

static void write_file(const char *path, const uint8_t *data, size_t n)
{
	FILE *f = fopen(path, "wb");
	if (!f) { perror(path); exit(2); }
	fwrite(data, 1, n, f);
	fclose(f);
}

int main(int argc, char **argv)
{
	static uint32_t frame[MV_SCREEN_WIDTH * MV_SCREEN_HEIGHT];
	static uint8_t buf[MV_ROM_SIZE];
	char path[1024], msg[256];
	uint32_t sum = 0;
	uint64_t n;
	int i;

	if (argc < 3) {
		fprintf(stderr, "usage: %s test.rom scratch-dir\n", argv[0]);
		return 2;
	}

	/* ROM checks */
	snprintf(path, sizeof path, "%s/missing.rom", argv[2]);
	CHECK(MVCoreCheckROM(path, NULL) == MVRomMissing, "missing ROM is reported");

	snprintf(path, sizeof path, "%s/plus.rom", argv[2]);
	write_file(path, buf, 0x20000);
	CHECK(MVCoreCheckROM(path, NULL) == MVRomWrongSize, "128 KB ROM is the wrong size");

	FILE *f = fopen(argv[1], "rb");
	if (!f || fread(buf, 1, MV_ROM_SIZE, f) != MV_ROM_SIZE) { fprintf(stderr, "can't read test ROM\n"); return 2; }
	fclose(f);
	buf[0x2000] ^= 0x55;
	snprintf(path, sizeof path, "%s/bad.rom", argv[2]);
	write_file(path, buf, MV_ROM_SIZE);
	CHECK(MVCoreCheckROM(path, NULL) == MVRomBadChecksum, "damaged ROM fails its checksum");

	CHECK(MVCoreCheckROM(argv[1], &sum) == MVRomUnknown && sum != 0,
		"test ROM is valid but unknown (checksum %08X)", sum);

	CHECK(!MVCoreStart(path), "damaged ROM does not start");
	CHECK(MVCoreTakeMessage(msg, sizeof msg) && strlen(msg) > 0, "message for damaged ROM: %s", msg);
	CHECK(MVCoreGetState() == MVStateNotStarted, "still not started");

	/* Start */
	CHECK(MVCoreStart(argv[1]), "test ROM starts");
	CHECK(MVCoreGetState() == MVStateRunning, "running");
	MVCoreSetSpeed(0);

	for (i = 0; i < 120; ++i) {
		MVCoreRunTick(2000);
	}
	CHECK(MVCoreTickCount() == 120, "120 ticks emulated (%llu)", (unsigned long long)MVCoreTickCount());

	printf("video memory: %02X %02X %02X %02X ... %02X %02X | %02X\n", VidMem[0], VidMem[1], VidMem[2],
		VidMem[3], VidMem[0xFFFC], VidMem[0xFFFF], VidMem[0x10000]);
	CHECK(VidMem && VidMem[0] == 0x12 && VidMem[1] == 0x34 && VidMem[2] == 0x56 && VidMem[3] == 0x78
		&& VidMem[0xFFFC] == 0x12 && VidMem[0xFFFF] == 0x78
		&& !(VidMem[0x10000] == 0x12 && VidMem[0x10001] == 0x34),
		"CPU ran the ROM and filled 64 KB of video memory");

	n = MVCoreCopyFrame(frame, 0);
	CHECK(n > 0, "a frame was produced (#%llu)", (unsigned long long)n);
	{
		/* Monochrome at start-up: 0x12 = 00010010 -> pixels 3 and 6 black. */
		static const uint8_t bytes[4] = {0x12, 0x34, 0x56, 0x78};
		int ok = 1, b, k;
		for (b = 0; b < 4; ++b) {
			for (k = 0; k < 8; ++k) {
				uint32_t want = ((bytes[b] >> (7 - k)) & 1) ? 0xFF000000u : 0xFFFFFFFFu;
				if (frame[b * 8 + k] != want) ok = 0;
			}
		}
		CHECK(ok, "first 32 pixels match the pattern (%08X %08X %08X %08X)",
			frame[0], frame[1], frame[2], frame[3]);
		/* 64 KB of 1-bit pixels covers rows 0..818 of an 80-byte row: the whole screen. */
		CHECK(frame[(MV_SCREEN_HEIGHT - 1) * MV_SCREEN_WIDTH + 3] == 0xFF000000u, "bottom row drawn too");
	}

	/* Input */
	MVCoreMouseSet(700, -5);
	{
		int x, y;
		MVCoreMousePosition(&x, &y);
		CHECK(x == 639 && y == 0, "mouse is clamped to the screen (%d,%d)", x, y);
	}
	MVCoreMouseButton(1);
	MVCoreKey(0x00, 1);
	MVCoreKey(0x00, 0);
	MVCoreMouseButton(0);
	MVCoreReleaseAll();

	/* Disks */
	{
		static uint8_t disk[400 * 1024];
		snprintf(path, sizeof path, "%s/blank.dsk", argv[2]);
		write_file(path, disk, sizeof disk);
		CHECK(MVCoreInsertDisk(path), "disk queued");
		MVCoreRunTick(1000);
		CHECK(MVCoreDiskCount() == 1, "disk inserted (%d)", MVCoreDiskCount());
		char back[1024] = {0};
		CHECK(MVCoreDiskPath(0, back, sizeof back) && strcmp(back, path) == 0, "disk path kept");
		snprintf(path, sizeof path, "%s/nope.dsk", argv[2]);
		MVCoreInsertDisk(path);
		MVCoreRunTick(1000);
		CHECK(MVCoreDiskCount() == 1 && MVCoreTakeMessage(msg, sizeof msg), "missing disk reported: %s", msg);
	}

	/* Fast speed uses the time budget */
	MVCoreSetSpeed(-1);
	for (i = 0; i < 10; ++i) MVCoreRunTick(3000);
	CHECK(MVCoreTickCount() == 132, "fast ticks keep counting");

	/* Sound */
	{
		static float l[4096], r[4096];
		int got = MVCoreReadAudio(l, r, 4096);
		CHECK(got >= 0 && got <= 4096, "sound read (%d samples)", got);
	}

	/* Reset runs the ROM again */
	memset(VidMem, 0, 16);
	MVCoreReset();
	for (i = 0; i < 5; ++i) MVCoreRunTick(1000);
	CHECK(VidMem[0] == 0x12, "reset re-ran the ROM");

	CHECK(MVCoreStart(argv[1]), "second start is a no-op");

	printf(failures ? "\n%d FAILED\n" : "\nall passed\n", failures);
	return failures ? 1 : 0;
}
