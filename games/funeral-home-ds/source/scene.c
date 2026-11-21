// Top screen: chapel (services), prep room (prep) and the outside (title, end of day).
#include <string.h>

#include "art.h"
#include "game.h"
#include "gfx.h"
#include "scene.h"

#define MAX_MOURNERS 10
#define HUD_H 12
#define DOOR_X 250
#define LANE_Y 108          // walkway between the stage and the first pew (feet y)
#define AISLE_X 128
#define CASKET_HOME_X 100
#define CASKET_HOME_Y 74

static const int PEW_Y[3] = { 116, 140, 164 };
static const int SEAT_X[8] = { 28, 50, 72, 94, 162, 184, 206, 228 };

typedef enum { M_WAIT, M_ENTER, M_SEATED, M_LEAVE, M_GONE } MState;

typedef struct {
    int x, y;
    int seat_x, seat_y;
    int step;          // waypoint index along the path
    MState st;
    int delay;
    Look look;
    bool flip;
} Mourner;

static Mourner mourners[MAX_MOURNERS];
static int mourner_count;
static int casket_x = CASKET_HOME_X, casket_y = CASKET_HOME_Y, casket_dir = 1;
static int raccoon_x;
static color_t chapel_bg[SCREEN_W * SCREEN_H] __attribute__((aligned(4)));
static bool chapel_ready;
static int intern_x = 40, intern_dir = 1;

static const color_t COATS[] = {
    RGB(3, 3, 4), RGB(6, 6, 8), RGB(3, 4, 10), RGB(8, 3, 10), RGB(9, 6, 3), RGB(28, 22, 2),
};
static const color_t HAIRS[] = {
    RGB(3, 2, 2), RGB(14, 8, 3), RGB(25, 25, 25), RGB(26, 20, 8), RGB(20, 7, 3), RGB(10, 6, 2),
};

static Look random_look(void)
{
    Look l;
    int coat = rng_range(10) == 0 ? 5 : rng_range(5);     // the odd guest wears mustard yellow
    l.coat = COATS[coat];
    l.hair = HAIRS[rng_range(6)];
    l.skin = SKIN[rng_range(SKIN_TONES)];
    l.pants = rng_range(2) ? RGB(3, 3, 4) : RGB(6, 6, 8);
    l.long_hair = rng_range(2);
    return l;
}

static Look director_look(void)
{
    return (Look){ RGB(2, 2, 3), RGB(21, 21, 22), SKIN[1], RGB(2, 2, 3), false };
}

// ---------------------------------------------------------------------------
// Simulation

void scene_init(void)
{
    mourner_count = 0;
    casket_x = CASKET_HOME_X;
    casket_y = CASKET_HOME_Y;
}

void scene_start_service(void)
{
    mourner_count = 6 + rng_range(5);
    uint8_t taken[24] = { 0 };
    for (int i = 0; i < mourner_count; i++) {
        Mourner *m = &mourners[i];
        // Front rows fill first, random side.
        int seat;
        do {
            int row = i < 6 ? i / 3 : rng_range(3);
            seat = row * 8 + rng_range(8);
        } while (taken[seat]);
        taken[seat] = 1;
        m->seat_x = SEAT_X[seat % 8];
        m->seat_y = PEW_Y[seat / 8] + 6;   // feet hidden behind the pew; head and shoulders show
        m->x = DOOR_X;
        m->y = LANE_Y;
        m->step = 0;
        m->st = M_WAIT;
        m->delay = 10 + i * 24;
        m->look = random_look();
        m->flip = false;
    }
    casket_x = CASKET_HOME_X;
    casket_y = CASKET_HOME_Y;
    casket_dir = 1;
    raccoon_x = 166;
}

void scene_start_leaving(void)
{
    for (int i = 0; i < mourner_count; i++) {
        mourners[i].st = M_LEAVE;
        mourners[i].step = 0;
        mourners[i].delay = i * 12;
    }
}

bool scene_all_seated(void)
{
    for (int i = 0; i < mourner_count; i++)
        if (mourners[i].st != M_SEATED)
            return false;
    return true;
}

bool scene_all_gone(void)
{
    for (int i = 0; i < mourner_count; i++)
        if (mourners[i].st != M_GONE)
            return false;
    return true;
}

// Moves toward (tx, ty) two pixels a frame; returns true on arrival.
static bool walk_to(Mourner *m, int tx, int ty)
{
    for (int k = 0; k < 2; k++) {
        if (m->x != tx) {
            m->flip = tx > m->x;
            m->x += tx > m->x ? 1 : -1;
        } else if (m->y != ty) {
            m->y += ty > m->y ? 1 : -1;
        } else {
            return true;
        }
    }
    return m->x == tx && m->y == ty;
}

void scene_update(void)
{
    for (int i = 0; i < mourner_count; i++) {
        Mourner *m = &mourners[i];
        if (m->delay > 0) {
            m->delay--;
            continue;
        }
        if (m->st == M_WAIT)
            m->st = M_ENTER;
        if (m->st == M_ENTER) {
            bool arrived;
            if (m->step == 0)
                arrived = walk_to(m, AISLE_X, LANE_Y);
            else if (m->step == 1)
                arrived = walk_to(m, AISLE_X, m->seat_y);
            else
                arrived = walk_to(m, m->seat_x, m->seat_y);
            if (arrived && ++m->step == 3)
                m->st = M_SEATED;
        } else if (m->st == M_LEAVE) {
            bool arrived;
            if (m->step == 0)
                arrived = walk_to(m, AISLE_X, m->y);
            else if (m->step == 1)
                arrived = walk_to(m, AISLE_X, LANE_Y);
            else
                arrived = walk_to(m, DOOR_X, LANE_Y);
            if (arrived && ++m->step == 3)
                m->st = M_GONE;
        }
    }

    if (g.state == STATE_SERVICE) {
        Funeral *f = current_funeral();
        if (f->disaster == DISASTER_ROLLING && g.phase == SERVICE_DISASTER) {
            casket_y += casket_dir;
            if (casket_y > 168 || casket_y < CASKET_HOME_Y)
                casket_dir = -casket_dir;
        } else if (casket_y != CASKET_HOME_Y) {
            casket_y += casket_y > CASKET_HOME_Y ? -2 : 1;
            if (casket_y < CASKET_HOME_Y)
                casket_y = CASKET_HOME_Y;
        }
        if (f->disaster == DISASTER_RACCOON && g.phase >= SERVICE_FIXED && raccoon_x < 260)
            raccoon_x += 3;
    }

    intern_x += intern_dir;
    if (intern_x > 220 || intern_x < 20)
        intern_dir = -intern_dir;
}

// ---------------------------------------------------------------------------
// Chapel background (static, drawn once)

static void draw_window(Canvas *c, int x, int y, bool open)
{
    fill_rect(c, x - 2, y - 2, 32, 48, RGB(12, 8, 6));
    static const color_t panes[4] = { RGB(28, 6, 8), RGB(6, 12, 28), RGB(30, 24, 6), RGB(6, 20, 10) };
    for (int j = 0; j < 4; j++)
        for (int i = 0; i < 3; i++)
            fill_rect(c, x + i * 9 + 1, y + j * 11 + 1, 8, 10, open ? RGB(16, 24, 31) : panes[(i + j) % 4]);
    // Arch
    for (int k = 0; k < 6; k++)
        hline(c, x - 2 + (6 - k), y - 3 - k, 32 - 2 * (6 - k), RGB(12, 8, 6));
    if (open)
        fill_rect(c, x + 28, y - 2, 6, 46, RGB(12, 8, 6));
}

static void build_chapel(void)
{
    Canvas c = { chapel_bg };
    gfx_clear(&c, RGB(19, 16, 22));
    // Wallpaper stripes and wainscot
    for (int x = 0; x < SCREEN_W; x += 12)
        fill_rect(&c, x, HUD_H, 2, 80, RGB(17, 14, 20));
    fill_rect(&c, 0, 78, SCREEN_W, 18, RGB(11, 7, 6));
    hline(&c, 0, 78, SCREEN_W, RGB(16, 11, 8));
    // Windows
    draw_window(&c, 16, 26, false);
    draw_window(&c, 212, 26, false);
    // Door on the right wall
    fill_rect(&c, 238, 48, 18, 48, RGB(9, 5, 3));
    fill_rect(&c, 240, 50, 16, 46, RGB(15, 9, 5));
    plot(&c, 243, 74, C_GOLD);
    // Carpet and aisle runner
    fill_rect(&c, 0, 96, SCREEN_W, SCREEN_H - 96, RGB(14, 3, 4));
    for (int y = 98; y < SCREEN_H; y += 4)
        hline(&c, 0, y, SCREEN_W, RGB(12, 2, 3));
    fill_rect(&c, 118, 100, 21, SCREEN_H - 100, RGB(20, 6, 6));
    vline(&c, 118, 100, SCREEN_H - 100, C_GOLD);
    vline(&c, 138, 100, SCREEN_H - 100, C_GOLD);
    // Stage
    fill_rect(&c, 56, 88, 144, 12, RGB(13, 8, 4));
    hline(&c, 56, 88, 144, RGB(19, 12, 6));
    hline(&c, 56, 99, 144, RGB(7, 4, 2));
    // Casket stand
    fill_rect(&c, 106, 90, 4, 10, RGB(6, 6, 7));
    fill_rect(&c, 146, 90, 4, 10, RGB(6, 6, 7));
    // Organ
    fill_rect(&c, 2, 60, 34, 38, RGB(10, 5, 3));
    for (int i = 0; i < 7; i++)
        fill_rect(&c, 4 + i * 4, 40 + (i % 3) * 4, 3, 22 - (i % 3) * 4, RGB(24, 22, 14));
    fill_rect(&c, 4, 72, 30, 3, C_WHITE);
    for (int i = 0; i < 10; i++)
        vline(&c, 5 + i * 3, 72, 2, C_BLACK);
    // Podium
    fill_rect(&c, 204, 84, 20, 18, RGB(12, 7, 3));
    hline(&c, 202, 84, 24, RGB(19, 12, 6));
    chapel_ready = true;
}

static void draw_pew(Canvas *c, int x, int y, int w)
{
    fill_rect(c, x, y, w, 7, RGB(9, 5, 2));
    hline(c, x, y, w, RGB(16, 10, 5));
    fill_rect(c, x, y + 7, w, 5, RGB(13, 8, 4));
    fill_rect(c, x, y + 12, 3, 4, RGB(6, 3, 1));
    fill_rect(c, x + w - 3, y + 12, 3, 4, RGB(6, 3, 1));
}

static void draw_hud(Canvas *c, const char *left, const char *right, color_t bg)
{
    fill_rect(c, 0, 0, SCREEN_W, HUD_H, bg);
    draw_text(c, 3, 2, left, C_CREAM);
    if (right)
        draw_text(c, SCREEN_W - 3 - text_width(right, 1), 2, right, C_GOLD);
}

static void time_label(char *buf, int hour)
{
    buf[0] = 0;
    str_cat_int(buf, hour > 12 ? hour - 12 : hour);
    str_cat(buf, hour >= 12 ? ":00 PM" : ":00 AM");
}

// ---------------------------------------------------------------------------
// Chapel drawing

static int seated_bob(int i)
{
    Funeral *f = current_funeral();
    if (g.state != STATE_SERVICE)
        return 0;
    if (g.phase == SERVICE_DISASTER && f->disaster == DISASTER_RINGTONE)
        return ((g.frame / 8) + i) % 2 ? -2 : 0;
    if (g.phase == SERVICE_DISASTER && f->disaster == DISASTER_EXES && i < 2)
        return (g.frame / 4) % 2 ? -6 : -2;
    return 0;
}

static void draw_deceased_in_casket(Canvas *c, Funeral *f, int x, int y)
{
    const Person *p = &CAST[f->person];
    color_t hair = RGB(p->hair_r, p->hair_g, p->hair_b);
    draw_outfit(c, x + 16, y + 1, 26, 5, f->outfit_done ? f->outfit : OUTFIT_SUIT, g.frame);
    draw_face(c, x + 10, y + 2, 5, SKIN[f->person % SKIN_TONES], hair, p->long_hair,
              f->makeup_style, f->makeup_coverage > 0 ? f->makeup_cells : NULL);
}

static void draw_chapel(Canvas *c)
{
    if (!chapel_ready)
        build_chapel();
    gfx_copy(c, chapel_bg);
    Funeral *f = current_funeral();
    bool service = g.state == STATE_SERVICE;
    bool disaster = service && g.phase == SERVICE_DISASTER;
    bool fixed = service && g.phase >= SERVICE_FIXED;
    int d = f->disaster;

    // Portrait of the guest of honour
    if (service || g.state == STATE_RESULT) {
        const Person *p = &CAST[f->person];
        fill_rect(c, 112, 22, 32, 36, C_GOLD);
        fill_rect(c, 114, 24, 28, 32, RGB(8, 12, 16));
        draw_face(c, 128, 40, 9, SKIN[f->person % SKIN_TONES], RGB(p->hair_r, p->hair_g, p->hair_b),
                  p->long_hair, -1, NULL);
        // A big portrait smile (eyes open in the photo)
        fill_rect(c, 124, 38, 2, 2, C_INK);
        fill_rect(c, 131, 38, 2, 2, C_INK);
        fill_rect(c, 124, 45, 9, 1, C_INK);
        plot(c, 123, 44, C_INK);
        plot(c, 133, 44, C_INK);
    }
    if (fixed && d == DISASTER_SNEEZING)
        draw_window(c, 16, 26, true);

    // Organist (bobs along to the music)
    {
        Look o = { RGB(10, 3, 12), RGB(25, 25, 26), SKIN[0], RGB(3, 3, 4), true };
        int bob = service && (g.frame / 15) % 2 ? 1 : 0;
        draw_person(c, 30, 98 + bob, &o, 0, true, RGB(10, 3, 12));
    }

    // Flowers (the right-hand ones get raided)
    bool raid = disaster && d == DISASTER_RACCOON;
    draw_flowers(c, 82, 74, 0);
    draw_flowers(c, 162, 74, raid ? ((g.frame / 3) % 3) - 1 : 0);
    if (raid) {
        draw_raccoon(c, 160 + ((g.frame / 10) % 2), 82, false, g.frame / 6);
        for (int k = 0; k < 6; k++) {
            int t = (g.frame + k * 11) % 40;
            plot(c, 166 + k * 3 - t / 3, 76 - t + t * t / 40, RGB(29, 5, 8));
        }
    } else if (service && d == DISASTER_RACCOON && fixed && raccoon_x < 256) {
        draw_raccoon(c, raccoon_x, LANE_Y - 8, true, g.frame / 3);
    }

    // Casket
    if (service || g.state == STATE_RESULT) {
        int type = f->casket >= 0 ? f->casket : CASKET_OAK;
        bool taped = fixed && d == DISASTER_LID;
        int lift = taped ? 0 : 9;
        if (disaster && d == DISASTER_LID)
            lift = (g.frame / 5) % 2 ? 16 : 0;
        if (g.state == STATE_RESULT)
            lift = 0;
        draw_casket(c, casket_x, casket_y, type, lift, taped);
        if (lift > 0)
            draw_deceased_in_casket(c, f, casket_x, casket_y);
        if (disaster && d == DISASTER_LID && lift)
            draw_text(c, casket_x + 60, casket_y - 14, "BOING!", C_GOLD);
        if (disaster && d == DISASTER_ROLLING) {
            fill_circle(c, casket_x + 6, casket_y + 17, 2, C_BLACK);
            fill_circle(c, casket_x + 49, casket_y + 17, 2, C_BLACK);
        }
        if (fixed && d == DISASTER_POWER) {
            draw_candle(c, casket_x - 6, casket_y - 2, g.frame);
            draw_candle(c, casket_x + 58, casket_y - 2, g.frame + 7);
        }
    }

    // Director behind the podium
    {
        Look dl = director_look();
        int jump = disaster && (g.frame / 6) % 2 ? -3 : 0;
        int dx = 214;
        if (!service && g.state == STATE_BOOKINGS)
            dx = 60 + (int)((g.frame / 2) % 140);
        draw_person(c, dx, 100 + jump, &dl, 0, false, C_RED);
        fill_rect(c, 204, 86, 20, 16, RGB(12, 7, 3));
        hline(c, 202, 86, 24, RGB(19, 12, 6));
        draw_text(c, 208, 90, "RIP", C_GOLD);
    }

    // Mourners and pews, sorted by feet position so pews hide seated legs.
    int order[MAX_MOURNERS];
    for (int i = 0; i < mourner_count; i++)
        order[i] = i;
    for (int i = 1; i < mourner_count; i++) {
        int v = order[i], j = i - 1;
        while (j >= 0 && mourners[order[j]].y > mourners[v].y) {
            order[j + 1] = order[j];
            j--;
        }
        order[j + 1] = v;
    }
    int next = 0;
    for (int row = 0; row < 3; row++) {
        int pew_key = PEW_Y[row] + 12;
        while (next < mourner_count && mourners[order[next]].y <= pew_key) {
            int i = order[next++];
            Mourner *m = &mourners[i];
            if (m->st == M_WAIT || m->st == M_GONE)
                continue;
            int bob = m->st == M_SEATED ? seated_bob(i) : 0;
            int walk = m->st != M_SEATED && ((m->x + m->y) / 6) % 2;
            draw_person(c, m->x, m->y + bob, &m->look, walk, m->flip, RGB(6, 6, 8));
        }
        draw_pew(c, 14, PEW_Y[row], 98);
        draw_pew(c, 144, PEW_Y[row], 98);
    }
    while (next < mourner_count) {
        Mourner *m = &mourners[order[next++]];
        if (m->st != M_WAIT && m->st != M_GONE)
            draw_person(c, m->x, m->y, &m->look, ((m->x + m->y) / 6) % 2, m->flip, RGB(6, 6, 8));
    }

    // Waiting family before the next service
    if (g.state == STATE_BOOKINGS || g.state == STATE_PREP) {
        Look a = { RGB(3, 3, 4), HAIRS[2], SKIN[2], RGB(3, 3, 4), true };
        Look b = { RGB(3, 4, 10), HAIRS[0], SKIN[3], RGB(3, 3, 4), false };
        draw_person(c, 228, LANE_Y, &a, 0, false, C_BLACK);
        draw_person(c, 214, LANE_Y, &b, 0, false, C_BLACK);
        if ((g.frame / 120) % 2)
            draw_bubble(c, 170, 70, "WE'RE EARLY.", C_CREAM, C_INK);
    }

    // Disaster effects drawn over everything
    if (service && (disaster || fixed)) {
        Mourner *seated[MAX_MOURNERS];
        int ns = 0;
        for (int i = 0; i < mourner_count; i++)
            if (mourners[i].st == M_SEATED)
                seated[ns++] = &mourners[i];
        switch (d) {
        case DISASTER_SPRINKLERS:
            for (int k = 0; k < (disaster ? 70 : 25); k++) {
                int x = (k * 37 + (int)(g.frame / 30) * 13) % SCREEN_W;
                int y = HUD_H + (k * 53 + (int)g.frame * 4) % (SCREEN_H - HUD_H);
                vline(c, x, y, 3, RGB(12, 20, 31));
            }
            if (fixed)
                for (int i = 0; i < ns; i++)
                    draw_umbrella(c, seated[i]->x - 8, seated[i]->y - 29);
            break;
        case DISASTER_POWER:
            darken(c, 0, HUD_H, SCREEN_W, SCREEN_H - HUD_H, disaster ? 3 : 1);
            if (disaster) {
                for (int i = 0; i < ns; i++) {
                    if ((g.frame / 40 + i) % 5 == 0)
                        continue;   // blink
                    plot(c, seated[i]->x - 2, seated[i]->y - 17, C_WHITE);
                    plot(c, seated[i]->x + 1, seated[i]->y - 17, C_WHITE);
                }
                draw_text_center(c, 128, 60, "WHO'S TOUCHING ME?", RGB(20, 20, 20), 1);
            }
            break;
        case DISASTER_EXES:
            if (ns >= 2) {
                if (disaster) {
                    draw_bubble(c, seated[0]->x - 14, seated[0]->y - 36, "#@!%", C_WHITE, C_RED);
                    draw_bubble(c, seated[1]->x - 14, seated[1]->y - 40, "YOU %@#!", C_WHITE, C_RED);
                } else {
                    draw_bubble(c, seated[0]->x - 14, seated[0]->y - 34, "MMM, DIP.", C_CREAM, C_INK);
                }
            }
            break;
        case DISASTER_RINGTONE:
            if (disaster && ns >= 3) {
                fill_rect(c, seated[2]->x + 5, seated[2]->y - 18, 4, 7, C_BLACK);
                fill_rect(c, seated[2]->x + 6, seated[2]->y - 17, 2, 4, RGB(12, 28, 31));
                for (int k = 0; k < 4; k++) {
                    int t = (g.frame + k * 15) % 60;
                    draw_note(c, seated[2]->x + 8 + t / 2 + k * 4, seated[2]->y - 22 - t, RGB(12, 28, 31));
                }
            } else if (fixed) {
                for (int k = 0; k < 4; k++) {
                    int t = (g.frame + k * 15) % 60;
                    draw_note(c, 36 + t / 2 + k * 6, 50 - t / 2, C_GOLD);
                }
            }
            break;
        case DISASTER_SNEEZING:
            if (disaster) {
                for (int k = 0; k < 2 && ns; k++) {
                    Mourner *m = seated[(g.frame / 30 + k * 3) % ns];
                    draw_bubble(c, m->x - 20, m->y - 34, "ACHOO!", C_WHITE, C_INK);
                }
                for (int k = 0; k < 20; k++)
                    plot(c, 70 + (k * 29 + g.frame) % 120, 60 + (k * 17 + g.frame / 2) % 50, C_GOLD);
            }
            break;
        default:
            break;
        }
    }

    // Eulogy and wrap-up captions
    if (service) {
        const Person *p = &CAST[f->person];
        const char *line = 0;
        if (g.phase == SERVICE_EULOGY)
            line = (g.phase_timer / 100) % 2 == 0 ? "WE GATHER TO REMEMBER..." : p->eulogy;
        else if (g.phase == SERVICE_FIXED)
            line = f->timed_out ? "IT SORTED ITSELF OUT. SORT OF." : DISASTERS[d].fixed;
        else if (g.phase == SERVICE_LEAVING)
            line = f->wrong_fixes == 0 && !f->timed_out ? "COUSIN BO: BEST FUNERAL EVER!" : "AUNT JUNE: I'M LEAVING A REVIEW.";
        if (line)
            draw_bubble(c, 128 - text_width(line, 1) / 2 - 3, 14, line, C_CREAM, C_INK);
    }

    // HUD
    char right[16];
    if (service) {
        char left[40] = "IN MEMORY: ";
        str_cat(left, CAST[f->person].name);
        if (disaster && (g.frame / 15) % 2)
            draw_hud(c, "!!! UH-OH !!!", 0, C_RED);
        else {
            time_label(right, f->hour);
            draw_hud(c, left, 0, RGB(5, 2, 7));
        }
    } else if (g.state == STATE_BOOKINGS) {
        time_label(right, 9);
        draw_hud(c, "GRAVE MISTAKES CHAPEL", right, RGB(5, 2, 7));
    } else {
        time_label(right, f->hour);
        draw_hud(c, "THE FAMILY HAS LEFT.", right, RGB(5, 2, 7));
    }
}

// ---------------------------------------------------------------------------
// Prep room

static void draw_prep_room(Canvas *c)
{
    Funeral *f = current_funeral();
    const Person *p = &CAST[f->person];
    gfx_clear(c, RGB(18, 25, 24));
    for (int y = HUD_H; y < 120; y += 10)
        hline(c, 0, y, SCREEN_W, RGB(15, 21, 20));
    for (int x = 0; x < SCREEN_W; x += 10)
        vline(c, x, HUD_H, 108, RGB(15, 21, 20));
    for (int y = 120; y < SCREEN_H; y += 12)
        for (int x = ((y / 12) % 2) * 12; x < SCREEN_W; x += 24)
            fill_rect(c, x, y, 12, 12, RGB(23, 23, 24));
    // Wall clock and a motivational poster
    fill_circle(c, 128, 32, 10, C_WHITE);
    fill_circle(c, 128, 32, 8, C_CREAM);
    vline(c, 128, 25, 7, C_INK);
    hline(c, 128, 32, 3 + (int)(g.frame / 60) % 5, C_INK);
    fill_rect(c, 160, 20, 54, 30, C_CREAM);
    frame_rect(c, 160, 20, 54, 30, RGB(9, 9, 9));
    draw_text(c, 164, 24, "SAFETY", C_RED);
    draw_text(c, 164, 33, "3 DAYS", C_INK);
    draw_text(c, 164, 41, "NO OOPS", C_INK);

    // The chosen casket waits on a cart on the left
    if (f->casket >= 0) {
        draw_casket(c, 6, 60, f->casket, 0, false);
        fill_rect(c, 10, 76, 48, 3, C_GREY);
        draw_text(c, 8, 82, CASKET_NAMES[f->casket], C_INK);
    }

    // Prep table and the guest of honour
    fill_rect(c, 40, 120, 170, 6, RGB(20, 21, 23));
    hline(c, 40, 120, 170, C_WHITE);
    fill_rect(c, 50, 126, 4, 30, C_GREY);
    fill_rect(c, 196, 126, 4, 30, C_GREY);
    int puff = f->embalm == EMBALM_HIGH ? 6 : 0;
    draw_outfit(c, 78, 104 - puff, 82, 16 + puff, f->outfit_done ? f->outfit : OUTFIT_SUIT, g.frame);
    fill_rect(c, 160, 108, 34, 10, RGB(4, 4, 6));
    fill_rect(c, 194, 106, 6, 13, C_BLACK);
    draw_face(c, 64, 108, 12, SKIN[f->person % SKIN_TONES], RGB(p->hair_r, p->hair_g, p->hair_b), p->long_hair,
              f->makeup_style, f->makeup_style >= 0 ? f->makeup_cells : NULL);
    if (f->embalm == EMBALM_LOW) {
        // A faint smell, and its fan club.
        for (int k = 0; k < 3; k++) {
            int t = (g.frame + k * 20) % 60;
            plot(c, 110 + k * 20 + (t / 8) % 2, 98 - t / 3, RGB(10, 22, 6));
            plot(c, 111 + k * 20 + (t / 8 + 1) % 2, 97 - t / 3, RGB(10, 22, 6));
        }
        for (int k = 0; k < 3; k++) {
            int a = (int)(g.frame * 3 + k * 40) % 120;
            int fx = 110 + (a < 60 ? a : 120 - a) - 30, fy = 90 + ((a / 7 + k) % 3) * 3;
            fill_rect(c, fx, fy, 2, 2, C_BLACK);
        }
    }

    // Embalming machine, fluid level follows the pump
    fill_rect(c, 218, 66, 30, 54, RGB(12, 12, 14));
    fill_rect(c, 222, 70, 22, 40, RGB(26, 28, 30));
    int level = g.tab == TAB_EMBALM && g.pumping ? g.pump : (f->embalm == EMBALM_LOW ? 400 : f->embalm == EMBALM_RIGHT ? 650 : f->embalm == EMBALM_HIGH ? 900 : 0);
    int lh = level * 40 / 1000;
    fill_rect(c, 222, 110 - lh, 22, lh, RGB(28, 8, 18));
    if (g.pumping)
        for (int k = 0; k < 4; k++)
            plot(c, 226 + k * 5, 108 - (int)((g.frame * 2 + k * 9) % (lh + 1)), C_WHITE);
    for (int x = 196; x < 222; x++)
        plot(c, x, 100 + (x - 196) / 4, RGB(28, 8, 18));

    // The intern, forever on break
    Look in = { RGB(5, 18, 9), RGB(20, 9, 3), SKIN[3], RGB(4, 4, 10), false };
    draw_person(c, intern_x, 186, &in, (intern_x / 6) % 2, intern_dir > 0, C_WHITE);
    fill_rect(c, intern_x + (intern_dir > 0 ? 5 : -9), 176, 5, 3, RGB(28, 22, 10));
    if ((g.frame / 150) % 3 == 1)
        draw_bubble(c, intern_x - 20, 150, "I'M ON BREAK.", C_WHITE, C_INK);

    char left[40] = "PREP ROOM: ";
    str_cat(left, p->name);
    draw_hud(c, left, 0, RGB(5, 2, 7));
}

// ---------------------------------------------------------------------------
// Outside: title screen and end of day

static void draw_outside(Canvas *c, bool night)
{
    for (int y = 0; y < 150; y++) {
        int t = y * 10 / 150;
        hline(c, 0, y, SCREEN_W, night ? RGB(2, 2, 6 + t / 2) : RGB(14 + t, 20 + t, 31));
    }
    if (night) {
        for (int k = 0; k < 40; k++)
            plot(c, (k * 61) % SCREEN_W, (k * 37) % 60, (g.frame / 20 + k) % 7 ? C_WHITE : C_GREY);
        fill_circle(c, 220, 24, 10, C_CREAM);
        fill_circle(c, 224, 21, 9, RGB(2, 2, 7));
    } else {
        fill_circle(c, 30, 26, 10, RGB(31, 29, 12));
        for (int k = 0; k < 3; k++) {
            int cx = (int)((g.frame / 4 + k * 90) % 300) - 30;
            fill_circle(c, cx, 30 + k * 8, 6, C_WHITE);
            fill_circle(c, cx + 8, 28 + k * 8, 8, C_WHITE);
        }
    }
    fill_rect(c, 0, 150, SCREEN_W, 42, night ? RGB(2, 8, 3) : RGB(6, 20, 6));
    // Path to the door
    for (int y = 150; y < SCREEN_H; y++)
        hline(c, 112 - (y - 150) / 2, y, 32 + (y - 150), night ? RGB(10, 10, 9) : RGB(22, 21, 18));
    // Building
    fill_rect(c, 44, 82, 168, 68, night ? RGB(12, 11, 10) : RGB(27, 25, 21));
    for (int k = 0; k < 24; k++)
        hline(c, 44 + 24 - k, 58 + k, 120 + 2 * k, night ? RGB(5, 3, 3) : RGB(12, 5, 4));
    fill_rect(c, 120, 36, 16, 28, night ? RGB(12, 11, 10) : RGB(27, 25, 21));
    for (int k = 0; k < 10; k++)
        hline(c, 128 - k, 26 + k, 2 * k + 1, night ? RGB(5, 3, 3) : RGB(12, 5, 4));
    fill_rect(c, 127, 22, 2, 5, C_GOLD);
    // Columns, windows, door
    for (int i = 0; i < 4; i++)
        fill_rect(c, 56 + i * 44, 84, 6, 66, night ? RGB(16, 15, 14) : C_WHITE);
    for (int i = 0; i < 4; i++) {
        if (i == 1 || i == 2)
            continue;
        fill_rect(c, 66 + i * 44, 96, 20, 26, night ? RGB(6, 6, 9) : RGB(28, 26, 12));
        hline(c, 66 + i * 44, 108, 20, RGB(12, 8, 6));
        vline(c, 76 + i * 44, 96, 26, RGB(12, 8, 6));
    }
    fill_rect(c, 114, 112, 28, 38, RGB(9, 5, 3));
    vline(c, 128, 112, 38, RGB(6, 3, 2));
    fill_rect(c, 96, 88, 64, 14, C_BLACK);
    draw_text_center(c, 128, 91, "EST.1987", C_GOLD, 1);
    if (night) {
        fill_rect(c, 111, 120, 34, 10, C_RED);
        draw_text(c, 112, 121, "SHUT", C_WHITE);
    }
    // The hearse
    int hx = night ? 168 : 170;
    fill_rect(c, hx, 160, 64, 14, C_BLACK);
    fill_rect(c, hx + 14, 152, 40, 10, C_BLACK);
    fill_rect(c, hx + 16, 154, 10, 6, RGB(10, 14, 18));
    fill_rect(c, hx + 28, 154, 24, 6, RGB(10, 14, 18));
    fill_circle(c, hx + 12, 174, 5, RGB(5, 5, 5));
    fill_circle(c, hx + 52, 174, 5, RGB(5, 5, 5));
    fill_circle(c, hx + 12, 174, 2, C_GREY);
    fill_circle(c, hx + 52, 174, 2, C_GREY);
    draw_text(c, hx + 36, 165, "RIP", C_GOLD);
}

static void draw_title_top(Canvas *c)
{
    draw_outside(c, false);
    draw_text_center(c, 129, 5, "GRAVE MISTAKES", C_BLACK, 2);
    draw_text_center(c, 128, 4, "GRAVE MISTAKES", C_WHITE, 2);
    draw_text_center(c, 128, 24, "FUNERAL HOME & CHAPEL", C_INK, 1);
}

static void draw_day_end_top(Canvas *c)
{
    draw_outside(c, true);
    char line[40] = "DAY ";
    str_cat_int(line, g.day);
    str_cat(line, " IS OVER");
    draw_text_center(c, 128, 4, line, C_WHITE, 2);
    int total = 0, sat = 0;
    for (int i = 0; i < FUNERALS_PER_DAY; i++) {
        Funeral *f = &g.funerals[i];
        total += f->fee + f->casket_sale + f->tip - f->casket_cost - f->supplies - f->fix_costs - f->refund;
        sat += f->satisfaction;
    }
    char money[20];
    format_money(money, total);
    draw_text_center(c, 128, 24, money, total >= 0 ? C_GOLD : C_RED, 2);
    sat /= FUNERALS_PER_DAY;
    int stars = sat >= 90 ? 5 : sat >= 75 ? 4 : sat >= 60 ? 3 : sat >= 40 ? 2 : 1;
    for (int i = 0; i < 5; i++)
        draw_star(c, 34 + i * 40, 42, i < stars);
}

void scene_draw(void)
{
    Canvas *c = &g_top;
    switch (g.state) {
    case STATE_TITLE:
        draw_title_top(c);
        break;
    case STATE_PREP:
        draw_prep_room(c);
        break;
    case STATE_DAY_END:
        draw_day_end_top(c);
        break;
    default:
        draw_chapel(c);
        break;
    }
}
