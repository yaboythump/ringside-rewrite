#include <nds.h>

#include "sfx.h"

// A sound effect is a list of (frequency Hz, frames) steps; 0 Hz is a rest.
typedef struct {
    uint16_t hz;
    uint8_t frames;
} Step;

static const Step TAP[] = { { 1320, 3 }, { 0, 0 } };
static const Step BAD[] = { { 180, 8 }, { 140, 14 }, { 0, 0 } };
static const Step ALARM[] = { { 880, 8 }, { 660, 8 }, { 880, 8 }, { 660, 8 }, { 880, 8 }, { 660, 8 }, { 0, 0 } };
static const Step FIXED[] = { { 523, 5 }, { 659, 5 }, { 784, 5 }, { 1047, 10 }, { 0, 0 } };
static const Step CASH[] = { { 1568, 5 }, { 2093, 14 }, { 0, 0 } };
static const Step PUMP[] = { { 220, 2 }, { 0, 0 } };
static const Step DONE[] = { { 784, 4 }, { 1047, 8 }, { 0, 0 } };

static const Step *const EFFECTS[] = { TAP, BAD, ALARM, FIXED, CASH, PUMP, DONE };

// Chopin's funeral march opening (1839, public domain), played slowly.
static const Step DIRGE[] = {
    { 233, 40 }, { 233, 30 }, { 233, 10 }, { 233, 40 }, { 277, 30 }, { 262, 10 },
    { 262, 30 }, { 233, 10 }, { 233, 30 }, { 220, 10 }, { 233, 60 }, { 0, 30 }, { 0, 0 },
};
// A generic, extremely loud phone ringtone (original).
static const Step RINGTONE[] = {
    { 1175, 6 }, { 1397, 6 }, { 1760, 6 }, { 1397, 6 }, { 1175, 6 }, { 0, 6 },
    { 1568, 6 }, { 1760, 6 }, { 2093, 12 }, { 0, 12 }, { 0, 0 },
};

typedef struct {
    const Step *steps;
    int index;
    int left;
    int channel;
    bool loop;
    uint8_t volume;
    DutyCycle duty;
} Voice;

static Voice fx = { 0, 0, 0, -1, false, 90, DutyCycle_50 };
static Voice music = { 0, 0, 0, -1, true, 45, DutyCycle_25 };

void sfx_init(void)
{
    soundEnable();
}

static void voice_stop(Voice *v)
{
    if (v->channel >= 0)
        soundKill(v->channel);
    v->channel = -1;
}

static void voice_start_step(Voice *v)
{
    voice_stop(v);
    const Step *s = &v->steps[v->index];
    v->left = s->frames;
    if (s->hz)
        v->channel = soundPlayPSG(v->duty, s->hz, v->volume, 64);
}

static void voice_update(Voice *v)
{
    if (!v->steps)
        return;
    if (--v->left > 0)
        return;
    v->index++;
    if (v->steps[v->index].frames == 0) {
        if (!v->loop) {
            voice_stop(v);
            v->steps = 0;
            return;
        }
        v->index = 0;
    }
    voice_start_step(v);
}

void sfx_play(Sfx s)
{
    fx.steps = EFFECTS[s];
    fx.index = 0;
    voice_start_step(&fx);
}

void sfx_music(Music m)
{
    const Step *want = m == MUSIC_DIRGE ? DIRGE : m == MUSIC_RINGTONE ? RINGTONE : 0;
    if (want == music.steps)
        return;
    voice_stop(&music);
    music.steps = want;
    music.index = 0;
    music.volume = m == MUSIC_RINGTONE ? 70 : 45;
    music.duty = m == MUSIC_RINGTONE ? DutyCycle_12 : DutyCycle_25;
    if (want)
        voice_start_step(&music);
}

void sfx_update(void)
{
    voice_update(&fx);
    voice_update(&music);
}
