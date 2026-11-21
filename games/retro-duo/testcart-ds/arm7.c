// Retro Duo DS Test Cart - ARM7 side (touch screen, X/Y buttons, sound).
// Passes touch and X/Y to the ARM9 through main RAM and beeps on A (high) and B (low).
typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;

#define REG16(a) (*(volatile u16 *)(a))
#define REG32(a) (*(volatile u32 *)(a))
#define SHARED ((volatile u32 *)0x023FF000)

#define SPICNT REG16(0x040001C0)
#define SPIDATA REG16(0x040001C2)

void main7(void);

__attribute__((naked, section(".text.start"))) void _start(void) {
    __asm__ volatile("mov sp, #0x03800000\n"
                     "add sp, sp, #0xF000\n"
                     "b main7\n");
}

static void spiWait(void) {
    while (SPICNT & 0x80) {}
}

/* Reads one 12-bit touch screen channel (0xD1 = X, 0x91 = Y). */
static u32 touchRead(u8 command) {
    SPICNT = 0x8A01; /* enable, touch screen, hold chip select */
    SPIDATA = command;
    spiWait();
    SPIDATA = 0;
    spiWait();
    u32 high = SPIDATA;
    SPICNT = 0x8201; /* last byte: release chip select */
    SPIDATA = 0;
    spiWait();
    u32 low = SPIDATA >> 3;
    return ((high & 0x7F) << 5) | low;
}

static void beep(u32 hertz) {
    REG32(0x04000480) = 0; /* restart PSG channel 8 */
    REG16(0x04000488) = (u16)(0x10000 - 16756991u / (hertz * 8));
    REG32(0x04000480) = 0xE340007Fu; /* start, PSG, 50% duty, centre, full volume */
}

void main7(void) {
    REG16(0x04000304) = 0x0001; /* speakers on */
    REG16(0x04000500) = 0x807F; /* sound on, full master volume */
    u16 previous = 0;
    int beepFrames = 0;
    for (;;) {
        while (REG16(0x04000006) == 192) {}
        while (REG16(0x04000006) != 192) {}

        u16 extKeys = ~REG16(0x04000136);
        u32 touch = 0;
        if (extKeys & 0x40) {
            u32 x = touchRead(0xD1) >> 4;
            u32 y = touchRead(0x91) >> 4;
            if (x > 255) x = 255;
            if (y > 191) y = 191;
            touch = 0x80000000u | x | (y << 8);
        }
        SHARED[0] = touch;
        SHARED[1] = extKeys & 3;

        u16 keys = ~REG16(0x04000130) & 0x3FF;
        u16 pressed = keys & ~previous;
        previous = keys;
        if (pressed & 1) { beep(880); beepFrames = 8; }
        else if (pressed & 2) { beep(440); beepFrames = 8; }
        if (beepFrames && --beepFrames == 0) REG32(0x04000480) = 0;
    }
}
