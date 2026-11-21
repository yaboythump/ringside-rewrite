// Software drawing into two 256x192 RGB555 framebuffers (top and bottom screen).
#ifndef GFX_H
#define GFX_H

#include <stdbool.h>
#include <stdint.h>

#define SCREEN_W 256
#define SCREEN_H 192

typedef uint16_t color_t;

// Opaque RGB555 colour from 5-bit channels.
#define RGB(r, g, b) ((color_t)((r) | ((g) << 5) | ((b) << 10) | 0x8000))

typedef struct {
    color_t *px;   // SCREEN_W * SCREEN_H pixels
} Canvas;

extern Canvas g_top;
extern Canvas g_bottom;

// Sprite art: rows of characters; '.' is transparent, every other character
// is looked up in the palette passed to draw_sprite.
typedef struct {
    int w, h;
    const char *const *rows;
} Sprite;

typedef struct {
    char key;
    color_t color;
} PalEntry;

#define PAL_MAX 16
typedef struct {
    PalEntry e[PAL_MAX];
    int n;
} Palette;

void gfx_init(void);
// Copies both framebuffers to the screens. Call right after the vertical blank.
void gfx_present(void);

void gfx_set_clip(int x, int y, int w, int h);
void gfx_reset_clip(void);

void gfx_copy(Canvas *dst, const color_t *src);
void gfx_clear(Canvas *c, color_t color);
void fill_rect(Canvas *c, int x, int y, int w, int h, color_t color);
void frame_rect(Canvas *c, int x, int y, int w, int h, color_t color);
void hline(Canvas *c, int x, int y, int w, color_t color);
void vline(Canvas *c, int x, int y, int h, color_t color);
void plot(Canvas *c, int x, int y, color_t color);
void fill_circle(Canvas *c, int cx, int cy, int r, color_t color);
void fill_ellipse(Canvas *c, int cx, int cy, int rx, int ry, color_t color);
void panel(Canvas *c, int x, int y, int w, int h, color_t fill, color_t border);
// Halves the brightness of a region `steps` times (0-3) - used for power cuts and greyed buttons.
void darken(Canvas *c, int x, int y, int w, int h, int steps);

void draw_text(Canvas *c, int x, int y, const char *s, color_t color);
void draw_text_scaled(Canvas *c, int x, int y, const char *s, color_t color, int scale);
void draw_text_center(Canvas *c, int cx, int y, const char *s, color_t color, int scale);
int text_width(const char *s, int scale);

void pal_set(Palette *p, char key, color_t color);
void draw_sprite(Canvas *c, int x, int y, const Sprite *s, const Palette *pal, bool flip);
void draw_sprite_scaled(Canvas *c, int x, int y, const Sprite *s, const Palette *pal, bool flip, int scale);

// Formats dollars like "$12,345" or "-$300" into buf (at least 16 bytes).
void format_money(char *buf, int amount);
// Tiny sprintf replacements so the game needs no stdio.
char *str_cat(char *dst, const char *src);
char *str_cat_int(char *dst, int value);

#endif
