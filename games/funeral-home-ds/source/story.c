// The story: Great-Uncle Mort's ghost, Kevin the intern, Vivian Vance-Prestige
// from Eternal Elegance across the street, and the families. All fictional.
#include <string.h>

#include "art.h"
#include "game.h"
#include "portrait.h"
#include "sfx.h"
#include "story.h"

// ---------------------------------------------------------------------------
// Cast

typedef struct {
    const char *name;
    const char *role;
    PortraitLook look;
    uint16_t voice;      // blip pitch in Hz
} Character;

static const Character REGULARS[3] = {
    [SPK_MORT] = { "GREAT-UNCLE MORT", "FOUNDER. GHOST.",
        { RGB(15, 23, 27), RGB(31, 31, 31), RGB(8, 11, 20), RGB(4, 7, 15), RGB(26, 4, 8), HAIR_BIG,
          ACC_GHOST | ACC_MUSTACHE | ACC_BOWTIE | ACC_COLLAR }, 330 },
    [SPK_KEVIN] = { "KEVIN", "INTERN. ON BREAK.",
        { RGB(23, 15, 9), RGB(14, 8, 3), RGB(5, 18, 9), RGB(4, 14, 14), RGB(27, 5, 6), HAIR_CAP,
          ACC_FRECKLES | ACC_SANDWICH | ACC_COLLAR }, 520 },
    [SPK_VIVIAN] = { "VIVIAN", "THE RIVAL. AWFUL.",
        { RGB(31, 24, 20), RGB(30, 26, 12), RGB(16, 4, 20), RGB(12, 2, 10), RGB(22, 5, 25), HAIR_BOB,
          ACC_HAT | ACC_PEARLS | ACC_EARRINGS }, 900 },
};

typedef struct {
    const char *name;
    const char *role;
    const char *intro;   // who the deceased was
    const char *wishes;  // must name the makeup and outfit the family wants
    const char *happy;
    const char *upset;
    PortraitLook look;
    uint16_t voice;
} Family;

// Same order as CAST in data.c.
static const Family FAMILIES[] = {
    { "RHONDA PEMBERTON", "GUS'S DAUGHTER",
      "Dad was a rodeo clown for forty years. He got kicked by a bull named Kevin. Twice.",
      "He wants CLOWN makeup. Full honk. But put him in a SUNDAY SUIT so people know he was serious.",
      "Dad would've honked his nose at this. That means he loved it.",
      "Dad got sat on by a bull once. This was worse.",
      { SKIN_C1, RGB(26, 12, 4), RGB(8, 14, 26), RGB(20, 10, 6), RGB(28, 22, 4), HAIR_LONG, ACC_EARRINGS }, 640 },
    { "BIG LENNY KRUEGER", "DOT'S HUSBAND",
      "My Dot bowled a perfect game twice. Once was at our wedding. She brought her own ball.",
      "Keep her makeup NATURAL. And she goes in her BOWLING SHIRT. Lucky number seven.",
      "Strike! Dot would've called that a strike.",
      "That, pal, was a gutter ball.",
      { SKIN_C2, RGB(10, 10, 10), RGB(4, 16, 18), RGB(16, 6, 8), C_RED, HAIR_BALD, ACC_MUSTACHE | ACC_COLLAR }, 260 },
    { "CONNIE MANCINI", "SAL'S WIFE",
      "Sal was the third-best Elvis impersonator in Reno. Fourth if you count the dog.",
      "GLAM makeup. The sideburns stay. And the SEQUIN JUMPSUIT, obviously.",
      "Thank you. Thank you very much. He'd have said it better.",
      "Sal is rolling in that casket. Which, honestly, you should check.",
      { SKIN_C1, RGB(4, 3, 3), RGB(22, 4, 10), RGB(10, 4, 14), C_GOLD, HAIR_BIG, ACC_EARRINGS | ACC_PEARLS }, 700 },
    { "TODD WILLOUGHBY", "BARB'S SON",
      "Mom ran the HOA for thirty-one years. She once fined a squirrel. It paid.",
      "She left a nine-page memo. GLAM makeup. The FLORAL DRESS. Page six is about you.",
      "Mom would approve. In writing. With a stamp.",
      "I'm going to get fined for this. Somehow. From beyond.",
      { SKIN_C0, RGB(24, 18, 8), RGB(14, 16, 18), RGB(8, 12, 8), RGB(8, 10, 24), HAIR_SHORT, ACC_GLASSES | ACC_TIE | ACC_COLLAR }, 560 },
    { "CRYSTAL HUBBARD", "EARL'S WIFE",
      "Earl drove a monster truck called Big Earl's Revenge. Nobody knows what he was avenging.",
      "NATURAL makeup. And his HAWAIIAN SHIRT. The one with the burn holes.",
      "Earl would've revved his engine for you. That's a compliment.",
      "Earl crushed cars for less than this.",
      { SKIN_C0, RGB(31, 26, 10), RGB(28, 8, 20), RGB(14, 6, 2), RGB(31, 14, 24), HAIR_BIG, ACC_EARRINGS }, 760 },
    { "DR. FEMI OKAFOR", "MAVIS'S SON",
      "Mother judged dog shows for thirty years. She judged people too. Mostly me.",
      "GLAM makeup and her FLORAL DRESS. She would want to be best in show.",
      "Best in show. Mother would agree, which never happens.",
      "Mother would have disqualified you. And the poodle.",
      { SKIN_C4, RGB(3, 3, 3), RGB(6, 8, 14), RGB(6, 14, 12), RGB(26, 22, 6), HAIR_SHORT, ACC_GLASSES | ACC_BOWTIE | ACC_COLLAR }, 480 },
    { "DESHAWN BANKS", "LEROY'S GRANDSON",
      "Grandpa guarded the Pinewood Mall for thirty years. No teen ever loitered on his watch.",
      "NATURAL makeup. And the SUPERHERO CAPE. He wore it on Halloween. And Tuesdays.",
      "Grandpa's on patrol up there now. Thanks.",
      "Grandpa would've written you a ticket. He couldn't, legally. He did anyway.",
      { SKIN_C3, RGB(3, 3, 3), RGB(4, 6, 20), RGB(18, 14, 4), RGB(28, 6, 6), HAIR_CAP, ACC_COLLAR }, 600 },
    { "AGNES DOOLITTLE", "FERN'S SISTER",
      "My sister Fern once knitted a sweater for a car. A whole car. It's still wearing it.",
      "NATURAL makeup, dear. And her FLORAL DRESS. Not the sweater. That stays on the car.",
      "Lovely, dear. I'll knit you something. You can't stop me.",
      "I'm going to knit something rude about you.",
      { SKIN_C0, RGB(26, 26, 27), RGB(18, 8, 16), RGB(16, 12, 18), RGB(30, 18, 22), HAIR_BUN, ACC_GLASSES | ACC_PEARLS }, 820 },
    { "CHUCK RIZZO JR.", "CHUCK'S SON",
      "Pops sold ten thousand used cars. Some of them even had engines.",
      "GLAM makeup. He wore bronzer to the beach. And his lucky HAWAIIAN SHIRT.",
      "You're a closer, kid! Pops would've hired you on the spot.",
      "I want to speak to your manager. Wait, is that a ghost?",
      { SKIN_C1, RGB(6, 4, 2), RGB(30, 14, 4), RGB(4, 10, 20), C_GOLD, HAIR_POMP, ACC_SUNGLASS | ACC_COLLAR }, 450 },
    { "TAMMY PICKETT", "WANDA'S DAUGHTER",
      "Mama sang karaoke every night for twenty-two years. She's banned from four bars.",
      "CLOWN makeup from her clown phase. And the SEQUIN JUMPSUIT. She'd want an encore.",
      "Mama's getting a standing ovation up there.",
      "Mama would've booed. Loudly. On key.",
      { SKIN_C2, RGB(28, 6, 14), RGB(30, 26, 6), RGB(12, 4, 16), RGB(20, 28, 30), HAIR_BIG, ACC_EARRINGS }, 740 },
    { "PROF. GAIL FLOOP", "NED'S WIFE",
      "Ned invented the spork. He also invented the knork. We don't talk about the knork.",
      "CLOWN makeup. He said life was a circus. And the SUPERHERO CAPE. He was a hero. To cutlery.",
      "Half spoon. Half fork. All perfect. Thank you.",
      "That was a knork of a funeral.",
      { SKIN_C0, RGB(18, 12, 6), RGB(10, 18, 10), RGB(18, 16, 6), C_RED, HAIR_BUN, ACC_GLASSES | ACC_COLLAR }, 580 },
};

_Static_assert(sizeof(FAMILIES) / sizeof(FAMILIES[0]) == 11, "one family per cast member");

static const char *const BUDGET_LINES[3] = {
    "We can spend {BUDGET} on the casket. Not a penny more.",
    "Casket budget is {BUDGET}. Please don't upsell me. I can see you thinking about it.",
    "Our budget is {BUDGET}. {FIRST} was cheap. It's what {FIRST} would want.",
};

// Kevin's findings after each disaster: the sabotage trail. Indexed by Disaster.
static const char *const CLUES[DISASTER_COUNT] = {
    "Boss, someone loosened the lid hinges. There was a business card inside. ETERNAL ELEGANCE.",
    "That raccoon had a collar. 'Mr. Fluffington. Property of Eternal Elegance.'",
    "Somebody set the sprinklers to MONSOON. They left a gold-plated wrench.",
    "The fuse box had a sticky note on it. It just says 'xoxo V.'",
    "Those exes said a lady in a giant hat paid them fifty bucks each to show up.",
    "Uncle Ray's phone was brand new. Gift-wrapped. The card says 'From a friend. Wink.'",
    "The lilies came with a note. 'Extra pollen. You're welcome. -V'",
    "Someone greased the casket stand. With fancy imported butter.",
};

// ---------------------------------------------------------------------------
// Scene playback

#define MAX_LINES 14
#define TEXT_MAX 200
#define BOX_COLS 29
#define BOX_ROWS 5

typedef struct {
    uint8_t speaker;
    uint8_t expr;
    char text[TEXT_MAX];
} SceneLine;

static struct {
    bool active;
    SceneLine lines[MAX_LINES];
    int count;
    int line;
    int page;              // which 5-row page of the current line
    int shown;             // characters revealed on this page
    int timer;
    AfterScene after;
    // Wrapped rows of the current line
    char rows[16][BOX_COLS + 1];
    int row_count;
    int profit;
} S;

int daily_goal(int day)
{
    return 7500 + (day - 1) * 1000;
}

static const char *family_first_name(char *buf)
{
    const char *n = CAST[current_funeral()->person].name;
    int i = 0;
    while (n[i] && n[i] != ' ' && i < 15) {
        buf[i] = (i == 0) ? n[i] : (char)(n[i] >= 'A' && n[i] <= 'Z' ? n[i] + 32 : n[i]);
        i++;
    }
    buf[i] = 0;
    return buf;
}

static void expand(char *out, const char *in)
{
    char *o = out;
    char *end = out + TEXT_MAX - 1;
    while (*in && o < end) {
        if (*in == '{') {
            const char *close = strchr(in, '}');
            char key[12] = { 0 };
            if (close && close - in - 1 < (int)sizeof(key)) {
                memcpy(key, in + 1, (size_t)(close - in - 1));
                char val[40] = "";
                if (!strcmp(key, "GOAL")) format_money(val, daily_goal(g.day));
                else if (!strcmp(key, "BUDGET")) format_money(val, current_funeral()->casket_budget);
                else if (!strcmp(key, "PROFIT")) format_money(val, S.profit);
                else if (!strcmp(key, "DAY")) str_cat_int(val, g.day);
                else if (!strcmp(key, "FIRST")) family_first_name(val);
                for (const char *v = val; *v && o < end; v++)
                    *o++ = *v;
                in = close + 1;
                continue;
            }
        }
        *o++ = *in++;
    }
    *o = 0;
}

static void add(Speaker who, Expr expr, const char *text)
{
    if (S.count >= MAX_LINES)
        return;
    SceneLine *l = &S.lines[S.count++];
    l->speaker = (uint8_t)who;
    l->expr = (uint8_t)expr;
    expand(l->text, text);
}

// Word-wraps the current line into rows.
static void wrap_line(void)
{
    const char *t = S.lines[S.line].text;
    S.row_count = 0;
    while (*t && S.row_count < 16) {
        while (*t == ' ')
            t++;
        int len = (int)strlen(t);
        int take = len;
        if (len > BOX_COLS) {
            take = BOX_COLS;
            while (take > 0 && t[take] != ' ')
                take--;
            if (take == 0)
                take = BOX_COLS;
        }
        memcpy(S.rows[S.row_count], t, (size_t)take);
        S.rows[S.row_count][take] = 0;
        S.row_count++;
        t += take;
    }
}

static int page_chars(void)
{
    int n = 0;
    for (int r = S.page * BOX_ROWS; r < S.row_count && r < (S.page + 1) * BOX_ROWS; r++)
        n += (int)strlen(S.rows[r]);
    return n;
}

static void begin(AfterScene after)
{
    S.active = S.count > 0;
    S.line = 0;
    S.page = 0;
    S.shown = 0;
    S.timer = 0;
    S.after = after;
    if (S.active)
        wrap_line();
    else
        game_after_scene(after);
}

static void reset(void)
{
    S.count = 0;
}

bool story_active(void) { return S.active; }

Speaker story_speaker(void)
{
    return S.active ? (Speaker)S.lines[S.line].speaker : SPK_COUNT;
}

bool story_features(Speaker s)
{
    if (!S.active)
        return false;
    for (int i = 0; i < S.count; i++)
        if (S.lines[i].speaker == s)
            return true;
    return false;
}

// ---------------------------------------------------------------------------
// Scenes

void story_day_intro(void)
{
    reset();
    if (g.day == 1) {
        add(SPK_MORT, EXPR_HAPPY, "Kiddo! You made it! It's me, your Great-Uncle Mort!");
        add(SPK_MORT, EXPR_SHOCK, "Yes, I'm a ghost. I passed last Tuesday. Slipped on a casket brochure.");
        add(SPK_MORT, EXPR_HAPPY, "I left you Grave Mistakes in my will. Congratulations! Also, it's broke.");
        add(SPK_KEVIN, EXPR_SMUG, "Hey. I'm Kevin. The intern. I'm on break.");
        add(SPK_MORT, EXPR_NEUTRAL, "He's been on break since 2019.");
        add(SPK_VIVIAN, EXPR_SMUG, "Darling! Vivian Vance-Prestige, of ETERNAL ELEGANCE. Across the street. The nice one.");
        add(SPK_VIVIAN, EXPR_SMUG, "I'll buy this dump for one dollar. Or you can make {GOAL} today and pretend you're a business.");
        add(SPK_VIVIAN, EXPR_HAPPY, "Ta-ta! Try not to lose anybody.");
        add(SPK_MORT, EXPR_ANGRY, "That woman stole my parking spot in 1987 and NEVER gave it back.");
        add(SPK_MORT, EXPR_HAPPY, "Three funerals today. Prep 'em, run 'em, make {GOAL}. Easy! Tap a booking to start.");
        add(SPK_KEVIN, EXPR_NEUTRAL, "I'll be on break if you need me.");
    } else {
        static const char *const QUIPS[] = {
            "I brought a sandwich for my break. And a backup sandwich for my other break.",
            "I alphabetized the caskets. By color.",
            "Someone left a fruit basket from Eternal Elegance. I ate it. It was fine. Probably.",
            "Morning. Is it morning? I've been on break.",
        };
        add(SPK_MORT, EXPR_HAPPY, "Day {DAY}, kiddo! Three more funerals. Vivian wants {GOAL} or she's back with that dollar.");
        add(SPK_KEVIN, EXPR_SMUG, QUIPS[rng_range(4)]);
    }
    begin(AFTER_NOTHING);
}

void story_family_meeting(void)
{
    reset();
    const Family *fam = &FAMILIES[current_funeral()->person];
    add(SPK_FAMILY, EXPR_SAD, fam->intro);
    add(SPK_FAMILY, EXPR_NEUTRAL, fam->wishes);
    add(SPK_FAMILY, EXPR_SMUG, BUDGET_LINES[current_funeral()->person % 3]);
    begin(AFTER_OPEN_PREP);
}

void story_service_tutorial(void)
{
    reset();
    add(SPK_MORT, EXPR_NEUTRAL, "First service! Fair warning: services here always go a little... sideways.");
    add(SPK_MORT, EXPR_SHOCK, "When something breaks, tap the right quick fix down here. FAST.");
    add(SPK_MORT, EXPR_SAD, "Pick wrong and it gets worse. Wait too long and they want a refund.");
    add(SPK_KEVIN, EXPR_SMUG, "I'll supervise. From the snack table.");
    begin(AFTER_START_SERVICE);
}

void story_after_service(void)
{
    reset();
    Funeral *f = current_funeral();
    add(SPK_KEVIN, EXPR_SHOCK, CLUES[f->disaster]);
    int clues = g.current + 1;   // one clue per service so far today
    if (g.day == 1 && clues == 1)
        add(SPK_MORT, EXPR_ANGRY, "Sabotage?! In MY funeral home? Keep your eyes open, kiddo.");
    else if (g.day == 1 && clues == 2)
        add(SPK_MORT, EXPR_ANGRY, "Twice! Someone with a lot of money and a very big hat...");
    else
        add(SPK_MORT, EXPR_ANGRY, "VIVIAN!!");
    const Family *fam = &FAMILIES[f->person];
    if (f->satisfaction >= 60)
        add(SPK_FAMILY, EXPR_HAPPY, fam->happy);
    else
        add(SPK_FAMILY, EXPR_ANGRY, fam->upset);
    begin(AFTER_NOTHING);
}

void story_midday_visit(void)
{
    reset();
    add(SPK_VIVIAN, EXPR_SMUG, "Still open, darling? How quaint. Like a cottage. That's on fire.");
    add(SPK_KEVIN, EXPR_SHOCK, "Why is there a raccoon in your purse?");
    add(SPK_VIVIAN, EXPR_SHOCK, "That is a very expensive ferret. Mind your business.");
    add(SPK_MORT, EXPR_SMUG, "One more funeral, kiddo. Let's ruin her afternoon.");
    begin(AFTER_NOTHING);
}

void story_day_end(int profit)
{
    reset();
    S.profit = profit;
    if (profit >= daily_goal(g.day)) {
        add(SPK_VIVIAN, EXPR_ANGRY, "{PROFIT}?! That's impossible! Do you know what my raccoon costs?!");
        add(SPK_MORT, EXPR_HAPPY, "Ha! Did you see her hat shake? Best day since I died!");
    } else {
        add(SPK_VIVIAN, EXPR_SMUG, "{PROFIT}? Adorable. My offer stands. One dollar. I'll even round up.");
        add(SPK_MORT, EXPR_SAD, "Chin up, kiddo. She's not getting this place. I'm haunting the deed.");
    }
    if (g.day == 1)
        add(SPK_MORT, EXPR_ANGRY, "And now we know who's behind every disaster. Tomorrow, we get even.");
    add(SPK_KEVIN, EXPR_SMUG, "Can I go home? I've been on break for nine hours.");
    begin(AFTER_NOTHING);
}

// ---------------------------------------------------------------------------
// Update and draw

#define SKIP_X 200
#define SKIP_Y 88
#define SKIP_W 52
#define SKIP_H 16

static uint16_t voice_of(const SceneLine *l)
{
    if (l->speaker == SPK_FAMILY)
        return FAMILIES[current_funeral()->person].voice;
    return REGULARS[l->speaker].voice;
}

static void finish(void)
{
    S.active = false;
    game_after_scene(S.after);
}

void story_update(bool tapped, int tx, int ty, bool advance)
{
    if (!S.active)
        return;
    S.timer++;
    int total = page_chars();
    if (S.shown < total) {
        S.shown++;
        if (S.shown % 3 == 1)
            sfx_blip(voice_of(&S.lines[S.line]));
    }
    if (tapped && tx >= SKIP_X && tx < SKIP_X + SKIP_W && ty >= SKIP_Y && ty < SKIP_Y + SKIP_H) {
        sfx_play(SFX_TAP);
        finish();
        return;
    }
    if (!(tapped || advance))
        return;
    if (S.shown < total) {
        S.shown = total;
        return;
    }
    if ((S.page + 1) * BOX_ROWS < S.row_count) {
        S.page++;
        S.shown = 0;
        return;
    }
    if (++S.line >= S.count) {
        finish();
        return;
    }
    S.page = 0;
    S.shown = 0;
    wrap_line();
}

void story_draw(Canvas *c)
{
    const SceneLine *l = &S.lines[S.line];
    const PortraitLook *look;
    const char *name, *role;
    if (l->speaker == SPK_FAMILY) {
        const Family *fam = &FAMILIES[current_funeral()->person];
        look = &fam->look;
        name = fam->name;
        role = fam->role;
    } else {
        look = &REGULARS[l->speaker].look;
        name = REGULARS[l->speaker].name;
        role = REGULARS[l->speaker].role;
    }
    gfx_clear(c, C_PLUM);
    for (int y = 0; y < 104; y += 4)
        hline(c, 0, y, SCREEN_W, C_PLUM2);
    bool talking = S.shown < page_chars();
    draw_portrait(c, 6, 6, look, (Expr)l->expr, talking, g.frame);

    // Name plate
    int nw = text_width(name, 1) + 12;
    if (nw > 150) nw = 150;
    panel(c, 100, 12, nw, 14, look->coat, C_GOLD);
    draw_text(c, 106, 15, name, C_WHITE);
    draw_text(c, 102, 32, role, C_DIM);

    // Scene progress pips
    for (int i = 0; i < S.count; i++)
        fill_rect(c, 102 + i * 7, 50, 5, 5, i < S.line ? C_GOLD : i == S.line ? C_CREAM : RGB(12, 8, 15));

    // SKIP
    panel(c, SKIP_X, SKIP_Y, SKIP_W, SKIP_H, RGB(9, 5, 12), C_CREAM);
    draw_text(c, SKIP_X + 10, SKIP_Y + 4, "SKIP", C_CREAM);

    // Text box with typewriter reveal
    panel(c, 4, 108, 248, 80, C_CREAM, look->coat);
    panel(c, 5, 109, 246, 78, C_CREAM, C_GOLD);
    int left = S.shown;
    for (int r = 0; r < BOX_ROWS; r++) {
        int row = S.page * BOX_ROWS + r;
        if (row >= S.row_count || left <= 0)
            break;
        char buf[BOX_COLS + 1];
        int len = (int)strlen(S.rows[row]);
        int take = left < len ? left : len;
        memcpy(buf, S.rows[row], (size_t)take);
        buf[take] = 0;
        draw_text(c, 12, 114 + r * 14, buf, C_INK);
        left -= take;
    }
    if (!talking && (g.frame / 20) % 2) {
        // "more" arrow
        for (int k = 0; k < 4; k++)
            hline(c, 233 + k, 176 + k, 7 - 2 * k, RGB(20, 6, 8));
    }
}
