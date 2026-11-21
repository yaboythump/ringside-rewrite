#include <nds.h>
#include <string.h>

#include "font8.h"
#include "gfx.h"

static color_t top_px[SCREEN_W * SCREEN_H] __attribute__((aligned(4)));
static color_t bottom_px[SCREEN_W * SCREEN_H] __attribute__((aligned(4)));

Canvas g_top = { top_px };
Canvas g_bottom = { bottom_px };

// Drawing is clipped to this rectangle (the whole screen unless gfx_set_clip is used).
static int clip_x0 = 0, clip_y0 = 0, clip_x1 = SCREEN_W, clip_y1 = SCREEN_H;

void gfx_set_clip(int x, int y, int w, int h)
{
    clip_x0 = x < 0 ? 0 : x;
    clip_y0 = y < 0 ? 0 : y;
    clip_x1 = x + w > SCREEN_W ? SCREEN_W : x + w;
    clip_y1 = y + h > SCREEN_H ? SCREEN_H : y + h;
}

void gfx_reset_clip(void)
{
    gfx_set_clip(0, 0, SCREEN_W, SCREEN_H);
}

void gfx_init(void)
{
    // Both engines show a 16-bit bitmap background: main engine on the top
    // screen, sub engine on the bottom (touch) screen.
    videoSetMode(MODE_5_2D);
    videoSetModeSub(MODE_5_2D);
    vramSetBankA(VRAM_A_MAIN_BG);
    vramSetBankC(VRAM_C_SUB_BG);
    bgInit(3, BgType_Bmp16, BgSize_B16_256x256, 0, 0);
    bgInitSub(3, BgType_Bmp16, BgSize_B16_256x256, 0, 0);
    lcdMainOnTop();
}

void gfx_present(void)
{
    DC_FlushRange(top_px, sizeof(top_px));
    DC_FlushRange(bottom_px, sizeof(bottom_px));
    dmaCopy(top_px, BG_GFX, sizeof(top_px));
    dmaCopy(bottom_px, BG_GFX_SUB, sizeof(bottom_px));
}

void gfx_copy(Canvas *dst, const color_t *src)
{
    memcpy(dst->px, src, sizeof(top_px));
}

void gfx_clear(Canvas *c, color_t color)
{
    uint32_t v = color | ((uint32_t)color << 16);
    uint32_t *p = (uint32_t *)c->px;
    for (int i = 0; i < SCREEN_W * SCREEN_H / 2; i++)
        p[i] = v;
}

void fill_rect(Canvas *c, int x, int y, int w, int h, color_t color)
{
    if (x < clip_x0) { w -= clip_x0 - x; x = clip_x0; }
    if (y < clip_y0) { h -= clip_y0 - y; y = clip_y0; }
    if (x + w > clip_x1) w = clip_x1 - x;
    if (y + h > clip_y1) h = clip_y1 - y;
    if (w <= 0 || h <= 0)
        return;
    for (int j = y; j < y + h; j++) {
        color_t *row = c->px + j * SCREEN_W + x;
        for (int i = 0; i < w; i++)
            row[i] = color;
    }
}

void hline(Canvas *c, int x, int y, int w, color_t color) { fill_rect(c, x, y, w, 1, color); }
void vline(Canvas *c, int x, int y, int h, color_t color) { fill_rect(c, x, y, 1, h, color); }

void frame_rect(Canvas *c, int x, int y, int w, int h, color_t color)
{
    hline(c, x, y, w, color);
    hline(c, x, y + h - 1, w, color);
    vline(c, x, y, h, color);
    vline(c, x + w - 1, y, h, color);
}

void plot(Canvas *c, int x, int y, color_t color)
{
    if (x >= clip_x0 && y >= clip_y0 && x < clip_x1 && y < clip_y1)
        c->px[y * SCREEN_W + x] = color;
}

void fill_circle(Canvas *c, int cx, int cy, int r, color_t color)
{
    for (int dy = -r; dy <= r; dy++)
        for (int dx = -r; dx <= r; dx++)
            if (dx * dx + dy * dy <= r * r + r)
                plot(c, cx + dx, cy + dy, color);
}

void fill_ellipse(Canvas *c, int cx, int cy, int rx, int ry, color_t color)
{
    if (rx <= 0 || ry <= 0)
        return;
    for (int dy = -ry; dy <= ry; dy++) {
        // Half-width of this row: rx * sqrt(1 - (dy/ry)^2), in integers.
        int w = 0;
        while (w <= rx && (w * w) * (ry * ry) + (dy * dy) * (rx * rx) <= (rx * rx) * (ry * ry) + rx * ry)
            w++;
        if (w > 0)
            fill_rect(c, cx - (w - 1), cy + dy, 2 * (w - 1) + 1, 1, color);
    }
}

void panel(Canvas *c, int x, int y, int w, int h, color_t fill, color_t border)
{
    // Rounded-corner box: border with the corner pixels cut away.
    fill_rect(c, x + 1, y + 1, w - 2, h - 2, fill);
    hline(c, x + 1, y, w - 2, border);
    hline(c, x + 1, y + h - 1, w - 2, border);
    vline(c, x, y + 1, h - 2, border);
    vline(c, x + w - 1, y + 1, h - 2, border);
}

void darken(Canvas *c, int x, int y, int w, int h, int steps)
{
    if (x < 0) { w += x; x = 0; }
    if (y < 0) { h += y; y = 0; }
    if (x + w > SCREEN_W) w = SCREEN_W - x;
    if (y + h > SCREEN_H) h = SCREEN_H - y;
    if (w <= 0 || h <= 0 || steps <= 0)
        return;
    // Shifting each channel right drops brightness; the mask keeps channels apart.
    static const color_t masks[4] = { 0x7FFF, 0x3DEF, 0x1CE7, 0x0C63 };
    color_t m = masks[steps > 3 ? 3 : steps];
    for (int j = y; j < y + h; j++) {
        color_t *row = c->px + j * SCREEN_W + x;
        for (int i = 0; i < w; i++)
            row[i] = ((row[i] >> steps) & m) | 0x8000;
    }
}

void draw_text_scaled(Canvas *c, int x, int y, const char *s, color_t color, int scale)
{
    for (; *s; s++, x += 8 * scale) {
        unsigned ch = (unsigned char)*s;
        if (ch < 32 || ch > 127)
            ch = '?';
        const unsigned char *g = FONT8[ch - 32];
        for (int row = 0; row < 8; row++) {
            unsigned bits = g[row];
            for (int col = 0; col < 8; col++) {
                if (bits & (0x80 >> col)) {
                    if (scale == 1)
                        plot(c, x + col, y + row, color);
                    else
                        fill_rect(c, x + col * scale, y + row * scale, scale, scale, color);
                }
            }
        }
    }
}

void draw_text(Canvas *c, int x, int y, const char *s, color_t color)
{
    draw_text_scaled(c, x, y, s, color, 1);
}

int text_width(const char *s, int scale)
{
    return (int)strlen(s) * 8 * scale;
}

void draw_text_center(Canvas *c, int cx, int y, const char *s, color_t color, int scale)
{
    draw_text_scaled(c, cx - text_width(s, scale) / 2, y, s, color, scale);
}

void pal_set(Palette *p, char key, color_t color)
{
    for (int i = 0; i < p->n; i++) {
        if (p->e[i].key == key) {
            p->e[i].color = color;
            return;
        }
    }
    if (p->n < PAL_MAX) {
        p->e[p->n].key = key;
        p->e[p->n].color = color;
        p->n++;
    }
}

static bool pal_lookup(const Palette *p, char key, color_t *out)
{
    for (int i = 0; i < p->n; i++) {
        if (p->e[i].key == key) {
            *out = p->e[i].color;
            return true;
        }
    }
    return false;
}

void draw_sprite_scaled(Canvas *c, int x, int y, const Sprite *s, const Palette *pal, bool flip, int scale)
{
    for (int j = 0; j < s->h; j++) {
        const char *row = s->rows[j];
        for (int i = 0; i < s->w; i++) {
            char k = row[flip ? s->w - 1 - i : i];
            color_t col;
            if (k == '.' || !pal_lookup(pal, k, &col))
                continue;
            if (scale == 1)
                plot(c, x + i, y + j, col);
            else
                fill_rect(c, x + i * scale, y + j * scale, scale, scale, col);
        }
    }
}

void draw_sprite(Canvas *c, int x, int y, const Sprite *s, const Palette *pal, bool flip)
{
    draw_sprite_scaled(c, x, y, s, pal, flip, 1);
}

char *str_cat(char *dst, const char *src)
{
    char *d = dst + strlen(dst);
    while ((*d++ = *src++))
        ;
    return dst;
}

char *str_cat_int(char *dst, int value)
{
    char tmp[12];
    int n = 0;
    unsigned v = value < 0 ? -(unsigned)value : (unsigned)value;
    do {
        tmp[n++] = '0' + v % 10;
        v /= 10;
    } while (v);
    char *d = dst + strlen(dst);
    if (value < 0)
        *d++ = '-';
    while (n)
        *d++ = tmp[--n];
    *d = 0;
    return dst;
}

void format_money(char *buf, int amount)
{
    char digits[12];
    int n = 0;
    unsigned v = amount < 0 ? -(unsigned)amount : (unsigned)amount;
    do {
        digits[n++] = '0' + v % 10;
        v /= 10;
    } while (v);
    char *d = buf;
    if (amount < 0)
        *d++ = '-';
    *d++ = '$';
    for (int i = n - 1; i >= 0; i--) {
        *d++ = digits[i];
        if (i > 0 && i % 3 == 0)
            *d++ = ',';
    }
    *d = 0;
}
