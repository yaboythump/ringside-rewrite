// Retro Duo GBA Test Cart - an original button and sound tester. Built with clang; see build.sh.
// D-pad moves the star, A and B beep, L and R light up, START changes colours, SELECT recentres.
#include "../testcart-ds/font.h"

typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;

#define REG16(a) (*(volatile u16 *)(a))
#define VRAM ((volatile u16 *)0x06000000)
#define RGB(r, g, b) ((u16)((r) | ((g) << 5) | ((b) << 10)))
#define INK RGB(31, 31, 31)
#define DIM RGB(8, 10, 18)
#define GOLD RGB(31, 25, 6)
#define PINK RGB(29, 9, 13)

void main_gba(void);

__attribute__((naked, section(".text.start"))) void _start(void) {
    __asm__ volatile("mov sp, #0x03000000\n"
                     "add sp, sp, #0x7F00\n"
                     "b main_gba\n");
}

static const u16 BACKGROUNDS[4] = {RGB(2, 3, 9), RGB(3, 9, 4), RGB(12, 3, 4), RGB(8, 2, 12)};

static void fill(int x, int y, int w, int h, u16 color) {
    for (int j = y; j < y + h; j++)
        if (j >= 0 && j < 160)
            for (int i = x; i < x + w; i++)
                if (i >= 0 && i < 240) VRAM[j * 240 + i] = color;
}

static void text(int x, int y, int scale, const char *s, u16 color) {
    for (; *s; s++, x += 8 * scale) {
        int index = 0;
        while (FONT_CHARS[index] && FONT_CHARS[index] != *s) index++;
        if (!FONT_CHARS[index]) continue;
        for (int row = 0; row < 8; row++)
            for (int col = 0; col < 8; col++)
                if (FONT[index][row] & (0x80 >> col)) fill(x + col * scale, y + row * scale, scale, scale, color);
    }
}

static void star(int x, int y, u16 color) {
    static const char *shape[8] = {"...##...", "...##...", "########", ".######.",
                                   "..####..", ".##..##.", "##....##", "........"};
    for (int row = 0; row < 8; row++)
        for (int col = 0; col < 8; col++)
            if (shape[row][col] == '#') fill(x + col * 2, y + row * 2, 2, 2, color);
}

static void waitVBlank(void) {
    while (REG16(0x04000006) == 160) {}
    while (REG16(0x04000006) != 160) {}
}

static void beep(u32 hertz) {
    REG16(0x04000060) = 0;                          /* no sweep */
    REG16(0x04000062) = 0xF180;                     /* full volume, quick fade, 50% duty */
    REG16(0x04000064) = 0x8000 | (u16)(2048 - 131072 / hertz);
}

static void drawScreen(u16 background) {
    fill(0, 0, 240, 160, background);
    fill(8, 6, 224, 3, INK);
    fill(8, 151, 224, 3, INK);
    text(48, 16, 2, "RETRO DUO", INK);
    text(72, 36, 1, "GBA TEST CART", GOLD);
}

int __aeabi_idiv(int n, int d);
unsigned __aeabi_uidiv(unsigned n, unsigned d) {
    unsigned q = 0, r = 0;
    if (!d) return 0;
    for (int bit = 31; bit >= 0; bit--) {
        r = (r << 1) | ((n >> bit) & 1);
        if (r >= d) { r -= d; q |= 1u << bit; }
    }
    return q;
}

void main_gba(void) {
    REG16(0x04000000) = 0x0403;   /* mode 3 bitmap, BG2 on */
    REG16(0x04000084) = 0x0080;   /* sound on */
    REG16(0x04000080) = 0x1177;   /* channel 1 on both speakers, full volume */
    REG16(0x04000082) = 0x0002;   /* PSG at 100% */

    int palette = 0;
    drawScreen(BACKGROUNDS[palette]);
    int x = 112, y = 72;
    u16 previous = 0;
    for (;;) {
        waitVBlank();
        u16 keys = ~REG16(0x04000130) & 0x3FF;
        u16 pressed = keys & ~previous;
        previous = keys;
        u16 background = BACKGROUNDS[palette];

        star(x, y, background);
        if (keys & 0x10) x += 2;
        if (keys & 0x20) x -= 2;
        if (keys & 0x40) y -= 2;
        if (keys & 0x80) y += 2;
        if (x < 0) x = 0;
        if (x > 224) x = 224;
        if (y < 50) y = 50;
        if (y > 120) y = 120;
        if (pressed & 0x04) { x = 112; y = 72; }
        if (pressed & 0x08) {
            palette = (palette + 1) & 3;
            drawScreen(BACKGROUNDS[palette]);
            background = BACKGROUNDS[palette];
        }
        if (pressed & 0x01) beep(880);
        if (pressed & 0x02) beep(440);
        star(x, y, GOLD);

        text(16, 138, 1, "A", (keys & 0x001) ? PINK : DIM);
        text(32, 138, 1, "B", (keys & 0x002) ? PINK : DIM);
        text(56, 138, 1, "L", (keys & 0x200) ? PINK : DIM);
        text(72, 138, 1, "R", (keys & 0x100) ? PINK : DIM);
        text(96, 138, 1, "SELECT", (keys & 0x004) ? PINK : DIM);
        text(160, 138, 1, "START", (keys & 0x008) ? PINK : DIM);
    }
}
