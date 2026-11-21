// Retro Duo - Nintendo DS core wrapper around melonDS.
// Copyright 2026 CT Network Studios. Licensed under the GNU GPL v3 or later (see LICENSE).
#include "MDCore.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "NDS.h"
#include "NDSCart.h"
#include "Savestate.h"
#include "SPU.h"

using namespace melonDS;

namespace {
constexpr double kFrameRate = 59.8260982881;
constexpr int kPixels = MD_SCREEN_WIDTH * MD_SCREEN_HEIGHT;
constexpr int kMaxQueuedAudio = 4096; // frames; beyond this the console waits for the speaker
}

struct MDCore {
    std::unique_ptr<NDS> nds;
    std::mutex consoleLock;          // guards nds between the console thread and callers
    std::thread thread;
    std::atomic<bool> quit{false};
    std::atomic<bool> running{false};
    std::atomic<uint32_t> keys{0};
    std::atomic<uint32_t> touch{0};  // bit 31 = down, bits 0-7 x, 8-15 y
    std::atomic<bool> saveChanged{false};
    std::atomic<uint64_t> frames{0};
    std::atomic<double> speed{0};

    std::mutex frameLock;
    std::vector<uint32_t> top = std::vector<uint32_t>(kPixels, 0xFF000000u);
    std::vector<uint32_t> bottom = std::vector<uint32_t>(kPixels, 0xFF000000u);
    bool hasCart = false;
    std::string name;

    void run();
    void runFrame();
};

// Called by melonDS (MelonPlatform.cpp) when the game writes its save memory.
void RetroDuoMarkSaveChanged(void *userdata) {
    if (auto *core = static_cast<MDCore *>(userdata)) core->saveChanged = true;
}

void MDCore::runFrame() {
    std::lock_guard<std::mutex> lock(consoleLock);
    if (!nds || !hasCart) return;
    nds->SetKeyMask(~keys.load() & 0xFFF);
    uint32_t t = touch.load();
    if (t & 0x80000000u) nds->TouchScreen(t & 0xFF, (t >> 8) & 0xFF);
    else nds->ReleaseScreen();
    nds->RunFrame();

    int front = nds->GPU.FrontBuffer;
    const u32 *a = nds->GPU.Framebuffer[front][0].get();
    const u32 *b = nds->GPU.Framebuffer[front][1].get();
    if (a && b) {
        std::lock_guard<std::mutex> frame(frameLock);
        // melonDS pixels are 0x--RRGGBB; the app wants bytes R, G, B, X (0xXXBBGGRR).
        auto convert = [](u32 p) {
            return ((p >> 16) & 0xFFu) | (p & 0xFF00u) | ((p & 0xFFu) << 16) | 0xFF000000u;
        };
        for (int i = 0; i < kPixels; i++) {
            top[i] = convert(a[i]);
            bottom[i] = convert(b[i]);
        }
    }
    frames++;
}

void MDCore::run() {
    using clock = std::chrono::steady_clock;
    const auto frameTime = std::chrono::duration_cast<clock::duration>(std::chrono::duration<double>(1.0 / kFrameRate));
    auto next = clock::now();
    auto windowStart = clock::now();
    uint64_t windowFrames = 0;
    while (!quit) {
        if (!running) {
            std::this_thread::sleep_for(std::chrono::milliseconds(8));
            next = clock::now();
            continue;
        }
        // If the speaker has plenty queued, give it time instead of running ahead.
        if (nds && nds->SPU.GetOutputSize() > kMaxQueuedAudio) {
            std::this_thread::sleep_for(std::chrono::milliseconds(2));
            continue;
        }
        runFrame();
        windowFrames++;
        auto now = clock::now();
        if (now - windowStart >= std::chrono::seconds(1)) {
            speed = windowFrames / std::chrono::duration<double>(now - windowStart).count();
            windowStart = now;
            windowFrames = 0;
        }
        next += frameTime;
        if (next > now) {
            std::this_thread::sleep_until(next);
        } else if (now - next > frameTime * 4) {
            next = now; // too slow to keep up; don't try to catch up in a burst
        }
    }
}

extern "C" {

MDCore *MDCoreCreate(unsigned sampleRate) {
    auto *core = new MDCore();
    NDSArgs args;               // FreeBIOS + generated firmware: no Nintendo files needed
    args.JIT = std::nullopt;    // iOS apps can't generate code at runtime
    args.OutputSampleRate = sampleRate ? sampleRate : 48000;
    args.Interpolation = AudioInterpolation::Cosine;
    core->nds = std::make_unique<NDS>(std::move(args), core);
    core->thread = std::thread([core] { core->run(); });
    return core;
}

void MDCoreDestroy(MDCore *core) {
    if (!core) return;
    core->quit = true;
    if (core->thread.joinable()) core->thread.join();
    {
        std::lock_guard<std::mutex> lock(core->consoleLock);
        if (core->nds) core->nds->Stop();
        core->nds.reset();
    }
    delete core;
}

bool MDCoreLoadROM(MDCore *core, const uint8_t *rom, size_t length, const uint8_t *save, size_t saveLength, const char *name) {
    if (!core || !rom || length < 0x200 || length > 512u * 1024 * 1024) return false;
    auto data = std::make_unique<u8[]>(length);
    memcpy(data.get(), rom, length);
    NDSCart::NDSCartArgs cartArgs;
    if (save && saveLength) {
        cartArgs.SRAM = std::make_unique<u8[]>(saveLength);
        memcpy(cartArgs.SRAM.get(), save, saveLength);
        cartArgs.SRAMLength = (u32)saveLength;
    }
    auto cart = NDSCart::ParseROM(std::move(data), (u32)length, core, std::move(cartArgs));
    if (!cart) return false;

    std::lock_guard<std::mutex> lock(core->consoleLock);
    core->name = name ? name : "game";
    core->nds->Reset();
    core->nds->SetNDSCart(std::move(cart));
    if (core->nds->NeedsDirectBoot()) core->nds->SetupDirectBoot(core->name + ".nds");
    core->nds->Start();
    core->hasCart = true;
    core->saveChanged = false;
    return true;
}

void MDCoreSetRunning(MDCore *core, bool running) {
    if (core) core->running = running;
}

void MDCoreReset(MDCore *core) {
    if (!core) return;
    std::lock_guard<std::mutex> lock(core->consoleLock);
    if (!core->hasCart) return;
    core->nds->Reset();
    if (core->nds->NeedsDirectBoot()) core->nds->SetupDirectBoot(core->name + ".nds");
    core->nds->Start();
}

void MDCoreSetKeys(MDCore *core, uint32_t pressed) {
    if (core) core->keys = pressed & 0xFFF;
}

void MDCoreSetTouch(MDCore *core, bool down, int x, int y) {
    if (!core) return;
    if (!down) {
        core->touch = 0;
        return;
    }
    x = std::clamp(x, 0, MD_SCREEN_WIDTH - 1);
    y = std::clamp(y, 0, MD_SCREEN_HEIGHT - 1);
    core->touch = 0x80000000u | (uint32_t)x | ((uint32_t)y << 8);
}

uint64_t MDCoreCopyScreens(MDCore *core, uint32_t *top, uint32_t *bottom) {
    if (!core) return 0;
    std::lock_guard<std::mutex> frame(core->frameLock);
    if (top) memcpy(top, core->top.data(), kPixels * 4);
    if (bottom) memcpy(bottom, core->bottom.data(), kPixels * 4);
    return core->frames.load();
}

size_t MDCoreReadAudio(MDCore *core, float *left, float *right, size_t frames) {
    size_t got = 0;
    if (core && core->nds && frames) {
        int16_t buffer[2048 * 2];
        size_t want = std::min<size_t>(frames, 2048);
        int available = core->nds->SPU.GetOutputSize();
        if (available > 0) {
            got = (size_t)core->nds->SPU.ReadOutput(buffer, (int)std::min<size_t>(want, (size_t)available));
            for (size_t i = 0; i < got; i++) {
                left[i] = buffer[i * 2] / 32768.0f;
                right[i] = buffer[i * 2 + 1] / 32768.0f;
            }
        }
    }
    for (size_t i = got; i < frames; i++) {
        left[i] = 0;
        right[i] = 0;
    }
    return got;
}

size_t MDCoreSaveSize(MDCore *core) {
    if (!core) return 0;
    std::lock_guard<std::mutex> lock(core->consoleLock);
    return core->hasCart ? core->nds->GetNDSSaveLength() : 0;
}

size_t MDCoreCopySave(MDCore *core, uint8_t *buffer, size_t length) {
    if (!core || !buffer) return 0;
    std::lock_guard<std::mutex> lock(core->consoleLock);
    if (!core->hasCart) return 0;
    size_t size = core->nds->GetNDSSaveLength();
    const u8 *save = core->nds->GetNDSSave();
    if (!save || !size || length < size) return 0;
    memcpy(buffer, save, size);
    return size;
}

bool MDCoreSaveChanged(MDCore *core) {
    return core && core->saveChanged.exchange(false);
}

uint8_t *MDCoreSaveState(MDCore *core, size_t *length) {
    if (length) *length = 0;
    if (!core) return nullptr;
    std::lock_guard<std::mutex> lock(core->consoleLock);
    if (!core->hasCart) return nullptr;
    Savestate state;
    if (state.Error || !core->nds->DoSavestate(&state) || state.Error) return nullptr;
    state.Finish();
    size_t size = state.Length();
    auto *out = (uint8_t *)malloc(size);
    if (!out) return nullptr;
    memcpy(out, state.Buffer(), size);
    if (length) *length = size;
    return out;
}

bool MDCoreLoadState(MDCore *core, const uint8_t *data, size_t length) {
    if (!core || !data || length < 16) return false;
    std::vector<u8> copy(data, data + length);
    std::lock_guard<std::mutex> lock(core->consoleLock);
    if (!core->hasCart) return false;
    // Keep a backup so a bad file can't leave the console half-loaded.
    Savestate backup;
    if (backup.Error || !core->nds->DoSavestate(&backup) || backup.Error) return false;
    backup.Finish();
    Savestate state(copy.data(), (u32)copy.size(), false);
    if (!state.Error && core->nds->DoSavestate(&state) && !state.Error) return true;
    std::vector<u8> restore((const u8 *)backup.Buffer(), (const u8 *)backup.Buffer() + backup.Length());
    Savestate undo(restore.data(), (u32)restore.size(), false);
    core->nds->DoSavestate(&undo);
    return false;
}

void MDCoreFreeBuffer(uint8_t *buffer) { free(buffer); }

void MDCoreTitle(MDCore *core, char title[13]) {
    if (!title) return;
    memset(title, 0, 13);
    if (!core) return;
    std::lock_guard<std::mutex> lock(core->consoleLock);
    if (!core->hasCart || !core->nds->NDSCartSlot.GetCart()) return;
    memcpy(title, core->nds->NDSCartSlot.GetCart()->GetHeader().GameTitle, 12);
}

double MDCoreSpeed(MDCore *core) { return core ? core->speed.load() : 0; }

} // extern "C"
