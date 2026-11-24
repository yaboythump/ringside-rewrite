// RetroAchievements for Retro Duo: a small C layer over rcheevos' rc_client, so Swift deals in
// plain callbacks and strings. Everything here runs on the main thread: the app performs the
// web requests and hands the answers back with RDAchRequestDone.
#ifndef RD_ACHIEVEMENTS_H
#define RD_ACHIEVEMENTS_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct RDAch RDAch;
typedef struct RDAchRequest RDAchRequest;

enum {
    RD_ACH_LOGIN = 1, // a sign-in finished
    RD_ACH_GAME = 2,  // a game finished loading (or wasn't recognized)
};

enum {
    RD_ACH_EVENT_UNLOCKED = 1,   // [item] was earned
    RD_ACH_EVENT_COMPLETED = 2,  // every achievement in the game is earned
    RD_ACH_EVENT_OFFLINE = 3,    // an unlock couldn't be sent yet (it's retried)
    RD_ACH_EVENT_ONLINE = 4,     // pending unlocks were sent
    RD_ACH_EVENT_ERROR = 5,      // the server refused something; message in [item].title
};

typedef struct {
    uint32_t id;
    uint32_t points;
    const char *title;
    const char *description;
    const char *badgeURL;     // the badge as shown for this item's state (may be NULL)
    const char *progress;     // such as "3/10", or ""
    float percent;
    int unlocked;
} RDAchItem;

typedef struct {
    void *context;
    // Reads one byte at a console address (as ConsoleBackend.peek takes them).
    // Returns the byte, or a value above 0xFF where nothing can be read.
    uint32_t (*read)(void *context, uint32_t address);
    // Performs a web request: POST `post` (form data) to `url`, or GET when `post` is NULL.
    // Answer with RDAchRequestDone(request, ...), exactly once, on the main thread.
    void (*request)(void *context, const char *url, const char *post, const char *contentType, RDAchRequest *request);
    // A sign-in or game load finished. `ok` is 1 on success; `message` explains a failure.
    void (*finished)(void *context, int what, int ok, const char *message);
    void (*event)(void *context, int type, const RDAchItem *item);
} RDAchCallbacks;

RDAch *RDAchCreate(RDAchCallbacks callbacks);
void RDAchDestroy(RDAch *ach);
/// The server to use, such as "https://retroachievements.org" (tests point it elsewhere).
void RDAchSetHost(RDAch *ach, const char *host);
/// "rcheevos/12.5" and the like, to add to the app's User-Agent.
void RDAchUserAgentClause(RDAch *ach, char *buffer, size_t size);
void RDAchRequestDone(RDAchRequest *request, int httpStatus, const char *body, size_t length);

void RDAchLoginWithPassword(RDAch *ach, const char *username, const char *password);
void RDAchLoginWithToken(RDAch *ach, const char *username, const char *token);
void RDAchLogout(RDAch *ach);
/// The signed-in player (NULL when signed out), their API token and points.
const char *RDAchUserName(RDAch *ach);
const char *RDAchUserToken(RDAch *ach);
uint32_t RDAchUserScore(RDAch *ach);

/// RetroAchievements' console number for Retro Duo's file extensions ("gb", "nds", ...), or 0.
uint32_t RDAchConsoleID(const char *extension);
/// Where a RetroAchievements address lives on the console. Returns 0 if it isn't readable here.
int RDAchConsoleAddress(uint32_t consoleID, uint32_t address, uint32_t *consoleAddress);

/// Identifies the game file (by hash) and loads its achievements; RD_ACH_GAME reports back.
void RDAchLoadGame(RDAch *ach, uint32_t consoleID, const char *path);
void RDAchUnloadGame(RDAch *ach);
/// Call once per emulated frame; RDAchIdle about once a second while paused.
void RDAchDoFrame(RDAch *ach);
void RDAchIdle(RDAch *ach);
/// After loading a save state: rewinds achievement progress to match.
void RDAchReset(RDAch *ach);

/// The loaded game's title (NULL if none), and how many achievements and points are earned.
const char *RDAchGameTitle(RDAch *ach);
void RDAchGameSummary(RDAch *ach, uint32_t *earned, uint32_t *total, uint32_t *pointsEarned, uint32_t *pointsTotal);
/// The loaded game's achievements, locked ones first. Valid until the next RDAchListBuild.
uint32_t RDAchListBuild(RDAch *ach);
int RDAchListItem(RDAch *ach, uint32_t index, RDAchItem *item);

#ifdef __cplusplus
}
#endif

#endif
