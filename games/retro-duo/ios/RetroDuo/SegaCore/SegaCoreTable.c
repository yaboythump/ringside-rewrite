// The BlastEm libretro core's functions, under their renamed (blastem_retro_*) names.
// Copyright 2026 CT Network Studios. GPL v3 or later.
#include "SegaConfig.h"
#include "RDLibretroCore.h"

#include <string.h>

/* Phone-friendly defaults: no MegaWiFi networking, standard pads in both ports. */
static const char *const SegaOptions[] = {
    "blastem_megawifi", "off",
    "blastem_io_1", "gamepad6.1",
    0,
};

/* BlastEm's save state is a size_t length followed by that many bytes, and it trusts the
   length. Reject anything that doesn't add up before it reaches the core. */
static bool SegaStateOK(const void *data, size_t length) {
    size_t inner;
    if (length < sizeof inner) return false;
    memcpy(&inner, data, sizeof inner);
    return inner > 0 && inner <= length - sizeof inner;
}

const RDLRCoreTable RDLRSegaCore = {
    "BlastEm", retro_set_environment, retro_set_video_refresh,
    retro_set_audio_sample, retro_set_audio_sample_batch, retro_set_input_poll, retro_set_input_state,
    retro_init, retro_deinit, retro_get_system_info, retro_get_system_av_info,
    retro_set_controller_port_device, retro_reset, retro_run, retro_serialize_size, retro_serialize,
    retro_unserialize, retro_load_game, retro_unload_game, retro_get_memory_data, retro_get_memory_size,
    SegaOptions, SegaStateOK,
};
