// Headless test of the app's NES code: Nestopia + NESCore.
// Boots the bundled NES test cart and checks the picture, buttons, sound and save states.
#include "NESCore.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <vector>

static int failures = 0;
#define CHECK(cond, msg) do { if (cond) printf("ok   %s\n", msg); else { printf("FAIL %s\n", msg); failures++; } } while (0)

static std::vector<uint8_t> readFile(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) { fprintf(stderr, "cannot open %s\n", path); exit(2); }
    std::vector<uint8_t> data;
    int c;
    while ((c = fgetc(f)) != EOF) data.push_back((uint8_t)c);
    fclose(f);
    return data;
}

static double run(NESCore *core, int frames, uint8_t keys) {
    float l[4096], r[4096];
    double peak = 0;
    NESCoreSetKeys(core, keys);
    for (int i = 0; i < frames; i++) {
        NESCoreRunFrame(core);
        size_t got = NESCoreReadAudio(core, l, r, 4096);
        for (size_t j = 0; j < got; j++) peak = std::fmax(peak, std::fabs(l[j]));
    }
    return peak;
}

static bool isGold(uint32_t p) { return (p & 0xFF) > 180 && ((p >> 8) & 0xFF) > 140 && ((p >> 16) & 0xFF) < 120; }

static bool findStar(NESCore *core, int *x, int *y) {
    const uint32_t *px = NESCorePixels(core);
    long sx = 0, sy = 0, n = 0;
    for (int j = 0; j < NES_SCREEN_HEIGHT; j++) for (int i = 0; i < NES_SCREEN_WIDTH; i++)
        if (isGold(px[j * NES_SCREEN_WIDTH + i])) { sx += i; sy += j; n++; }
    if (!n) return false;
    *x = (int)(sx / n); *y = (int)(sy / n);
    return true;
}

static void screenshot(NESCore *core, const char *dir, const char *name) {
    char path[1024];
    snprintf(path, sizeof path, "%s/%s.ppm", dir, name);
    FILE *f = fopen(path, "wb");
    if (!f) return;
    fprintf(f, "P6\n%d %d\n255\n", NES_SCREEN_WIDTH, NES_SCREEN_HEIGHT);
    const uint32_t *px = NESCorePixels(core);
    for (int i = 0; i < NES_SCREEN_WIDTH * NES_SCREEN_HEIGHT; i++) { fputc(px[i] & 0xFF, f); fputc((px[i] >> 8) & 0xFF, f); fputc((px[i] >> 16) & 0xFF, f); }
    fclose(f);
}

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: nes_core_test cart.nes outdir\n"); return 2; }
    auto rom = readFile(argv[1]);
    NESCore *core = NESCoreCreate(48000);
    CHECK(core != nullptr, "NES core created");
    uint8_t junk[64] = {0};
    CHECK(!NESCoreLoadROM(core, junk, sizeof junk, nullptr, 0), "rejects a file that isn't an NES game");
    CHECK(NESCoreLoadROM(core, rom.data(), rom.size(), nullptr, 0), "NES test cart loads");

    run(core, 30, 0);
    screenshot(core, argv[2], "nes_title");
    CHECK(NESCoreFrameCount(core) == 30, "frames are produced");
    uint32_t bg = NESCorePixels(core)[100 * NES_SCREEN_WIDTH + 2];
    CHECK((bg & 0xFF) < 60 && ((bg >> 16) & 0xFF) > 80, "background is navy (right colour order)");
    int lit = 0;
    for (int j = 40; j < 80; j++) for (int i = 80; i < 180; i++) lit += (NESCorePixels(core)[j * NES_SCREEN_WIDTH + i] & 0xFF) > 200;
    CHECK(lit > 100, "title text is drawn");

    int x0, y0, x1, y1;
    CHECK(findStar(core, &x0, &y0), "star sprite is on screen");
    // The cart keeps the star at $16 (X) and $15 (Y) for the tracker to read.
    uint8_t ramX = NESCoreReadRAM(core, 0x16), ramY = NESCoreReadRAM(core, 0x15);
    run(core, 20, NES_KEY_RIGHT | NES_KEY_DOWN);
    run(core, 2, 0);
    CHECK(findStar(core, &x1, &y1) && x1 >= x0 + 15 && y1 >= y0 + 15, "D-pad moves the star");
    CHECK(NESCoreReadRAM(core, 0x16) > ramX && NESCoreReadRAM(core, 0x15) > ramY, "the star's position in RAM follows the D-pad");
    CHECK(NESCoreReadRAM(core, 0x816) == NESCoreReadRAM(core, 0x16), "RAM mirrors read the same bytes");
    screenshot(core, argv[2], "nes_moved");

    double quiet = run(core, 10, 0);
    double loud = run(core, 1, NES_KEY_A) ;
    loud = std::fmax(loud, run(core, 6, 0));
    CHECK(loud > 0.05 && loud > quiet * 2, "pressing A makes a beep");
    size_t buffered = NESCoreBufferedAudioFrames(core);
    CHECK(buffered == 0, "audio is fully drained by the reader");

    uint32_t before = NESCorePixels(core)[100 * NES_SCREEN_WIDTH + 2];
    run(core, 2, NES_KEY_START);
    run(core, 2, 0);
    CHECK(NESCorePixels(core)[100 * NES_SCREEN_WIDTH + 2] != before, "START changes the background colour");

    size_t length = 0;
    uint8_t *state = NESCoreSaveState(core, &length);
    CHECK(state && length > 1000, "save state is created");
    findStar(core, &x0, &y0);
    run(core, 30, NES_KEY_LEFT);
    findStar(core, &x1, &y1);
    CHECK(x1 < x0 - 20, "star moved after saving");
    CHECK(NESCoreLoadState(core, state, length), "save state loads");
    run(core, 1, 0);
    findStar(core, &x1, &y1);
    CHECK(std::abs(x1 - x0) <= 1 && std::abs(y1 - y0) <= 1, "loading the state puts the star back");
    CHECK(!NESCoreLoadState(core, state, 64), "a truncated save state is rejected");
    run(core, 2, 0);
    CHECK(findStar(core, &x1, &y1), "console still runs after a rejected state");
    NESCoreFreeBuffer(state);

    CHECK(NESCoreBatterySize(core) == 0, "cart without battery reports no save RAM");
    for (int i = 0; i < 300; i++) NESCoreRunFrame(core);
    CHECK(NESCoreBufferedAudioFrames(core) <= 6144, "audio buffer stays capped when nobody listens");

    NESCoreReset(core);
    run(core, 5, 0);
    CHECK(findStar(core, &x1, &y1) && std::abs(x1 - 128) <= 6, "reset restarts the game");

    NESCoreDestroy(core);
    printf(failures ? "\n%d check(s) failed\n" : "\nall NES core checks passed\n", failures);
    return failures ? 1 : 0;
}
