; ---------------------------------------------------------------------------
; Screen buffers: A = bank 5 at $4000, B = bank 7 (paged at $C000)
; ---------------------------------------------------------------------------

; Clear both buffers and set the sky attributes. Expects bank 7 at $C000.
InitScreens:
        ld hl, $4000
        call ClearScreen
        ld hl, $C000
        ; fall through

; HL = buffer base. Clears the bitmap; sky rows get ATTR_SKY, road rows grass.
ClearScreen:
        ld d, h
        ld e, l
        inc de
        ld (hl), 0
        ld bc, 6143
        ldir
        ld h, d
        ld l, e
        inc de
        ld (hl), ATTR_SKY
        ld bc, 32 * ROAD_ROW0 - 1
        ldir
        ld h, d
        ld l, e
        inc de
        ld (hl), ATTR_GRASS_L
        ld bc, 32 * (24 - ROAD_ROW0) - 1
        ldir
        ret

; Page in the back buffer and point the renderer at it.
SelectBackBuffer:
        ld a, (BackBuf)
        or a
        jr nz, .bufB
        ld a, P7FFD_ROM48 | P7FFD_SHADOW    ; B displayed, draw into A
        ld e, 0
        ld d, high StateA1
        ld c, $58
        jr .set
.bufB:  ld a, P7FFD_ROM48 | 7                ; A displayed, bank 7 at $C000
        ld e, $80
        ld d, high StateB1
        ld c, $D8
.set:   ld (Port7FFD), a
        push bc
        ld bc, PORT_7FFD
        out (c), a
        pop bc
        ld a, e
        ld (BufHiOr), a
        ld a, d
        ld (StatePage), a
        ld a, c
        ld (AttrHi), a
        ret

; Ask the interrupt handler to display the buffer just drawn, wait for it,
; then swap roles.
FlipBuffers:
        ld a, (BackBuf)
        or a
        ld a, P7FFD_ROM48 | 7                ; show A
        jr z, .set
        ld a, P7FFD_ROM48 | P7FFD_SHADOW     ; show B
.set:   ld (FlipValue), a
        ld a, 1
        ld (FlipPending), a
.wait:  halt
        ld a, (FlipPending)
        or a
        jr nz, .wait
        ld a, (BackBuf)
        xor 1
        ld (BackBuf), a
        ret

; A = value, B = count (0-32), HL = destination; advances L only.
FillA:
        ex af, af'
        ld a, b
        or a
        jr z, .none
        add a, a
        neg
        ld (.jump + 1), a
        ex af, af'
.jump:  jp FILL_END - 256       ; low byte patched: FILL_END - 2*count
.none:  ex af, af'
        ret
