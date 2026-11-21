#include "art.h"
#include "portrait.h"

static int chan(color_t c, int shift) { return (c >> shift) & 31; }

// Darker (d > 0) or lighter (d < 0) version of a colour.
static color_t shade(color_t c, int d)
{
    int r = chan(c, 0) - d, g = chan(c, 5) - d, b = chan(c, 10) - d;
    r = r < 0 ? 0 : r > 31 ? 31 : r;
    g = g < 0 ? 0 : g > 31 ? 31 : g;
    b = b < 0 ? 0 : b > 31 ? 31 : b;
    return RGB(r, g, b);
}

static void thick_line(Canvas *c, int x0, int y0, int x1, int y1, int t, color_t col)
{
    int steps = (x1 > x0 ? x1 - x0 : x0 - x1);
    int dy = y1 - y0;
    if (steps < (dy < 0 ? -dy : dy))
        steps = dy < 0 ? -dy : dy;
    if (steps == 0)
        steps = 1;
    for (int i = 0; i <= steps; i++) {
        int x = x0 + (x1 - x0) * i / steps, y = y0 + dy * i / steps;
        fill_rect(c, x, y, t, t, col);
    }
}

static void eye(Canvas *c, int ex, int ey, int side, Expr expr, bool blink, uint16_t acc, color_t skin)
{
    if (acc & ACC_SUNGLASS)
        return;   // drawn over later
    if (blink) {
        fill_rect(c, ex - 4, ey, 9, 2, C_INK);
        return;
    }
    switch (expr) {
    case EXPR_HAPPY:
        thick_line(c, ex - 4, ey + 1, ex, ey - 2, 2, C_INK);
        thick_line(c, ex, ey - 2, ex + 4, ey + 1, 2, C_INK);
        break;
    case EXPR_SHOCK:
        fill_circle(c, ex, ey, 5, C_WHITE);
        fill_rect(c, ex - 1, ey - 1, 3, 3, C_INK);
        break;
    case EXPR_SMUG:
        fill_ellipse(c, ex, ey + 1, 5, 3, C_WHITE);
        fill_rect(c, ex - 5, ey - 2, 11, 3, shade(skin, 3));   // heavy lids
        hline(c, ex - 5, ey + 1, 11, C_INK);
        fill_rect(c, ex + side * 2 - 1, ey + 1, 3, 3, C_INK);   // side-eye
        break;
    default:
        fill_ellipse(c, ex, ey, 5, 4, C_WHITE);
        fill_rect(c, ex - 1, ey - 2 + (expr == EXPR_SAD), 3, 4, C_INK);
        plot(c, ex, ey - 1 + (expr == EXPR_SAD), C_WHITE);
        break;
    }
}

static void brows(Canvas *c, int hx, int ey, Expr expr, color_t col)
{
    for (int side = -1; side <= 1; side += 2) {
        int inner = hx + side * 5, outer = hx + side * 15;
        int yi = ey - 8, yo = ey - 8;
        switch (expr) {
        case EXPR_ANGRY: yi = ey - 5; yo = ey - 10; break;
        case EXPR_SAD: yi = ey - 11; yo = ey - 7; break;
        case EXPR_SHOCK: yi = yo = ey - 12; break;
        case EXPR_SMUG: if (side > 0) { yi = yo = ey - 11; } break;
        default: break;
        }
        thick_line(c, inner, yi, outer, yo, 2, col);
    }
}

static void mouth(Canvas *c, int mx, int my, Expr expr, bool open, color_t skin)
{
    color_t lip = RGB(18, 5, 7);
    if (open) {
        int ry = expr == EXPR_SHOCK ? 6 : 4;
        fill_ellipse(c, mx, my + 1, 6, ry, lip);
        fill_ellipse(c, mx, my + ry - 1, 3, 1, RGB(29, 12, 14));
        if (expr == EXPR_HAPPY || expr == EXPR_SMUG)
            hline(c, mx - 4, my - 2, 9, C_WHITE);
        return;
    }
    switch (expr) {
    case EXPR_HAPPY:
        for (int dx = -7; dx <= 7; dx++)
            fill_rect(c, mx + dx, my + 2 - (dx * dx) / 16, 1, 2, lip);
        break;
    case EXPR_SHOCK:
        fill_ellipse(c, mx, my + 2, 3, 4, lip);
        break;
    case EXPR_SMUG:
        thick_line(c, mx - 5, my + 2, mx + 6, my - 1, 2, lip);
        break;
    case EXPR_ANGRY:
        fill_rect(c, mx - 6, my, 13, 4, lip);
        hline(c, mx - 5, my + 1, 11, C_WHITE);
        vline(c, mx - 2, my + 1, 2, lip);
        vline(c, mx + 2, my + 1, 2, lip);
        break;
    case EXPR_SAD:
        for (int dx = -6; dx <= 6; dx++)
            fill_rect(c, mx + dx, my + (dx * dx) / 14, 1, 2, lip);
        break;
    default:
        fill_rect(c, mx - 5, my + 1, 11, 2, lip);
        break;
    }
    (void)skin;
}

void draw_portrait(Canvas *c, int x, int y, const PortraitLook *L, Expr expr, bool talking, uint32_t frame)
{
    bool ghost = L->acc & ACC_GHOST;
    int bob = ghost ? ((frame / 10) % 4 == 0 ? 0 : (frame / 10) % 4 == 2 ? 2 : 1) : 0;
    gfx_set_clip(x, y, PORTRAIT_W, PORTRAIT_H);

    // Backdrop with diagonal stripes
    fill_rect(c, x, y, PORTRAIT_W, PORTRAIT_H, L->bg);
    for (int k = -PORTRAIT_H; k < PORTRAIT_W; k += 12)
        for (int j = 0; j < PORTRAIT_H; j++)
            if (((j + k) & 7) < 3 && x + k + j >= x)
                plot(c, x + k + j, y + j, shade(L->bg, -2));

    int hx = x + 44, hy = y + 42 + bob;
    color_t skin = L->skin, hair = L->hair;

    // Hair behind the head
    switch (L->hair_style) {
    case HAIR_LONG: fill_ellipse(c, hx, hy + 6, 31, 34, hair); fill_rect(c, hx - 30, hy + 6, 61, 46, hair); break;
    case HAIR_BOB: fill_ellipse(c, hx, hy + 2, 31, 31, hair); break;
    case HAIR_BIG: fill_ellipse(c, hx, hy - 6, 38, 34, hair); break;
    case HAIR_BUN: fill_circle(c, hx, hy - 36, 10, hair); break;
    default: break;
    }

    // Shoulders (a fading tail for ghosts)
    for (int j = 0; j < 24; j++) {
        int w = 56 + j + j / 2;
        int sy = y + 72 + j + bob;
        if (ghost && ((j / 3 + (int)(frame / 6)) % 4 == 0 || j > 14))
            continue;
        fill_rect(c, hx - w / 2, sy, w, 1, L->coat);
    }
    fill_rect(c, hx - 8, hy + 20, 17, 14, shade(skin, 4));       // neck in shadow
    if (L->acc & ACC_COLLAR) {
        for (int k = 0; k < 8; k++) {
            hline(c, hx - 14 + k, hy + 30 + k, 6, C_WHITE);
            hline(c, hx + 9 - k, hy + 30 + k, 6, C_WHITE);
        }
    }
    if (L->acc & ACC_TIE) {
        fill_rect(c, hx - 2, hy + 32, 5, 4, L->accent);
        for (int k = 0; k < 14; k++)
            hline(c, hx - 2 - k / 5, hy + 36 + k, 5 + 2 * (k / 5), L->accent);
    }
    if (L->acc & ACC_BOWTIE) {
        for (int k = 0; k < 5; k++) {
            vline(c, hx - 8 + k, hy + 33 - k / 2, 3 + k, L->accent);
            vline(c, hx + 8 - k, hy + 33 - k / 2, 3 + k, L->accent);
        }
        fill_rect(c, hx - 2, hy + 33, 5, 4, shade(L->accent, 6));
    }
    if (L->acc & ACC_PEARLS)
        for (int k = -5; k <= 5; k++)
            fill_circle(c, hx + k * 3, hy + 33 + (k * k) / 6, 1, C_WHITE);

    // Ears, head, jaw shadow
    fill_ellipse(c, hx - 24, hy + 2, 4, 6, shade(skin, 2));
    fill_ellipse(c, hx + 24, hy + 2, 4, 6, shade(skin, 2));
    if (L->acc & ACC_EARRINGS) {
        fill_circle(c, hx - 25, hy + 10, 2, L->accent);
        fill_circle(c, hx + 25, hy + 10, 2, L->accent);
    }
    fill_ellipse(c, hx, hy, 24, 28, skin);
    fill_ellipse(c, hx + 6, hy + 4, 14, 22, shade(skin, -1));    // soft highlight

    // Hair on top
    switch (L->hair_style) {
    case HAIR_BALD:
        fill_ellipse(c, hx - 22, hy - 6, 4, 8, hair);
        fill_ellipse(c, hx + 22, hy - 6, 4, 8, hair);
        fill_ellipse(c, hx - 8, hy - 20, 5, 2, shade(skin, -4));   // shine
        break;
    case HAIR_POMP:
        fill_ellipse(c, hx, hy - 20, 25, 12, hair);
        fill_ellipse(c, hx - 4, hy - 30, 20, 10, hair);
        fill_ellipse(c, hx - 8, hy - 32, 9, 3, shade(hair, -6));
        break;
    case HAIR_BIG:
        fill_ellipse(c, hx, hy - 22, 24, 10, hair);
        fill_circle(c, hx - 22, hy - 14, 8, hair);
        fill_circle(c, hx + 22, hy - 14, 8, hair);
        break;
    case HAIR_CAP:
        fill_ellipse(c, hx, hy - 18, 26, 14, L->accent);
        fill_rect(c, hx - 26, hy - 18, 53, 6, L->accent);
        fill_rect(c, hx + 16, hy - 14, 16, 4, shade(L->accent, 5));   // brim, worn backwards
        fill_circle(c, hx, hy - 30, 2, shade(L->accent, 6));
        fill_rect(c, hx - 26, hy - 12, 6, 10, hair);
        break;
    default:
        fill_ellipse(c, hx, hy - 18, 26, 14, hair);
        fill_rect(c, hx - 25, hy - 18, 6, 18, hair);
        fill_rect(c, hx + 20, hy - 18, 6, 18, hair);
        fill_ellipse(c, hx - 6, hy - 24, 10, 3, shade(hair, -5));
        break;
    }

    // Face
    int ey = hy + 1;
    if (L->acc & ACC_BEARD)
        fill_ellipse(c, hx, hy + 18, 20, 12, hair);
    bool blink = (frame % 200) < 6;
    eye(c, hx - 10, ey, -1, expr, blink, L->acc, skin);
    eye(c, hx + 10, ey, 1, expr, blink, L->acc, skin);
    brows(c, hx, ey, expr, L->hair_style == HAIR_BALD || L->hair_style == HAIR_CAP ? shade(hair, 4) : shade(hair, 3));
    if (L->acc & ACC_GLASSES) {
        frame_rect(c, hx - 17, ey - 5, 14, 11, C_INK);
        frame_rect(c, hx + 3, ey - 5, 14, 11, C_INK);
        hline(c, hx - 3, ey - 2, 6, C_INK);
    }
    if (L->acc & ACC_SUNGLASS) {
        fill_rect(c, hx - 18, ey - 5, 15, 9, C_BLACK);
        fill_rect(c, hx + 3, ey - 5, 15, 9, C_BLACK);
        hline(c, hx - 3, ey - 3, 6, C_BLACK);
        hline(c, hx - 16, ey - 3, 5, C_GREY);
        hline(c, hx + 5, ey - 3, 5, C_GREY);
    }
    vline(c, hx + 1, ey + 4, 6, shade(skin, 5));          // nose
    hline(c, hx - 1, ey + 10, 4, shade(skin, 5));
    if (expr == EXPR_HAPPY || expr == EXPR_SHOCK || (L->acc & ACC_FRECKLES)) {
        fill_ellipse(c, hx - 15, hy + 9, 4, 2, RGB(31, 17, 17));
        fill_ellipse(c, hx + 15, hy + 9, 4, 2, RGB(31, 17, 17));
    }
    if (L->acc & ACC_FRECKLES)
        for (int k = 0; k < 6; k++)
            plot(c, hx - 18 + (k % 3) * 3 + (k / 3) * 26, hy + 8 + (k % 2) * 2, shade(skin, 8));
    bool open = talking && (frame / 4) % 2;
    mouth(c, hx, hy + 15, expr, open, skin);
    if (L->acc & ACC_MUSTACHE) {
        fill_ellipse(c, hx - 6, hy + 12, 7, 3, hair);
        fill_ellipse(c, hx + 6, hy + 12, 7, 3, hair);
    }
    if (expr == EXPR_SAD && (frame / 20) % 3 == 0)
        fill_rect(c, hx - 13, ey + 5 + (int)(frame % 20) / 3, 2, 3, RGB(14, 22, 31));
    if (expr == EXPR_ANGRY)
        for (int k = 0; k < 3; k++)
            thick_line(c, hx + 22 + k * 3, hy - 30, hx + 24 + k * 3, hy - 24, 1, C_RED);

    // The hat (it deserves its own scope)
    if (L->acc & ACC_HAT) {
        fill_ellipse(c, hx, hy - 22, 40, 7, L->accent);
        fill_ellipse(c, hx, hy - 30, 22, 10, L->accent);
        fill_rect(c, hx - 22, hy - 28, 45, 4, shade(L->accent, 6));
        for (int k = 0; k < 22; k++)
            fill_rect(c, hx + 14 + k, hy - 34 - (k * k) / 14, 3, 2, C_GOLD);
    }
    if (L->acc & ACC_SANDWICH) {
        int sx = x + 60, sy = y + 70 + bob;
        fill_rect(c, sx, sy, 22, 4, RGB(29, 22, 12));
        fill_rect(c, sx + 1, sy + 4, 20, 2, RGB(8, 24, 6));
        fill_rect(c, sx + 1, sy + 6, 20, 2, RGB(28, 10, 10));
        fill_rect(c, sx, sy + 8, 22, 4, RGB(29, 22, 12));
        fill_rect(c, sx + 18, sy, 4, 3, L->bg);   // bite
    }
    if (ghost) {
        // See-through: let the backdrop show through every other pixel of the lower body,
        // and give the whole spirit a pale glow line.
        for (int j = y + 60; j < y + PORTRAIT_H; j++)
            for (int i = x + ((j + (int)frame / 8) & 1); i < x + PORTRAIT_W; i += 2)
                if (c->px[j * SCREEN_W + i] == L->coat)
                    c->px[j * SCREEN_W + i] = L->bg;
        frame_rect(c, x + 1, y + 1, PORTRAIT_W - 2, PORTRAIT_H - 2, RGB(20, 28, 31));
    }
    gfx_reset_clip();
    frame_rect(c, x, y, PORTRAIT_W, PORTRAIT_H, C_CREAM);
}
