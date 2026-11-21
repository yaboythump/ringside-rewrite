// Talking-head portraits for dialogue: a bust drawn from a handful of parts.
#ifndef GM_PORTRAIT_H
#define GM_PORTRAIT_H

#include <stdbool.h>
#include <stdint.h>

#include "gfx.h"

#define PORTRAIT_W 88
#define PORTRAIT_H 96

typedef enum {
    HAIR_BALD, HAIR_SHORT, HAIR_POMP, HAIR_BOB, HAIR_BUN, HAIR_BIG, HAIR_LONG, HAIR_CAP,
} HairStyle;

typedef enum { EXPR_NEUTRAL, EXPR_HAPPY, EXPR_ANGRY, EXPR_SHOCK, EXPR_SMUG, EXPR_SAD } Expr;

enum {
    ACC_GLASSES   = 1 << 0,
    ACC_MUSTACHE  = 1 << 1,
    ACC_HAT       = 1 << 2,   // enormous feathered hat
    ACC_PEARLS    = 1 << 3,
    ACC_FRECKLES  = 1 << 4,
    ACC_GHOST     = 1 << 5,   // see-through, glowing, wavy
    ACC_EARRINGS  = 1 << 6,
    ACC_BEARD     = 1 << 7,
    ACC_BOWTIE    = 1 << 8,
    ACC_SANDWICH  = 1 << 9,
    ACC_TIE       = 1 << 10,
    ACC_SUNGLASS  = 1 << 11,
    ACC_COLLAR    = 1 << 12,  // shirt collar under the coat
};

typedef struct {
    color_t skin, hair, coat, bg, accent;
    uint8_t hair_style;
    uint16_t acc;
} PortraitLook;

// Draws the bust in an 88x96 box at (x, y). `talking` flaps the mouth; blinking is automatic.
void draw_portrait(Canvas *c, int x, int y, const PortraitLook *look, Expr expr, bool talking, uint32_t frame);

#endif
