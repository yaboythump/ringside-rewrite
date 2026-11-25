// The bsnes libretro core's functions, under their renamed (bsnes_retro_*) names.
#include "SNESConfig.h"
#include "RDLibretroCore.h"

/* Speed-friendly defaults for a phone: bsnes's fast PPU and DSP (still accurate for
   nearly every game), no run-ahead, square pixels. */
static const char *const SNESOptions[] = {
    "bsnes_ppu_fast", "ON",
    "bsnes_dsp_fast", "ON",
    "bsnes_ppu_deinterlace", "OFF",
    "bsnes_aspect_ratio", "8:7",
    "bsnes_run_ahead_frames", "OFF",
    "bsnes_entropy", "Low",
    "bsnes_touchscreen_lightgun", "OFF",
    0,
};

const RDLRCoreTable RDLRSNESCore = RDLR_CORE_TABLE_WITH_CHEATS("bsnes", SNESOptions);
