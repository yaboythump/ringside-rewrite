// Game rules and the touch screen (bookings, prep, quick fixes, money).
#include <nds.h>
#include <string.h>

#include "art.h"
#include "game.h"
#include "gfx.h"
#include "scene.h"
#include "sfx.h"

Game g;

// ---------------------------------------------------------------------------
// Helpers

uint32_t rng_next(void)
{
    uint32_t x = g.rng;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    return g.rng = x;
}

int rng_range(int n)
{
    return (int)(rng_next() % (uint32_t)n);
}

Funeral *current_funeral(void)
{
    return &g.funerals[g.current < FUNERALS_PER_DAY ? g.current : FUNERALS_PER_DAY - 1];
}

bool prep_tab_done(const Funeral *f, PrepTab tab)
{
    switch (tab) {
    case TAB_EMBALM: return f->embalm != EMBALM_NONE;
    case TAB_MAKEUP: return f->makeup_style >= 0 && f->makeup_coverage >= 90;
    case TAB_OUTFIT: return f->outfit_done;
    default:         return f->casket >= 0;
    }
}

bool prep_complete(const Funeral *f)
{
    for (int t = 0; t < TAB_COUNT; t++)
        if (!prep_tab_done(f, (PrepTab)t))
            return false;
    return true;
}

static int funeral_net(const Funeral *f)
{
    return f->fee + f->casket_sale + f->tip - f->casket_cost - f->supplies - f->fix_costs - f->refund;
}

static void note(Funeral *f, const char *text)
{
    if (f->note_count < 3)
        f->notes[f->note_count++] = text;
}

void finish_funeral(Funeral *f)
{
    const Person *p = &CAST[f->person];
    int sat = 40;
    f->note_count = 0;
    if (f->embalm == EMBALM_RIGHT) sat += 15;
    else { sat -= 10; note(f, f->embalm == EMBALM_HIGH ? "\"LOOKED A BIT... INFLATED.\"" : "\"WHAT IS THAT SMELL?\""); }
    if (f->makeup_style == p->makeup_wish) sat += 15;
    else { sat -= 5; note(f, "\"WRONG MAKEUP. HONESTLY.\""); }
    if (f->outfit == p->outfit_wish) { sat += 15; note(f, "\"THE OUTFIT WAS PERFECT!\""); }
    else sat -= 5;
    if (CASKET_PRICE[f->casket] <= f->casket_budget) sat += 10;
    else { sat -= 20; note(f, "\"THE CASKET BILL! OUTRAGEOUS!\""); }
    if (f->timed_out) { sat -= 25; note(f, "\"WE WANT A REFUND.\""); }
    else if (f->wrong_fixes == 0) { sat += 15; note(f, "\"YOU HANDLED THAT LIKE A PRO.\""); }
    else sat += 5;
    if (sat < 0) sat = 0;
    if (sat > 100) sat = 100;
    f->satisfaction = sat;
    f->fee = SERVICE_FEE;
    f->casket_sale = CASKET_PRICE[f->casket];
    f->casket_cost = CASKET_COST[f->casket];
    f->supplies = SUPPLIES_COST;
    f->tip = sat >= 60 ? (sat - 50) * 20 : 0;
    f->refund = f->timed_out ? REFUND_TIMEOUT : 0;
    f->done = true;
}

// ---------------------------------------------------------------------------
// Input

static bool touching, tapped, released;
static int tx, ty;

static void read_input(void)
{
    scanKeys();
    uint32_t down = keysDown(), held = keysHeld(), up = keysUp();
    if (held & KEY_TOUCH) {
        touchPosition t;
        touchRead(&t);
        tx = t.px;
        ty = t.py;
    }
    touching = held & KEY_TOUCH;
    tapped = down & KEY_TOUCH;
    released = up & KEY_TOUCH;
}

static bool tap_in(int x, int y, int w, int h)
{
    return tapped && tx >= x && tx < x + w && ty >= y && ty < y + h;
}

static void flash(const char *msg, bool good)
{
    g.flash_msg = msg;
    g.flash_timer = 120;
    g.flash_good = good;
}

// ---------------------------------------------------------------------------
// Layout shared by update and draw

#define HEADER_H 19
#define TAB_Y 22
#define TAB_H 22
#define FOOT_X 32
#define FOOT_Y 166
#define FOOT_W 192
#define FOOT_H 22
#define CARD_Y(i) (24 + (i) * 54)
#define CARD_BTN_X 176
#define CARD_BTN_W 72
#define FACE_X 128
#define FACE_Y 120
#define FACE_R 34
#define PUMP_X 16
#define PUMP_Y 64
#define PUMP_W 104
#define PUMP_H 86
#define FIX_X(i) (6 + ((i) % 2) * 124)
#define FIX_Y(i) (70 + ((i) / 2) * 24)
#define FIX_W 120
#define FIX_H 21
#define AMOUNT_X 168

// ---------------------------------------------------------------------------
// Day flow

static void new_day(void)
{
    g.day++;
    int picks[FUNERALS_PER_DAY];
    for (int i = 0; i < FUNERALS_PER_DAY; i++) {
        bool again;
        do {
            picks[i] = rng_range(CAST_COUNT);
            again = false;
            for (int j = 0; j < i; j++)
                again |= picks[j] == picks[i];
        } while (again);
    }
    int disasters[DISASTER_COUNT];
    for (int i = 0; i < DISASTER_COUNT; i++)
        disasters[i] = i;
    for (int i = DISASTER_COUNT - 1; i > 0; i--) {
        int j = rng_range(i + 1), t = disasters[i];
        disasters[i] = disasters[j];
        disasters[j] = t;
    }
    static const int HOURS[FUNERALS_PER_DAY] = { 10, 13, 16 };
    for (int i = 0; i < FUNERALS_PER_DAY; i++) {
        Funeral *f = &g.funerals[i];
        memset(f, 0, sizeof(*f));
        f->person = picks[i];
        f->hour = HOURS[i];
        f->casket_budget = 1500 + rng_range(10) * 500;
        f->makeup_style = -1;
        f->casket = -1;
        f->disaster = disasters[i];
    }
    g.current = 0;
    g.state = STATE_BOOKINGS;
    scene_init();
}

static void open_prep(void)
{
    Funeral *f = current_funeral();
    g.state = STATE_PREP;
    g.tab = TAB_EMBALM;
    for (int t = 0; t < TAB_COUNT; t++) {
        if (!prep_tab_done(f, (PrepTab)t)) {
            g.tab = (PrepTab)t;
            break;
        }
    }
    g.outfit_view = f->outfit_done ? f->outfit : 0;
    g.pumping = false;
}

static void start_service(void)
{
    g.state = STATE_SERVICE;
    g.phase = SERVICE_ARRIVING;
    g.phase_timer = 0;
    g.service_timer = 0;
    g.disaster_at = 150 + rng_range(120);
    g.flash_timer = 0;
    scene_start_service();
    sfx_music(MUSIC_DIRGE);
}

static void set_phase(ServicePhase p)
{
    g.phase = p;
    g.phase_timer = 0;
}

// ---------------------------------------------------------------------------
// Update

static void update_prep(void)
{
    Funeral *f = current_funeral();
    if (tap_in(196, 2, 56, 15)) {
        sfx_play(SFX_TAP);
        g.state = STATE_BOOKINGS;
        return;
    }
    for (int t = 0; t < TAB_COUNT; t++) {
        if (tap_in(t * 64, TAB_Y, 64, TAB_H)) {
            g.tab = (PrepTab)t;
            g.pumping = false;
            sfx_play(SFX_TAP);
        }
    }
    if (prep_complete(f) && tap_in(FOOT_X, FOOT_Y, FOOT_W, FOOT_H)) {
        sfx_play(SFX_DONE);
        start_service();
        return;
    }

    switch (g.tab) {
    case TAB_EMBALM:
        if (tap_in(PUMP_X, PUMP_Y, PUMP_W, PUMP_H)) {
            g.pumping = true;
            g.pump = 0;
        }
        if (g.pumping) {
            if (touching) {
                g.pump += 6;
                if (g.pump > 1000)
                    g.pump = 1000;
                if (g.frame % 8 == 0)
                    sfx_play(SFX_PUMP);
            } else {
                g.pumping = false;
                f->embalm = g.pump < 550 ? EMBALM_LOW : g.pump <= 750 ? EMBALM_RIGHT : EMBALM_HIGH;
                sfx_play(f->embalm == EMBALM_RIGHT ? SFX_DONE : SFX_BAD);
            }
        }
        break;
    case TAB_MAKEUP:
        for (int s = 0; s < MAKEUP_COUNT; s++) {
            if (tap_in(8 + s * 82, 62, 76, 16)) {
                f->makeup_style = s;
                sfx_play(SFX_TAP);
            }
        }
        if (touching && f->makeup_style >= 0 && ty > 80) {
            int cell = face_cell_size(FACE_R);
            int ox = FACE_X - 4 * cell, oy = FACE_Y - 4 * cell;
            int face_cells = 0, covered = 0;
            bool was_done = f->makeup_coverage >= 90;
            for (int j = 0; j < MAKEUP_GRID; j++) {
                for (int i = 0; i < MAKEUP_GRID; i++) {
                    int ccx = ox + i * cell + cell / 2, ccy = oy + j * cell + cell / 2;
                    int dx = ccx - tx, dy = ccy - ty;
                    if (dx * dx + dy * dy <= 13 * 13)
                        f->makeup_cells[j * MAKEUP_GRID + i] = 1;
                    int fx = ccx - FACE_X, fy = ccy - FACE_Y;
                    if (fx * fx + fy * fy <= FACE_R * FACE_R) {
                        face_cells++;
                        covered += f->makeup_cells[j * MAKEUP_GRID + i];
                    }
                }
            }
            f->makeup_coverage = covered * 100 / face_cells;
            if (!was_done && f->makeup_coverage >= 90)
                sfx_play(SFX_DONE);
        }
        break;
    case TAB_OUTFIT:
        if (tap_in(8, 76, 44, 40)) {
            g.outfit_view = (g.outfit_view + OUTFIT_COUNT - 1) % OUTFIT_COUNT;
            sfx_play(SFX_TAP);
        }
        if (tap_in(204, 76, 44, 40)) {
            g.outfit_view = (g.outfit_view + 1) % OUTFIT_COUNT;
            sfx_play(SFX_TAP);
        }
        if (tap_in(88, 144, 80, 18)) {
            f->outfit = g.outfit_view;
            f->outfit_done = true;
            sfx_play(SFX_DONE);
        }
        break;
    default:
        for (int i = 0; i < CASKET_COUNT; i++) {
            if (tap_in(6 + i * 84, 62, 78, 96)) {
                f->casket = i;
                sfx_play(SFX_TAP);
            }
        }
        break;
    }
}

static void update_service(void)
{
    Funeral *f = current_funeral();
    g.phase_timer++;
    g.service_timer++;

    for (int i = 0; i < DISASTER_COUNT; i++) {
        if (!tap_in(FIX_X(i), FIX_Y(i), FIX_W, FIX_H))
            continue;
        if (g.phase != SERVICE_DISASTER) {
            sfx_play(SFX_TAP);
            flash(g.phase < SERVICE_DISASTER ? "NOTHING TO FIX... YET." : "IT'S FINE NOW. RELAX.", true);
        } else if (i == f->disaster) {
            f->fix_costs += FIXES[i].cost;
            g.last_fix = i;
            sfx_play(SFX_FIXED);
            sfx_music(MUSIC_DIRGE);
            flash("FIXED! CRISIS AVERTED.", true);
            set_phase(SERVICE_FIXED);
        } else {
            f->fix_costs += FIXES[i].cost;
            f->wrong_fixes++;
            g.fix_timer -= 60;
            sfx_play(SFX_BAD);
            flash(FIXES[i].wrong, false);
        }
    }

    switch (g.phase) {
    case SERVICE_ARRIVING:
        if (scene_all_seated() || g.phase_timer > 600)
            set_phase(SERVICE_EULOGY);
        break;
    case SERVICE_EULOGY:
        if (g.phase_timer >= g.disaster_at) {
            set_phase(SERVICE_DISASTER);
            g.fix_timer = FIX_TIME;
            sfx_play(SFX_ALARM);
            if (f->disaster == DISASTER_RINGTONE)
                sfx_music(MUSIC_RINGTONE);
        }
        break;
    case SERVICE_DISASTER:
        if (--g.fix_timer <= 0) {
            f->timed_out = true;
            sfx_play(SFX_BAD);
            sfx_music(MUSIC_DIRGE);
            flash("TOO SLOW! THEY WANT A REFUND.", false);
            set_phase(SERVICE_FIXED);
        }
        break;
    case SERVICE_FIXED:
        if (g.phase_timer > 150) {
            set_phase(SERVICE_LEAVING);
            scene_start_leaving();
        }
        break;
    case SERVICE_LEAVING:
        if (scene_all_gone() || g.phase_timer > 600) {
            finish_funeral(f);
            sfx_music(MUSIC_NONE);
            sfx_play(SFX_CASH);
            g.state = STATE_RESULT;
        }
        break;
    }
}

void game_init(void)
{
    memset(&g, 0, sizeof(g));
    g.rng = 0x2545F491;
    g.state = STATE_TITLE;
}

void game_update(bool fresh_input)
{
    if (fresh_input)
        read_input();
    else
        tapped = released = false;
    g.frame++;
    if (g.flash_timer > 0)
        g.flash_timer--;

    switch (g.state) {
    case STATE_TITLE:
        if (tap_in(28, 120, 200, 30) || (fresh_input && (keysDown() & KEY_START))) {
            g.rng ^= g.frame * 2654435761u;
            if (!g.rng)
                g.rng = 1;
            sfx_play(SFX_DONE);
            new_day();
        }
        break;
    case STATE_BOOKINGS: {
        Funeral *f = current_funeral();
        if (tap_in(CARD_BTN_X, CARD_Y(g.current) + 12, CARD_BTN_W, 26)) {
            sfx_play(SFX_TAP);
            if (prep_complete(f))
                start_service();
            else
                open_prep();
        }
        break;
    }
    case STATE_PREP:
        update_prep();
        break;
    case STATE_SERVICE:
        update_service();
        break;
    case STATE_RESULT:
        if (tap_in(FOOT_X, FOOT_Y, FOOT_W, FOOT_H)) {
            sfx_play(SFX_TAP);
            g.current++;
            if (g.current >= FUNERALS_PER_DAY) {
                int total = 0;
                for (int i = 0; i < FUNERALS_PER_DAY; i++)
                    total += funeral_net(&g.funerals[i]);
                if (g.day == 1 || total > g.best_profit)
                    g.best_profit = total;
                g.state = STATE_DAY_END;
                sfx_play(SFX_CASH);
            } else {
                g.state = STATE_BOOKINGS;
            }
        }
        break;
    case STATE_DAY_END:
        if (tap_in(FOOT_X, FOOT_Y, FOOT_W, FOOT_H)) {
            sfx_play(SFX_DONE);
            new_day();
        }
        break;
    }
    scene_update();
    sfx_update();
}

// ---------------------------------------------------------------------------
// Drawing the touch screen

static void header(Canvas *c, const char *title, const char *right, color_t bg)
{
    fill_rect(c, 0, 0, SCREEN_W, HEADER_H, bg);
    hline(c, 0, HEADER_H - 1, SCREEN_W, C_GOLD);
    draw_text(c, 4, 6, title, C_CREAM);
    if (right)
        draw_text(c, SCREEN_W - 4 - text_width(right, 1), 6, right, C_GOLD);
}

static void button(Canvas *c, int x, int y, int w, int h, const char *label, bool enabled, color_t fill)
{
    panel(c, x, y, w, h, enabled ? fill : RGB(9, 7, 11), enabled ? C_CREAM : RGB(13, 11, 15));
    if (enabled)
        hline(c, x + 2, y + h - 2, w - 4, ((fill >> 1) & 0x3DEF) | 0x8000);
    draw_text_center(c, x + w / 2, y + (h - 8) / 2, label, enabled ? C_WHITE : RGB(15, 13, 17), 1);
}

static void time_text(char *buf, int hour)
{
    buf[0] = 0;
    str_cat_int(buf, hour > 12 ? hour - 12 : hour);
    str_cat(buf, hour >= 12 ? ":00 PM" : ":00 AM");
}

static int day_profit_so_far(void)
{
    int total = 0;
    for (int i = 0; i < FUNERALS_PER_DAY; i++)
        if (g.funerals[i].done)
            total += funeral_net(&g.funerals[i]);
    return total;
}

static void draw_title(Canvas *c)
{
    gfx_clear(c, C_PLUM);
    for (int y = 0; y < SCREEN_H; y += 16)
        hline(c, 0, y, SCREEN_W, C_PLUM2);
    draw_text_center(c, 128, 18, "A FUNERAL HOME SIM", C_GOLD, 1);
    draw_text_center(c, 128, 40, "3 FUNERALS. 0 MISTAKES.", C_CREAM, 1);
    draw_text_center(c, 128, 52, "PROBABLY.", C_DIM, 1);
    draw_text_center(c, 128, 76, "PREP THE BODIES, RUN THE", C_CREAM, 1);
    draw_text_center(c, 128, 88, "SERVICE, FIX WHAT BREAKS.", C_CREAM, 1);
    button(c, 28, 120, 200, 30, "TAP TO OPEN UP", true, C_GREEN);
    if (g.best_profit) {
        char best[32] = "BEST DAY: ";
        char m[16];
        format_money(m, g.best_profit);
        str_cat(best, m);
        draw_text_center(c, 128, 158, best, C_GOLD, 1);
    }
    draw_text_center(c, 128, 178, "BUILT WITH BLOCKSDS", RGB(12, 10, 14), 1);
}

static void draw_bookings(Canvas *c)
{
    gfx_clear(c, C_PLUM);
    char cash[20];
    format_money(cash, day_profit_so_far());
    char title[24] = "DAY ";
    str_cat_int(title, g.day);
    str_cat(title, " BOOKINGS");
    header(c, title, cash, RGB(4, 2, 6));
    for (int i = 0; i < FUNERALS_PER_DAY; i++) {
        Funeral *f = &g.funerals[i];
        const Person *p = &CAST[f->person];
        int y = CARD_Y(i);
        bool active = i == g.current;
        panel(c, 4, y, 248, 50, active ? C_CREAM : RGB(17, 14, 19), active ? C_GOLD : RGB(12, 9, 14));
        char t[16];
        time_text(t, f->hour);
        draw_text(c, 10, y + 5, t, active ? C_RED : RGB(9, 6, 9));
        draw_text(c, 10, y + 17, p->name, C_INK);
        draw_text(c, 10, y + 29, p->trait, active ? RGB(9, 7, 11) : RGB(9, 6, 9));
        if (f->done) {
            char m[16];
            format_money(m, funeral_net(f));
            draw_text(c, CARD_BTN_X + 4, y + 13, "DONE", C_GREEN);
            draw_text(c, CARD_BTN_X + 4, y + 25, m, funeral_net(f) >= 0 ? C_GREEN : C_RED);
        } else if (active) {
            int steps = 0;
            for (int t2 = 0; t2 < TAB_COUNT; t2++)
                steps += prep_tab_done(f, (PrepTab)t2);
            bool ready = steps == TAB_COUNT;
            button(c, CARD_BTN_X, y + 12, CARD_BTN_W, 26, ready ? "START" : "PREP", true, ready ? C_GREEN : C_RED);
            char prog[16] = "";
            str_cat_int(prog, steps);
            str_cat(prog, "/4 READY");
            draw_text(c, 10 + 104, y + 5, prog, RGB(9, 7, 11));
        } else {
            draw_text(c, CARD_BTN_X + 12, y + 19, "LATER", RGB(10, 7, 11));
        }
    }
}

static void draw_wants(Canvas *c, const char *wish, bool match)
{
    char line[40] = "WANTS: ";
    str_cat(line, wish);
    draw_text(c, 6, 50, line, C_CREAM);
    if (match)
        draw_text(c, 250 - text_width("MATCH!", 1), 50, "MATCH!", C_GOLD);
}

static void draw_prep(Canvas *c)
{
    Funeral *f = current_funeral();
    const Person *p = &CAST[f->person];
    gfx_clear(c, C_PLUM);
    header(c, p->name, 0, RGB(4, 2, 6));
    button(c, 196, 2, 56, 15, "BACK", true, RGB(9, 5, 12));

    static const char *const TABS[TAB_COUNT] = { "EMBALM", "MAKEUP", "OUTFIT", "CASKET" };
    for (int t = 0; t < TAB_COUNT; t++) {
        bool sel = g.tab == (PrepTab)t;
        bool done = prep_tab_done(f, (PrepTab)t);
        panel(c, t * 64 + 1, TAB_Y, 62, TAB_H, sel ? C_CREAM : RGB(14, 10, 17), done ? C_GREEN : C_GOLD);
        draw_text_center(c, t * 64 + 32, TAB_Y + 3, TABS[t], sel ? C_INK : C_CREAM, 1);
        draw_text_center(c, t * 64 + 32, TAB_Y + 12, done ? "DONE" : "TO DO", done ? C_GREEN : sel ? C_RED : RGB(22, 12, 14), 1);
    }

    switch (g.tab) {
    case TAB_EMBALM: {
        draw_text(c, 6, 50, "HOLD PUMP. LET GO IN GREEN.", C_CREAM);
        bool held = g.pumping;
        panel(c, PUMP_X, PUMP_Y, PUMP_W, PUMP_H, held ? RGB(20, 4, 8) : RGB(26, 6, 10), C_CREAM);
        fill_circle(c, PUMP_X + PUMP_W / 2, PUMP_Y + 34, held ? 18 : 20, RGB(31, 12, 14));
        fill_circle(c, PUMP_X + PUMP_W / 2, PUMP_Y + 34, held ? 12 : 14, RGB(22, 3, 6));
        draw_text_center(c, PUMP_X + PUMP_W / 2, PUMP_Y + 62, "HOLD TO", C_WHITE, 1);
        draw_text_center(c, PUMP_X + PUMP_W / 2, PUMP_Y + 72, "PUMP", C_WHITE, 1);
        // Gauge
        int gx = 140, gy = 64, gh = 86;
        fill_rect(c, gx, gy, 28, gh, RGB(4, 3, 5));
        frame_rect(c, gx - 1, gy - 1, 30, gh + 2, C_CREAM);
        int g0 = gy + gh - 550 * gh / 1000, g1 = gy + gh - 750 * gh / 1000;
        fill_rect(c, gx, g1, 28, g0 - g1, RGB(4, 16, 6));
        int level = held ? g.pump : f->embalm == EMBALM_LOW ? 400 : f->embalm == EMBALM_RIGHT ? 650 : f->embalm == EMBALM_HIGH ? 900 : 0;
        int ny = gy + gh - level * gh / 1000;
        fill_rect(c, gx - 4, ny - 1, 36, 3, C_GOLD);
        const char *zone = level < 550 ? "TOO LOW" : level <= 750 ? "JUST RIGHT" : "TOO MUCH";
        if (held || f->embalm != EMBALM_NONE) {
            draw_text(c, 176, 92, zone, level >= 550 && level <= 750 ? C_GREEN : C_RED);
            if (!held)
                draw_text(c, 176, 104, "(TAP PUMP", C_DIM), draw_text(c, 176, 114, " TO REDO)", C_DIM);
        }
        break;
    }
    case TAB_MAKEUP: {
        draw_wants(c, MAKEUP_NAMES[p->makeup_wish], f->makeup_style == p->makeup_wish);
        for (int s = 0; s < MAKEUP_COUNT; s++) {
            bool sel = f->makeup_style == s;
            button(c, 8 + s * 82, 62, 76, 16, MAKEUP_NAMES[s], true, sel ? RGB(20, 6, 18) : RGB(9, 5, 12));
            if (sel)
                frame_rect(c, 7 + s * 82, 61, 78, 18, C_GOLD);
        }
        draw_face(c, FACE_X, FACE_Y, FACE_R, SKIN[f->person % SKIN_TONES], RGB(p->hair_r, p->hair_g, p->hair_b),
                  p->long_hair, f->makeup_style, f->makeup_cells);
        char cov[24] = "";
        str_cat_int(cov, f->makeup_coverage);
        str_cat(cov, "%");
        draw_text(c, 8, 96, "COVER", C_DIM);
        draw_text(c, 8, 106, cov, f->makeup_coverage >= 90 ? C_GREEN : C_CREAM);
        if (f->makeup_style < 0)
            draw_text(c, 176, 96, "PICK A", C_DIM), draw_text(c, 176, 106, "LOOK", C_DIM);
        else if (f->makeup_coverage < 90)
            draw_text(c, 176, 96, "NOW RUB", C_DIM), draw_text(c, 176, 106, "IT ON!", C_DIM);
        break;
    }
    case TAB_OUTFIT: {
        draw_wants(c, OUTFIT_NAMES[p->outfit_wish], g.outfit_view == p->outfit_wish);
        // Mannequin
        fill_circle(c, 128, 70, 8, RGB(24, 22, 20));
        draw_outfit(c, 100, 80, 56, 52, g.outfit_view, g.frame);
        button(c, 8, 76, 44, 40, "<", true, RGB(9, 5, 12));
        button(c, 204, 76, 44, 40, ">", true, RGB(9, 5, 12));
        draw_text_center(c, 128, 134, OUTFIT_NAMES[g.outfit_view], C_CREAM, 1);
        bool worn = f->outfit_done && f->outfit == g.outfit_view;
        button(c, 88, 146, 80, 16, worn ? "WEARING" : "DRESS", true, worn ? C_GREEN : RGB(20, 6, 18));
        break;
    }
    default: {
        char line[32] = "BUDGET: ";
        char m[16];
        format_money(m, f->casket_budget);
        str_cat(line, m);
        draw_text(c, 6, 50, line, C_CREAM);
        for (int i = 0; i < CASKET_COUNT; i++) {
            int x = 6 + i * 84;
            bool sel = f->casket == i;
            panel(c, x, 62, 78, 96, sel ? C_CREAM : RGB(14, 10, 17), sel ? C_GOLD : RGB(20, 16, 22));
            draw_casket(c, x + 11, 76, i, 0, false);
            const char *name = CASKET_NAMES[i];
            const char *space = strchr(name, ' ');
            char first[12] = "";
            strncat(first, name, (size_t)(space - name));
            draw_text_center(c, x + 39, 102, first, sel ? C_INK : C_CREAM, 1);
            draw_text_center(c, x + 39, 112, space + 1, sel ? C_INK : C_CREAM, 1);
            format_money(m, CASKET_PRICE[i]);
            bool over = CASKET_PRICE[i] > f->casket_budget;
            draw_text_center(c, x + 39, 128, m, over ? C_RED : C_GREEN, 1);
            if (sel)
                draw_text_center(c, x + 39, 142, "CHOSEN", C_INK, 1);
        }
        break;
    }
    }

    button(c, FOOT_X, FOOT_Y, FOOT_W, FOOT_H, "START SERVICE", prep_complete(f), C_GREEN);
}

static void draw_service(Canvas *c)
{
    Funeral *f = current_funeral();
    gfx_clear(c, C_PLUM);
    bool disaster = g.phase == SERVICE_DISASTER;
    if (disaster)
        header(c, (g.frame / 10) % 2 ? "!! DISASTER !!" : "", "QUICK!", C_RED);
    else {
        char t[40] = "SERVICE: ";
        str_cat(t, CAST[f->person].name);
        header(c, t, 0, RGB(4, 2, 6));
    }
    panel(c, 4, 22, 248, 44, disaster ? RGB(31, 26, 22) : C_CREAM, disaster ? C_RED : C_GOLD);
    const char *l1, *l2;
    switch (g.phase) {
    case SERVICE_ARRIVING: l1 = "MOURNERS ARE ARRIVING."; l2 = "LOOK SOLEMN."; break;
    case SERVICE_EULOGY: l1 = "THE EULOGY IS GOING"; l2 = "BEAUTIFULLY. FOR NOW."; break;
    case SERVICE_DISASTER: l1 = DISASTERS[f->disaster].line1; l2 = DISASTERS[f->disaster].line2; break;
    case SERVICE_FIXED: l1 = "PHEW."; l2 = "BACK TO MOURNING."; break;
    default: l1 = "SERVICE IS WRAPPING UP."; l2 = "SHAKE HANDS. LOOK SAD."; break;
    }
    draw_text(c, 10, 27, l1, disaster ? C_RED : C_INK);
    draw_text(c, 10, 37, l2, disaster ? C_RED : C_INK);
    if (g.flash_timer > 0 && g.flash_msg)
        draw_text(c, 10, 48, g.flash_msg, g.flash_good ? C_GREEN : C_RED);
    if (disaster) {
        int w = g.fix_timer * 236 / FIX_TIME;
        if (w < 0)
            w = 0;
        fill_rect(c, 10, 58, 236, 4, RGB(20, 18, 16));
        fill_rect(c, 10, 58, w, 4, g.fix_timer > FIX_TIME / 3 ? C_GREEN : C_RED);
    }
    for (int i = 0; i < DISASTER_COUNT; i++) {
        int x = FIX_X(i), y = FIX_Y(i);
        button(c, x, y, FIX_W, FIX_H, "", disaster, i % 2 ? RGB(9, 5, 12) : RGB(10, 6, 13));
        draw_text(c, x + 6, y + 7, FIXES[i].label, disaster ? C_WHITE : RGB(15, 13, 17));
        char m[12];
        if (FIXES[i].cost)
            format_money(m, FIXES[i].cost);
        else
            strcpy(m, "$0");
        draw_text(c, x + FIX_W - 5 - text_width(m, 1), y + 7, m, disaster ? C_GOLD : RGB(13, 11, 15));
    }
    char spent[32] = "FIX SPENDING: ";
    char m[12];
    format_money(m, f->fix_costs);
    str_cat(spent, m);
    draw_text_center(c, 128, 168, spent, C_DIM, 1);
}

static void ledger(Canvas *c, int y, const char *label, int amount, color_t color)
{
    char m[16];
    format_money(m, amount);
    char s[18] = "";
    if (amount > 0)
        str_cat(s, "+");
    str_cat(s, m);
    draw_text(c, 12, y, label, C_CREAM);
    draw_text(c, AMOUNT_X, y, s, color);
}

static void draw_result(Canvas *c)
{
    Funeral *f = current_funeral();
    gfx_clear(c, C_PLUM);
    header(c, "SERVICE COMPLETE", 0, RGB(4, 2, 6));
    draw_text(c, 12, 24, CAST[f->person].name, C_GOLD);
    int y = 38;
    ledger(c, y, "SERVICE FEE", f->fee, C_GREEN); y += 10;
    ledger(c, y, "CASKET SALE", f->casket_sale, C_GREEN); y += 10;
    ledger(c, y, "TIP", f->tip, C_GREEN); y += 10;
    ledger(c, y, "CASKET COST", -f->casket_cost, C_RED); y += 10;
    ledger(c, y, "SUPPLIES", -f->supplies, C_RED); y += 10;
    ledger(c, y, "QUICK FIXES", -f->fix_costs, C_RED); y += 10;
    ledger(c, y, "REFUND", -f->refund, C_RED); y += 10;
    hline(c, 12, y, 232, C_DIM);
    y += 4;
    int net = funeral_net(f);
    ledger(c, y, "NET", net, net >= 0 ? C_GOLD : C_RED);
    y += 14;
    char mood[24] = "FAMILY MOOD: ";
    str_cat_int(mood, f->satisfaction);
    str_cat(mood, "%");
    draw_text(c, 12, y, mood, f->satisfaction >= 60 ? C_GREEN : C_RED);
    y += 12;
    for (int i = 0; i < f->note_count && i < 2; i++, y += 10)
        draw_text(c, 12, y, f->notes[i], C_DIM);
    button(c, FOOT_X, FOOT_Y, FOOT_W, FOOT_H, g.current + 1 < FUNERALS_PER_DAY ? "NEXT FUNERAL" : "CLOSE UP SHOP", true, C_GREEN);
}

static void draw_day_end(Canvas *c)
{
    gfx_clear(c, C_PLUM);
    char title[24] = "END OF DAY ";
    str_cat_int(title, g.day);
    header(c, title, 0, RGB(4, 2, 6));
    int revenue = 0, tips = 0, costs = 0, refunds = 0, sat = 0;
    for (int i = 0; i < FUNERALS_PER_DAY; i++) {
        Funeral *f = &g.funerals[i];
        revenue += f->fee + f->casket_sale;
        tips += f->tip;
        costs += f->casket_cost + f->supplies + f->fix_costs;
        refunds += f->refund;
        sat += f->satisfaction;
    }
    int profit = revenue + tips - costs - refunds;
    sat /= FUNERALS_PER_DAY;
    int y = 28;
    ledger(c, y, "REVENUE", revenue, C_GREEN); y += 11;
    ledger(c, y, "TIPS", tips, C_GREEN); y += 11;
    ledger(c, y, "COSTS", -costs, C_RED); y += 11;
    ledger(c, y, "REFUNDS", -refunds, C_RED); y += 11;
    hline(c, 12, y, 232, C_DIM);
    y += 4;
    ledger(c, y, "PROFIT", profit, profit >= 0 ? C_GOLD : C_RED);
    int stars = sat >= 90 ? 5 : sat >= 75 ? 4 : sat >= 60 ? 3 : sat >= 40 ? 2 : 1;
    char rating[24] = "RATING: ";
    str_cat_int(rating, stars);
    str_cat(rating, "/5 STARS");
    draw_text(c, 12, 98, rating, C_CREAM);
    static const char *const REVIEWS[6][2] = {
        { "", "" },
        { "\"DO NOT DIE HERE.\"", "ZERO STARS IF I COULD." },
        { "\"I CAME FOR A FUNERAL", "AND GOT A SITCOM.\"" },
        { "\"IT WAS... A FUNERAL.", "THE DIP WAS GOOD.\"" },
        { "\"LOVELY SERVICE. ONLY", "ONE SMALL INCIDENT.\"" },
        { "\"BEST FUNERAL EVER.", "WOULD DIE AGAIN.\"" },
    };
    panel(c, 8, 112, 240, 34, C_CREAM, C_GOLD);
    draw_text(c, 14, 117, REVIEWS[stars][0], C_INK);
    draw_text(c, 14, 128, REVIEWS[stars][1], C_INK);
    char best[32] = "BEST DAY: ";
    char m[16];
    format_money(m, g.best_profit);
    str_cat(best, m);
    draw_text_center(c, 128, 152, best, C_DIM, 1);
    button(c, FOOT_X, FOOT_Y, FOOT_W, FOOT_H, "OPEN TOMORROW", true, C_GREEN);
}

void game_draw(void)
{
    scene_draw();
    Canvas *c = &g_bottom;
    switch (g.state) {
    case STATE_TITLE: draw_title(c); break;
    case STATE_BOOKINGS: draw_bookings(c); break;
    case STATE_PREP: draw_prep(c); break;
    case STATE_SERVICE: draw_service(c); break;
    case STATE_RESULT: draw_result(c); break;
    case STATE_DAY_END: draw_day_end(c); break;
    }
}
