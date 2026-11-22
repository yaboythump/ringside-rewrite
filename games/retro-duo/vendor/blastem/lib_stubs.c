/*
 Stubs for the UI/debugger entry points that the emulation core calls, but whose
 implementations live in objects that are not part of the libretro core build
 (oscilloscope.o, debug.o and the render backends).
*/
#include "oscilloscope.h"
#include "upd78k2.h"
#include <stdint.h>

uint8_t scope_add_channel(oscilloscope *scope, const char *name, uint32_t sample_rate)
{
	return 0;
}

void scope_add_sample(oscilloscope *scope, uint8_t channel, int16_t value, uint8_t trigger)
{
}

void upd_debugger(upd78k2_context *upd)
{
}
