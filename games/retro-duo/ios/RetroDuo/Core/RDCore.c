#include "RDCore.h"

#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#include "Core/gb.h"

#define RD_AUDIO_CAPACITY 16384u          /* power of two */
#define RD_AUDIO_MAX_LATENCY 6144u        /* frames kept before older audio is dropped */

struct RDCore {
    GB_gameboy_t *gb;
    uint8_t *bootROM;
    size_t bootROMLength;
    uint32_t pixels[256 * 224];           /* large enough for any SameBoy screen mode */
    uint64_t frames;
    double rumble;
    int16_t audio[RD_AUDIO_CAPACITY * 2];
    _Atomic size_t audioWrite;
    _Atomic size_t audioRead;
    bool hasROM;
};

static uint32_t encodeRGB(GB_gameboy_t *gb, uint8_t r, uint8_t g, uint8_t b) {
    (void)gb;
    /* Little-endian: bytes in memory become R, G, B, X. */
    return (uint32_t)r | ((uint32_t)g << 8) | ((uint32_t)b << 16) | 0xFF000000u;
}

static void vblank(GB_gameboy_t *gb, GB_vblank_type_t type) {
    (void)type;
    RDCore *core = GB_get_user_data(gb);
    core->frames++;
}

static void sample(GB_gameboy_t *gb, GB_sample_t *s) {
    RDCore *core = GB_get_user_data(gb);
    size_t write = atomic_load_explicit(&core->audioWrite, memory_order_relaxed);
    size_t read = atomic_load_explicit(&core->audioRead, memory_order_acquire);
    if (write - read >= RD_AUDIO_MAX_LATENCY) {
        return; /* the speaker is behind; drop this sample instead of adding lag */
    }
    size_t slot = (write & (RD_AUDIO_CAPACITY - 1)) * 2;
    core->audio[slot] = s->left;
    core->audio[slot + 1] = s->right;
    atomic_store_explicit(&core->audioWrite, write + 1, memory_order_release);
}

static void rumble(GB_gameboy_t *gb, double amplitude) {
    RDCore *core = GB_get_user_data(gb);
    core->rumble = amplitude;
}

static void loadBootROM(GB_gameboy_t *gb, GB_boot_rom_t type) {
    (void)type; /* Retro Duo always emulates a Game Boy Color. */
    RDCore *core = GB_get_user_data(gb);
    GB_load_boot_rom_from_buffer(gb, core->bootROM, core->bootROMLength);
}

static void ignoreLog(GB_gameboy_t *gb, const char *string, GB_log_attributes_t attributes) {
    (void)gb; (void)string; (void)attributes;
}

RDCore *RDCoreCreate(const uint8_t *bootROM, size_t bootROMLength, unsigned sampleRate) {
    if (!bootROM || bootROMLength == 0 || bootROMLength > 0x1000) return NULL;
    RDCore *core = calloc(1, sizeof(RDCore));
    if (!core) return NULL;
    core->bootROM = malloc(bootROMLength);
    core->gb = GB_alloc();
    if (!core->bootROM || !core->gb) {
        RDCoreDestroy(core);
        return NULL;
    }
    memcpy(core->bootROM, bootROM, bootROMLength);
    core->bootROMLength = bootROMLength;

    GB_init(core->gb, GB_MODEL_CGB_E);
    GB_set_user_data(core->gb, core);
    GB_set_log_callback(core->gb, ignoreLog);
    GB_set_boot_rom_load_callback(core->gb, loadBootROM);
    GB_set_border_mode(core->gb, GB_BORDER_NEVER);
    GB_set_pixels_output(core->gb, core->pixels);
    GB_set_rgb_encode_callback(core->gb, encodeRGB);
    GB_set_vblank_callback(core->gb, vblank);
    GB_set_rumble_mode(core->gb, GB_RUMBLE_CARTRIDGE_ONLY);
    GB_set_rumble_callback(core->gb, rumble);
    GB_set_sample_rate(core->gb, sampleRate ? sampleRate : 48000);
    GB_set_highpass_filter_mode(core->gb, GB_HIGHPASS_ACCURATE);
    GB_apu_set_sample_callback(core->gb, sample);
    GB_set_color_correction_mode(core->gb, GB_COLOR_CORRECTION_MODERN_BALANCED);
    loadBootROM(core->gb, GB_BOOT_ROM_CGB_E);
    return core;
}

void RDCoreDestroy(RDCore *core) {
    if (!core) return;
    if (core->gb) {
        GB_free(core->gb);
        GB_dealloc(core->gb);
    }
    free(core->bootROM);
    free(core);
}

bool RDCoreLoadROM(RDCore *core, const uint8_t *rom, size_t length) {
    if (!core || !rom || length < 0x150 || length > 8 * 1024 * 1024) return false;
    GB_load_rom_from_buffer(core->gb, rom, length);
    RDCoreReset(core);
    core->hasROM = true;
    return true;
}

void RDCoreReset(RDCore *core) {
    if (!core) return;
    GB_reset(core->gb);
    core->rumble = 0;
}

void RDCoreSetKeys(RDCore *core, uint8_t mask) {
    if (!core) return;
    static const GB_key_t keys[8] = {
        GB_KEY_RIGHT, GB_KEY_LEFT, GB_KEY_UP, GB_KEY_DOWN,
        GB_KEY_A, GB_KEY_B, GB_KEY_SELECT, GB_KEY_START,
    };
    for (unsigned i = 0; i < 8; i++) {
        GB_set_key_state(core->gb, keys[i], (mask >> i) & 1);
    }
}

void RDCoreRunFrame(RDCore *core) {
    if (!core || !core->hasROM) return;
    GB_run_frame(core->gb);
}

uint64_t RDCoreFrameCount(const RDCore *core) { return core ? core->frames : 0; }
void RDCoreSetCheats(RDCore *core, const char *const *entries, size_t count, bool *accepted) {
    if (!core || !core->gb) return;
    GB_remove_all_cheats(core->gb);
    for (size_t i = 0; i < count; i++) {
        bool ok = entries[i] && entries[i][0];
        char line[64];
        const char *p = entries[i] ? entries[i] : "";
        while (*p) {
            size_t n = strcspn(p, "\n");
            if (n > 0 && n < sizeof line) {
                memcpy(line, p, n);
                line[n] = 0;
                if (!GB_import_cheat(core->gb, line, "", true)) ok = false;
            } else if (n >= sizeof line) {
                ok = false;
            }
            p += n;
            if (*p == '\n') p++;
        }
        if (accepted) accepted[i] = ok;
    }
    GB_set_cheats_enabled(core->gb, true);
}

uint8_t RDCoreReadMemory(const RDCore *core, uint16_t address) {
    return core && core->gb ? GB_safe_read_memory(core->gb, address) : 0;
}
const uint32_t *RDCorePixels(const RDCore *core) { return core ? core->pixels : NULL; }
unsigned RDCoreScreenWidth(const RDCore *core) { return core ? GB_get_screen_width(core->gb) : 160; }
unsigned RDCoreScreenHeight(const RDCore *core) { return core ? GB_get_screen_height(core->gb) : 144; }

size_t RDCoreBufferedAudioFrames(const RDCore *core) {
    if (!core) return 0;
    return atomic_load_explicit(&core->audioWrite, memory_order_acquire) -
           atomic_load_explicit(&core->audioRead, memory_order_acquire);
}

size_t RDCoreReadAudio(RDCore *core, float *left, float *right, size_t frames) {
    if (!core) return 0;
    size_t read = atomic_load_explicit(&core->audioRead, memory_order_relaxed);
    size_t write = atomic_load_explicit(&core->audioWrite, memory_order_acquire);
    size_t available = write - read;
    size_t count = available < frames ? available : frames;
    for (size_t i = 0; i < count; i++) {
        size_t slot = ((read + i) & (RD_AUDIO_CAPACITY - 1)) * 2;
        left[i] = core->audio[slot] / 32768.0f;
        right[i] = core->audio[slot + 1] / 32768.0f;
    }
    for (size_t i = count; i < frames; i++) {
        left[i] = 0;
        right[i] = 0;
    }
    atomic_store_explicit(&core->audioRead, read + count, memory_order_release);
    return count;
}

size_t RDCoreBatterySize(RDCore *core) {
    if (!core || !core->hasROM) return 0;
    int size = GB_save_battery_size(core->gb);
    return size > 0 ? (size_t)size : 0;
}

size_t RDCoreSaveBattery(RDCore *core, uint8_t *buffer, size_t length) {
    size_t size = RDCoreBatterySize(core);
    if (!size || !buffer || length < size) return 0;
    int written = GB_save_battery_to_buffer(core->gb, buffer, length);
    return written > 0 ? (size_t)written : 0;
}

void RDCoreLoadBattery(RDCore *core, const uint8_t *buffer, size_t length) {
    if (!core || !buffer || !length) return;
    GB_load_battery_from_buffer(core->gb, buffer, length);
}

size_t RDCoreStateSize(RDCore *core) {
    return core && core->hasROM ? GB_get_save_state_size(core->gb) : 0;
}

void RDCoreSaveState(RDCore *core, uint8_t *buffer) {
    if (!core || !buffer || !core->hasROM) return;
    GB_save_state_to_buffer(core->gb, buffer);
}

bool RDCoreLoadState(RDCore *core, const uint8_t *buffer, size_t length) {
    if (!core || !buffer || !core->hasROM) return false;
    return GB_load_state_from_buffer(core->gb, buffer, length) == 0;
}

void RDCoreTitle(RDCore *core, char title[17]) {
    if (!core || !title) return;
    memset(title, 0, 17);
    if (core->hasROM) GB_get_rom_title(core->gb, title);
}

double RDCoreRumble(const RDCore *core) { return core ? core->rumble : 0; }
