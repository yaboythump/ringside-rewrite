// Grave Mistakes - a chaotic funeral home sim for the Nintendo DS (BlocksDS).
// Top screen: the funeral home, live. Bottom screen: bookings, prep, quick fixes, money.
#include <nds.h>

#include "game.h"
#include "gfx.h"
#include "sfx.h"

static volatile uint32_t vblanks;

static void on_vblank(void)
{
    vblanks++;
}

int main(int argc, char **argv)
{
    (void)argc;
    (void)argv;
    gfx_init();
    sfx_init();
    game_init();
    irqSet(IRQ_VBLANK, on_vblank);
    irqEnable(IRQ_VBLANK);

    // Fixed 60 Hz game logic: drawing both screens in software can take more
    // than one frame, so the game catches up on missed ticks instead of slowing down.
    uint32_t last = vblanks;
    while (1) {
        swiWaitForVBlank();
        gfx_present();
        uint32_t now = vblanks;
        int ticks = (int)(now - last);
        last = now;
        if (ticks < 1)
            ticks = 1;
        if (ticks > 4)
            ticks = 4;
        for (int i = 0; i < ticks; i++)
            game_update(i == 0);
        game_draw();
    }
    return 0;
}
