// Grave Mistakes: shared game state for the funeral home day.
#ifndef GAME_H
#define GAME_H

#include <stdbool.h>
#include <stdint.h>

#define FUNERALS_PER_DAY 3

typedef enum {
    STATE_TITLE,
    STATE_BOOKINGS,
    STATE_PREP,
    STATE_SERVICE,
    STATE_RESULT,
    STATE_DAY_END,
} GameState;

typedef enum { TAB_EMBALM, TAB_MAKEUP, TAB_OUTFIT, TAB_CASKET, TAB_COUNT } PrepTab;

typedef enum { EMBALM_NONE, EMBALM_LOW, EMBALM_RIGHT, EMBALM_HIGH } EmbalmResult;

enum { MAKEUP_NATURAL, MAKEUP_GLAM, MAKEUP_CLOWN, MAKEUP_COUNT };
enum { OUTFIT_SUIT, OUTFIT_FLORAL, OUTFIT_HAWAIIAN, OUTFIT_BOWLING, OUTFIT_SEQUIN, OUTFIT_CAPE, OUTFIT_COUNT };
enum { CASKET_PINE, CASKET_OAK, CASKET_GOLD, CASKET_COUNT };

typedef enum {
    DISASTER_LID,
    DISASTER_RACCOON,
    DISASTER_SPRINKLERS,
    DISASTER_POWER,
    DISASTER_EXES,
    DISASTER_RINGTONE,
    DISASTER_SNEEZING,
    DISASTER_ROLLING,
    DISASTER_COUNT,
} Disaster;

typedef enum { SERVICE_ARRIVING, SERVICE_EULOGY, SERVICE_DISASTER, SERVICE_FIXED, SERVICE_LEAVING } ServicePhase;

#define MAKEUP_GRID 8   // the face is split into 8x8 cells that the stylus scrubs

typedef struct {
    int person;            // index into the cast of characters
    int hour;              // 10, 13 or 16
    int casket_budget;
    // Prep
    int embalm;            // EmbalmResult
    int makeup_style;      // -1 until picked
    uint8_t makeup_cells[MAKEUP_GRID * MAKEUP_GRID];
    int makeup_coverage;   // 0-100
    int outfit;            // currently shown outfit
    bool outfit_done;
    int casket;            // -1 until picked
    // Service
    int disaster;
    int wrong_fixes;
    bool timed_out;
    int fix_costs;
    bool done;
    bool met;              // the family meeting has happened
    // Results
    int satisfaction;      // 0-100
    const char *notes[3];  // what the family thought
    int note_count;
    int fee, casket_sale, casket_cost, supplies, tip, refund;
} Funeral;

typedef struct {
    const char *name;
    const char *trait;
    const char *eulogy;    // second line the director reads out
    int makeup_wish;
    int outfit_wish;
    uint8_t hair_r, hair_g, hair_b;
    bool long_hair;
} Person;

typedef struct {
    const char *label;
    int cost;
    const char *wrong;     // what happens when used on the wrong disaster
} QuickFix;

typedef struct {
    const char *line1, *line2;   // shown on the touch screen
    const char *fixed;           // caption once fixed
} DisasterInfo;

typedef struct {
    GameState state;
    uint32_t frame;
    uint32_t rng;
    int day;
    int current;           // funeral being prepped or served
    Funeral funerals[FUNERALS_PER_DAY];
    // Prep screen
    PrepTab tab;
    int outfit_view;       // outfit shown on the rack
    int pump;              // embalming pressure 0-1000 while holding
    bool pumping;
    // Service
    ServicePhase phase;
    int phase_timer;
    int service_timer;
    int disaster_at;
    int fix_timer;         // frames left to fix the disaster
    const char *flash_msg; // short-lived feedback on the touch screen
    int flash_timer;
    bool flash_good;
    int last_fix;          // quick fix shown on the top screen
    // Day totals
    int best_profit;
    bool tutorial_done;    // Mort's first-service briefing
} Game;

extern Game g;
extern const Person CAST[];
extern const int CAST_COUNT;
extern const char *const MAKEUP_NAMES[MAKEUP_COUNT];
extern const char *const OUTFIT_NAMES[OUTFIT_COUNT];
extern const char *const CASKET_NAMES[CASKET_COUNT];
extern const int CASKET_PRICE[CASKET_COUNT];
extern const int CASKET_COST[CASKET_COUNT];
extern const QuickFix FIXES[DISASTER_COUNT];
extern const DisasterInfo DISASTERS[DISASTER_COUNT];

#define SERVICE_FEE 1200
#define SUPPLIES_COST 260
#define FIX_TIME (8 * 60)
#define REFUND_TIMEOUT 600

uint32_t rng_next(void);
int rng_range(int n);

Funeral *current_funeral(void);
bool prep_tab_done(const Funeral *f, PrepTab tab);
bool prep_complete(const Funeral *f);
void finish_funeral(Funeral *f);

void game_init(void);
// read_input is false for catch-up ticks that reuse this frame's touch state.
void game_update(bool read_input);
void game_draw(void);

#endif
