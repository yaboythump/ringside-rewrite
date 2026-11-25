// Checks Retro Duo's RetroAchievements layer (ios/RetroDuo/Achievements/RDAchievements.c) with
// a stand-in server: signing in, recognizing a game by its hash, an achievement unlocking from
// the game's memory, and the address mapping for every console.
// Built and run by tests/run_achievements_test.sh.
#include "RDAchievements.h"
#include "rc_consoles.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures = 0;
#define CHECK(cond, ...) do { printf((cond) ? "ok   " : "FAIL "); printf(__VA_ARGS__); printf("\n"); if (!(cond)) failures++; } while (0)

static uint8_t memory[0x10000];
static int loginOK = -1, gameOK = -1, unlocked = 0, completed = 0;
static char lastUnlock[128], lastPost[512], gameMessage[256];
static int awardRequests = 0, sawPassword = 0, sawToken = 0;

static uint32_t readByte(void *context, uint32_t address) {
    (void)context;
    return address < sizeof memory ? memory[address] : 0x100;
}

static const char *answer(const char *post) {
    if (strstr(post, "r=login2")) {
        if (strstr(post, "p=")) sawPassword = 1;
        if (strstr(post, "t=SavedToken")) sawToken = 1;
        if (strstr(post, "p=wrong")) return "{\"Success\":false,\"Error\":\"Invalid username/password combination. Please try again.\",\"Code\":\"invalid_credentials\"}";
        return "{\"Success\":true,\"User\":\"Player\",\"Token\":\"SavedToken\",\"Score\":100,\"SoftcoreScore\":20,\"Messages\":0,\"Permissions\":1,\"AccountType\":\"Registered\"}";
    }
    if (strstr(post, "r=achievementsets")) {
        if (!strstr(post, "m=")) return "{\"Success\":false,\"Error\":\"No hash\"}";
        return "{\"Success\":true,\"GameId\":1234,\"Title\":\"Test Cart\",\"ConsoleId\":4,"
               "\"ImageIconUrl\":\"https://media.retroachievements.org/Images/000001.png\","
               "\"RichPresenceGameId\":1234,\"RichPresencePatch\":\"\",\"Sets\":[{"
               "\"AchievementSetId\":1,\"GameId\":1234,\"Title\":null,\"Type\":\"core\","
               "\"ImageIconUrl\":\"https://media.retroachievements.org/Images/000001.png\","
               "\"Achievements\":["
               "{\"ID\":501,\"Title\":\"Three\",\"Description\":\"Set $C001 to 3\",\"Flags\":3,\"Points\":5,"
               "\"MemAddr\":\"0xHc001=3\",\"Author\":\"Test\",\"BadgeName\":\"00001\",\"Created\":1,\"Modified\":1},"
               "{\"ID\":502,\"Title\":\"Already\",\"Description\":\"Earned before\",\"Flags\":3,\"Points\":10,"
               "\"MemAddr\":\"0xHc002=9\",\"Author\":\"Test\",\"BadgeName\":\"00002\",\"Created\":1,\"Modified\":1}"
               "],\"Leaderboards\":[]}]}";
    }
    if (strstr(post, "r=startsession"))
        return "{\"Success\":true,\"Unlocks\":[{\"ID\":502,\"When\":1700000000}],\"HardcoreUnlocks\":[],\"ServerNow\":1700000100}";
    if (strstr(post, "r=awardachievement")) {
        awardRequests++;
        return "{\"Success\":true,\"Score\":125,\"SoftcoreScore\":25,\"AchievementID\":501,\"AchievementsRemaining\":0}";
    }
    if (strstr(post, "r=ping")) return "{\"Success\":true}";
    return "{\"Success\":false,\"Error\":\"Unexpected request\"}";
}

static void request(void *context, const char *url, const char *post, const char *contentType, RDAchRequest *pending) {
    (void)context; (void)contentType;
    const char *query = post ? post : (strchr(url, '?') ? strchr(url, '?') + 1 : "");
    snprintf(lastPost, sizeof lastPost, "%s", query);
    const char *body = answer(query);
    RDAchRequestDone(pending, 200, body, strlen(body));
}

static void finished(void *context, int what, int ok, const char *message) {
    (void)context;
    if (what == RD_ACH_LOGIN) loginOK = ok;
    if (what == RD_ACH_GAME) { gameOK = ok; snprintf(gameMessage, sizeof gameMessage, "%s", message ? message : ""); }
}

static void event(void *context, int type, const RDAchItem *item) {
    (void)context;
    if (type == RD_ACH_EVENT_UNLOCKED) { unlocked++; snprintf(lastUnlock, sizeof lastUnlock, "%s", item->title); }
    if (type == RD_ACH_EVENT_COMPLETED) completed++;
}

static uint32_t mapped(uint32_t console, uint32_t address) {
    uint32_t out = 0xFFFFFFFF;
    return RDAchConsoleAddress(console, address, &out) ? out : 0xFFFFFFFF;
}

int main(int argc, char **argv) {
    const char *romPath = argc > 1 ? argv[1] : "/tmp/rd_ach_test.gb";
    FILE *rom = fopen(romPath, "wb");
    for (int i = 0; i < 0x8000; i++) fputc(i & 0xFF, rom);
    fclose(rom);

    // Address mapping, checked against rcheevos' own console memory maps.
    CHECK(mapped(RC_CONSOLE_GAMEBOY, 0xC001) == 0xC001, "Game Boy: the CPU bus as is");
    CHECK(mapped(RC_CONSOLE_NINTENDO, 0x0812) == 0x0012, "NES: RAM mirrors fold to $0000-$07FF");
    CHECK(mapped(RC_CONSOLE_NINTENDO, 0x6000) == 0xFFFFFFFF, "NES: cartridge RAM isn't readable here");
    CHECK(mapped(RC_CONSOLE_SUPER_NINTENDO, 0x1FFFF) == 0x7FFFFF, "SNES: work RAM at $7E0000");
    CHECK(mapped(RC_CONSOLE_GAMEBOY_ADVANCE, 0x10) == 0x03000010, "GBA: internal work RAM first");
    CHECK(mapped(RC_CONSOLE_GAMEBOY_ADVANCE, 0x8010) == 0x02000010, "GBA: then external work RAM");
    CHECK(mapped(RC_CONSOLE_MEGA_DRIVE, 0x0100) == 0xFF0101, "Genesis: byte pairs swapped (RetroAchievements' order)");
    CHECK(mapped(RC_CONSOLE_MASTER_SYSTEM, 0x1FFF) == 0xDFFF && mapped(RC_CONSOLE_GAME_GEAR, 0) == 0xC000, "Master System / Game Gear: RAM at $C000");
    CHECK(mapped(RC_CONSOLE_NINTENDO_DS, 0x123456) == 0x02123456, "DS: main RAM at $02000000");
    CHECK(RDAchConsoleID("GBC") == RC_CONSOLE_GAMEBOY_COLOR && RDAchConsoleID("nds") == RC_CONSOLE_NINTENDO_DS
          && RDAchConsoleID("gen") == RC_CONSOLE_MEGA_DRIVE && RDAchConsoleID("txt") == 0, "file extensions to consoles");

    RDAchCallbacks callbacks = { NULL, readByte, request, finished, event };
    RDAch *ach = RDAchCreate(callbacks);
    char agent[64] = "";
    RDAchUserAgentClause(ach, agent, sizeof agent);
    CHECK(strstr(agent, "rcheevos/") != NULL, "user agent names rcheevos (%s)", agent);

    RDAchLoginWithPassword(ach, "Player", "wrong");
    CHECK(loginOK == 0 && RDAchUserName(ach) == NULL, "a wrong password is refused");
    RDAchLoginWithPassword(ach, "Player", "secret");
    CHECK(loginOK == 1 && sawPassword, "signs in with a password");
    CHECK(RDAchUserName(ach) && strcmp(RDAchUserName(ach), "Player") == 0, "knows the player's name");
    CHECK(RDAchUserToken(ach) && strcmp(RDAchUserToken(ach), "SavedToken") == 0, "keeps the token for next time");
    CHECK(RDAchUserScore(ach) == 120, "shows the player's points (%u)", RDAchUserScore(ach));

    RDAchLoadGame(ach, RC_CONSOLE_GAMEBOY, romPath);
    CHECK(gameOK == 1, "recognizes the game by its hash (%s)", gameMessage);
    CHECK(RDAchGameTitle(ach) && strcmp(RDAchGameTitle(ach), "Test Cart") == 0, "has the game's title");
    uint32_t earned, total, points, pointsTotal;
    RDAchGameSummary(ach, &earned, &total, &points, &pointsTotal);
    CHECK(earned == 1 && total == 2 && points == 10 && pointsTotal == 15, "1 of 2 earned before (%u/%u, %u/%u points)", earned, total, points, pointsTotal);
    uint32_t count = RDAchListBuild(ach);
    RDAchItem item;
    CHECK(count == 2 && RDAchListItem(ach, 0, &item) && !item.unlocked && strcmp(item.title, "Three") == 0,
          "the list puts the locked one first");
    CHECK(RDAchListItem(ach, 1, &item) && item.unlocked && item.badgeURL && strstr(item.badgeURL, "00002"), "with badge pictures");

    for (int frame = 0; frame < 5; frame++) RDAchDoFrame(ach);
    CHECK(unlocked == 0, "nothing unlocks while the game's memory doesn't match");
    memory[0xC001] = 3;
    RDAchDoFrame(ach);
    CHECK(unlocked == 1 && strcmp(lastUnlock, "Three") == 0, "the achievement unlocks when $C001 becomes 3");
    CHECK(awardRequests == 1, "and the unlock is sent to the server");
    CHECK(completed == 1, "earning the last one completes the game");
    RDAchGameSummary(ach, &earned, &total, &points, &pointsTotal);
    CHECK(earned == 2, "the summary counts it (%u/%u)", earned, total);
    for (int frame = 0; frame < 5; frame++) RDAchDoFrame(ach);
    CHECK(unlocked == 1, "it only unlocks once");

    RDAchUnloadGame(ach);
    CHECK(RDAchGameTitle(ach) == NULL, "closing the game unloads it");
    RDAchLogout(ach);
    CHECK(RDAchUserName(ach) == NULL, "signs out");
    RDAchLoginWithToken(ach, "Player", "SavedToken");
    CHECK(loginOK == 1 && sawToken && RDAchUserName(ach), "signs back in with the saved token");

    memory[0xC001] = 0;
    RDAchLoadGame(ach, RC_CONSOLE_GAMEBOY, "/nonexistent/game.gb");
    CHECK(gameOK == 0, "a missing file doesn't load (%s)", gameMessage);

    RDAchDestroy(ach);
    printf(failures ? "\n%d achievements check(s) failed\n" : "\nall achievements checks passed\n", failures);
    return failures ? 1 : 0;
}
