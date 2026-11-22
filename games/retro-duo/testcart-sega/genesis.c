/* Retro Duo Genesis Test Cart - an original controls tester. Copyright 2026 CT Network Studios.
   GPL v3 or later. Built by make_genesis.py (clang for the 68000 + a small linker).
   D-pad moves the star, A/B/C/X/Y/Z light up, START changes the background colour,
   MODE recentres the star. No interrupts, no RAM variables outside the stack. */
#include <stdint.h>
#include "genesis_data.h" /* FONT, FONT_WORDS, TEXT_*, STAR_TILE, LETTER_* (generated) */

#define VDP_DATA (*(volatile uint16_t *)0xC00000)
#define VDP_CTRL (*(volatile uint16_t *)0xC00004)
#define VDP_CTRL32 (*(volatile uint32_t *)0xC00004)
#define PAD_DATA (*(volatile uint8_t *)0xA10003)
#define PAD_CTRL (*(volatile uint8_t *)0xA10009)
#define VERSION (*(volatile uint8_t *)0xA10001)
#define TMSS (*(volatile uint32_t *)0xA14000)

static void vram_write(uint16_t address) {
    VDP_CTRL32 = 0x40000000u | ((uint32_t)(address & 0x3FFF) << 16) | (address >> 14);
}

static void cram_write(uint16_t address) { VDP_CTRL32 = 0xC0000000u | ((uint32_t)address << 16); }
static void vsram_write(uint16_t address) { VDP_CTRL32 = 0x40000010u | ((uint32_t)address << 16); }

static void put_text(int row, int column, const uint8_t *chars, uint16_t attributes) {
    vram_write(0xC000 + (row * 64 + column) * 2);
    for (; *chars != 0xFF; chars++) VDP_DATA = attributes | *chars;
}

static void wait_frame(void) {
    while (VDP_CTRL & 8) {}
    while (!(VDP_CTRL & 8)) {}
}

/* Returns buttons active-high: bit 0 up, 1 down, 2 left, 3 right, 4 B, 5 C, 6 A, 7 START,
   8 Z, 9 Y, 10 X, 11 MODE (6-button pad protocol: three TH pulses per read). */
static uint16_t read_pad(void) {
    uint8_t first, second, sixth;
    PAD_DATA = 0x40; __asm__ volatile("nop\n nop"); first = PAD_DATA;   /* ?1CBRLDU */
    PAD_DATA = 0x00; __asm__ volatile("nop\n nop"); second = PAD_DATA;  /* ?0SA00DU */
    PAD_DATA = 0x40; __asm__ volatile("nop\n nop");
    PAD_DATA = 0x00; __asm__ volatile("nop\n nop");
    PAD_DATA = 0x40; __asm__ volatile("nop\n nop");
    PAD_DATA = 0x00; __asm__ volatile("nop\n nop");
    PAD_DATA = 0x40; __asm__ volatile("nop\n nop"); sixth = PAD_DATA;   /* ?1..MXYZ on a 6-button pad */
    PAD_DATA = 0x00; __asm__ volatile("nop\n nop");
    PAD_DATA = 0x40;
    uint16_t pressed = (uint16_t)(~first & 0x3F) | (uint16_t)((~second & 0x30) << 2);
    pressed |= (uint16_t)(~sixth & 0x0F) << 8;
    return pressed;
}

static const uint16_t BACKDROPS[4] = {0x0420, 0x0240, 0x0204, 0x0402}; /* navy, green, red, purple (BGR) */
static const uint16_t PALETTES[4][2] = {
    {0x0420, 0x0EEE},  /* 0: background + white text */
    {0x0000, 0x0A6E},  /* 1: lit button (pink) */
    {0x0000, 0x0864},  /* 2: dim button */
    {0x0000, 0x00CE},  /* 3: gold star */
};

void start(void) {
    if (VERSION & 0x0F) TMSS = 0x53454741u; /* "SEGA" */
    (void)VDP_CTRL;
    static const uint16_t registers[] = {
        0x8004, 0x8104, 0x8230, 0x8407, 0x8578, 0x8700, 0x8A00, 0x8B00,
        0x8C00, 0x8D3F, 0x8F02, 0x9001, 0x9100, 0x9200,
    };
    for (unsigned i = 0; i < sizeof registers / sizeof *registers; i++) VDP_CTRL = registers[i];

    vram_write(0); /* clear all 64 KB of VRAM */
    for (uint16_t i = 0; i < 0x8000; i++) VDP_DATA = 0;
    vram_write(0);
    for (uint16_t i = 0; i < FONT_WORDS; i++) VDP_DATA = FONT[i];
    for (int p = 0; p < 4; p++) {
        cram_write(p * 32);
        VDP_DATA = PALETTES[p][0];
        VDP_DATA = PALETTES[p][1];
    }
    put_text(2, 4, TEXT_BAR, 0);
    put_text(5, 11, TEXT_TITLE, 0);
    put_text(7, 8, TEXT_CART, 0);
    put_text(19, 6, TEXT_MOVE, 0);
    put_text(21, 6, TEXT_COLOR, 0);
    put_text(26, 4, TEXT_BAR, 0);
    vram_write(0xE000 + (13 * 64 + 15) * 2); /* plane B: the star, gold */
    VDP_DATA = 0x6000 | STAR_TILE;
    PAD_CTRL = 0x40;
    PAD_DATA = 0x40;
    VDP_CTRL = 0x8144; /* display on */

    int16_t x = 0, y = 0;
    uint16_t previous = 0, backdrop = 0;
    static const uint16_t light_bits[6] = {0x40, 0x10, 0x20, 0x400, 0x200, 0x100}; /* A B C X Y Z */
    for (;;) {
        wait_frame();
        uint16_t pad = read_pad();
        uint16_t pressed = pad & ~previous;
        previous = pad;
        if (pad & 8) x += 2;
        if (pad & 4) x -= 2;
        if (pad & 2) y += 2;
        if (pad & 1) y -= 2;
        if (pressed & 0x800) { x = 0; y = 0; }
        if (pressed & 0x80) {
            backdrop = (backdrop + 1) & 3;
            cram_write(0);
            VDP_DATA = BACKDROPS[backdrop];
        }
        vram_write(0xFC00); /* full-screen scroll: plane A, then plane B */
        VDP_DATA = 0;
        VDP_DATA = (uint16_t)x;
        vsram_write(0);
        VDP_DATA = 0;
        VDP_DATA = (uint16_t)-y;
        vram_write(0xC000 + (24 * 64 + 10) * 2);
        for (int i = 0; i < 6; i++) {
            VDP_DATA = ((pad & light_bits[i]) ? 0x2000 : 0x4000) | LETTERS[i];
            VDP_DATA = 0;
        }
    }
}
