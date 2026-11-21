; Retro Duo Test Cart - an original button and sound tester.
; Build: python3 make_tiles.py && ./build.sh   (RGBDS 0.9)
; D-pad moves the star, A and B beep, START changes colours, SELECT recentres.

DEF rP1   EQU $FF00
DEF rIF   EQU $FF0F
DEF rNR10 EQU $FF10
DEF rNR11 EQU $FF11
DEF rNR12 EQU $FF12
DEF rNR13 EQU $FF13
DEF rNR14 EQU $FF14
DEF rNR21 EQU $FF16
DEF rNR22 EQU $FF17
DEF rNR23 EQU $FF18
DEF rNR24 EQU $FF19
DEF rNR50 EQU $FF24
DEF rNR51 EQU $FF25
DEF rNR52 EQU $FF26
DEF rLCDC EQU $FF40
DEF rLY   EQU $FF44
DEF rBGP  EQU $FF47
DEF rOBP0 EQU $FF48
DEF rBCPS EQU $FF68
DEF rBCPD EQU $FF69
DEF rOCPS EQU $FF6A
DEF rOCPD EQU $FF6B
DEF rIE   EQU $FFFF

DEF SPRITES   EQU $FE00
DEF MAP   EQU $9800

MACRO rgb
    dw (\1) | ((\2) << 5) | ((\3) << 10)
ENDM

SECTION "Header", ROM0[$100]
    nop
    jp Start
    ds $150 - @, 0

SECTION "Code", ROM0[$150]
Start:
    di
    ld sp, $E000
    cp $11                  ; A is $11 when a Game Boy Color boots
    ld a, 0
    jr nz, .notColor
    inc a
.notColor:
    ld [wIsColor], a

    ; Wait for vertical blank, then switch the screen off so VRAM is free.
.waitVBlank:
    ldh a, [rLY]
    cp 144
    jr c, .waitVBlank
    xor a
    ldh [rLCDC], a
    ldh [rIE], a
    ldh [rIF], a

    ld de, Tiles
    ld hl, $8000
    ld bc, TilesEnd - Tiles
    call MemCopy

    ld hl, MAP
    ld bc, 32 * 32
    ld d, 0
    call MemSet

    ld hl, SPRITES
    ld bc, 160
    ld d, 0
    call MemSet

    ld hl, MAP + 32 * 1 + 1
    ld de, TextBar
    call PutText
    ld hl, MAP + 32 * 3 + 5
    ld de, TextTitle
    call PutText
    ld hl, MAP + 32 * 5 + 5
    ld de, TextCart
    call PutText
    ld hl, MAP + 32 * 12 + 2
    ld de, TextMove
    call PutText
    ld hl, MAP + 32 * 13 + 2
    ld de, TextBeep
    call PutText
    ld hl, MAP + 32 * 14 + 2
    ld de, TextColor
    call PutText
    ld hl, MAP + 32 * 16 + 1
    ld de, TextBar
    call PutText

    call Recentre
    ld a, STAR_TILE
    ld [SPRITES + 2], a
    xor a
    ld [SPRITES + 3], a
    ld [wPalette], a
    ldh [hPad], a
    call ApplyPalette

    ; Sound on, both speakers, full volume.
    ld a, $80
    ldh [rNR52], a
    ld a, $77
    ldh [rNR50], a
    ld a, $FF
    ldh [rNR51], a

    ld a, %10010011         ; screen on, tiles at $8000, sprites on, background on
    ldh [rLCDC], a

MainLoop:
    call WaitFrame
    ld a, [wStarY]
    ld [SPRITES + 0], a
    ld a, [wStarX]
    ld [SPRITES + 1], a
    ld a, [wPaletteDirty]
    and a
    call nz, ApplyPalette

    call ReadPad
    ldh a, [hPad]
    ld b, a
    bit 4, b
    jr z, .noRight
    ld hl, wStarX
    inc [hl]
.noRight:
    bit 5, b
    jr z, .noLeft
    ld hl, wStarX
    dec [hl]
.noLeft:
    bit 6, b
    jr z, .noUp
    ld hl, wStarY
    dec [hl]
.noUp:
    bit 7, b
    jr z, .noDown
    ld hl, wStarY
    inc [hl]
.noDown:
    ldh a, [hPressed]
    bit 0, a
    call nz, BeepHigh
    ldh a, [hPressed]
    bit 1, a
    call nz, BeepLow
    ldh a, [hPressed]
    bit 2, a
    call nz, Recentre
    ldh a, [hPressed]
    bit 3, a
    jr z, MainLoop
    ld a, [wPalette]
    inc a
    and 3
    ld [wPalette], a
    ld a, 1
    ld [wPaletteDirty], a
    jr MainLoop

; Waits for the start of the next vertical blank.
WaitFrame:
.leave:
    ldh a, [rLY]
    cp 144
    jr z, .leave
.enter:
    ldh a, [rLY]
    cp 144
    jr nz, .enter
    ret

; hPad: held buttons. Bits 0-3 = A, B, SELECT, START; bits 4-7 = RIGHT, LEFT, UP, DOWN.
; hPressed: buttons that went down this frame.
ReadPad:
    ld a, $20
    ldh [rP1], a
    ldh a, [rP1]
    ldh a, [rP1]
    cpl
    and $0F
    swap a
    ld b, a
    ld a, $10
    ldh [rP1], a
    ldh a, [rP1]
    ldh a, [rP1]
    ldh a, [rP1]
    ldh a, [rP1]
    cpl
    and $0F
    or b
    ld b, a
    ld a, $30
    ldh [rP1], a
    ldh a, [hPad]
    cpl
    and b
    ldh [hPressed], a
    ld a, b
    ldh [hPad], a
    ret

Recentre:
    ld a, 16 + 68
    ld [wStarY], a
    ld a, 8 + 76
    ld [wStarX], a
    ret

BeepHigh:                   ; about 880 Hz on pulse channel 1
    xor a
    ldh [rNR10], a
    ld a, $80
    ldh [rNR11], a
    ld a, $F3
    ldh [rNR12], a
    ld a, $6B
    ldh [rNR13], a
    ld a, $87
    ldh [rNR14], a
    ret

BeepLow:                    ; about 440 Hz on pulse channel 2
    ld a, $80
    ldh [rNR21], a
    ld a, $F3
    ldh [rNR22], a
    ld a, $D6
    ldh [rNR23], a
    ld a, $86
    ldh [rNR24], a
    ret

ApplyPalette:
    xor a
    ld [wPaletteDirty], a
    ld a, [wPalette]
    ld c, a
    ld a, [wIsColor]
    and a
    jr nz, .color
    ld hl, MonoPalettes
    ld b, 0
    add hl, bc
    ld a, [hl]
    ldh [rBGP], a
    ld a, %11100100
    ldh [rOBP0], a
    ret
.color:
    ld a, c
    add a, a
    add a, a
    add a, a                ; 8 bytes per palette
    ld c, a
    ld b, 0
    ld hl, ColorPalettes
    add hl, bc
    ld a, $80
    ldh [rBCPS], a
    ld b, 8
.bg:
    ld a, [hli]
    ldh [rBCPD], a
    dec b
    jr nz, .bg
    ld a, $80
    ldh [rOCPS], a
    ld hl, StarPalette
    ld b, 8
.obj:
    ld a, [hli]
    ldh [rOCPD], a
    dec b
    jr nz, .obj
    ret

; Copies BC bytes from DE to HL.
MemCopy:
    ld a, [de]
    ld [hli], a
    inc de
    dec bc
    ld a, b
    or c
    jr nz, MemCopy
    ret

; Fills BC bytes at HL with D.
MemSet:
    ld a, d
    ld [hli], a
    dec bc
    ld a, b
    or c
    jr nz, MemSet
    ret

; Writes the $FF-terminated string at DE to the map at HL.
PutText:
    ld a, [de]
    cp $FF
    ret z
    ld [hli], a
    inc de
    jr PutText

INCLUDE "tiles.inc"

TextBar:   db "==================", $FF
TextTitle: db "RETRO DUO", $FF
TextCart:  db "TEST CART", $FF
TextMove:  db "D-PAD  MOVE STAR", $FF
TextBeep:  db "A  B   BEEP", $FF
TextColor: db "START  COLOR", $FF

MonoPalettes:
    db %11100100, %00011011, %11010000, %01101100

ColorPalettes:
    rgb 2, 3, 9
    rgb 6, 8, 18
    rgb 14, 16, 26
    rgb 31, 31, 31          ; night: white on navy
    rgb 26, 29, 16
    rgb 18, 22, 10
    rgb 9, 13, 6
    rgb 3, 7, 3             ; classic green
    rgb 31, 21, 12
    rgb 26, 12, 10
    rgb 16, 5, 10
    rgb 8, 1, 7             ; sunset
    rgb 10, 3, 16
    rgb 16, 6, 22
    rgb 24, 14, 24
    rgb 31, 27, 8           ; gold on grape

StarPalette:
    rgb 0, 0, 0
    rgb 31, 24, 6
    rgb 31, 14, 4
    rgb 31, 26, 4

SECTION "Variables", WRAM0
wIsColor:      ds 1
wStarX:        ds 1
wStarY:        ds 1
wPalette:      ds 1
wPaletteDirty: ds 1

SECTION "Fast variables", HRAM
hPad:     ds 1
hPressed: ds 1
