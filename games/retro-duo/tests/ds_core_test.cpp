// Headless test of the app's Nintendo DS code: melonDS + MDCore + MelonPlatform.
// Boots the bundled DS test cart and checks both screens, buttons, touch, sound and save states.
#include "MDCore.h"

#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <thread>
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

struct Screens { std::vector<uint32_t> top = std::vector<uint32_t>(256 * 192), bottom = std::vector<uint32_t>(256 * 192); uint64_t frame = 0; };

// Plays like the app: drains audio as a speaker would and waits for `frames` new frames.
static Screens waitFrames(MDCore *core, int frames, double *peak = nullptr) {
    Screens s;
    uint64_t start = MDCoreCopyScreens(core, nullptr, nullptr);
    float l[1024], r[1024];
    auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(20);
    while (MDCoreCopyScreens(core, nullptr, nullptr) < start + (uint64_t)frames && std::chrono::steady_clock::now() < deadline) {
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
        size_t got = MDCoreReadAudio(core, l, r, 240);
        if (peak) for (size_t i = 0; i < got; i++) *peak = std::fmax(*peak, std::fabs(l[i]));
    }
    s.frame = MDCoreCopyScreens(core, s.top.data(), s.bottom.data());
    return s;
}

static bool isGold(uint32_t p) { return (p & 0xFF) > 200 && ((p >> 8) & 0xFF) > 150 && ((p >> 16) & 0xFF) < 90; }

static bool findStar(const Screens &s, int *x, int *y) {
    long sx = 0, sy = 0, n = 0;
    for (int j = 50; j < 160; j++) for (int i = 0; i < 256; i++) if (isGold(s.top[j * 256 + i])) { sx += i; sy += j; n++; }
    if (!n) return false;
    *x = (int)(sx / n); *y = (int)(sy / n);
    return true;
}

static int goldOnBottom(const Screens &s) {
    int n = 0;
    for (uint32_t p : s.bottom) n += isGold(p);
    return n;
}

static void writePPM(const Screens &s, const char *dir, const char *name) {
    char path[1024];
    snprintf(path, sizeof path, "%s/%s.ppm", dir, name);
    FILE *f = fopen(path, "wb");
    if (!f) return;
    fprintf(f, "P6\n256 384\n255\n");
    for (const auto *screen : {&s.top, &s.bottom})
        for (uint32_t p : *screen) { fputc(p & 0xFF, f); fputc((p >> 8) & 0xFF, f); fputc((p >> 16) & 0xFF, f); }
    fclose(f);
}

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: ds_core_test cart.nds outdir\n"); return 2; }
    auto rom = readFile(argv[1]);
    MDCore *core = MDCoreCreate(48000);
    CHECK(core != nullptr, "DS core created");
    uint8_t junk[64] = {0};
    CHECK(!MDCoreLoadROM(core, junk, sizeof junk, nullptr, 0, "junk"), "rejects a file too small to be a DS game");
    CHECK(MDCoreLoadROM(core, rom.data(), rom.size(), nullptr, 0, "Retro Duo DS Test Cart"), "DS test cart loads");
    char title[13];
    MDCoreTitle(core, title);
    CHECK(strcmp(title, "RETRODUODS") == 0, "cartridge title reads RETRODUODS");

    MDCoreSetRunning(core, true);
    Screens s = waitFrames(core, 30);
    writePPM(s, argv[2], "ds_boot");
    CHECK(s.frame >= 30, "frames are produced");
    // Navy top background (RGB 2,3,9 in 5-bit) -> red low, blue higher.
    uint32_t bg = s.top[100 * 256 + 4];
    CHECK((bg & 0xFF) < 40 && ((bg >> 16) & 0xFF) > 50, "top screen shows the navy background in the right colours");

    int x0, y0, x1, y1;
    CHECK(findStar(s, &x0, &y0), "star is on the top screen");
    MDCoreSetKeys(core, MD_KEY_RIGHT | MD_KEY_DOWN);
    waitFrames(core, 12);
    MDCoreSetKeys(core, 0);
    s = waitFrames(core, 3);
    CHECK(findStar(s, &x1, &y1) && x1 >= x0 + 12 && y1 >= y0 + 12, "D-pad moves the star");

    MDCoreSetKeys(core, MD_KEY_X | MD_KEY_L);
    s = waitFrames(core, 4);
    int lit = 0;
    for (int j = 164; j < 172; j++) for (int i = 40; i < 120; i++) { uint32_t p = s.top[j * 256 + i]; lit += (p & 0xFF) > 200 && ((p >> 16) & 0xFF) < 140; }
    CHECK(lit > 10, "X and L light up (X/Y come through the ARM7)");
    MDCoreSetKeys(core, 0);

    // Touch: draw a line across the bottom screen.
    int before = goldOnBottom(waitFrames(core, 2));
    for (int x = 40; x <= 200; x += 10) {
        MDCoreSetTouch(core, true, x, 150);
        waitFrames(core, 1);
    }
    MDCoreSetTouch(core, false, 0, 0);
    s = waitFrames(core, 3);
    writePPM(s, argv[2], "ds_touch");
    int after = goldOnBottom(s);
    CHECK(after > before + 500, "touching the bottom screen draws on it");
    int lineY = 0, lineN = 0;
    for (int j = 0; j < 192; j++) for (int i = 0; i < 256; i++) if (isGold(s.bottom[j * 256 + i])) { lineY += j; lineN++; }
    CHECK(lineN && std::abs(lineY / lineN - 150) <= 3, "touch lands where it was pressed");

    // RetroAchievements reads main RAM: the game's ARM9 code sits there where its header says.
    {
        auto word = [&](size_t at) { return uint32_t(rom[at]) | uint32_t(rom[at + 1]) << 8 | uint32_t(rom[at + 2]) << 16 | uint32_t(rom[at + 3]) << 24; };
        uint32_t romOffset = word(0x20), ramAddress = word(0x28);
        uint8_t ram[256] = {};
        size_t copied = MDCoreReadMainRAM(core, ramAddress - 0x02000000, ram, sizeof ram);
        CHECK(copied == sizeof ram && ramAddress >= 0x02000000 && romOffset + sizeof ram <= rom.size()
              && memcmp(ram, rom.data() + romOffset, sizeof ram) == 0,
              "main RAM reads back the game's code (RetroAchievements)");
    }

    // Sound: A beeps.
    waitFrames(core, 10);
    double quiet = 0, loud = 0;
    waitFrames(core, 5, &quiet);
    MDCoreSetKeys(core, MD_KEY_A);
    waitFrames(core, 4, &loud);
    MDCoreSetKeys(core, 0);
    CHECK(loud > 0.05 && loud > quiet * 2, "pressing A makes a beep");

    // Save states.
    size_t length = 0;
    uint8_t *state = MDCoreSaveState(core, &length);
    CHECK(state && length > 100000, "save state is created");
    s = waitFrames(core, 2);
    findStar(s, &x0, &y0);
    MDCoreSetKeys(core, MD_KEY_LEFT);
    waitFrames(core, 15);
    MDCoreSetKeys(core, 0);
    s = waitFrames(core, 2);
    findStar(s, &x1, &y1);
    CHECK(x1 < x0 - 15, "star moved after saving");
    CHECK(MDCoreLoadState(core, state, length), "save state loads");
    s = waitFrames(core, 3);
    findStar(s, &x1, &y1);
    CHECK(std::abs(x1 - x0) <= 2 && std::abs(y1 - y0) <= 2, "loading the state puts the star back");
    CHECK(!MDCoreLoadState(core, state, 64), "a truncated save state is rejected");
    s = waitFrames(core, 3);
    CHECK(findStar(s, &x1, &y1), "console still runs after a rejected state");
    MDCoreFreeBuffer(state);

    // Cheats (melonDS's Action Replay engine).
    {
        const char *codes[] = { "02000100 00000042\n12000104 00000001", "02000100", "" };
        bool ok[3] = { false, true, true };
        MDCoreSetCheats(core, codes, 3, ok);
        CHECK(ok[0] && !ok[1] && !ok[2], "Action Replay lines are accepted, broken ones aren't");
        s = waitFrames(core, 10);
        CHECK(findStar(s, &x1, &y1), "the game keeps running with a cheat on");
        MDCoreSetCheats(core, nullptr, 0, nullptr);
    }

    // Pause and reset.
    MDCoreSetRunning(core, false);
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
    uint64_t paused = MDCoreCopyScreens(core, nullptr, nullptr);
    std::this_thread::sleep_for(std::chrono::milliseconds(200));
    CHECK(MDCoreCopyScreens(core, nullptr, nullptr) == paused, "pausing stops the console");
    // Rewind shows each step back by running one frame while stopped.
    MDCoreStepFrame(core);
    CHECK(MDCoreCopyScreens(core, nullptr, nullptr) == paused + 1, "a stopped console can step one frame (rewind)");
    MDCoreSetRunning(core, true);

    // Fast-forward: more frames in the same time.
    auto countFrames = [&](double seconds) {
        uint64_t start = MDCoreCopyScreens(core, nullptr, nullptr);
        auto end = std::chrono::steady_clock::now() + std::chrono::duration<double>(seconds);
        float l[1024], r[1024];
        while (std::chrono::steady_clock::now() < end) {
            std::this_thread::sleep_for(std::chrono::milliseconds(5));
            MDCoreReadAudio(core, l, r, 240);
        }
        return MDCoreCopyScreens(core, nullptr, nullptr) - start;
    };
    uint64_t normal = countFrames(1.5);
    MDCoreSetSpeedMultiplier(core, 3);
    uint64_t fast = countFrames(1.5);
    MDCoreSetSpeedMultiplier(core, 1);
    printf("     normal %llu frames, fast-forward %llu frames in 1.5 s\n", (unsigned long long)normal, (unsigned long long)fast);
    CHECK(fast > normal * 3 / 2, "fast-forward runs faster than normal speed");
    MDCoreReset(core);
    s = waitFrames(core, 20);
    CHECK(findStar(s, &x1, &y1) && std::abs(x1 - 128) <= 4, "reset restarts the game");
    printf("speed: %.1f frames per second\n", MDCoreSpeed(core));

    MDCoreDestroy(core);
    printf(failures ? "\n%d check(s) failed\n" : "\nall DS core checks passed\n", failures);
    return failures ? 1 : 0;
}
