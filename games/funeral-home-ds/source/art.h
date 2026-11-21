// Characters, props and the procedural bits (caskets, faces, outfits).
#ifndef ART_H
#define ART_H

#include "game.h"
#include "gfx.h"

// Shared colours.
#define C_BLACK   RGB(2, 2, 3)
#define C_INK     RGB(4, 3, 6)
#define C_WHITE   RGB(31, 31, 31)
#define C_CREAM   RGB(30, 28, 23)
#define C_PAPER   RGB(27, 25, 20)
#define C_GOLD    RGB(31, 24, 6)
#define C_RED     RGB(28, 5, 5)
#define C_GREEN   RGB(6, 22, 8)
#define C_BLUE    RGB(6, 12, 28)
#define C_GREY    RGB(16, 16, 17)
#define C_DIM     RGB(19, 16, 22)
#define C_PLUM    RGB(7, 3, 10)
#define C_PLUM2   RGB(11, 6, 15)

typedef struct {
    color_t coat, hair, skin, pants;
    bool long_hair;
} Look;

#define SKIN_C0 RGB(31, 24, 19)
#define SKIN_C1 RGB(28, 20, 14)
#define SKIN_C2 RGB(23, 15, 9)
#define SKIN_C3 RGB(17, 10, 6)
#define SKIN_C4 RGB(11, 7, 4)
#define SKIN_TONES 5
extern const color_t SKIN[SKIN_TONES];

void draw_person(Canvas *c, int x, int feet_y, const Look *look, int walk_frame, bool flip, color_t tie);
void draw_casket(Canvas *c, int x, int y, int type, int lid_open, bool taped);
void draw_casket_icon(Canvas *c, int x, int y, int type);
// Face with makeup applied on covered cells (cells == NULL means fully made up when style >= 0).
// Cells are (2r+7)/8 pixels square, the 8x8 grid centred on the face.
int face_cell_size(int r);
void draw_face(Canvas *c, int cx, int cy, int r, color_t skin, color_t hair, bool long_hair,
               int style, const uint8_t *cells);
void draw_outfit(Canvas *c, int x, int y, int w, int h, int outfit, uint32_t frame);
void draw_flowers(Canvas *c, int x, int y, int shake);
void draw_raccoon(Canvas *c, int x, int y, bool flip, int frame);
void draw_umbrella(Canvas *c, int x, int y);
void draw_candle(Canvas *c, int x, int y, uint32_t frame);
void draw_note(Canvas *c, int x, int y, color_t color);
void draw_star(Canvas *c, int x, int y, bool filled);
void draw_bubble(Canvas *c, int x, int y, const char *text, color_t fill, color_t ink);

#endif
