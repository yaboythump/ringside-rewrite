// Retro Duo - Game Boy Advance core wrapper around mGBA.
// Copyright 2026 CT Network Studios. Licensed under the GNU GPL v3 or later (see LICENSE).
#include "GBAConfig.h"
#include "RDGBA.h"

#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#include <mgba/core/core.h>
#include <mgba/core/config.h>
#include <mgba/core/interface.h>
#include <mgba/core/serialize.h>
#include <mgba/core/cheats.h>
#include <mgba/internal/gba/cheats.h>
#include <mgba-util/vfs.h>
#include <mgba/core/blip_buf.h>
#include <mgba/internal/gba/gba.h>
#include <mgba/gba/core.h>

#define AUDIO_CAPACITY 16384u   /* stereo frames, power of two */
#define AUDIO_MAX_LATENCY 6144u
#define SAVE_SIZE 0x20000       /* largest GBA save (128 KB flash) */

struct RDGBA {
    struct mCore *core;
    struct mRumble rumble;
    uint32_t pixels[GBA_SCREEN_WIDTH * GBA_SCREEN_HEIGHT];
    uint8_t *save;
    uint64_t frames;
    unsigned sampleRate;
    double rumbleLevel;
    int16_t scratch[4096 * 2];
    int16_t audio[AUDIO_CAPACITY * 2];
    _Atomic size_t audioWrite;
    _Atomic size_t audioRead;
};

static void setRumble(struct mRumble *rumble, int enable) {
    struct RDGBA *bridge = (struct RDGBA *)((char *)rumble - offsetof(struct RDGBA, rumble));
    bridge->rumbleLevel = enable ? 1 : 0;
}

RDGBA *RDGBACreate(unsigned sampleRate) {
    RDGBA *bridge = calloc(1, sizeof(RDGBA));
    if (!bridge) return NULL;
    bridge->sampleRate = sampleRate ? sampleRate : 48000;
    bridge->rumble.setRumble = setRumble;
    return bridge;
}

void RDGBADestroy(RDGBA *bridge) {
    if (!bridge) return;
    if (bridge->core) {
        mCoreConfigDeinit(&bridge->core->config);
        bridge->core->deinit(bridge->core);
    }
    free(bridge->save);
    free(bridge);
}

bool RDGBALoadROM(RDGBA *bridge, const uint8_t *rom, size_t length, const uint8_t *save, size_t saveLength) {
    if (!bridge || bridge->core || !rom || length < 0xC0 || length > 32 * 1024 * 1024) return false;
    /* mGBA reads the ROM straight from this copy for as long as the game runs. */
    void *romCopy = malloc(length);
    if (!romCopy) return false;
    memcpy(romCopy, rom, length);
    struct VFile *romFile = VFileFromMemory(romCopy, length);
    if (!romFile || !GBAIsROM(romFile)) {
        if (romFile) romFile->close(romFile);
        free(romCopy);
        return false;
    }

    struct mCore *core = GBACoreCreate();
    if (!core) {
        romFile->close(romFile);
        free(romCopy);
        return false;
    }
    mCoreInitConfig(core, NULL);
    core->init(core);
    core->setVideoBuffer(core, (color_t *)bridge->pixels, GBA_SCREEN_WIDTH);
    size_t perFrame = (size_t)((double)bridge->sampleRate * core->frameCycles(core) / core->frequency(core));
    core->setAudioBufferSize(core, perFrame * 2 > 0x4000 ? 0x4000 : perFrame * 2);
    blip_set_rates(core->getAudioChannel(core, 0), core->frequency(core), bridge->sampleRate);
    blip_set_rates(core->getAudioChannel(core, 1), core->frequency(core), bridge->sampleRate);
    core->setPeripheral(core, mPERIPH_RUMBLE, &bridge->rumble);

    struct mCoreOptions options = { .useBios = false, .skipBios = true, .volume = 0x100 };
    mCoreConfigLoadDefaults(&core->config, &options);
    mCoreLoadConfig(core);

    if (!core->loadROM(core, romFile)) {
        mCoreConfigDeinit(&core->config);
        core->deinit(core);
        return false;
    }
    /* Battery saves live in a fixed buffer the game writes into directly. */
    bridge->save = malloc(SAVE_SIZE);
    memset(bridge->save, 0xFF, SAVE_SIZE);
    if (save && saveLength) memcpy(bridge->save, save, saveLength < SAVE_SIZE ? saveLength : SAVE_SIZE);
    struct VFile *saveFile = VFileFromMemory(bridge->save, SAVE_SIZE);
    if (!core->loadSave(core, saveFile)) saveFile->close(saveFile);

    core->reset(core);
    bridge->core = core;
    bridge->frames = 0;
    return true;
}

void RDGBAReset(RDGBA *bridge) {
    if (bridge && bridge->core) bridge->core->reset(bridge->core);
}

void RDGBASetKeys(RDGBA *bridge, uint16_t pressed) {
    if (!bridge || !bridge->core) return;
    uint32_t keys = pressed & 0x3FF;
    /* A real D-pad can't press opposite directions. */
    if ((keys & GBA_PAD_LEFT) && (keys & GBA_PAD_RIGHT)) keys &= ~(GBA_PAD_LEFT | GBA_PAD_RIGHT);
    if ((keys & GBA_PAD_UP) && (keys & GBA_PAD_DOWN)) keys &= ~(GBA_PAD_UP | GBA_PAD_DOWN);
    bridge->core->setKeys(bridge->core, keys);
}

static void pushAudio(RDGBA *bridge) {
    struct mCore *core = bridge->core;
    blip_t *left = core->getAudioChannel(core, 0);
    blip_t *right = core->getAudioChannel(core, 1);
    int available = blip_samples_avail(left);
    while (available > 0) {
        int chunk = available > 4096 ? 4096 : available;
        int produced = blip_read_samples(left, bridge->scratch, chunk, true);
        blip_read_samples(right, bridge->scratch + 1, chunk, true);
        size_t write = atomic_load_explicit(&bridge->audioWrite, memory_order_relaxed);
        size_t read = atomic_load_explicit(&bridge->audioRead, memory_order_acquire);
        for (int i = 0; i < produced; i++) {
            if (write - read >= AUDIO_MAX_LATENCY) break;
            size_t slot = (write & (AUDIO_CAPACITY - 1)) * 2;
            bridge->audio[slot] = bridge->scratch[i * 2];
            bridge->audio[slot + 1] = bridge->scratch[i * 2 + 1];
            write++;
        }
        atomic_store_explicit(&bridge->audioWrite, write, memory_order_release);
        available -= chunk;
    }
}

void RDGBARunFrame(RDGBA *bridge) {
    if (!bridge || !bridge->core) return;
    bridge->core->runFrame(bridge->core);
    pushAudio(bridge);
    /* mGBA leaves the alpha byte at 0; make every pixel opaque for the screen view. */
    for (int i = 0; i < GBA_SCREEN_WIDTH * GBA_SCREEN_HEIGHT; i++) bridge->pixels[i] |= 0xFF000000u;
    bridge->frames++;
}

uint64_t RDGBAFrameCount(const RDGBA *bridge) { return bridge ? bridge->frames : 0; }
void RDGBASetCheats(RDGBA *bridge, const char *const *entries, size_t count, bool *accepted) {
    if (!bridge || !bridge->core) return;
    struct mCheatDevice *device = bridge->core->cheatDevice(bridge->core);
    if (!device) {
        for (size_t i = 0; accepted && i < count; i++) accepted[i] = false;
        return;
    }
    while (mCheatSetsSize(&device->cheats)) {
        struct mCheatSet *set = *mCheatSetsGetPointer(&device->cheats, 0);
        mCheatRemoveSet(device, set); // undoes any ROM patches
        mCheatSetDeinit(set);
    }
    for (size_t i = 0; i < count; i++) {
        struct mCheatSet *set = device->createSet(device, "AVYDRIX");
        bool ok = set && entries[i] && entries[i][0];
        const char *p = entries[i] ? entries[i] : "";
        char line[96];
        while (ok && *p) {
            size_t n = strcspn(p, "\n");
            if (n >= sizeof line) { ok = false; break; }
            if (n > 0) {
                memcpy(line, p, n);
                line[n] = 0;
                if (!mCheatAddLine(set, line, GBA_CHEAT_AUTODETECT)) ok = false;
            }
            p += n;
            if (*p == '\n') p++;
        }
        if (set && ok) {
            mCheatAddSet(device, set);
        } else if (set) {
            mCheatSetDeinit(set);
        }
        if (accepted) accepted[i] = ok;
    }
}

uint8_t RDGBARead8(const RDGBA *bridge, uint32_t address) {
    if (!bridge || !bridge->core) return 0;
    return (uint8_t)bridge->core->rawRead8(bridge->core, address, -1);
}
const uint32_t *RDGBAPixels(const RDGBA *bridge) { return bridge ? bridge->pixels : NULL; }
double RDGBARumble(const RDGBA *bridge) { return bridge ? bridge->rumbleLevel : 0; }

size_t RDGBABufferedAudioFrames(const RDGBA *bridge) {
    if (!bridge) return 0;
    return atomic_load_explicit(&((RDGBA *)bridge)->audioWrite, memory_order_acquire) -
           atomic_load_explicit(&((RDGBA *)bridge)->audioRead, memory_order_acquire);
}

size_t RDGBAReadAudio(RDGBA *bridge, float *left, float *right, size_t frames) {
    if (!bridge) return 0;
    size_t read = atomic_load_explicit(&bridge->audioRead, memory_order_relaxed);
    size_t write = atomic_load_explicit(&bridge->audioWrite, memory_order_acquire);
    size_t count = write - read < frames ? write - read : frames;
    for (size_t i = 0; i < count; i++) {
        size_t slot = ((read + i) & (AUDIO_CAPACITY - 1)) * 2;
        left[i] = bridge->audio[slot] / 32768.0f;
        right[i] = bridge->audio[slot + 1] / 32768.0f;
    }
    for (size_t i = count; i < frames; i++) {
        left[i] = 0;
        right[i] = 0;
    }
    atomic_store_explicit(&bridge->audioRead, read + count, memory_order_release);
    return count;
}

uint8_t *RDGBACopySave(RDGBA *bridge, size_t *length) {
    if (length) *length = 0;
    if (!bridge || !bridge->core) return NULL;
    void *data = NULL;
    size_t size = bridge->core->savedataClone(bridge->core, &data);
    if (!data || !size) {
        free(data);
        return NULL;
    }
    if (length) *length = size;
    return data;
}

uint8_t *RDGBASaveState(RDGBA *bridge, size_t *length) {
    if (length) *length = 0;
    if (!bridge || !bridge->core) return NULL;
    struct VFile *memory = VFileMemChunk(NULL, 0);
    if (!memory) return NULL;
    if (!mCoreSaveStateNamed(bridge->core, memory, SAVESTATE_SAVEDATA | SAVESTATE_RTC)) {
        memory->close(memory);
        return NULL;
    }
    ssize_t size = memory->size(memory);
    uint8_t *out = size > 0 ? malloc((size_t)size) : NULL;
    if (out) {
        memory->seek(memory, 0, SEEK_SET);
        memory->read(memory, out, (size_t)size);
        if (length) *length = (size_t)size;
    }
    memory->close(memory);
    return out;
}

bool RDGBALoadState(RDGBA *bridge, const uint8_t *data, size_t length) {
    if (!bridge || !bridge->core || !data || length < 64) return false;
    struct VFile *memory = VFileFromConstMemory(data, length);
    if (!memory) return false;
    bool loaded = mCoreLoadStateNamed(bridge->core, memory, SAVESTATE_RTC);
    memory->close(memory);
    return loaded;
}

void RDGBAFreeBuffer(uint8_t *buffer) { free(buffer); }
