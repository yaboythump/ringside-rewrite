// Headless playthrough of Grave Mistakes on Retro Duo's melonDS core.
//
// Plays a whole day with the stylus only: three funerals, all four prep steps,
// a disaster during every service, and the end-of-day money screen. The test
// reads both screens with the game's own 8x8 font, so it checks what a player
// would actually see.
#include "MDCore.h"

extern "C" {
#include "../source/game.h"
}
#include "../source/font8.h"

#include <chrono>
#include <cmath>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

static int failures = 0;
static void check(bool ok, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    printf(ok ? "ok   " : "FAIL ");
    vprintf(fmt, ap);
    printf("\n");
    va_end(ap);
    if (!ok)
        failures++;
}

typedef std::vector<uint32_t> Screen;

struct Emu {
    MDCore *core = nullptr;
    Screen top = Screen(256 * 192), bottom = Screen(256 * 192);
    double peak = 0;
    const char *outdir = ".";

    void frames(int n)
    {
        uint64_t start = MDCoreCopyScreens(core, nullptr, nullptr);
        float l[1024], r[1024];
        auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(60);
        while (MDCoreCopyScreens(core, nullptr, nullptr) < start + (uint64_t)n && std::chrono::steady_clock::now() < deadline) {
            std::this_thread::sleep_for(std::chrono::microseconds(500));
            size_t got = MDCoreReadAudio(core, l, r, 1024);
            for (size_t i = 0; i < got; i++)
                peak = std::fmax(peak, std::fabs(l[i]));
        }
        MDCoreCopyScreens(core, top.data(), bottom.data());
    }
    void touch(int x, int y) { MDCoreSetTouch(core, true, x, y); }
    void lift() { MDCoreSetTouch(core, false, 0, 0); }
    void tap(int x, int y)
    {
        touch(x, y);
        frames(5);
        lift();
        frames(7);
    }
    void shot(const char *name)
    {
        char path[1024];
        snprintf(path, sizeof path, "%s/%s.ppm", outdir, name);
        FILE *f = fopen(path, "wb");
        if (!f)
            return;
        fprintf(f, "P6\n256 384\n255\n");
        for (const Screen *s : { &top, &bottom })
            for (uint32_t p : *s) {
                fputc(p & 0xFF, f);
                fputc((p >> 8) & 0xFF, f);
                fputc((p >> 16) & 0xFF, f);
            }
        fclose(f);
    }
};

// ---------------------------------------------------------------------------
// Screen reading with the game's font

static uint32_t px(const Screen &s, int x, int y) { return (x < 0 || y < 0 || x >= 256 || y >= 192) ? 0xDEADBEEF : s[y * 256 + x] & 0xFFFFFF; }

static bool glyph_at(const Screen &s, int x, int y, char ch, uint32_t color)
{
    const unsigned char *g = FONT8[(unsigned char)ch - 32];
    for (int r = 0; r < 8; r++)
        for (int c = 0; c < 8; c++) {
            bool on = g[r] & (0x80 >> c);
            if (on != (px(s, x + c, y + r) == color))
                return false;
        }
    return true;
}

static bool first_lit(char ch, int *fx, int *fy)
{
    const unsigned char *g = FONT8[(unsigned char)ch - 32];
    for (int r = 0; r < 8; r++)
        for (int c = 0; c < 8; c++)
            if (g[r] & (0x80 >> c)) {
                *fx = c;
                *fy = r;
                return true;
            }
    return false;
}

static bool text_at(const Screen &s, int x, int y, const char *text)
{
    int fx, fy;
    if (!first_lit(text[0], &fx, &fy))
        return false;
    uint32_t color = px(s, x + fx, y + fy);
    for (int i = 0; text[i]; i++)
        if (!glyph_at(s, x + i * 8, y, text[i], color))
            return false;
    return true;
}

static bool find_text(const Screen &s, const char *text, int *ox = nullptr, int *oy = nullptr)
{
    for (int y = 0; y <= 184; y++)
        for (int x = 0; x <= 256 - 8 * (int)strlen(text); x++)
            if (text_at(s, x, y, text)) {
                if (ox) *ox = x;
                if (oy) *oy = y;
                return true;
            }
    return false;
}

// Reads glyphs at a known position until a cell matches nothing (or only blanks remain).
static std::string read_text(const Screen &s, int x, int y, int max_chars = 30)
{
    std::string out;
    uint32_t color = 0;
    bool have_color = false;
    int blanks = 0;
    for (int i = 0; i < max_chars; i++) {
        int cx = x + i * 8;
        char found = 0;
        for (int ch = 33; ch < 127 && !found; ch++) {
            int fx, fy;
            first_lit((char)ch, &fx, &fy);
            uint32_t c = have_color ? color : px(s, cx + fx, y + fy);
            if (glyph_at(s, cx, y, (char)ch, c)) {
                found = (char)ch;
                color = c;
                have_color = true;
            }
        }
        if (!found) {
            if (have_color && glyph_at(s, cx, y, ' ', color) && ++blanks < 2) {
                out += ' ';
                continue;
            }
            break;
        }
        blanks = 0;
        out += found;
    }
    while (!out.empty() && out.back() == ' ')
        out.pop_back();
    return out;
}

static int parse_money(const std::string &s)
{
    int sign = 1, v = 0;
    bool any = false;
    for (char c : s) {
        if (c == '-') sign = -1;
        if (c >= '0' && c <= '9') { v = v * 10 + (c - '0'); any = true; }
    }
    return any ? sign * v : -999999;
}

template <typename F> static bool wait_for(Emu &emu, int max_frames, F cond, int step = 4)
{
    for (int f = 0; f < max_frames; f += step) {
        if (cond())
            return true;
        emu.frames(step);
    }
    return cond();
}

static int find_index(const char *const *names, int n, const std::string &s)
{
    for (int i = 0; i < n; i++)
        if (s == names[i])
            return i;
    return -1;
}

// Layout constants mirrored from source/game.c
static int card_y(int i) { return 24 + i * 54; }
static int fix_x(int i) { return 6 + (i % 2) * 124; }
static int fix_y(int i) { return 70 + (i / 2) * 24; }

static std::vector<uint8_t> read_file(const char *path)
{
    FILE *f = fopen(path, "rb");
    if (!f) { fprintf(stderr, "cannot open %s\n", path); exit(2); }
    std::vector<uint8_t> d;
    int c;
    while ((c = fgetc(f)) != EOF) d.push_back((uint8_t)c);
    fclose(f);
    return d;
}

int main(int argc, char **argv)
{
    if (argc < 3) { fprintf(stderr, "usage: playthrough_test game.nds outdir\n"); return 2; }
    auto rom = read_file(argv[1]);
    Emu emu;
    emu.outdir = argv[2];
    emu.core = MDCoreCreate(48000);
    check(MDCoreLoadROM(emu.core, rom.data(), rom.size(), nullptr, 0, "Grave Mistakes"), "game loads");
    char title[13];
    MDCoreTitle(emu.core, title);
    check(strcmp(title, "GRAVEMISTAKE") == 0, "cartridge title is GRAVEMISTAKE (got %s)", title);
    MDCoreSetRunning(emu.core, true);

    // Title screen
    emu.frames(90);
    emu.shot("01_title");
    check(find_text(emu.top, "FUNERAL HOME & CHAPEL"), "top screen shows the funeral home");
    check(find_text(emu.bottom, "TAP TO OPEN UP"), "touch screen says tap to open");
    emu.tap(128, 135);
    emu.frames(10);
    emu.shot("02_bookings");
    check(find_text(emu.bottom, "DAY 1 BOOKINGS"), "bookings for day 1 are shown");

    std::string names[3];
    for (int i = 0; i < 3; i++) {
        names[i] = read_text(emu.bottom, 10, card_y(i) + 17);
        bool known = false;
        for (int k = 0; k < CAST_COUNT; k++)
            known |= names[i] == CAST[k].name;
        check(known, "booking %d is for %s", i + 1, names[i].c_str());
    }
    check(names[0] != names[1] && names[1] != names[2] && names[0] != names[2], "three different funerals");
    check(find_text(emu.bottom, "LATER"), "later funerals wait their turn");
    check(find_text(emu.top, "GRAVE MISTAKES CHAPEL"), "top screen shows the empty chapel before the first service");

    int nets[3] = { 0, 0, 0 };
    int moods[3] = { 0, 0, 0 };
    double service_peak = 0;

    for (int i = 0; i < 3; i++) {
        char tag[64];
        const Person *person = nullptr;
        for (int k = 0; k < CAST_COUNT; k++)
            if (names[i] == CAST[k].name)
                person = &CAST[k];
        if (!person) { check(false, "funeral %d has a known person", i + 1); break; }

        // ---- Prep ----
        emu.tap(176 + 36, card_y(i) + 25);
        emu.frames(4);
        check(read_text(emu.bottom, 4, 6) == names[i], "prep screen opens for %s", names[i].c_str());
        check(find_text(emu.top, ("PREP ROOM: " + names[i]).c_str()), "top screen moves to the prep room");
        check(find_text(emu.bottom, "START SERVICE"), "start button is on the prep screen");

        // Embalming: hold the pump and let go in the green.
        emu.tap(32, 33);
        if (i == 1) {
            // Overdo it first, then redo it properly.
            emu.touch(68, 100);
            bool much = wait_for(emu, 400, [&] { return find_text(emu.bottom, "TOO MUCH"); }, 2);
            emu.lift();
            emu.frames(6);
            check(much && find_text(emu.bottom, "TOO MUCH") && find_text(emu.bottom, "(TAP PUMP"), "over-pumping is recorded as TOO MUCH");
            emu.shot("04_overpumped");
        }
        emu.touch(68, 100);
        bool right = wait_for(emu, 400, [&] { return find_text(emu.bottom, "JUST RIGHT"); }, 2);
        emu.frames(8);
        emu.lift();
        emu.frames(6);
        check(right && find_text(emu.bottom, "JUST RIGHT"), "embalming lands in the green");

        // Makeup: pick what the family wants and rub it on.
        emu.tap(96, 33);
        std::string wants = read_text(emu.bottom, 6 + 7 * 8, 50);
        int makeup = find_index(MAKEUP_NAMES, MAKEUP_COUNT, wants);
        check(makeup == person->makeup_wish, "family wants %s makeup", wants.c_str());
        if (makeup < 0) makeup = 0;
        emu.tap(8 + makeup * 82 + 38, 70);
        check(find_text(emu.bottom, "MATCH!"), "chosen makeup matches the wish");
        for (int y = 86; y <= 156; y += 7) {
            for (int x = (y / 7) % 2 ? 92 : 166; (y / 7) % 2 ? x <= 166 : x >= 92; x += (y / 7) % 2 ? 6 : -6) {
                emu.touch(x, y);
                emu.frames(1);
            }
        }
        emu.lift();
        emu.frames(4);
        int coverage = atoi(read_text(emu.bottom, 8, 106).c_str());
        check(coverage >= 90, "scrubbing covers the face (%d%%)", coverage);
        if (i == 0) emu.shot("05_makeup");

        // Outfit: flip through the rack until it matches, then dress.
        emu.tap(160, 33);
        wants = read_text(emu.bottom, 6 + 7 * 8, 50);
        check(find_index(OUTFIT_NAMES, OUTFIT_COUNT, wants) == person->outfit_wish, "family wants a %s", wants.c_str());
        for (int k = 0; k < OUTFIT_COUNT && !find_text(emu.bottom, "MATCH!"); k++)
            emu.tap(226, 96);
        check(find_text(emu.bottom, "MATCH!"), "found the requested outfit on the rack");
        emu.tap(128, 154);
        check(find_text(emu.bottom, "WEARING"), "dressed in the %s", wants.c_str());
        if (i == 0) emu.shot("06_outfit");

        // Casket: read the budget and pick.
        emu.tap(224, 33);
        int budget = parse_money(read_text(emu.bottom, 6 + 8 * 8, 50));
        check(budget >= 1500 && budget <= 6000, "casket budget is $%d", budget);
        int casket = 0;
        for (int k = 0; k < CASKET_COUNT; k++)
            if (CASKET_PRICE[k] <= budget)
                casket = k;
        bool over_budget = false;
        if (i == 2 && budget < CASKET_PRICE[CASKET_GOLD]) {
            casket = CASKET_GOLD;   // upsell the family. They will not love this.
            over_budget = true;
        }
        emu.tap(6 + casket * 84 + 39, 110);
        check(find_text(emu.bottom, "CHOSEN"), "picked the %s", CASKET_NAMES[casket]);
        check(find_text(emu.top, CASKET_NAMES[casket]), "chosen casket waits in the prep room");
        snprintf(tag, sizeof tag, "07_prep_done_%d", i + 1);
        emu.shot(tag);
        int done_tabs = 0;
        for (int t = 0; t < 4; t++)
            done_tabs += text_at(emu.bottom, t * 64 + 32 - 16, 22 + 12, "DONE");
        check(done_tabs == 4, "all four prep steps are done (%d/4)", done_tabs);

        // ---- Service ----
        emu.tap(128, 177);
        emu.frames(6);
        check(find_text(emu.bottom, ("SERVICE: " + names[i]).c_str()), "service for %s begins", names[i].c_str());
        check(find_text(emu.top, ("IN MEMORY: " + names[i]).c_str()), "top screen shows the chapel in memory of %s", names[i].c_str());
        Screen early = emu.top;
        emu.frames(150);
        int changed = 0;
        for (int y = 12; y < 192; y++)
            for (int x = 0; x < 256; x++)
                changed += px(early, x, y) != px(emu.top, x, y);
        check(changed > 300, "mourners arrive in the chapel (%d pixels changed)", changed);
        emu.peak = 0;
        bool disaster = wait_for(emu, 1500, [&] { return find_text(emu.bottom, "QUICK!"); });
        service_peak = std::fmax(service_peak, emu.peak);
        check(disaster, "a disaster strikes during the service");
        std::string line1 = read_text(emu.bottom, 10, 27);
        int d = -1;
        for (int k = 0; k < DISASTER_COUNT; k++)
            if (line1 == DISASTERS[k].line1)
                d = k;
        check(d >= 0, "disaster: %s", line1.c_str());
        if (d < 0) d = 0;
        bool uhoh = wait_for(emu, 40, [&] { return find_text(emu.top, "!!! UH-OH !!!"); }, 2);
        check(uhoh, "top screen panics too");
        emu.frames(20);
        snprintf(tag, sizeof tag, "08_disaster_%d", i + 1);
        emu.shot(tag);

        int expected_fix_cost = 0;
        if (i == 0) {
            int wrong = (d + 1) % DISASTER_COUNT;
            emu.tap(fix_x(wrong) + 60, fix_y(wrong) + 10);
            check(find_text(emu.bottom, FIXES[wrong].wrong), "wrong fix backfires: %s", FIXES[wrong].wrong);
            check(find_text(emu.bottom, "QUICK!"), "disaster is still going after a wrong fix");
            expected_fix_cost += FIXES[wrong].cost;
        }
        if (i < 2) {
            emu.tap(fix_x(d) + 60, fix_y(d) + 10);
            check(find_text(emu.bottom, "FIXED! CRISIS AVERTED."), "%s fixes it", FIXES[d].label);
            expected_fix_cost += FIXES[d].cost;
            emu.frames(30);
            check(find_text(emu.top, DISASTERS[d].fixed), "top screen shows: %s", DISASTERS[d].fixed);
        } else {
            bool slow = wait_for(emu, 700, [&] { return find_text(emu.bottom, "TOO SLOW! THEY WANT A REFUND."); });
            check(slow, "ignoring the disaster runs out the clock");
        }
        snprintf(tag, sizeof tag, "09_fixed_%d", i + 1);
        emu.shot(tag);

        bool complete = wait_for(emu, 1500, [&] { return find_text(emu.bottom, "SERVICE COMPLETE"); });
        check(complete, "service %d completes", i + 1);
        snprintf(tag, sizeof tag, "10_result_%d", i + 1);
        emu.shot(tag);

        // ---- Money for this funeral ----
        const int ax = 168;
        int fee = parse_money(read_text(emu.bottom, ax, 38));
        int sale = parse_money(read_text(emu.bottom, ax, 48));
        int tip = parse_money(read_text(emu.bottom, ax, 58));
        int cost = parse_money(read_text(emu.bottom, ax, 68));
        int supplies = parse_money(read_text(emu.bottom, ax, 78));
        int fixes = parse_money(read_text(emu.bottom, ax, 88));
        int refund = parse_money(read_text(emu.bottom, ax, 98));
        int net = parse_money(read_text(emu.bottom, ax, 112));
        check(fee == SERVICE_FEE, "service fee $%d", fee);
        check(sale == CASKET_PRICE[casket] && cost == -CASKET_COST[casket], "casket sold for $%d, cost $%d", sale, -cost);
        check(supplies == -SUPPLIES_COST, "supplies $%d", -supplies);
        check(fixes == -expected_fix_cost, "quick fixes cost $%d (expected $%d)", -fixes, expected_fix_cost);
        check(refund == (i == 2 ? -REFUND_TIMEOUT : 0), "refund $%d", -refund);
        check(net == fee + sale + tip + cost + supplies + fixes + refund, "net $%d adds up", net);
        std::string mood = read_text(emu.bottom, 12, 126);
        moods[i] = atoi(mood.c_str() + strlen("FAMILY MOOD: "));
        int expect_mood = i < 2 ? 100 : (over_budget ? 40 : 70);
        check(moods[i] == expect_mood, "family mood %d%% (expected %d%%)", moods[i], expect_mood);
        check(tip == (moods[i] >= 60 ? (moods[i] - 50) * 20 : 0), "tip $%d follows the mood", tip);
        nets[i] = net;
        emu.tap(128, 177);
        emu.frames(6);
    }

    check(service_peak > 0.02, "the organ plays during services (peak %.3f)", service_peak);

    // ---- End of day ----
    emu.frames(20);
    emu.shot("11_day_end");
    check(find_text(emu.bottom, "END OF DAY 1"), "end-of-day money screen");
    int profit = parse_money(read_text(emu.bottom, 168, 76));
    check(profit == nets[0] + nets[1] + nets[2], "profit $%d is the sum of the three funerals", profit);
    int avg = (moods[0] + moods[1] + moods[2]) / 3;
    int stars = avg >= 90 ? 5 : avg >= 75 ? 4 : avg >= 60 ? 3 : avg >= 40 ? 2 : 1;
    char rating[32];
    snprintf(rating, sizeof rating, "RATING: %d/5 STARS", stars);
    check(find_text(emu.bottom, rating), "%s", rating);
    emu.tap(128, 177);
    emu.frames(10);
    check(find_text(emu.bottom, "DAY 2 BOOKINGS"), "a new day starts");
    emu.shot("12_day2");

    printf("speed: %.1f frames per second\n", MDCoreSpeed(emu.core));
    MDCoreDestroy(emu.core);
    printf(failures ? "\n%d check(s) failed\n" : "\nall playthrough checks passed\n", failures);
    return failures ? 1 : 0;
}
