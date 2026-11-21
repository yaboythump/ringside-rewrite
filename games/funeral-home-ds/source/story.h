// Characters, dialogue scenes and the typewriter text box.
#ifndef STORY_H
#define STORY_H

#include <stdbool.h>
#include <stdint.h>

#include "gfx.h"

typedef enum { SPK_MORT, SPK_KEVIN, SPK_VIVIAN, SPK_FAMILY, SPK_COUNT } Speaker;

// What the game does once a scene ends.
typedef enum {
    AFTER_NOTHING,
    AFTER_OPEN_PREP,
    AFTER_START_SERVICE,
} AfterScene;

bool story_active(void);
// True while the running scene has lines for this speaker (they appear on the top screen).
bool story_features(Speaker s);
Speaker story_speaker(void);

void story_day_intro(void);
void story_family_meeting(void);
void story_service_tutorial(void);
void story_after_service(void);
void story_midday_visit(void);
void story_day_end(int profit);

// tapped/tx/ty: this frame's touch; advance: A button.
void story_update(bool tapped, int tx, int ty, bool advance);
void story_draw(Canvas *c);

// Implemented by game.c: called when a scene finishes.
void game_after_scene(AfterScene after);

int daily_goal(int day);

#endif
