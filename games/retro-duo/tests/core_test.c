// Headless test of the exact C code the iPhone app ships: SameBoy core + RDCore wrapper.
// Boots the Game Boy Color boot ROM, runs the bundled test cart, and checks video,
// input, sound, save states and battery saves. Writes screenshots for review.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include "RDCore.h"

static unsigned char *readFile(const char *path, size_t *length) {
    FILE *f = fopen(path, "rb");
    if (!f) { fprintf(stderr, "cannot open %s\n", path); exit(1); }
    fseek(f, 0, SEEK_END);
    *length = (size_t)ftell(f);
    fseek(f, 0, SEEK_SET);
    unsigned char *data = malloc(*length);
    if (fread(data, 1, *length, f) != *length) exit(1);
    fclose(f);
    return data;
}

static void screenshot(RDCore *core, const char *path) {
    unsigned w = RDCoreScreenWidth(core), h = RDCoreScreenHeight(core);
    const unsigned char *px = (const unsigned char *)RDCorePixels(core);
    FILE *f = fopen(path, "wb");
    if (!f) return;
    fprintf(f, "P6\n%u %u\n255\n", w, h);
    for (unsigned i = 0; i < w * h; i++) fwrite(px + i * 4, 1, 3, f);
    fclose(f);
}

static int failures = 0;
#define CHECK(cond, msg) do { if (cond) printf("ok   %s\n", msg); else { printf("FAIL %s\n", msg); failures++; } } while (0)

static void run(RDCore *core, unsigned frames, uint8_t keys) {
    float l[4096], r[4096];
    RDCoreSetKeys(core, keys);
    for (unsigned i = 0; i < frames; i++) {
        RDCoreRunFrame(core);
        RDCoreReadAudio(core, l, r, 4096); // keep the buffer drained like the speaker would
    }
}

// Centre of the star sprite, found by its unique gold colour.
static int findStar(RDCore *core, int *x, int *y) {
    unsigned w = RDCoreScreenWidth(core), h = RDCoreScreenHeight(core);
    const unsigned char *px = (const unsigned char *)RDCorePixels(core);
    long sx = 0, sy = 0, n = 0;
    for (unsigned j = 0; j < h; j++) for (unsigned i = 0; i < w; i++) {
        const unsigned char *p = px + (j * w + i) * 4;
        if (p[0] > 200 && p[1] > 120 && p[2] < 90) { sx += i; sy += j; n++; }
    }
    if (!n) return 0;
    *x = (int)(sx / n); *y = (int)(sy / n);
    return 1;
}

int main(int argc, char **argv) {
    if (argc < 4) { fprintf(stderr, "usage: core_test boot.bin cart.gbc outdir\n"); return 2; }
    size_t bootLen, romLen;
    unsigned char *boot = readFile(argv[1], &bootLen);
    unsigned char *rom = readFile(argv[2], &romLen);
    char path[1024];

    RDCore *core = RDCoreCreate(boot, bootLen, 48000);
    CHECK(core != NULL, "core created");
    CHECK(!RDCoreLoadROM(core, rom, 0x40), "rejects a file too small to be a cartridge");
    CHECK(RDCoreLoadROM(core, rom, romLen), "test cart loads");
    CHECK(RDCoreScreenWidth(core) == 160 && RDCoreScreenHeight(core) == 144, "screen is 160x144");

    char title[17];
    RDCoreTitle(core, title);
    CHECK(strcmp(title, "RETRO DUO") == 0, "cartridge title reads RETRO DUO");

    run(core, 60, 0);
    snprintf(path, sizeof path, "%s/boot.ppm", argv[3]);
    screenshot(core, path);
    run(core, 400, 0);                       // boot animation finishes, cart starts
    snprintf(path, sizeof path, "%s/title.ppm", argv[3]);
    screenshot(core, path);
    CHECK(RDCoreFrameCount(core) >= 450, "frames are produced");

    int x0, y0, x1, y1;
    CHECK(findStar(core, &x0, &y0), "star sprite is on screen after boot");

    run(core, 20, RD_KEY_RIGHT | RD_KEY_DOWN);
    run(core, 2, 0);
    CHECK(findStar(core, &x1, &y1) && x1 >= x0 + 15 && y1 >= y0 + 15, "D-pad moves the star right and down");
    snprintf(path, sizeof path, "%s/moved.ppm", argv[3]);
    screenshot(core, path);

    // Audio: press A and measure the beep.
    float l[2048], r[2048];
    while (RDCoreReadAudio(core, l, r, 2048)) {}
    RDCoreSetKeys(core, RD_KEY_A);
    RDCoreRunFrame(core);
    RDCoreRunFrame(core);
    RDCoreSetKeys(core, 0);
    for (int i = 0; i < 4; i++) RDCoreRunFrame(core);
    size_t buffered = RDCoreBufferedAudioFrames(core);
    CHECK(buffered > 3000 && buffered < 7000, "about 6 frames of 48 kHz audio are buffered");
    double peak = 0;
    size_t got = RDCoreReadAudio(core, l, r, 2048);
    for (size_t i = 0; i < got; i++) if (fabs(l[i]) > peak) peak = fabs(l[i]);
    CHECK(peak > 0.05, "pressing A makes a beep");

    // START changes the colour palette.
    unsigned before = RDCorePixels(core)[0];
    run(core, 2, RD_KEY_START);
    run(core, 2, 0);
    CHECK(RDCorePixels(core)[0] != before, "START changes the background colour");

    // Save state round trip.
    size_t stateSize = RDCoreStateSize(core);
    CHECK(stateSize > 1000, "save state has a size");
    unsigned char *state = malloc(stateSize);
    RDCoreSaveState(core, state);
    findStar(core, &x0, &y0);
    run(core, 30, RD_KEY_LEFT);
    findStar(core, &x1, &y1);
    CHECK(x1 < x0 - 20, "star moved away after saving");
    CHECK(RDCoreLoadState(core, state, stateSize), "save state loads");
    run(core, 1, 0);
    findStar(core, &x1, &y1);
    CHECK(abs(x1 - x0) <= 1 && abs(y1 - y0) <= 1, "loading the state puts the star back");
    CHECK(!RDCoreLoadState(core, state, 10), "a truncated save state is rejected");

    // This cart has no battery; the API must report that cleanly.
    CHECK(RDCoreBatterySize(core) == 0, "cart without battery reports no save RAM");

    // Overflow guard: running without draining audio must not grow past the latency cap.
    for (int i = 0; i < 300; i++) RDCoreRunFrame(core);
    CHECK(RDCoreBufferedAudioFrames(core) <= 6144, "audio buffer stays capped when nobody listens");

    RDCoreReset(core);
    run(core, 10, 0);
    CHECK(RDCoreFrameCount(core) > 0, "reset keeps running");

    RDCoreDestroy(core);
    free(state);
    printf(failures ? "\n%d check(s) failed\n" : "\nall core checks passed\n", failures);
    return failures ? 1 : 0;
}
