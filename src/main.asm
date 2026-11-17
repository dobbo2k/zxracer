; ---------------------------------------------------------------------------
; ZX Racer - entry point and main loop
; Target: ZX Spectrum 128K, assembled with sjasmplus
; ---------------------------------------------------------------------------
        DEVICE ZXSPECTRUM128
        INCLUDE "defs.asm"

        ORG $8000
start:
        di
        ld sp, STACK_TOP
        ld a, P7FFD_ROM48 | 7   ; display bank 5, bank 7 paged at $C000
        ld (Port7FFD), a
        ld bc, PORT_7FFD
        out (c), a
        call InitScreens
        xor a
        call InitHud
        ld a, $80
        call InitHud
        call InitInterrupts
        ei

MainLoop:
        BORDER 1                ; blue: game logic
        call ReadInput
        call UpdatePlayer
        call SelectBackBuffer
        BORDER 3                ; magenta: sprites
        call EraseSprites
        BORDER 4                ; green: horizon
        call DrawHorizon
        BORDER 2                ; red: road
        call DrawRoad
        BORDER 3                ; magenta: sprites
        call DrawSprites
        call DrawCar
        BORDER 5                ; cyan: HUD
        call DrawHud
        BORDER 0                ; black: waiting for flip
        call FlipBuffers
        jr MainLoop

        INCLUDE "interrupt.asm"
        INCLUDE "screen.asm"
        INCLUDE "input.asm"
        INCLUDE "player.asm"
        INCLUDE "road.asm"
        INCLUDE "track.asm"
        INCLUDE "car_data.asm"
        INCLUDE "car.asm"
        INCLUDE "scenery.asm"
        INCLUDE "horizon.asm"
        INCLUDE "hud.asm"
        INCLUDE "game.asm"
        INCLUDE "sound.asm"
        INCLUDE "horizon_data.asm"
        INCLUDE "vars.asm"
        INCLUDE "track_data.asm"
CodeEnd:
        ASSERT CodeEnd <= TABLES

        ORG TABLES
        INCLUDE "tables.asm"
TablesEnd:
        ASSERT TablesEnd <= PANO_LDI_END - 64

; Unrolled LDI chain for the panorama: entered at PanoLdiEnd - 2*n
        ORG PANO_LDI_END - 64
        DUP 32
        ldi
        EDUP
PanoLdiEnd:
        ret
        ASSERT $ <= XOR_END - 5 * 8

; Unrolled XOR chain for sprites: entered at XorEnd - 5*n for n bytes
        ORG XOR_END - 5 * 8
        DUP 8
        ld a, (de)
        xor (hl)
        ld (hl), a
        inc l
        inc de
        EDUP
XorEnd: jp (iy)
        ASSERT $ <= LDI_END - 2 * STRIP_PAD

; Unrolled LDI chain: entered at LdiEnd - 2*n to copy n bytes (HL) -> (DE)
        ORG LDI_END - 2 * STRIP_PAD
        DUP STRIP_PAD
        ldi
        EDUP
LdiEnd: ret

; Unrolled fill: entered at FILL_END - 2*n to write n bytes (see FillA)
        ORG FILL_END - 64
FillBlock:
        DUP 32
        ld (hl), a
        inc l
        EDUP
        ret

        ORG ISR_JP
        jp Isr

; Scenery sprites in the spare part of bank 5 (visible whichever buffer is drawn)
        ORG SCN_DATA
        INCLUDE "scenery_data.asm"
        INCLUDE "font_data.asm"
ScnEnd:
        ASSERT ScnEnd <= $8000

        SAVESNA "build/zxracer.sna", start
