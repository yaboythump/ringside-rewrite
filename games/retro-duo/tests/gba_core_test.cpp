// Headless test of the app's NES code: Nestopia + RDGBA.
// Boots the bundled GBA test cart and checks the picture, buttons, sound and save states.
#include "RDGBA.h"

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

static double run(RDGBA *core, int frames, uint16_t keys) {
    float l[4096], r[4096];
    double peak = 0;
    RDGBASetKeys(core, keys);
    for (int i = 0; i < frames; i++) {
        RDGBARunFrame(core);
        size_t got = RDGBAReadAudio(core, l, r, 4096);
        for (size_t j = 0; j < got; j++) peak = std::fmax(peak, std::fabs(l[j]));
    }
    return peak;
}

static bool isGold(uint32_t p) { return (p & 0xFF) > 180 && ((p >> 8) & 0xFF) > 140 && ((p >> 16) & 0xFF) < 120; }

static bool findStar(RDGBA *core, int *x, int *y) {
    const uint32_t *px = RDGBAPixels(core);
    long sx = 0, sy = 0, n = 0;
    // Only the play area: the title text is gold too.
    for (int j = 46; j < 136; j++) for (int i = 0; i < GBA_SCREEN_WIDTH; i++)
        if (isGold(px[j * GBA_SCREEN_WIDTH + i])) { sx += i; sy += j; n++; }
    if (!n) return false;
    *x = (int)(sx / n); *y = (int)(sy / n);
    return true;
}

static void screenshot(RDGBA *core, const char *dir, const char *name) {
    char path[1024];
    snprintf(path, sizeof path, "%s/%s.ppm", dir, name);
    FILE *f = fopen(path, "wb");
    if (!f) return;
    fprintf(f, "P6\n%d %d\n255\n", GBA_SCREEN_WIDTH, GBA_SCREEN_HEIGHT);
    const uint32_t *px = RDGBAPixels(core);
    for (int i = 0; i < GBA_SCREEN_WIDTH * GBA_SCREEN_HEIGHT; i++) { fputc(px[i] & 0xFF, f); fputc((px[i] >> 8) & 0xFF, f); fputc((px[i] >> 16) & 0xFF, f); }
    fclose(f);
}

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: gba_core_test cart.gba outdir\n"); return 2; }
    auto rom = readFile(argv[1]);
    RDGBA *core = RDGBACreate(48000);
    CHECK(core != nullptr, "GBA core created");
    uint8_t junk[64] = {0};
    CHECK(!RDGBALoadROM(core, junk, sizeof junk, nullptr, 0), "rejects a file that isn't a GBA game");
    CHECK(RDGBALoadROM(core, rom.data(), rom.size(), nullptr, 0), "GBA test cart loads");

    run(core, 30, 0);
    screenshot(core, argv[2], "gba_title");
    CHECK(RDGBAFrameCount(core) == 30, "frames are produced");
    uint32_t bg = RDGBAPixels(core)[100 * GBA_SCREEN_WIDTH + 2];
    CHECK((bg & 0xFF) < 40 && ((bg >> 16) & 0xFF) > 60, "background is navy (right colour order)");
    int lit = 0;
    for (int j = 14; j < 34; j++) for (int i = 50; i < 190; i++) lit += (RDGBAPixels(core)[j * GBA_SCREEN_WIDTH + i] & 0xFF) > 200;
    CHECK(lit > 100, "title text is drawn");

    int x0, y0, x1, y1;
    CHECK(findStar(core, &x0, &y0), "star sprite is on screen");
    run(core, 20, GBA_PAD_RIGHT | GBA_PAD_DOWN);
    {
        RDGBASetKeys(core, GBA_PAD_L | GBA_PAD_R);
        run(core, 6, GBA_PAD_L | GBA_PAD_R);
        int lit = 0;
        const uint32_t *px = RDGBAPixels(core);
        for (int j = 138; j < 146; j++) for (int i = 54; i < 82; i++) lit += (px[j * GBA_SCREEN_WIDTH + i] & 0xFF) > 200 && ((px[j * GBA_SCREEN_WIDTH + i] >> 16) & 0xFF) < 140;
        CHECK(lit > 10, "L and R light up");
    }
    run(core, 2, 0);
    CHECK(findStar(core, &x1, &y1) && x1 >= x0 + 15 && y1 >= y0 + 15, "D-pad moves the star");
    screenshot(core, argv[2], "gba_moved");
    CHECK(RDGBARead8(core, 0x080000A0) == rom[0xA0] && RDGBARead8(core, 0x080000A1) == rom[0xA1], "memory reads see the console's address space");

    double quiet = run(core, 10, 0);
    double loud = run(core, 1, GBA_PAD_A) ;
    loud = std::fmax(loud, run(core, 6, 0));
    CHECK(loud > 0.05 && loud > quiet * 2, "pressing A makes a beep");
    CHECK(RDGBABufferedAudioFrames(core) == 0, "audio is fully drained by the reader");

    uint32_t before = RDGBAPixels(core)[100 * GBA_SCREEN_WIDTH + 2];
    run(core, 3, GBA_PAD_START);
    run(core, 8, 0);
    CHECK(RDGBAPixels(core)[100 * GBA_SCREEN_WIDTH + 2] != before, "START changes the background colour");

    size_t length = 0;
    uint8_t *state = RDGBASaveState(core, &length);
    CHECK(state && length > 1000, "save state is created");
    findStar(core, &x0, &y0);
    run(core, 30, GBA_PAD_LEFT);
    findStar(core, &x1, &y1);
    CHECK(x1 < x0 - 20, "star moved after saving");
    CHECK(RDGBALoadState(core, state, length), "save state loads");
    run(core, 1, 0);
    findStar(core, &x1, &y1);
    CHECK(std::abs(x1 - x0) <= 1 && std::abs(y1 - y0) <= 1, "loading the state puts the star back");
    CHECK(!RDGBALoadState(core, state, 64), "a truncated save state is rejected");
    run(core, 2, 0);
    CHECK(findStar(core, &x1, &y1), "console still runs after a rejected state");
    RDGBAFreeBuffer(state);

    { size_t n = 0; uint8_t *save = RDGBACopySave(core, &n); CHECK(save == nullptr || n > 0, "save data copy works"); RDGBAFreeBuffer(save); }
    for (int i = 0; i < 300; i++) RDGBARunFrame(core);
    CHECK(RDGBABufferedAudioFrames(core) <= 6144, "audio buffer stays capped when nobody listens");

    RDGBAReset(core);
    run(core, 30, 0);
    CHECK(findStar(core, &x1, &y1) && std::abs(x1 - 120) <= 6, "reset restarts the game");

    RDGBADestroy(core);
    printf(failures ? "\n%d check(s) failed\n" : "\nall GBA core checks passed\n", failures);
    return failures ? 1 : 0;
}
