// Headless test of the app's SNES code: bsnes behind the Retro Duo libretro host.
// Boots the bundled SNES test cart and checks the picture, buttons, audio and save states.
#include "RDLibretro.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
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

static void run(RDLRHost *core, int frames, uint32_t keys) {
    float l[4096], r[4096];
    RDLRSetKeys(core, keys);
    for (int i = 0; i < frames; i++) {
        RDLRRunFrame(core);
        RDLRReadAudio(core, l, r, 4096);
    }
}

// Reads a pixel in SNES coordinates (256 x 224), whatever size the core outputs.
static uint32_t at(RDLRHost *core, int x, int y) {
    unsigned w = RDLRWidth(core), h = RDLRHeight(core);
    int sx = x * (int)w / 256, sy = y * (int)h / 224;
    return RDLRPixels(core)[sy * w + sx];
}

static bool isGold(uint32_t p) { return (p & 0xFF) > 180 && ((p >> 8) & 0xFF) > 140 && ((p >> 16) & 0xFF) < 120; }
static bool isPink(uint32_t p) { return (p & 0xFF) > 200 && ((p >> 8) & 0xFF) < 120 && ((p >> 16) & 0xFF) > 60; }

static bool findStar(RDLRHost *core, int *x, int *y) {
    long sx = 0, sy = 0, n = 0;
    for (int j = 0; j < 224; j++) for (int i = 0; i < 256; i++)
        if (isGold(at(core, i, j))) { sx += i; sy += j; n++; }
    if (!n) return false;
    *x = (int)(sx / n); *y = (int)(sy / n);
    return true;
}

static void screenshot(RDLRHost *core, const char *dir, const char *name) {
    char path[1024];
    snprintf(path, sizeof path, "%s/%s.ppm", dir, name);
    FILE *f = fopen(path, "wb");
    if (!f) return;
    unsigned w = RDLRWidth(core), h = RDLRHeight(core);
    fprintf(f, "P6\n%u %u\n255\n", w, h);
    const uint32_t *px = RDLRPixels(core);
    for (unsigned i = 0; i < w * h; i++) { fputc(px[i] & 0xFF, f); fputc((px[i] >> 8) & 0xFF, f); fputc((px[i] >> 16) & 0xFF, f); }
    fclose(f);
}

static int litCount(RDLRHost *core, int column) {
    int lit = 0;
    for (int j = 192; j < 200; j++) for (int i = column * 8; i < column * 8 + 8; i++) lit += isPink(at(core, i, j));
    return lit;
}

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: snes_core_test cart.sfc outdir\n"); return 2; }
    auto rom = readFile(argv[1]);
    RDLRHost *core = RDLRCreate(RDLR_SYSTEM_SNES, argv[2]);
    CHECK(core != nullptr, "SNES core created");
    CHECK(RDLRCreate(RDLR_SYSTEM_SNES, argv[2]) == nullptr, "only one libretro core runs at a time");
    CHECK(RDLRCreate(99, argv[2]) == nullptr, "unknown systems are refused");
    CHECK(RDLRLoadROM(core, rom.data(), rom.size(), nullptr, 0, "game.sfc"), "SNES test cart loads");
    CHECK(std::fabs(RDLRFrameRate(core) - 60.1) < 0.2, "runs at NTSC speed");
    CHECK(RDLRSampleRate(core) > 30000, "reports its sample rate");
    printf("     %ux%u, %.3f fps, %.0f Hz, aspect %.3f\n", RDLRWidth(core), RDLRHeight(core),
           RDLRFrameRate(core), RDLRSampleRate(core), RDLRDisplayAspect(core));

    run(core, 40, 0);
    screenshot(core, argv[2], "snes_title");
    printf("     picture %ux%u\n", RDLRWidth(core), RDLRHeight(core));
    CHECK(RDLRFrameCount(core) == 40, "frames are produced");
    CHECK(RDLRWidth(core) >= 256 && RDLRHeight(core) >= 224, "picture is at least 256x224");
    uint32_t bg = at(core, 2, 100);
    CHECK((bg & 0xFF) < 40 && ((bg >> 16) & 0xFF) > 50, "background is navy (right colour order)");
    int white = 0;
    for (int j = 40; j < 48; j++) for (int i = 88; i < 160; i++) white += (at(core, i, j) & 0xFFFFFF) == 0xFFFFFF;
    CHECK(white > 60, "title text is drawn");

    int x0 = 0, y0 = 0, x1 = 0, y1 = 0;
    CHECK(findStar(core, &x0, &y0) && std::abs(x0 - 124) <= 4 && std::abs(y0 - 108) <= 4, "star is in the middle");
    run(core, 10, RDLR_PAD_RIGHT | RDLR_PAD_DOWN);
    run(core, 1, 0);
    CHECK(findStar(core, &x1, &y1) && x1 >= x0 + 15 && y1 >= y0 + 15, "D-pad moves the star");
    screenshot(core, argv[2], "snes_moved");
    run(core, 2, RDLR_PAD_SELECT);
    run(core, 2, 0);
    CHECK(findStar(core, &x1, &y1) && std::abs(x1 - x0) <= 1 && std::abs(y1 - y0) <= 1, "SELECT recentres the star");

    const struct { uint32_t key; int column; const char *name; } lights[] = {
        {RDLR_PAD_A, 10, "A lights up"}, {RDLR_PAD_B, 12, "B lights up"}, {RDLR_PAD_X, 14, "X lights up"},
        {RDLR_PAD_Y, 16, "Y lights up"}, {RDLR_PAD_L, 18, "L lights up"}, {RDLR_PAD_R, 20, "R lights up"},
    };
    for (auto &light : lights) {
        run(core, 3, light.key);
        bool on = litCount(core, light.column) > 4;
        int others = 0;
        for (auto &other : lights) if (&other != &light) others += litCount(core, other.column);
        CHECK(on && others == 0, light.name);
    }
    run(core, 3, 0);
    { int all = 0; for (auto &light : lights) all += litCount(core, light.column); CHECK(all == 0, "lights go out on release"); }

    uint32_t before = at(core, 2, 100);
    run(core, 3, RDLR_PAD_START);
    run(core, 3, 0);
    CHECK(at(core, 2, 100) != before, "START changes the background colour");

    run(core, 5, RDLR_PAD_LEFT | RDLR_PAD_RIGHT);
    run(core, 1, 0);
    CHECK(findStar(core, &x1, &y1) && std::abs(x1 - x0) <= 1, "opposite directions cancel out");

    size_t length = 0;
    uint8_t *state = RDLRSaveState(core, &length);
    CHECK(state && length > 1000, "save state is created");
    run(core, 20, RDLR_PAD_LEFT);
    run(core, 1, 0);
    findStar(core, &x1, &y1);
    CHECK(x1 < x0 - 20, "star moved after saving");
    CHECK(RDLRLoadState(core, state, length), "save state loads");
    run(core, 1, 0);
    findStar(core, &x1, &y1);
    CHECK(std::abs(x1 - x0) <= 1 && std::abs(y1 - y0) <= 1, "loading the state puts the star back");
    std::vector<uint8_t> broken(state, state + length);
    memset(broken.data(), 0x5A, 64);
    CHECK(!RDLRLoadState(core, broken.data(), broken.size()), "a damaged save state is rejected");
    run(core, 2, 0);
    CHECK(findStar(core, &x1, &y1) && std::abs(x1 - x0) <= 1, "console still runs after a rejected state");
    RDLRFreeBuffer(state);

    { size_t n = 0; uint8_t *save = RDLRCopySave(core, &n); CHECK(save == nullptr && n == 0, "cart without battery has no save"); }

    for (int i = 0; i < 300; i++) RDLRRunFrame(core);
    size_t buffered = RDLRBufferedAudioFrames(core);
    CHECK(buffered > 1000 && buffered <= 6144, "audio is produced and stays capped when nobody listens");
    float l[8192], r[8192];
    RDLRReadAudio(core, l, r, 8192);
    CHECK(RDLRBufferedAudioFrames(core) == 0, "audio drains");

    RDLRReset(core);
    run(core, 40, 0);
    CHECK(findStar(core, &x1, &y1) && std::abs(x1 - 124) <= 4, "reset restarts the game");

    RDLRDestroy(core);
    RDLRHost *again = RDLRCreate(RDLR_SYSTEM_SNES, argv[2]);
    CHECK(again && RDLRLoadROM(again, rom.data(), rom.size(), nullptr, 0, "game.sfc"), "a second game can start after closing the first");
    run(again, 40, 0);
    CHECK(findStar(again, &x1, &y1), "second session draws");
    RDLRDestroy(again);
    printf(failures ? "\n%d check(s) failed\n" : "\nall SNES core checks passed\n", failures);
    return failures ? 1 : 0;
}
