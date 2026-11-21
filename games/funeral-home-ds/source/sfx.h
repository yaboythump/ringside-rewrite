// PSG square-wave sound effects and the (very solemn) organ.
#ifndef SFX_H
#define SFX_H

typedef enum {
    SFX_TAP,
    SFX_BAD,
    SFX_ALARM,
    SFX_FIXED,
    SFX_CASH,
    SFX_PUMP,
    SFX_DONE,
} Sfx;

typedef enum { MUSIC_NONE, MUSIC_DIRGE, MUSIC_RINGTONE } Music;

void sfx_init(void);
void sfx_play(Sfx s);
void sfx_music(Music m);
// A one-frame voice blip for dialogue text, at the speaker's pitch.
void sfx_blip(unsigned hz);
// Call once per frame.
void sfx_update(void);

#endif
