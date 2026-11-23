// Retro Duo - a small libretro host. Copyright 2026 CT Network Studios. GPL v3 or later.
#include "RDLibretro.h"
#include "RDLibretroCore.h"

#include <stdarg.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern const RDLRCoreTable RDLRSNESCore;
extern const RDLRCoreTable RDLRSegaCore;

#define MAX_WIDTH 1024
#define MAX_HEIGHT 1024
#define AUDIO_CAPACITY 16384u  /* stereo frames, power of two */
#define AUDIO_MAX_LATENCY 6144u
#define MAX_VARIABLES 128

struct RDLRHost {
    const RDLRCoreTable *core;
    char workDirectory[1024];
    char romPath[1100];
    bool loaded;
    enum retro_pixel_format format;
    uint32_t pixels[MAX_WIDTH * MAX_HEIGHT];
    unsigned width, height;
    unsigned cropX, cropY, cropWidth, cropHeight;
    double aspect;      /* display height / width */
    double fps, sampleRate;
    uint32_t keys;
    uint64_t frames;
    bool failed;
    char lastError[256];
    char *variableKeys[MAX_VARIABLES];
    char *variableValues[MAX_VARIABLES];
    int variableCount;
    int16_t audio[AUDIO_CAPACITY * 2];
    _Atomic size_t audioWrite;
    _Atomic size_t audioRead;
};

/* libretro callbacks carry no context, so the running host is global. */
static RDLRHost *current;

static const RDLRCoreTable *tableFor(int system) {
    switch (system) {
    case RDLR_SYSTEM_SNES: return &RDLRSNESCore;
    case RDLR_SYSTEM_SEGA: return &RDLRSegaCore;
    default: return NULL;
    }
}

static void hostLog(enum retro_log_level level, const char *fmt, ...) {
    va_list args;
#ifdef RETRO_DUO_VERBOSE
    va_start(args, fmt);
    vfprintf(stderr, fmt, args);
    va_end(args);
#endif
    /* Keep the last error: it explains a stop (RDLRFailure). */
    if (level >= RETRO_LOG_ERROR && current) {
        va_start(args, fmt);
        vsnprintf(current->lastError, sizeof current->lastError, fmt, args);
        va_end(args);
        size_t n = strlen(current->lastError);
        while (n && (current->lastError[n - 1] == '\n' || current->lastError[n - 1] == ' ')) current->lastError[--n] = 0;
    }
}

static const char *override(const RDLRHost *host, const char *key) {
    const char *const *options = host->core->options;
    for (int i = 0; options && options[i] && options[i + 1]; i += 2)
        if (strcmp(options[i], key) == 0) return options[i + 1];
    return NULL;
}

/* Remembers each option's default: the first choice in "Description; first|second|...". */
static void rememberVariables(RDLRHost *host, const struct retro_variable *vars) {
    for (; vars && vars->key && host->variableCount < MAX_VARIABLES; vars++) {
        const char *choices = vars->value ? strstr(vars->value, "; ") : NULL;
        if (!choices) continue;
        choices += 2;
        size_t length = strcspn(choices, "|");
        host->variableKeys[host->variableCount] = strdup(vars->key);
        host->variableValues[host->variableCount] = strndup(choices, length);
        host->variableCount++;
    }
}

static bool environment(unsigned cmd, void *data) {
    RDLRHost *host = current;
    if (!host) return false;
    switch (cmd) {
    case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
    case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
    case RETRO_ENVIRONMENT_GET_CORE_ASSETS_DIRECTORY:
        *(const char **)data = host->workDirectory;
        return true;
    case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: {
        enum retro_pixel_format format = *(const enum retro_pixel_format *)data;
        if (format != RETRO_PIXEL_FORMAT_XRGB8888 && format != RETRO_PIXEL_FORMAT_RGB565 &&
            format != RETRO_PIXEL_FORMAT_0RGB1555) return false;
        host->format = format;
        return true;
    }
    case RETRO_ENVIRONMENT_SET_VARIABLES:
        rememberVariables(host, (const struct retro_variable *)data);
        return true;
    case RETRO_ENVIRONMENT_GET_VARIABLE: {
        struct retro_variable *var = (struct retro_variable *)data;
        var->value = NULL;
        if (!var->key) return false;
        const char *forced = override(host, var->key);
        if (forced) { var->value = forced; return true; }
        for (int i = 0; i < host->variableCount; i++)
            if (strcmp(host->variableKeys[i], var->key) == 0) { var->value = host->variableValues[i]; return true; }
        return false;
    }
    case RETRO_ENVIRONMENT_SHUTDOWN:
        host->failed = true;
        return true;
    case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
        *(bool *)data = false;
        return true;
    case RETRO_ENVIRONMENT_GET_LOG_INTERFACE:
        ((struct retro_log_callback *)data)->log = hostLog;
        return true;
    case RETRO_ENVIRONMENT_GET_CAN_DUPE:
        *(bool *)data = true;
        return true;
    case RETRO_ENVIRONMENT_GET_FASTFORWARDING:
        *(bool *)data = false;
        return true;
    case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS:
        return true;
    case RETRO_ENVIRONMENT_GET_LANGUAGE:
        *(unsigned *)data = RETRO_LANGUAGE_ENGLISH;
        return true;
    case RETRO_ENVIRONMENT_GET_AUDIO_VIDEO_ENABLE:
        *(int *)data = 3;
        return true;
    case RETRO_ENVIRONMENT_SET_GEOMETRY: {
        const struct retro_game_geometry *geometry = (const struct retro_game_geometry *)data;
        if (geometry->aspect_ratio > 0) host->aspect = 1.0 / geometry->aspect_ratio;
        else if (geometry->base_width) host->aspect = (double)geometry->base_height / geometry->base_width;
        return true;
    }
    case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO: {
        const struct retro_system_av_info *info = (const struct retro_system_av_info *)data;
        if (info->timing.fps > 0) host->fps = info->timing.fps;
        if (info->geometry.aspect_ratio > 0) host->aspect = 1.0 / info->geometry.aspect_ratio;
        return true;
    }
    case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
    case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO:
    case RETRO_ENVIRONMENT_SET_SUBSYSTEM_INFO:
    case RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME:
    case RETRO_ENVIRONMENT_SET_MEMORY_MAPS:
    case RETRO_ENVIRONMENT_SET_SERIALIZATION_QUIRKS:
    case RETRO_ENVIRONMENT_SET_SUPPORT_ACHIEVEMENTS:
    case RETRO_ENVIRONMENT_SET_PERFORMANCE_LEVEL:
        return true;
    default:
        return false;
    }
}

static inline uint32_t fromXRGB8888(uint32_t p) {
    return ((p >> 16) & 0xFFu) | (p & 0xFF00u) | ((p & 0xFFu) << 16) | 0xFF000000u;
}

static inline uint32_t fromRGB565(uint16_t p) {
    uint32_t r = (p >> 11) & 0x1F, g = (p >> 5) & 0x3F, b = p & 0x1F;
    r = (r << 3) | (r >> 2); g = (g << 2) | (g >> 4); b = (b << 3) | (b >> 2);
    return r | (g << 8) | (b << 16) | 0xFF000000u;
}

static inline uint32_t from0RGB1555(uint16_t p) {
    uint32_t r = (p >> 10) & 0x1F, g = (p >> 5) & 0x1F, b = p & 0x1F;
    r = (r << 3) | (r >> 2); g = (g << 3) | (g >> 2); b = (b << 3) | (b >> 2);
    return r | (g << 8) | (b << 16) | 0xFF000000u;
}

static void videoRefresh(const void *data, unsigned width, unsigned height, size_t pitch) {
    RDLRHost *host = current;
    if (!host || !data || !width || !height) return; /* NULL = repeat the last frame */
    if (host->cropWidth && host->cropHeight &&
        width >= host->cropX + host->cropWidth && height >= host->cropY + host->cropHeight) {
        size_t bytes = host->format == RETRO_PIXEL_FORMAT_XRGB8888 ? 4 : 2;
        data = (const uint8_t *)data + host->cropY * pitch + host->cropX * bytes;
        width = host->cropWidth;
        height = host->cropHeight;
    }
    if (width > MAX_WIDTH) width = MAX_WIDTH;
    if (height > MAX_HEIGHT) height = MAX_HEIGHT;
    for (unsigned y = 0; y < height; y++) {
        const uint8_t *row = (const uint8_t *)data + y * pitch;
        uint32_t *out = host->pixels + y * width;
        if (host->format == RETRO_PIXEL_FORMAT_XRGB8888) {
            const uint32_t *in = (const uint32_t *)row;
            for (unsigned x = 0; x < width; x++) out[x] = fromXRGB8888(in[x]);
        } else if (host->format == RETRO_PIXEL_FORMAT_RGB565) {
            const uint16_t *in = (const uint16_t *)row;
            for (unsigned x = 0; x < width; x++) out[x] = fromRGB565(in[x]);
        } else {
            const uint16_t *in = (const uint16_t *)row;
            for (unsigned x = 0; x < width; x++) out[x] = from0RGB1555(in[x]);
        }
    }
    host->width = width;
    host->height = height;
}

static size_t audioBatch(const int16_t *data, size_t frames) {
    RDLRHost *host = current;
    if (!host) return frames;
    size_t write = atomic_load_explicit(&host->audioWrite, memory_order_relaxed);
    size_t read = atomic_load_explicit(&host->audioRead, memory_order_acquire);
    for (size_t i = 0; i < frames; i++) {
        if (write - read >= AUDIO_MAX_LATENCY) break; /* the speaker is behind; don't add lag */
        size_t slot = (write & (AUDIO_CAPACITY - 1)) * 2;
        host->audio[slot] = data[i * 2];
        host->audio[slot + 1] = data[i * 2 + 1];
        write++;
    }
    atomic_store_explicit(&host->audioWrite, write, memory_order_release);
    return frames;
}

static void audioSample(int16_t left, int16_t right) {
    int16_t frame[2] = {left, right};
    audioBatch(frame, 1);
}

static void inputPoll(void) {}

static int16_t inputState(unsigned port, unsigned device, unsigned index, unsigned id) {
    (void)index;
    RDLRHost *host = current;
    if (!host || port != 0 || (device & RETRO_DEVICE_MASK) != RETRO_DEVICE_JOYPAD) return 0;
    if (id == RETRO_DEVICE_ID_JOYPAD_MASK) return (int16_t)(host->keys & 0xFFFF);
    return id < 16 ? (int16_t)((host->keys >> id) & 1) : 0;
}

RDLRHost *RDLRCreate(int system, const char *workDirectory) {
    const RDLRCoreTable *core = tableFor(system);
    if (!core || current) return NULL;
    RDLRHost *host = calloc(1, sizeof(RDLRHost));
    if (!host) return NULL;
    host->core = core;
    host->format = RETRO_PIXEL_FORMAT_0RGB1555;
    host->aspect = 0.75;
    host->fps = 60;
    host->sampleRate = 48000;
    snprintf(host->workDirectory, sizeof host->workDirectory, "%s", workDirectory ? workDirectory : "/tmp");
    current = host;
    core->set_environment(environment);
    core->set_video_refresh(videoRefresh);
    core->set_audio_sample(audioSample);
    core->set_audio_sample_batch(audioBatch);
    core->set_input_poll(inputPoll);
    core->set_input_state(inputState);
    core->init();
    return host;
}

void RDLRDestroy(RDLRHost *host) {
    if (!host) return;
    /* A core that hands its battery RAM to the app (which keeps a save per game) may still
       write it beside the game file when it unloads (bsnes does). Every game uses the same
       file name, so remove that copy: the next game must not pick it up. */
    bool appKeepsSave = host->loaded && host->core->get_memory_size(RETRO_MEMORY_SAVE_RAM) > 0;
    if (host->loaded) host->core->unload_game();
    if (appKeepsSave && host->romPath[0]) {
        char saveFile[sizeof host->romPath + 8];
        snprintf(saveFile, sizeof saveFile, "%s", host->romPath);
        char *dot = strrchr(saveFile, '.');
        char *slash = strrchr(saveFile, '/');
        if (dot && (!slash || dot > slash)) *dot = 0;
        strcat(saveFile, ".srm");
        remove(saveFile);
    }
    host->core->deinit();
    if (host->romPath[0]) remove(host->romPath);
    for (int i = 0; i < host->variableCount; i++) {
        free(host->variableKeys[i]);
        free(host->variableValues[i]);
    }
    if (current == host) current = NULL;
    free(host);
}

bool RDLRLoadROM(RDLRHost *host, const uint8_t *rom, size_t length,
                 const uint8_t *save, size_t saveLength, const char *fileName) {
    if (!host || host->loaded || !rom || !length || !fileName) return false;
    /* Some cores (bsnes) read the game from disk, so always provide a real file too. */
    snprintf(host->romPath, sizeof host->romPath, "%s/%s", host->workDirectory, fileName);
    FILE *file = fopen(host->romPath, "wb");
    if (!file) return false;
    bool written = fwrite(rom, 1, length, file) == length;
    fclose(file);
    if (!written) return false;

    struct retro_game_info info = { host->romPath, rom, length, NULL };
    if (!host->core->load_game(&info)) return false;
    host->loaded = true;
    host->core->set_controller_port_device(0, RETRO_DEVICE_JOYPAD);

    struct retro_system_av_info av;
    memset(&av, 0, sizeof av);
    host->core->get_system_av_info(&av);
    if (av.timing.fps > 0) host->fps = av.timing.fps;
    if (av.timing.sample_rate > 0) host->sampleRate = av.timing.sample_rate;
    if (av.geometry.aspect_ratio > 0) host->aspect = 1.0 / av.geometry.aspect_ratio;
    else if (av.geometry.base_width) host->aspect = (double)av.geometry.base_height / av.geometry.base_width;
    host->width = av.geometry.base_width ? av.geometry.base_width : 256;
    host->height = av.geometry.base_height ? av.geometry.base_height : 224;
    for (unsigned i = 0; i < host->width * host->height && i < MAX_WIDTH * MAX_HEIGHT; i++) host->pixels[i] = 0xFF000000u;

    if (save && saveLength) {
        uint8_t *battery = host->core->get_memory_data(RETRO_MEMORY_SAVE_RAM);
        size_t size = host->core->get_memory_size(RETRO_MEMORY_SAVE_RAM);
        if (battery && size) memcpy(battery, save, saveLength < size ? saveLength : size);
    }
    return true;
}

void RDLRSetCrop(RDLRHost *host, unsigned x, unsigned y, unsigned width, unsigned height) {
    if (!host) return;
    host->cropX = x;
    host->cropY = y;
    host->cropWidth = width;
    host->cropHeight = height;
    if (width && height && host->width >= width && host->height >= height) {
        host->width = width;  /* until the next frame arrives */
        host->height = height;
    }
}

const char *RDLRFailure(const RDLRHost *host) {
    if (!host || !host->failed) return NULL;
    return host->lastError[0] ? host->lastError : "The emulator stopped unexpectedly.";
}

void RDLRReset(RDLRHost *host) {
    if (host && host->loaded) host->core->reset();
}

void RDLRSetKeys(RDLRHost *host, uint32_t pressed) {
    if (!host) return;
    /* A real D-pad can't press opposite directions. */
    if ((pressed & RDLR_PAD_LEFT) && (pressed & RDLR_PAD_RIGHT)) pressed &= ~(uint32_t)(RDLR_PAD_LEFT | RDLR_PAD_RIGHT);
    if ((pressed & RDLR_PAD_UP) && (pressed & RDLR_PAD_DOWN)) pressed &= ~(uint32_t)(RDLR_PAD_UP | RDLR_PAD_DOWN);
    host->keys = pressed;
}

void RDLRRunFrame(RDLRHost *host) {
    if (!host || !host->loaded || current != host) return;
    host->core->run();
    host->frames++;
}

uint64_t RDLRFrameCount(const RDLRHost *host) { return host ? host->frames : 0; }
const uint32_t *RDLRPixels(const RDLRHost *host) { return host ? host->pixels : NULL; }
unsigned RDLRWidth(const RDLRHost *host) { return host ? host->width : 0; }
unsigned RDLRHeight(const RDLRHost *host) { return host ? host->height : 0; }
double RDLRDisplayAspect(const RDLRHost *host) { return host ? host->aspect : 0.75; }
double RDLRFrameRate(const RDLRHost *host) { return host ? host->fps : 60; }
double RDLRSampleRate(const RDLRHost *host) { return host ? host->sampleRate : 48000; }

size_t RDLRBufferedAudioFrames(const RDLRHost *host) {
    if (!host) return 0;
    return atomic_load_explicit(&((RDLRHost *)host)->audioWrite, memory_order_acquire) -
           atomic_load_explicit(&((RDLRHost *)host)->audioRead, memory_order_acquire);
}

size_t RDLRReadAudio(RDLRHost *host, float *left, float *right, size_t frames) {
    if (!host) return 0;
    size_t read = atomic_load_explicit(&host->audioRead, memory_order_relaxed);
    size_t write = atomic_load_explicit(&host->audioWrite, memory_order_acquire);
    size_t count = write - read < frames ? write - read : frames;
    for (size_t i = 0; i < count; i++) {
        size_t slot = ((read + i) & (AUDIO_CAPACITY - 1)) * 2;
        left[i] = host->audio[slot] / 32768.0f;
        right[i] = host->audio[slot + 1] / 32768.0f;
    }
    for (size_t i = count; i < frames; i++) {
        left[i] = 0;
        right[i] = 0;
    }
    atomic_store_explicit(&host->audioRead, read + count, memory_order_release);
    return count;
}

uint8_t *RDLRCopySave(RDLRHost *host, size_t *length) {
    if (length) *length = 0;
    if (!host || !host->loaded) return NULL;
    const uint8_t *battery = host->core->get_memory_data(RETRO_MEMORY_SAVE_RAM);
    size_t size = host->core->get_memory_size(RETRO_MEMORY_SAVE_RAM);
    if (!battery || !size) return NULL;
    uint8_t *out = malloc(size);
    if (!out) return NULL;
    memcpy(out, battery, size);
    if (length) *length = size;
    return out;
}

size_t RDLRRAMSize(const RDLRHost *host) {
    if (!host || !host->loaded) return 0;
    return host->core->get_memory_data(RETRO_MEMORY_SYSTEM_RAM) ? host->core->get_memory_size(RETRO_MEMORY_SYSTEM_RAM) : 0;
}

size_t RDLRReadRAM(const RDLRHost *host, size_t offset, uint8_t *out, size_t count) {
    if (!host || !host->loaded || !out) return 0;
    const uint8_t *ram = host->core->get_memory_data(RETRO_MEMORY_SYSTEM_RAM);
    size_t size = host->core->get_memory_size(RETRO_MEMORY_SYSTEM_RAM);
    if (!ram || offset >= size) return 0;
    if (count > size - offset) count = size - offset;
    memcpy(out, ram + offset, count);
    return count;
}

uint8_t *RDLRSaveState(RDLRHost *host, size_t *length) {
    if (length) *length = 0;
    if (!host || !host->loaded) return NULL;
    size_t size = host->core->serialize_size();
    if (!size) return NULL;
    uint8_t *out = malloc(size);
    if (!out) return NULL;
    if (!host->core->serialize(out, size)) {
        free(out);
        return NULL;
    }
    if (length) *length = size;
    return out;
}

bool RDLRLoadState(RDLRHost *host, const uint8_t *data, size_t length) {
    if (!host || !host->loaded || !data || !length) return false;
    if (host->core->state_ok && !host->core->state_ok(data, length)) return false;
    /* Keep the current state so a bad file can't leave the console half-loaded. */
    size_t size = host->core->serialize_size();
    uint8_t *backup = size ? malloc(size) : NULL;
    bool haveBackup = backup && host->core->serialize(backup, size);
    bool loaded = host->core->unserialize(data, length);
    if (!loaded && haveBackup) host->core->unserialize(backup, size);
    free(backup);
    return loaded;
}

void RDLRFreeBuffer(uint8_t *buffer) { free(buffer); }
