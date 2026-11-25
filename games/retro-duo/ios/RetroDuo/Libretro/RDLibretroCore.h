// Function table for one libretro core. Each core's table lives in its own file,
// compiled with that core's renames (for example bsnes_retro_run for SNES).
#ifndef RETRO_DUO_LIBRETRO_CORE_H
#define RETRO_DUO_LIBRETRO_CORE_H

#include "libretro.h"

typedef struct RDLRCoreTable {
    const char *name;
    void (*set_environment)(retro_environment_t);
    void (*set_video_refresh)(retro_video_refresh_t);
    void (*set_audio_sample)(retro_audio_sample_t);
    void (*set_audio_sample_batch)(retro_audio_sample_batch_t);
    void (*set_input_poll)(retro_input_poll_t);
    void (*set_input_state)(retro_input_state_t);
    void (*init)(void);
    void (*deinit)(void);
    void (*get_system_info)(struct retro_system_info *);
    void (*get_system_av_info)(struct retro_system_av_info *);
    void (*set_controller_port_device)(unsigned, unsigned);
    void (*reset)(void);
    void (*run)(void);
    size_t (*serialize_size)(void);
    bool (*serialize)(void *, size_t);
    bool (*unserialize)(const void *, size_t);
    bool (*load_game)(const struct retro_game_info *);
    void (*unload_game)(void);
    void *(*get_memory_data)(unsigned);
    size_t (*get_memory_size)(unsigned);
    /// Option overrides, "key", "value" pairs, NULL-terminated.
    const char *const *options;
    /// Optional: checks a save state before the core sees it (for cores that trust their input).
    bool (*state_ok)(const void *data, size_t length);
    /// Optional: the core's own cheat engine (bsnes: Game Genie and Pro Action Replay).
    void (*cheat_reset)(void);
    void (*cheat_set)(unsigned index, bool enabled, const char *code);
} RDLRCoreTable;

#define RDLR_CORE_TABLE(NAME, OPTIONS) { NAME, retro_set_environment, retro_set_video_refresh, \
    retro_set_audio_sample, retro_set_audio_sample_batch, retro_set_input_poll, retro_set_input_state, \
    retro_init, retro_deinit, retro_get_system_info, retro_get_system_av_info, \
    retro_set_controller_port_device, retro_reset, retro_run, retro_serialize_size, retro_serialize, \
    retro_unserialize, retro_load_game, retro_unload_game, retro_get_memory_data, retro_get_memory_size, OPTIONS }

/* The same, for a core whose retro_cheat_set works. */
#define RDLR_CORE_TABLE_WITH_CHEATS(NAME, OPTIONS) { NAME, retro_set_environment, retro_set_video_refresh, \
    retro_set_audio_sample, retro_set_audio_sample_batch, retro_set_input_poll, retro_set_input_state, \
    retro_init, retro_deinit, retro_get_system_info, retro_get_system_av_info, \
    retro_set_controller_port_device, retro_reset, retro_run, retro_serialize_size, retro_serialize, \
    retro_unserialize, retro_load_game, retro_unload_game, retro_get_memory_data, retro_get_memory_size, OPTIONS, \
    0, retro_cheat_reset, retro_cheat_set }

#endif
