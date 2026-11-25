// RetroAchievements glue (see RDAchievements.h).
#include "AchievementsConfig.h"
#include "RDAchievements.h"

#include "rc_client.h"
#include "rc_consoles.h"
#include "rc_error.h"

#include <stdlib.h>
#include <string.h>
#include <strings.h>

struct RDAch {
    rc_client_t *client;
    RDAchCallbacks callbacks;
    uint32_t consoleID;
    rc_client_achievement_list_t *list;
    const rc_client_achievement_t **items;
    uint32_t itemCount;
};

struct RDAchRequest {
    rc_client_server_callback_t callback;
    void *callbackData;
};

uint32_t RDAchConsoleID(const char *extension) {
    static const struct { const char *extension; uint32_t console; } table[] = {
        {"gb", RC_CONSOLE_GAMEBOY}, {"gbc", RC_CONSOLE_GAMEBOY_COLOR}, {"cgb", RC_CONSOLE_GAMEBOY_COLOR},
        {"gba", RC_CONSOLE_GAMEBOY_ADVANCE}, {"agb", RC_CONSOLE_GAMEBOY_ADVANCE},
        {"nes", RC_CONSOLE_NINTENDO}, {"sfc", RC_CONSOLE_SUPER_NINTENDO}, {"smc", RC_CONSOLE_SUPER_NINTENDO},
        {"nds", RC_CONSOLE_NINTENDO_DS}, {"md", RC_CONSOLE_MEGA_DRIVE}, {"gen", RC_CONSOLE_MEGA_DRIVE},
        {"smd", RC_CONSOLE_MEGA_DRIVE}, {"sms", RC_CONSOLE_MASTER_SYSTEM}, {"gg", RC_CONSOLE_GAME_GEAR},
    };
    if (!extension) return 0;
    for (size_t i = 0; i < sizeof table / sizeof table[0]; i++) {
        if (strcasecmp(extension, table[i].extension) == 0) return table[i].console;
    }
    return 0;
}

// RetroAchievements numbers each console's memory its own way (rcheevos' consoleinfo.c);
// these turn its addresses into the console addresses the app's cores read.
int RDAchConsoleAddress(uint32_t consoleID, uint32_t address, uint32_t *out) {
    switch (consoleID) {
    case RC_CONSOLE_GAMEBOY:
    case RC_CONSOLE_GAMEBOY_COLOR:
        // The CPU's whole bus. (The Color's extra work RAM banks, $10000 up, aren't reachable.)
        if (address > 0xFFFF) return 0;
        *out = address;
        return 1;
    case RC_CONSOLE_NINTENDO:
        // 2KB of RAM, mirrored up to $1FFF.
        if (address > 0x1FFF) return 0;
        *out = address & 0x7FF;
        return 1;
    case RC_CONSOLE_SUPER_NINTENDO:
        // 128KB of work RAM at $7E0000.
        if (address > 0x1FFFF) return 0;
        *out = 0x7E0000 + address;
        return 1;
    case RC_CONSOLE_GAMEBOY_ADVANCE:
        // 32KB internal work RAM, then 256KB external.
        if (address <= 0x7FFF) { *out = 0x03000000 + address; return 1; }
        if (address <= 0x47FFF) { *out = 0x02000000 + (address - 0x8000); return 1; }
        return 0;
    case RC_CONSOLE_MEGA_DRIVE:
        // 64KB at $FF0000. RetroAchievements keeps it the way emulators store it, as
        // little-endian 16-bit words, so each byte pair is swapped from the 68000's view.
        if (address > 0xFFFF) return 0;
        *out = 0xFF0000 + (address ^ 1);
        return 1;
    case RC_CONSOLE_MASTER_SYSTEM:
    case RC_CONSOLE_GAME_GEAR:
        // 8KB at $C000.
        if (address > 0x1FFF) return 0;
        *out = 0xC000 + address;
        return 1;
    case RC_CONSOLE_NINTENDO_DS:
        // 4MB main RAM at $02000000.
        if (address > 0x3FFFFF) return 0;
        *out = 0x02000000 + address;
        return 1;
    default:
        return 0;
    }
}

static RDAch *owner(const rc_client_t *client) {
    return (RDAch *)rc_client_get_userdata(client);
}

static uint32_t readMemory(uint32_t address, uint8_t *buffer, uint32_t count, rc_client_t *client) {
    RDAch *ach = owner(client);
    for (uint32_t i = 0; i < count; i++) {
        uint32_t consoleAddress;
        if (!RDAchConsoleAddress(ach->consoleID, address + i, &consoleAddress)) return i;
        uint32_t value = ach->callbacks.read(ach->callbacks.context, consoleAddress);
        if (value > 0xFF) return i;
        buffer[i] = (uint8_t)value;
    }
    return count;
}

static void serverCall(const rc_api_request_t *request, rc_client_server_callback_t callback, void *callbackData,
                       rc_client_t *client) {
    RDAch *ach = owner(client);
    RDAchRequest *pending = malloc(sizeof *pending);
    pending->callback = callback;
    pending->callbackData = callbackData;
    ach->callbacks.request(ach->callbacks.context, request->url, request->post_data, request->content_type, pending);
}

void RDAchRequestDone(RDAchRequest *request, int httpStatus, const char *body, size_t length) {
    rc_api_server_response_t response;
    response.body = body ? body : "";
    response.body_length = body ? length : 0;
    // rcheevos retries "no response" (0) and server errors; anything else is final.
    response.http_status_code = httpStatus;
    request->callback(&response, request->callbackData);
    free(request);
}

static void fill(const rc_client_achievement_t *a, RDAchItem *item) {
    item->id = a->id;
    item->points = a->points;
    item->title = a->title ? a->title : "";
    item->description = a->description ? a->description : "";
    item->unlocked = a->unlocked != 0;
    item->badgeURL = item->unlocked || !a->badge_locked_url ? a->badge_url : a->badge_locked_url;
    item->progress = a->measured_progress;
    item->percent = a->measured_percent;
}

static void handleEvent(const rc_client_event_t *event, rc_client_t *client) {
    RDAch *ach = owner(client);
    RDAchItem item;
    memset(&item, 0, sizeof item);
    item.title = item.description = item.progress = "";
    switch (event->type) {
    case RC_CLIENT_EVENT_ACHIEVEMENT_TRIGGERED:
        fill(event->achievement, &item);
        ach->callbacks.event(ach->callbacks.context, RD_ACH_EVENT_UNLOCKED, &item);
        break;
    case RC_CLIENT_EVENT_GAME_COMPLETED:
        ach->callbacks.event(ach->callbacks.context, RD_ACH_EVENT_COMPLETED, &item);
        break;
    case RC_CLIENT_EVENT_DISCONNECTED:
        ach->callbacks.event(ach->callbacks.context, RD_ACH_EVENT_OFFLINE, &item);
        break;
    case RC_CLIENT_EVENT_RECONNECTED:
        ach->callbacks.event(ach->callbacks.context, RD_ACH_EVENT_ONLINE, &item);
        break;
    case RC_CLIENT_EVENT_SERVER_ERROR:
        if (event->server_error && event->server_error->error_message) item.title = event->server_error->error_message;
        ach->callbacks.event(ach->callbacks.context, RD_ACH_EVENT_ERROR, &item);
        break;
    default:
        break;
    }
}

RDAch *RDAchCreate(RDAchCallbacks callbacks) {
    RDAch *ach = calloc(1, sizeof *ach);
    ach->callbacks = callbacks;
    ach->client = rc_client_create(readMemory, serverCall);
    rc_client_set_userdata(ach->client, ach);
    rc_client_set_event_handler(ach->client, handleEvent);
    // Casual ("softcore") play: rewind, cheats and save states keep working. Hardcore
    // would turn them off.
    rc_client_set_hardcore_enabled(ach->client, 0);
    rc_client_set_unofficial_enabled(ach->client, 0);
    return ach;
}

static void dropList(RDAch *ach) {
    if (ach->list) rc_client_destroy_achievement_list(ach->list);
    free(ach->items);
    ach->list = NULL;
    ach->items = NULL;
    ach->itemCount = 0;
}

void RDAchDestroy(RDAch *ach) {
    dropList(ach);
    rc_client_destroy(ach->client);
    free(ach);
}

void RDAchSetHost(RDAch *ach, const char *host) {
    rc_client_set_host(ach->client, host);
}

void RDAchUserAgentClause(RDAch *ach, char *buffer, size_t size) {
    rc_client_get_user_agent_clause(ach->client, buffer, size);
}

static void loginDone(int result, const char *message, rc_client_t *client, void *userdata) {
    (void)userdata;
    RDAch *ach = owner(client);
    ach->callbacks.finished(ach->callbacks.context, RD_ACH_LOGIN, result == RC_OK,
                            message ? message : rc_error_str(result));
}

void RDAchLoginWithPassword(RDAch *ach, const char *username, const char *password) {
    rc_client_begin_login_with_password(ach->client, username, password, loginDone, NULL);
}

void RDAchLoginWithToken(RDAch *ach, const char *username, const char *token) {
    rc_client_begin_login_with_token(ach->client, username, token, loginDone, NULL);
}

void RDAchLogout(RDAch *ach) {
    dropList(ach);
    rc_client_logout(ach->client);
}

const char *RDAchUserName(RDAch *ach) {
    const rc_client_user_t *user = rc_client_get_user_info(ach->client);
    return user ? user->display_name : NULL;
}

const char *RDAchUserToken(RDAch *ach) {
    const rc_client_user_t *user = rc_client_get_user_info(ach->client);
    return user ? user->token : NULL;
}

uint32_t RDAchUserScore(RDAch *ach) {
    const rc_client_user_t *user = rc_client_get_user_info(ach->client);
    return user ? user->score + user->score_softcore : 0;
}

static void gameDone(int result, const char *message, rc_client_t *client, void *userdata) {
    (void)userdata;
    RDAch *ach = owner(client);
    ach->callbacks.finished(ach->callbacks.context, RD_ACH_GAME, result == RC_OK,
                            message ? message : rc_error_str(result));
}

void RDAchLoadGame(RDAch *ach, uint32_t consoleID, const char *path) {
    dropList(ach);
    ach->consoleID = consoleID;
    rc_client_begin_identify_and_load_game(ach->client, consoleID, path, NULL, 0, gameDone, NULL);
}

void RDAchUnloadGame(RDAch *ach) {
    dropList(ach);
    rc_client_unload_game(ach->client);
}

void RDAchDoFrame(RDAch *ach) {
    rc_client_do_frame(ach->client);
}

void RDAchIdle(RDAch *ach) {
    rc_client_idle(ach->client);
}

void RDAchReset(RDAch *ach) {
    rc_client_reset(ach->client);
}

const char *RDAchGameTitle(RDAch *ach) {
    const rc_client_game_t *game = rc_client_get_game_info(ach->client);
    return game && game->id ? game->title : NULL;
}

void RDAchGameSummary(RDAch *ach, uint32_t *earned, uint32_t *total, uint32_t *pointsEarned, uint32_t *pointsTotal) {
    rc_client_user_game_summary_t summary;
    memset(&summary, 0, sizeof summary);
    rc_client_get_user_game_summary(ach->client, &summary);
    *earned = summary.num_unlocked_achievements;
    *total = summary.num_core_achievements;
    *pointsEarned = summary.points_unlocked;
    *pointsTotal = summary.points_core;
}

uint32_t RDAchListBuild(RDAch *ach) {
    dropList(ach);
    ach->list = rc_client_create_achievement_list(ach->client, RC_CLIENT_ACHIEVEMENT_CATEGORY_CORE,
                                                  RC_CLIENT_ACHIEVEMENT_LIST_GROUPING_LOCK_STATE);
    if (!ach->list) return 0;
    uint32_t count = 0;
    for (uint32_t b = 0; b < ach->list->num_buckets; b++) count += ach->list->buckets[b].num_achievements;
    ach->items = calloc(count ? count : 1, sizeof *ach->items);
    for (uint32_t b = 0; b < ach->list->num_buckets; b++) {
        const rc_client_achievement_bucket_t *bucket = &ach->list->buckets[b];
        for (uint32_t i = 0; i < bucket->num_achievements; i++) ach->items[ach->itemCount++] = bucket->achievements[i];
    }
    return ach->itemCount;
}

int RDAchListItem(RDAch *ach, uint32_t index, RDAchItem *item) {
    if (index >= ach->itemCount) return 0;
    fill(ach->items[index], item);
    return 1;
}
