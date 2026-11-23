// Headless test of the app's Sega code: BlastEm behind the Retro Duo libretro host.
// Boots the bundled Genesis, Master System and Game Gear test carts and checks the picture,
// every button, save states (including damaged ones), reset and audio.
#include "RDLibretro.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <string>
#include <vector>

static int failures = 0;
static std::string prefix;
#define CHECK(cond, msg) do { if (cond) printf("ok   %s%s\n", prefix.c_str(), msg); else { printf("FAIL %s%s\n", prefix.c_str(), msg); failures++; } } while (0)

static std::vector<uint8_t> readFile(const std::string &path) {
    FILE *f = fopen(path.c_str(), "rb");
    if (!f) { fprintf(stderr, "cannot open %s\n", path.c_str()); exit(2); }
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

static bool isGold(uint32_t p) { return (p & 0xFF) > 180 && ((p >> 8) & 0xFF) > 140 && ((p >> 16) & 0xFF) < 120; }
static bool isPink(uint32_t p) { return (p & 0xFF) > 200 && ((p >> 8) & 0xFF) < 130 && ((p >> 16) & 0xFF) > 60; }

struct Blob { int count; double x, y; };
template <class F> static Blob find(RDLRHost *core, F match) {
    unsigned w = RDLRWidth(core), h = RDLRHeight(core);
    const uint32_t *px = RDLRPixels(core);
    Blob b{0, 0, 0};
    for (unsigned j = 0; j < h; j++) for (unsigned i = 0; i < w; i++)
        if (match(px[j * w + i])) { b.count++; b.x += i; b.y += j; }
    if (b.count) { b.x /= b.count; b.y /= b.count; }
    return b;
}

static uint32_t background(RDLRHost *core) {
    std::map<uint32_t, int> counts;
    unsigned w = RDLRWidth(core), h = RDLRHeight(core);
    const uint32_t *px = RDLRPixels(core);
    for (unsigned j = h / 8; j < h * 7 / 8; j++) for (unsigned i = w / 8; i < w * 7 / 8; i++) counts[px[j * w + i]]++;
    uint32_t best = 0; int most = -1;
    for (auto &[colour, n] : counts) if (n > most) { most = n; best = colour; }
    return best;
}

static void screenshot(RDLRHost *core, const char *dir, const std::string &name) {
    std::string path = std::string(dir) + "/" + name + ".ppm";
    FILE *f = fopen(path.c_str(), "wb");
    if (!f) return;
    unsigned w = RDLRWidth(core), h = RDLRHeight(core);
    fprintf(f, "P6\n%u %u\n255\n", w, h);
    const uint32_t *px = RDLRPixels(core);
    for (unsigned i = 0; i < w * h; i++) { fputc(px[i] & 0xFF, f); fputc((px[i] >> 8) & 0xFF, f); fputc((px[i] >> 16) & 0xFF, f); }
    fclose(f);
}

struct Light { uint32_t key; const char *name; };
struct Cart { const char *name, *file, *ext; std::vector<Light> lights; uint32_t colourKey; int crop; };
enum { NO_CROP, MASTER_SYSTEM_CROP, GAME_GEAR_CROP };

// The same crop the app sets: BlastEm draws Master System / Game Gear frames inside the
// Genesis-sized picture; the active 192 lines start 16 lines down (24 on PAL systems).
static void applyCrop(RDLRHost *core, int crop) {
    unsigned top = RDLRFrameRate(core) < 55 ? 24 : 16;
    if (crop == MASTER_SYSTEM_CROP) RDLRSetCrop(core, 0, top, 256, 192);
    if (crop == GAME_GEAR_CROP) RDLRSetCrop(core, 48, top + 24, 160, 144);
}

static void testCart(const Cart &cart, const char *resources, const char *out) {
    prefix = std::string(cart.name) + ": ";
    auto rom = readFile(std::string(resources) + "/" + cart.file);
    RDLRHost *core = RDLRCreate(RDLR_SYSTEM_SEGA, out);
    CHECK(core != nullptr, "core created");
    CHECK(RDLRLoadROM(core, rom.data(), rom.size(), nullptr, 0, (std::string("game.") + cart.ext).c_str()), "test cart loads");
    printf("     %ux%u, %.3f fps, %.0f Hz, aspect %.3f\n", RDLRWidth(core), RDLRHeight(core),
           RDLRFrameRate(core), RDLRSampleRate(core), RDLRDisplayAspect(core));
    CHECK(RDLRFrameRate(core) > 59 && RDLRFrameRate(core) < 61, "runs at 60 Hz");
    applyCrop(core, cart.crop);

    run(core, 60, 0);
    screenshot(core, out, std::string(cart.ext) + "_title");
    printf("     picture %ux%u\n", RDLRWidth(core), RDLRHeight(core));
    if (cart.crop == MASTER_SYSTEM_CROP) CHECK(RDLRWidth(core) == 256 && RDLRHeight(core) == 192, "picture is the Master System's 256x192");
    if (cart.crop == GAME_GEAR_CROP) CHECK(RDLRWidth(core) == 160 && RDLRHeight(core) == 144, "picture is the Game Gear's 160x144");
    if (cart.crop != NO_CROP) {
        // The cart's double bars sit at the very top and bottom of the visible screen.
        bool top = false, bottom = false;
        unsigned w = RDLRWidth(core), h = RDLRHeight(core);
        const uint32_t *px = RDLRPixels(core);
        for (unsigned j = 0; j < 40 && j < h; j++) top |= (px[j * w + w / 2] & 0xFFFFFF) == 0xFFFFFF;
        for (unsigned j = h - 40; j < h; j++) bottom |= (px[j * w + w / 2] & 0xFFFFFF) == 0xFFFFFF;
        CHECK(top && bottom, "crop lines up with the visible screen");
    }
    uint32_t bg = background(core);
    CHECK((bg & 0xFF) < 60 && ((bg >> 16) & 0xFF) > 60, "background is navy (right colour order)");
    Blob white = find(core, [](uint32_t p) { return (p & 0xFFFFFF) == 0xFFFFFF || ((p & 0xFF) > 230 && ((p >> 8) & 0xFF) > 230 && ((p >> 16) & 0xFF) > 230); });
    CHECK(white.count > 150, "title text is drawn");

    Blob star = find(core, isGold), moved;
    CHECK(star.count > 10, "star is on screen");
    run(core, 10, RDLR_PAD_RIGHT | RDLR_PAD_DOWN);
    run(core, 2, 0);
    moved = find(core, isGold);
    CHECK(moved.count > 10 && moved.x > star.x + 12 && moved.y > star.y + 12, "D-pad moves the star");
    screenshot(core, out, std::string(cart.ext) + "_moved");
    run(core, 10, RDLR_PAD_LEFT | RDLR_PAD_UP);
    run(core, 2, 0);
    moved = find(core, isGold);
    CHECK(std::fabs(moved.x - star.x) < 2 && std::fabs(moved.y - star.y) < 2, "and back");

    double lastX = -1;
    bool ordered = true;
    for (auto &light : cart.lights) {
        run(core, 3, light.key);
        Blob lit = find(core, isPink);
        char msg[64];
        snprintf(msg, sizeof msg, "%s lights up", light.name);
        CHECK(lit.count > 4, msg);
        if (lit.x <= lastX) ordered = false;
        lastX = lit.x;
    }
    CHECK(ordered, "each button lights its own letter");
    run(core, 3, 0);
    CHECK(find(core, isPink).count == 0, "lights go out on release");

    run(core, 3, cart.colourKey);
    run(core, 6, 0);
    CHECK(background(core) != bg, "START/PAUSE changes the background colour");

    size_t length = 0;
    uint8_t *state = RDLRSaveState(core, &length);
    CHECK(state && length > 1000, "save state is created");
    run(core, 20, RDLR_PAD_LEFT);
    run(core, 2, 0);
    moved = find(core, isGold);
    CHECK(moved.x < star.x - 20, "star moved after saving");
    CHECK(RDLRLoadState(core, state, length), "save state loads");
    run(core, 2, 0);
    moved = find(core, isGold);
    CHECK(std::fabs(moved.x - star.x) < 2 && std::fabs(moved.y - star.y) < 2, "loading the state puts the star back");
    std::vector<uint8_t> broken(state, state + length);
    memset(broken.data(), 0x5A, 16);
    CHECK(!RDLRLoadState(core, broken.data(), broken.size()), "a damaged save state is rejected");
    CHECK(!RDLRLoadState(core, state, 7), "a truncated save state is rejected");
    // A state whose length adds up but whose contents don't: BlastEm used to exit() here.
    std::vector<uint8_t> garbage(state, state + length);
    for (size_t i = sizeof(size_t); i < garbage.size(); i++) garbage[i] = (uint8_t)(i * 37 + 11);
    RDLRLoadState(core, garbage.data(), garbage.size());
    CHECK(RDLRFailure(core) == nullptr, "a garbage save state doesn't stop the emulator");
    CHECK(RDLRLoadState(core, state, length), "a good state still loads afterwards");
    run(core, 2, 0);
    CHECK(find(core, isGold).count > 10, "console still runs after rejected states");
    RDLRFreeBuffer(state);

    for (int i = 0; i < 300; i++) RDLRRunFrame(core);
    size_t buffered = RDLRBufferedAudioFrames(core);
    CHECK(buffered > 1000 && buffered <= 6144, "audio is produced and stays capped when nobody listens");

    RDLRReset(core);
    run(core, 60, 0);
    moved = find(core, isGold);
    CHECK(moved.count > 10 && std::fabs(moved.x - star.x) < 2, "reset restarts the game");
    RDLRDestroy(core);
}

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: sega_core_test resources-dir outdir\n"); return 2; }
    // Sega pad buttons on the RetroPad (BlastEm's layout): A=B, B=A, C=R, X=Y, Y=X, Z=L, MODE=SELECT.
    const Cart carts[] = {
        {"Genesis", "RetroDuoGenesisTestCart.md", "md",
         {{RDLR_PAD_B, "A"}, {RDLR_PAD_A, "B"}, {RDLR_PAD_R, "C"}, {RDLR_PAD_Y, "X"}, {RDLR_PAD_X, "Y"}, {RDLR_PAD_L, "Z"}},
         RDLR_PAD_START, NO_CROP},
        // Master System / Game Gear buttons 1 and 2 are the Sega pad's B and C.
        {"Master System", "RetroDuoMasterSystemTestCart.sms", "sms", {{RDLR_PAD_A, "1"}, {RDLR_PAD_R, "2"}}, RDLR_PAD_START, MASTER_SYSTEM_CROP},
        {"Game Gear", "RetroDuoGameGearTestCart.gg", "gg", {{RDLR_PAD_A, "1"}, {RDLR_PAD_R, "2"}}, RDLR_PAD_START, GAME_GEAR_CROP},
    };
    for (auto &cart : carts) testCart(cart, argv[1], argv[2]);

    prefix = "";
    RDLRHost *snes = RDLRCreate(RDLR_SYSTEM_SNES, argv[2]);
    auto sfc = readFile(std::string(argv[1]) + "/RetroDuoSNESTestCart.sfc");
    CHECK(snes && RDLRLoadROM(snes, sfc.data(), sfc.size(), nullptr, 0, "game.sfc"), "SNES still starts after the Sega core ran");
    run(snes, 40, 0);
    CHECK(find(snes, isGold).count > 10, "and draws");
    RDLRDestroy(snes);

    printf(failures ? "\n%d check(s) failed\n" : "\nall Sega core checks passed\n", failures);
    return failures ? 1 : 0;
}
