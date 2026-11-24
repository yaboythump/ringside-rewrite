// Retro Duo - NES core wrapper around Nestopia.
// Copyright 2026 CT Network Studios. Licensed under the GNU GPL v3 or later (see LICENSE).
#include "NESCore.h"

#include <algorithm>
#include <atomic>
#include <cstdlib>
#include <cstring>
#include <sstream>
#include <string>
#include <vector>

#include "core/api/NstApiCheats.hpp"
#include "core/api/NstApiEmulator.hpp"
#include "core/api/NstApiInput.hpp"
#include "core/api/NstApiMachine.hpp"
#include "core/api/NstApiSound.hpp"
#include "core/api/NstApiUser.hpp"
#include "core/api/NstApiVideo.hpp"

using namespace Nes;

namespace {
constexpr unsigned kAudioCapacity = 16384;   // frames, power of two
constexpr unsigned kMaxLatency = 6144;       // frames kept before older audio is dropped
constexpr double kFrameRate = 60.0988138974405;
constexpr int kOverscan = 8;
}

struct NESCore {
    Api::Emulator emulator;
    std::vector<uint32_t> frame = std::vector<uint32_t>(Api::Video::Output::WIDTH * Api::Video::Output::HEIGHT, 0xFF000000u);
    std::vector<int16_t> mono = std::vector<int16_t>(4096);
    Api::Input::Controllers controllers;
    uint64_t frames = 0;
    unsigned sampleRate = 48000;
    double sampleDebt = 0;
    bool loaded = false;

    std::vector<uint8_t> pendingSave;  // handed to the cartridge when it asks
    const uint8_t *battery = nullptr;  // the cartridge's live battery RAM
    size_t batterySize = 0;

    int16_t audio[kAudioCapacity];
    std::atomic<size_t> audioWrite{0};
    std::atomic<size_t> audioRead{0};

    void push(const int16_t *samples, unsigned count) {
        size_t write = audioWrite.load(std::memory_order_relaxed);
        size_t read = audioRead.load(std::memory_order_acquire);
        for (unsigned i = 0; i < count; i++) {
            if (write - read >= kMaxLatency) break; // the speaker is behind; don't add lag
            audio[write & (kAudioCapacity - 1)] = samples[i];
            write++;
        }
        audioWrite.store(write, std::memory_order_release);
    }
};

static void NST_CALLBACK fileIo(void *userData, Api::User::File &file) {
    auto *core = static_cast<NESCore *>(userData);
    if (!core) return;
    switch (file.GetAction()) {
    case Api::User::File::LOAD_BATTERY: {
        if (!core->pendingSave.empty()) file.SetContent(core->pendingSave.data(), core->pendingSave.size());
        const void *memory = nullptr;
        unsigned long size = 0;
        if (file.GetContent(memory, size) == RESULT_OK && memory && size) {
            core->battery = static_cast<const uint8_t *>(memory);
            core->batterySize = size;
        }
        break;
    }
    case Api::User::File::SAVE_BATTERY: {
        const void *memory = nullptr;
        unsigned long size = 0;
        if (file.GetContent(memory, size) == RESULT_OK && memory && size) {
            core->battery = static_cast<const uint8_t *>(memory);
            core->batterySize = size;
        }
        break;
    }
    default:
        break;
    }
}

extern "C" {

NESCore *NESCoreCreate(unsigned sampleRate) {
    auto *core = new NESCore();
    core->sampleRate = sampleRate ? sampleRate : 48000;
    return core;
}

void NESCoreDestroy(NESCore *core) {
    if (!core) return;
    if (core->loaded) {
        Api::Machine machine(core->emulator);
        machine.Power(false);
        machine.Unload();
    }
    Api::User::fileIoCallback.Set(nullptr, nullptr);
    delete core;
}

bool NESCoreLoadROM(NESCore *core, const uint8_t *rom, size_t length, const uint8_t *save, size_t saveLength) {
    if (!core || !rom || length < 16 || length > 16 * 1024 * 1024) return false;
    if (memcmp(rom, "NES\x1a", 4) != 0) return false;
    core->pendingSave.assign(save, save ? save + saveLength : save);
    core->battery = nullptr;
    core->batterySize = 0;
    Api::User::fileIoCallback.Set(fileIo, core);

    Api::Machine machine(core->emulator);
    std::istringstream stream(std::string(reinterpret_cast<const char *>(rom), length), std::ios::in | std::ios::binary);
    if (NES_FAILED(machine.Load(stream, Api::Machine::FAVORED_NES_NTSC, Api::Machine::DONT_ASK_PROFILE))) return false;
    machine.SetMode(machine.GetDesiredMode());

    Api::Video video(core->emulator);
    Api::Video::RenderState state;
    state.filter = Api::Video::RenderState::FILTER_NONE;
    state.width = Api::Video::Output::WIDTH;
    state.height = Api::Video::Output::HEIGHT;
    state.bits.count = 32;
    state.bits.mask.r = 0x000000FF; // RGBX byte order, as the app's screen view expects
    state.bits.mask.g = 0x0000FF00;
    state.bits.mask.b = 0x00FF0000;
    if (NES_FAILED(video.SetRenderState(state))) return false;

    Api::Sound sound(core->emulator);
    sound.SetSampleRate(core->sampleRate); // output is 16-bit mono
    sound.SetVolume(Api::Sound::ALL_CHANNELS, 85);

    Api::Input input(core->emulator);
    input.ConnectController(0, Api::Input::PAD1);
    input.ConnectController(1, Api::Input::PAD2); // a second Bluetooth controller plays as player 2

    if (NES_FAILED(machine.Power(true))) return false;
    core->loaded = true;
    core->frames = 0;
    return true;
}

void NESCoreReset(NESCore *core) {
    if (!core || !core->loaded) return;
    Api::Machine(core->emulator).Reset(true);
}

void NESCoreSetKeys(NESCore *core, uint8_t pressed) {
    NESCoreSetPlayerKeys(core, 0, pressed);
}

void NESCoreSetPlayerKeys(NESCore *core, unsigned player, uint8_t pressed) {
    if (!core || player > 1) return;
    unsigned buttons = 0;
    if (pressed & NES_KEY_A) buttons |= Api::Input::Controllers::Pad::A;
    if (pressed & NES_KEY_B) buttons |= Api::Input::Controllers::Pad::B;
    if (pressed & NES_KEY_SELECT) buttons |= Api::Input::Controllers::Pad::SELECT;
    if (pressed & NES_KEY_START) buttons |= Api::Input::Controllers::Pad::START;
    if (pressed & NES_KEY_UP) buttons |= Api::Input::Controllers::Pad::UP;
    if (pressed & NES_KEY_DOWN) buttons |= Api::Input::Controllers::Pad::DOWN;
    if (pressed & NES_KEY_LEFT) buttons |= Api::Input::Controllers::Pad::LEFT;
    if (pressed & NES_KEY_RIGHT) buttons |= Api::Input::Controllers::Pad::RIGHT;
    // A real D-pad can't press opposite directions; some games crash if they see that.
    if ((buttons & Api::Input::Controllers::Pad::LEFT) && (buttons & Api::Input::Controllers::Pad::RIGHT))
        buttons &= ~(Api::Input::Controllers::Pad::LEFT | Api::Input::Controllers::Pad::RIGHT);
    if ((buttons & Api::Input::Controllers::Pad::UP) && (buttons & Api::Input::Controllers::Pad::DOWN))
        buttons &= ~(Api::Input::Controllers::Pad::UP | Api::Input::Controllers::Pad::DOWN);
    core->controllers.pad[player].buttons = buttons;
}

void NESCoreRunFrame(NESCore *core) {
    if (!core || !core->loaded) return;
    core->sampleDebt += core->sampleRate / kFrameRate;
    unsigned count = (unsigned)core->sampleDebt;
    core->sampleDebt -= count;
    if (count > core->mono.size()) count = (unsigned)core->mono.size();

    Api::Video::Output video(core->frame.data(), Api::Video::Output::WIDTH * 4);
    Api::Sound::Output sound(core->mono.data(), count);
    core->emulator.Execute(&video, &sound, &core->controllers);
    core->push(core->mono.data(), count);
    core->frames++;
}

uint64_t NESCoreFrameCount(const NESCore *core) { return core ? core->frames : 0; }

uint8_t NESCoreReadRAM(NESCore *core, uint16_t address) {
    if (!core || !core->loaded || address >= 0x2000) return 0;
    return Api::Cheats(core->emulator).GetRam()[address & 0x7FF];
}

const uint32_t *NESCorePixels(const NESCore *core) {
    return core ? core->frame.data() + kOverscan * Api::Video::Output::WIDTH : nullptr;
}

size_t NESCoreBufferedAudioFrames(const NESCore *core) {
    if (!core) return 0;
    return core->audioWrite.load(std::memory_order_acquire) - core->audioRead.load(std::memory_order_acquire);
}

size_t NESCoreReadAudio(NESCore *core, float *left, float *right, size_t frames) {
    if (!core) return 0;
    size_t read = core->audioRead.load(std::memory_order_relaxed);
    size_t write = core->audioWrite.load(std::memory_order_acquire);
    size_t count = std::min(write - read, frames);
    for (size_t i = 0; i < count; i++) {
        float value = core->audio[(read + i) & (kAudioCapacity - 1)] / 32768.0f;
        left[i] = value;
        right[i] = value;
    }
    for (size_t i = count; i < frames; i++) {
        left[i] = 0;
        right[i] = 0;
    }
    core->audioRead.store(read + count, std::memory_order_release);
    return count;
}

size_t NESCoreBatterySize(NESCore *core) { return core && core->battery ? core->batterySize : 0; }

size_t NESCoreCopyBattery(NESCore *core, uint8_t *buffer, size_t length) {
    size_t size = NESCoreBatterySize(core);
    if (!size || !buffer || length < size) return 0;
    memcpy(buffer, core->battery, size);
    return size;
}

uint8_t *NESCoreSaveState(NESCore *core, size_t *length) {
    if (length) *length = 0;
    if (!core || !core->loaded) return nullptr;
    std::ostringstream stream(std::ios::out | std::ios::binary);
    if (NES_FAILED(Api::Machine(core->emulator).SaveState(stream, Api::Machine::NO_COMPRESSION))) return nullptr;
    std::string data = stream.str();
    auto *out = static_cast<uint8_t *>(malloc(data.size()));
    if (!out) return nullptr;
    memcpy(out, data.data(), data.size());
    if (length) *length = data.size();
    return out;
}

bool NESCoreLoadState(NESCore *core, const uint8_t *data, size_t length) {
    if (!core || !core->loaded || !data || length < 8) return false;
    // Keep the current state so a bad file can't leave the console half-loaded.
    std::ostringstream backup(std::ios::out | std::ios::binary);
    Api::Machine machine(core->emulator);
    machine.SaveState(backup, Api::Machine::NO_COMPRESSION);
    std::istringstream stream(std::string(reinterpret_cast<const char *>(data), length), std::ios::in | std::ios::binary);
    if (NES_SUCCEEDED(machine.LoadState(stream))) return true;
    std::istringstream undo(backup.str(), std::ios::in | std::ios::binary);
    machine.LoadState(undo);
    return false;
}

void NESCoreFreeBuffer(uint8_t *buffer) { free(buffer); }

} // extern "C"
