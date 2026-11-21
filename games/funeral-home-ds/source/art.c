#include <string.h>

#include "art.h"

const color_t SKIN[SKIN_TONES] = { SKIN_C0, SKIN_C1, SKIN_C2, SKIN_C3, SKIN_C4 };

// ---------------------------------------------------------------------------
// People: 10x20, assembled from a head, a body and a pair of legs.

static const char *const HEAD_SHORT[7] = {
    "...hhhh...",
    "..hhhhhh..",
    "..hssssh..",
    "..skssks..",
    "..ssssss..",
    "...sees...",
    "....ss....",
};
static const char *const HEAD_LONG[7] = {
    "...hhhh...",
    "..hhhhhh..",
    ".hhsssshh.",
    ".hskssksh.",
    ".hssssssh.",
    ".hhseeshh.",
    ".hh.ss.hh.",
};
static const char *const BODY[6] = {
    ".cccwwccc.",
    "ccccwtcccc",
    "ccccwtcccc",
    "sccccccccs",
    "s.cccccc.s",
    "..cccccc..",
};
static const char *const LEGS_STAND[7] = {
    "..pppppp..",
    "..pp..pp..",
    "..pp..pp..",
    "..pp..pp..",
    "..pp..pp..",
    "..pp..pp..",
    ".bbb..bbb.",
};
static const char *const LEGS_STEP[7] = {
    "...pppp...",
    "..pp..pp..",
    ".pp....pp.",
    ".pp....pp.",
    ".p......p.",
    ".p......p.",
    "bb......bb",
};

void draw_person(Canvas *c, int x, int feet_y, const Look *look, int walk_frame, bool flip, color_t tie)
{
    const char *rows[20];
    memcpy(rows, look->long_hair ? HEAD_LONG : HEAD_SHORT, sizeof(char *) * 7);
    memcpy(rows + 7, BODY, sizeof(char *) * 6);
    memcpy(rows + 13, walk_frame ? LEGS_STEP : LEGS_STAND, sizeof(char *) * 7);
    Sprite s = { 10, 20, rows };
    Palette p = { .n = 0 };
    pal_set(&p, 'h', look->hair);
    pal_set(&p, 's', look->skin);
    pal_set(&p, 'k', C_BLACK);
    pal_set(&p, 'e', RGB(18, 6, 8));
    pal_set(&p, 'c', look->coat);
    pal_set(&p, 'w', C_WHITE);
    pal_set(&p, 't', tie);
    pal_set(&p, 'p', look->pants);
    pal_set(&p, 'b', C_BLACK);
    draw_sprite(c, x - 5, feet_y - 20, &s, &p, flip);
}

// ---------------------------------------------------------------------------
// Caskets, drawn with rectangles: 56x16 with the lid on top.

typedef struct { color_t main, light, dark, trim; } Wood;

static Wood casket_wood(int type)
{
    switch (type) {
    case CASKET_PINE: return (Wood){ RGB(26, 19, 10), RGB(30, 25, 15), RGB(17, 11, 5), RGB(9, 9, 9) };
    case CASKET_OAK:  return (Wood){ RGB(15, 8, 4), RGB(21, 12, 6), RGB(8, 4, 2), C_GOLD };
    default:          return (Wood){ RGB(28, 21, 4), RGB(31, 29, 14), RGB(18, 12, 2), C_WHITE };
    }
}

void draw_casket(Canvas *c, int x, int y, int type, int lid_lift, bool taped)
{
    Wood w = casket_wood(type);
    // Body
    fill_rect(c, x, y + 6, 56, 10, w.main);
    hline(c, x, y + 6, 56, w.light);
    hline(c, x, y + 15, 56, w.dark);
    vline(c, x, y + 6, 10, w.dark);
    vline(c, x + 55, y + 6, 10, w.dark);
    hline(c, x + 4, y + 10, 48, w.trim);
    for (int i = 0; i < 3; i++)
        fill_rect(c, x + 8 + i * 18, y + 9, 4, 3, w.trim);
    if (lid_lift > 0) {
        // Satin lining shows while the lid is up.
        fill_rect(c, x + 2, y + 3, 52, 4, C_CREAM);
        hline(c, x + 2, y + 6, 52, RGB(26, 22, 24));
    }
    // Lid: a rounded slab.
    int ly = y - lid_lift;
    fill_rect(c, x + 2, ly + 1, 52, 5, w.main);
    hline(c, x + 4, ly, 48, w.light);
    hline(c, x + 2, ly + 5, 52, w.dark);
    plot(c, x + 3, ly + 1, w.light);
    plot(c, x + 52, ly + 1, w.light);
    if (taped) {
        for (int i = 0; i < 3; i++) {
            fill_rect(c, x + 10 + i * 16, ly - 1, 4, 12, RGB(21, 21, 22));
            vline(c, x + 11 + i * 16, ly - 1, 12, RGB(26, 26, 27));
        }
    }
}

void draw_casket_icon(Canvas *c, int x, int y, int type)
{
    draw_casket(c, x, y, type, 0, false);
}

// ---------------------------------------------------------------------------
// Faces (the guest of honour, eyes peacefully closed).

static void face_layer(Canvas *c, int cx, int cy, int r, color_t skin, int style)
{
    int hairline = cy - r / 3;
    int eye_dx = r / 3, eye_y = cy - r / 8, eye_w = r / 4 > 1 ? r / 4 : 2;
    int t = r / 10 > 0 ? r / 10 : 1;      // stroke thickness
    if (style == MAKEUP_CLOWN) {
        // Greasepaint below the hairline.
        for (int dy = hairline - cy; dy <= r; dy++)
            for (int dx = -r; dx <= r; dx++)
                if (dx * dx + dy * dy <= (r - 1) * (r - 1))
                    plot(c, cx + dx, cy + dy, C_WHITE);
        for (int s = -1; s <= 1; s += 2) {
            int ex = cx + s * eye_dx;
            for (int d = 0; d <= eye_w; d++) {
                vline(c, ex - d, eye_y - (eye_w - d), 2 * (eye_w - d) + 1, C_BLUE);
                vline(c, ex + d, eye_y - (eye_w - d), 2 * (eye_w - d) + 1, C_BLUE);
            }
            fill_circle(c, cx + s * (r / 2 + 1), cy + r / 3, r / 6, RGB(31, 12, 12));
        }
        // Huge grin
        for (int dx = -r / 2; dx <= r / 2; dx++) {
            int yy = cy + r / 2 + (r / 2 - (dx < 0 ? -dx : dx)) / 3;
            fill_rect(c, cx + dx, yy - t, 1, 2 * t + 1, C_RED);
        }
        fill_circle(c, cx, cy + r / 8 + 1, r / 5 > 1 ? r / 5 : 2, C_RED);
    } else if (style == MAKEUP_GLAM) {
        for (int s = -1; s <= 1; s += 2)
            fill_rect(c, cx + s * eye_dx - eye_w, eye_y - 2 * t - 1, 2 * eye_w + 1, 2 * t + 1, RGB(10, 14, 30));
        fill_rect(c, cx - r / 4, cy + r / 2 - t, r / 2 + 1, 2 * t + 1, RGB(29, 2, 8));
        plot(c, cx + r / 2, cy + r / 4, C_BLACK);
        for (int s = -1; s <= 1; s += 2)
            fill_circle(c, cx + s * (r / 2 + 1), cy + r / 4, r / 7, RGB(31, 16, 19));
    } else if (style == MAKEUP_NATURAL) {
        for (int s = -1; s <= 1; s += 2)
            fill_circle(c, cx + s * (r / 2 + 1), cy + r / 4, r / 6, RGB(31, 19, 18));
        fill_rect(c, cx - r / 5, cy + r / 2 - t / 2, 2 * (r / 5) + 1, t + 1, RGB(25, 11, 12));
    }
    (void)skin;
    // Closed eyes, drawn last so they sit on top of any paint.
    for (int s = -1; s <= 1; s += 2) {
        fill_rect(c, cx + s * eye_dx - eye_w, eye_y, 2 * eye_w + 1, t, C_INK);
        if (style == MAKEUP_GLAM)
            for (int k = -eye_w; k <= eye_w; k += 2)
                plot(c, cx + s * eye_dx + k, eye_y + t, C_INK);
    }
}

int face_cell_size(int r)
{
    return (2 * r + 7) / 8;
}

void draw_face(Canvas *c, int cx, int cy, int r, color_t skin, color_t hair, bool long_hair,
               int style, const uint8_t *cells)
{
    if (long_hair)
        fill_circle(c, cx, cy + r / 3, r + r / 6, hair);
    fill_circle(c, cx, cy, r, skin);
    // Hair cap
    int hairline = cy - r / 3;
    for (int dy = -r; dy < hairline - cy; dy++)
        for (int dx = -r; dx <= r; dx++)
            if (dx * dx + dy * dy <= r * r + r)
                plot(c, cx + dx, cy + dy, hair);
    // Unpainted features
    face_layer(c, cx, cy, r, skin, -1);
    fill_rect(c, cx - r / 6, cy + r / 2, r / 3 + 1, 1, RGB(20, 10, 10));
    if (style < 0)
        return;
    // The painted face is drawn once into a scratch canvas and cached; covered
    // cells are then copied across. Repainting per cell was far too slow.
    typedef struct { int cx, cy, r, style; color_t skin; bool used; } FaceKey;
    enum { CACHE = 3 };
    static color_t scratch[CACHE][SCREEN_W * SCREEN_H];
    static FaceKey keys[CACHE];
    static int next_slot;
    int slot = -1;
    for (int k = 0; k < CACHE; k++)
        if (keys[k].used && keys[k].cx == cx && keys[k].cy == cy && keys[k].r == r && keys[k].style == style && keys[k].skin == skin)
            slot = k;
    int cell = face_cell_size(r);
    int ox = cx - 4 * cell, oy = cy - 4 * cell;
    if (slot < 0) {
        slot = next_slot;
        next_slot = (next_slot + 1) % CACHE;
        keys[slot] = (FaceKey){ cx, cy, r, style, skin, true };
        Canvas tmp = { scratch[slot] };
        // Fill the face's bounding box with a key colour (no alpha bit) and paint.
        gfx_set_clip(ox, oy, 8 * cell, 8 * cell);
        fill_rect(&tmp, ox, oy, 8 * cell, 8 * cell, 0);
        face_layer(&tmp, cx, cy, r, skin, style);
        gfx_reset_clip();
    }
    const color_t *src = scratch[slot];
    for (int j = 0; j < MAKEUP_GRID; j++) {
        for (int i = 0; i < MAKEUP_GRID; i++) {
            if (cells && !cells[j * MAKEUP_GRID + i])
                continue;
            for (int y = oy + j * cell; y < oy + (j + 1) * cell; y++) {
                if (y < 0 || y >= SCREEN_H)
                    continue;
                for (int x = ox + i * cell; x < ox + (i + 1) * cell; x++) {
                    if (x < 0 || x >= SCREEN_W)
                        continue;
                    color_t v = src[y * SCREEN_W + x];
                    if (v & 0x8000)
                        c->px[y * SCREEN_W + x] = v;
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Outfits fill a rectangle with a pattern.

void draw_outfit(Canvas *c, int x, int y, int w, int h, int outfit, uint32_t frame)
{
    switch (outfit) {
    case OUTFIT_SUIT:
        fill_rect(c, x, y, w, h, RGB(4, 5, 11));
        for (int j = 0; j < h / 2; j++)
            hline(c, x + w / 2 - (h / 2 - j) / 2, y + j, h / 2 - j + 1, C_WHITE);
        fill_rect(c, x + w / 2 - 1, y + 2, 3, h / 2, C_RED);
        for (int j = h / 2 + 2; j < h - 2; j += 5)
            plot(c, x + w / 2 - 4, y + j, C_GREY);
        break;
    case OUTFIT_FLORAL:
        fill_rect(c, x, y, w, h, RGB(22, 16, 27));
        for (int j = 2; j < h; j += 6)
            for (int i = 2 + (j / 6 % 2) * 3; i < w; i += 6) {
                fill_rect(c, x + i, y + j, 2, 2, (i + j) % 4 ? RGB(31, 14, 20) : RGB(31, 28, 8));
            }
        break;
    case OUTFIT_HAWAIIAN:
        fill_rect(c, x, y, w, h, RGB(30, 14, 4));
        for (int j = 1; j < h; j += 7)
            for (int i = 1 + (j / 7 % 2) * 4; i < w - 2; i += 8) {
                fill_rect(c, x + i, y + j, 3, 2, RGB(4, 20, 6));
                plot(c, x + i + 3, y + j + 3, C_WHITE);
                plot(c, x + i + 4, y + j + 3, RGB(31, 26, 4));
            }
        vline(c, x + w / 2, y, h, RGB(24, 10, 2));
        break;
    case OUTFIT_BOWLING:
        fill_rect(c, x, y, w, h, RGB(3, 18, 19));
        fill_rect(c, x + w / 4, y, w / 10 + 1, h, C_CREAM);
        fill_rect(c, x + (3 * w) / 4, y, w / 10 + 1, h, C_CREAM);
        fill_rect(c, x + w / 2 + 2, y + h / 4, w / 6, h / 8 + 2, C_RED);
        break;
    case OUTFIT_SEQUIN:
        fill_rect(c, x, y, w, h, RGB(27, 27, 29));
        for (int k = 0; k < (w * h) / 24; k++) {
            uint32_t v = (uint32_t)k * 2654435761u;
            int px = x + (int)(v % (uint32_t)w), py = y + (int)((v >> 12) % (uint32_t)h);
            bool lit = ((frame / 8) + k) % 3 == 0;
            plot(c, px, py, lit ? C_WHITE : C_GOLD);
            if (lit) {
                plot(c, px - 1, py, C_GOLD);
                plot(c, px + 1, py, C_GOLD);
            }
        }
        fill_rect(c, x, y + h - h / 6, w, 2, C_GOLD);
        break;
    default: // OUTFIT_CAPE
        fill_rect(c, x, y, w, h, RGB(5, 9, 26));
        fill_rect(c, x, y, w / 8 + 1, h, C_RED);
        fill_rect(c, x + w - w / 8 - 1, y, w / 8 + 1, h, C_RED);
        {
            int cx = x + w / 2, cy = y + h / 3, d = h / 5 > 2 ? h / 5 : 2;
            for (int k = 0; k <= d; k++)
                hline(c, cx - (d - k), cy - k, 2 * (d - k) + 1, C_GOLD), hline(c, cx - (d - k), cy + k, 2 * (d - k) + 1, C_GOLD);
            plot(c, cx, cy, C_RED);
        }
        break;
    }
}

// ---------------------------------------------------------------------------
// Small sprites.

static const char *const FLOWERS[16] = {
    "...r..p.....",
    "..rrrppp.y..",
    "..rr.ppyyy..",
    ".w.r.gp.y...",
    "www.ggg.g.r.",
    ".w.gg.g.grrr",
    ".g.g..g.g.r.",
    "..gg.ggg.g..",
    "...ggg.ggg..",
    "....gg.gg...",
    "...vvvvvv...",
    "...vlvvvv...",
    "....vlvv....",
    "....vvvv....",
    "...vvvvvv...",
    "..vvvvvvvv..",
};

void draw_flowers(Canvas *c, int x, int y, int shake)
{
    Sprite s = { 12, 16, FLOWERS };
    Palette p = { .n = 0 };
    pal_set(&p, 'r', RGB(29, 5, 8));
    pal_set(&p, 'p', RGB(31, 15, 22));
    pal_set(&p, 'y', RGB(31, 27, 6));
    pal_set(&p, 'w', C_WHITE);
    pal_set(&p, 'g', RGB(5, 18, 6));
    pal_set(&p, 'v', RGB(9, 9, 14));
    pal_set(&p, 'l', RGB(16, 16, 22));
    draw_sprite(c, x + shake, y, &s, &p, shake < 0);
}

static const char *const RACCOON_A[8] = {
    "..k.k.........",
    ".kggggk......d",
    "kwkggkwgggg.dg",
    "gkkggkkggggggd",
    ".gggggggggggdg",
    "..gggggggggd..",
    "..g.g...g.g...",
    "..k.k...k.k...",
};
static const char *const RACCOON_B[8] = {
    "..k.k.........",
    ".kggggk.....d.",
    "kwkggkwgggg.dg",
    "gkkggkkgggggdg",
    ".gggggggggggd.",
    "..gggggggggd..",
    "...g.g.g.g....",
    "...k.k.k.k....",
};

void draw_raccoon(Canvas *c, int x, int y, bool flip, int frame)
{
    Sprite s = { 14, 8, (frame & 1) ? RACCOON_B : RACCOON_A };
    Palette p = { .n = 0 };
    pal_set(&p, 'k', C_BLACK);
    pal_set(&p, 'g', RGB(17, 17, 18));
    pal_set(&p, 'd', RGB(7, 7, 8));
    pal_set(&p, 'w', C_WHITE);
    draw_sprite(c, x, y, &s, &p, flip);
}

static const char *const UMBRELLA[8] = {
    "......rrrr......",
    "...rrrrrrrrrr...",
    ".rrrrrrrrrrrrrr.",
    "rrrrrrrrrrrrrrrr",
    "r..rr..kk..rr..r",
    ".......k........",
    ".......k........",
    "......kk........",
};

void draw_umbrella(Canvas *c, int x, int y)
{
    Sprite s = { 16, 8, UMBRELLA };
    Palette p = { .n = 0 };
    pal_set(&p, 'r', RGB(4, 4, 6));
    pal_set(&p, 'k', RGB(20, 14, 6));
    draw_sprite(c, x, y, &s, &p, false);
}

static const char *const CANDLE[10] = {
    ".y..",
    "yoy.",
    ".o..",
    ".k..",
    "wwww",
    "wwww",
    "wwww",
    "wwww",
    "wwww",
    "kkkk",
};

void draw_candle(Canvas *c, int x, int y, uint32_t frame)
{
    Sprite s = { 4, 10, CANDLE };
    Palette p = { .n = 0 };
    pal_set(&p, 'y', (frame / 6) & 1 ? RGB(31, 31, 12) : RGB(31, 24, 4));
    pal_set(&p, 'o', RGB(31, 14, 2));
    pal_set(&p, 'k', C_BLACK);
    pal_set(&p, 'w', C_CREAM);
    draw_sprite(c, x, y, &s, &p, (frame / 9) & 1);
}

static const char *const NOTE[6] = {
    "..kk.",
    "..k.k",
    "..k..",
    "..k..",
    "kkk..",
    "kkk..",
};

void draw_note(Canvas *c, int x, int y, color_t color)
{
    Sprite s = { 5, 6, NOTE };
    Palette p = { .n = 0 };
    pal_set(&p, 'k', color);
    draw_sprite(c, x, y, &s, &p, false);
}

static const char *const STAR[9] = {
    "....y....",
    "....y....",
    "...yyy...",
    "yyyyyyyyy",
    ".yyyyyyy.",
    "..yyyyy..",
    "..yy.yy..",
    ".yy...yy.",
    ".y.....y.",
};

void draw_star(Canvas *c, int x, int y, bool filled)
{
    Sprite s = { 9, 9, STAR };
    Palette p = { .n = 0 };
    pal_set(&p, 'y', filled ? C_GOLD : RGB(10, 9, 12));
    draw_sprite_scaled(c, x, y, &s, &p, false, 2);
}

void draw_bubble(Canvas *c, int x, int y, const char *text, color_t fill, color_t ink)
{
    int w = text_width(text, 1) + 6;
    if (x + w > SCREEN_W - 1)
        x = SCREEN_W - 1 - w;
    if (x < 1)
        x = 1;
    panel(c, x, y, w, 12, fill, ink);
    draw_text(c, x + 3, y + 2, text, ink);
}
