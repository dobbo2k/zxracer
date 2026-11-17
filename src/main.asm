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
        call InitInterrupts
        ei

MainLoop:
        BORDER 1                ; blue: game logic
        call ReadInput
        call UpdatePlayer
        call SelectBackBuffer
        BORDER 2                ; red: road
        call DrawRoad
        BORDER 3                ; magenta: sprites
        call DrawCar
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
        INCLUDE "vars.asm"
        INCLUDE "track_data.asm"
CodeEnd:
        ASSERT CodeEnd <= TABLES

        ORG TABLES
        INCLUDE "tables.asm"
TablesEnd:
        ASSERT TablesEnd <= LDI_END - 2 * STRIP_PAD

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

        SAVESNA "build/zxracer.sna", start
