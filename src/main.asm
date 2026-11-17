; ---------------------------------------------------------------------------
; ZX Racer - entry point (milestone 0 stub)
; Target: ZX Spectrum 128K, assembled with sjasmplus
; ---------------------------------------------------------------------------
        DEVICE ZXSPECTRUM128

BANK_PORT   EQU $7FFD           ; bits 0-2 RAM at $C000, bit 3 shadow screen, bit 4 ROM

        ORG $8000               ; bank 2: uncontended, always paged in
start:
        di
        ld sp, $BFFF + 1
        ld a, %00010000         ; RAM bank 0 at $C000, normal screen (bank 5), 48K ROM
        ld bc, BANK_PORT
        out (c), a

        ; clear the visible screen to a sky/road placeholder
        ld hl, $4000
        ld de, $4001
        ld bc, 6143
        ld (hl), 0
        ldir
        ld hl, $5800            ; attributes: top half cyan paper, bottom green paper
        ld de, $5801
        ld bc, 383
        ld (hl), %00101000      ; paper cyan, ink black
        ldir
        ld hl, $5800 + 384
        ld de, $5800 + 385
        ld bc, 383
        ld (hl), %00100000      ; paper green, ink black
        ldir

        ld a, 1                 ; blue border
        out ($FE), a
.loop:  jr .loop

        SAVESNA "build/zxracer.sna", start
