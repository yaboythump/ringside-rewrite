// Retro Duo DS Test Cart - ARM9 side (graphics).
// Top screen: title, a star moved by the D-pad, and lights for every button.
// Bottom screen: draw with your finger; START clears it.
// Built with clang for armv5te, no SDK. See build.sh.
#include "font.h"

typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;

#define REG8(a) (*(volatile u8 *)(a))
#define REG16(a) (*(volatile u16 *)(a))
#define REG32(a) (*(volatile u32 *)(a))
#define SHARED ((volatile u32 *)0x023FF000) /* written by the ARM7: [0] touch, [1] X/Y keys */

#define TOP ((volatile u16 *)0x06800000)    /* VRAM A shown directly on engine A */
#define BOTTOM ((volatile u16 *)0x06200000) /* VRAM C as engine B bitmap, 256 wide */

#define RGB(r, g, b) ((u16)((r) | ((g) << 5) | ((b) << 10) | 0x8000))
#define NAVY RGB(2, 3, 9)
#define INK RGB(31, 31, 31)
#define DIM RGB(8, 10, 18)
#define GOLD RGB(31, 25, 6)
#define PINK RGB(29, 9, 13)
#define PAPER RGB(4, 5, 12)

void main9(void);

/* ARMv5 has no divide instruction; the compiler calls this for `/`. */
int __aeabi_idiv(int numerator, int denominator) {
    int negative = (numerator < 0) != (denominator < 0);
    unsigned n = numerator < 0 ? -(unsigned)numerator : (unsigned)numerator;
    unsigned d = denominator < 0 ? -(unsigned)denominator : (unsigned)denominator;
    unsigned q = 0, r = 0;
    if (!d) return 0;
    for (int bit = 31; bit >= 0; bit--) {
        r = (r << 1) | ((n >> bit) & 1);
        if (r >= d) { r -= d; q |= 1u << bit; }
    }
    return negative ? -(int)q : (int)q;
}

__attribute__((naked, section(".text.start"))) void _start(void) {
    __asm__ volatile("mov sp, #0x02300000\n"
                     "b main9\n");
}

static void fill(volatile u16 *screen, int stride, int x, int y, int w, int h, u16 color) {
    for (int j = y; j < y + h; j++) {
        if (j < 0 || j >= 192) continue;
        for (int i = x; i < x + w; i++) {
            if (i >= 0 && i < 256) screen[j * stride + i] = color;
        }
    }
}

static void text(volatile u16 *screen, int stride, int x, int y, int scale, const char *s, u16 color) {
    for (; *s; s++, x += 8 * scale) {
        int index = 0;
        while (FONT_CHARS[index] && FONT_CHARS[index] != *s) index++;
        if (!FONT_CHARS[index]) continue;
        for (int row = 0; row < 8; row++) {
            u8 bits = FONT[index][row];
            for (int col = 0; col < 8; col++) {
                if (bits & (0x80 >> col)) fill(screen, stride, x + col * scale, y + row * scale, scale, scale, color);
            }
        }
    }
}

static void star(int x, int y, u16 color) {
    static const char *shape[8] = {"...##...", "...##...", "########", ".######.",
                                   "..####..", ".##..##.", "##....##", "........"};
    for (int row = 0; row < 8; row++)
        for (int col = 0; col < 8; col++)
            if (shape[row][col] == '#') fill(TOP, 256, x + col * 2, y + row * 2, 2, 2, color);
}

static void waitVBlank(void) {
    while (REG16(0x04000006) == 192) {}
    while (REG16(0x04000006) != 192) {}
}

static void clearBottom(void) {
    fill(BOTTOM, 256, 0, 0, 256, 192, PAPER);
    text(BOTTOM, 256, 48, 84, 2, "DRAW HERE", DIM);
}

void main9(void) {
    REG16(0x04000304) = 0x8203;      /* LCDs, 2D engines A and B, engine A on the top screen */
    REG8(0x04000240) = 0x80;         /* VRAM A: plain LCDC memory */
    REG8(0x04000242) = 0x84;         /* VRAM C: engine B background */
    REG32(0x04000000) = 0x00020000;  /* engine A: show VRAM A directly */
    REG32(0x04001000) = 0x00010805;  /* engine B: mode 5, BG3 on */
    REG16(0x0400100E) = 0x4084;      /* BG3: 256x256 direct-colour bitmap */
    REG16(0x04001030) = 0x0100;      /* BG3 identity transform */
    REG16(0x04001032) = 0;
    REG16(0x04001034) = 0;
    REG16(0x04001036) = 0x0100;
    REG32(0x04001038) = 0;
    REG32(0x0400103C) = 0;

    fill(TOP, 256, 0, 0, 256, 192, NAVY);
    fill(TOP, 256, 8, 8, 240, 4, INK);
    fill(TOP, 256, 8, 180, 240, 4, INK);
    text(TOP, 256, 56, 20, 2, "RETRO DUO", INK);
    text(TOP, 256, 80, 40, 1, "DS TEST CART", GOLD);
    clearBottom();

    int x = 120, y = 90, lastX = -1, lastY = -1;
    for (;;) {
        waitVBlank();
        u16 keys = ~REG16(0x04000130) & 0x3FF;
        u32 ext = SHARED[1];
        u32 touch = SHARED[0];

        star(x, y, NAVY);
        if (keys & 0x10) x += 2;
        if (keys & 0x20) x -= 2;
        if (keys & 0x40) y -= 2;
        if (keys & 0x80) y += 2;
        if (x < 0) x = 0;
        if (x > 240) x = 240;
        if (y < 60) y = 60;
        if (y > 156) y = 156;
        star(x, y, GOLD);

        /* Button lights along the bottom of the top screen. */
        text(TOP, 256, 16, 164, 1, "A", (keys & 0x001) ? PINK : DIM);
        text(TOP, 256, 32, 164, 1, "B", (keys & 0x002) ? PINK : DIM);
        text(TOP, 256, 48, 164, 1, "X", (ext & 1) ? PINK : DIM);
        text(TOP, 256, 64, 164, 1, "Y", (ext & 2) ? PINK : DIM);
        text(TOP, 256, 88, 164, 1, "L", (keys & 0x200) ? PINK : DIM);
        text(TOP, 256, 104, 164, 1, "R", (keys & 0x100) ? PINK : DIM);
        text(TOP, 256, 128, 164, 1, "SELECT", (keys & 0x004) ? PINK : DIM);
        text(TOP, 256, 192, 164, 1, "START", (keys & 0x008) ? PINK : DIM);

        if (keys & 0x008) clearBottom();
        if (touch & 0x80000000u) {
            int tx = (int)(touch & 0xFF), ty = (int)((touch >> 8) & 0xFF);
            if (lastX >= 0) {
                /* Connect to the previous point so fast strokes stay continuous. */
                int dx = tx - lastX, dy = ty - lastY;
                int steps = (dx < 0 ? -dx : dx) > (dy < 0 ? -dy : dy) ? (dx < 0 ? -dx : dx) : (dy < 0 ? -dy : dy);
                for (int s = 0; s <= steps; s++) {
                    int px = steps ? lastX + dx * s / steps : tx;
                    int py = steps ? lastY + dy * s / steps : ty;
                    fill(BOTTOM, 256, px - 2, py - 2, 5, 5, GOLD);
                }
            } else {
                fill(BOTTOM, 256, tx - 2, ty - 2, 5, 5, GOLD);
            }
            lastX = tx;
            lastY = ty;
        } else {
            lastX = lastY = -1;
        }
    }
}
