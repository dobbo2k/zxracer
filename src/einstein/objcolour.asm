; ---------------------------------------------------------------------------
; Einstein: the ground under an object, in a road cell of two colours (a
; ready-made kerb edge, or a slot drawn the exact way). EinSprCell draws an
; object's silhouette in its own ink over one ground colour, as over a solid
; cell, so traffic and scenery keep their colours wherever they are (on the
; Spectrum, and here at first, they took the cell's ink and changed colour
; as they crossed a kerb). Graphics II has two colours a line: the cell's
; other colour is lost under and around the object, so the one more of its
; pixels show is kept. An object in the colour of the ground under it takes
; a shade of the same hue (EinShadeE), not black: the coast's green palms
; on its green grass stayed green on one band and went black on the other.
; In bank 2's code: the platform code below $4000 is full.
; ---------------------------------------------------------------------------

; E = a TMS colour -> E: another of its hue, as far from it in lightness as
; the hue allows (Albert's palette: dark green 12 against light green 3, not
; medium green 2, which is too near it). A, BC, HL kept; D spent.
EinShadeE:
        push hl
        ld hl, EShade
        ld d, 0
        add hl, de
        ld e, (hl)
        pop hl
        ret
EShade: db 1, 14, 3, 12, 5, 4, 9, 4, 9, 6, 11, 10, 3, 9, 15, 14

; A cell under a silhouette in rows 12-15 whose row has no slot left (the
; middle third has 11 a row: a big palm's crown over the far road's kerbs
; uses them up): one of the panorama's cell patterns (PANO_SPR on, in the
; same third) that no silhouette covers this frame or covered the last,
; sent with them (EPanoList), so the object is never left out (the road
; showing through it). B = row, C = its colour byte, EPat its pixels,
; ESprName its name.
EinBorrowPano:
        ld a, b
        cp 16
        ret nc                  ; (the bottom third: none to borrow)
        ld a, (EPanoNext)       ; (the next to look at: one less, down to 0)
.find:  sub 1
        ret c                   ; none left
        ld e, a                 ; E: the pattern (its cell: row 10 + E / 32)
        and 7                   ; its cell's bit in EMaskU's rows 10-11
        add a, low EBitTab
        ld l, a
        ld h, high EBitTab
        ld d, (hl)
        ld a, e
        rrca
        rrca
        rrca
        and 7
        add a, low (EMaskU + PANO_ROW0 * MASK_ROW)
        ld l, a
        ld a, high (EMaskU + PANO_ROW0 * MASK_ROW)
        adc a, 0
        ld h, a
        ld a, (hl)
        and d
        ld a, e
        jr nz, .find            ; under a silhouette: the next down
        ld (EPanoNext), a
        ld l, a                 ; its pixels and colours, as EinPanoCell's
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        push hl
        ld de, EPanoSpr
        add hl, de
        ex de, hl
        ld hl, EPat
        push bc
        ld bc, 8
        ldir
        pop bc
        pop hl
        ld de, EPanoInkBuf
        add hl, de
        ld b, 8
.ink:   ld (hl), c
        inc hl
        djnz .ink
        ld hl, EPanoN           ; to be sent
        ld e, (hl)
        inc (hl)
        ld d, 0
        ld hl, EPanoList
        add hl, de
        ld a, (EPanoNext)
        ld (hl), a
        add a, PANO_SPR
        ld hl, (ESprName)
        ld (hl), a
        ret

; A = the road cell's name (SLOT_FIRST or more), B = its row (12-23)
; -> A = the TMS colour (0-15) of most of its pixels. BC kept.
EinCellGround:
        push bc
        ld e, a
        ld a, b                 ; a ready-made kerb edge (its third's)?
        cp 16
        ld a, e
        jr nc, .b3
        sub KERB_T1
        jr .st
.b3:    sub KERB_T2
.st:    jr c, .slot
        cp KERB_N
        jr nc, .slot
        ld l, a                 ; its byte on all 8 lines, its colour
        ld h, 0
        push hl
        ld de, EStatByte
        add hl, de
        ld a, (hl)
        call .bits
        add a, a                ; (x 8 lines)
        add a, a
        add a, a
        ld d, a
        pop hl
        ld bc, EStatCol
        add hl, bc
        jr .pick
.slot:  ld a, e                 ; a slot: its index, its 8 pattern bytes
        sub SLOT_FIRST
        ld l, a
        ld a, b
        cp 16
        ld a, l
        jr c, .t1
        add a, 4 * SLOTS_T1
.t1:    ld l, a
        ld h, 0
        ld d, h
        ld e, l
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, de              ; (x 9: SLOT_SIZE)
        IFDEF EIN_KERB
        add hl, de              ; (x 11)
        add hl, de
        ASSERT SLOT_SIZE == 11
        ELSE
        ASSERT SLOT_SIZE == 9
        ENDIF
        ld de, SlotShadow
        add hl, de
        ld d, 0
        ld b, 8
.c:     ld a, (hl)
        call .bits
        add a, d
        ld d, a
        inc hl
        djnz .c
.pick:  ld a, d                 ; HL: its colour byte. Its ink (the high
        cp 32                   ; nibble) on 32 pixels or more: the ink
        ld a, (hl)
        jr c, .paper
        rrca
        rrca
        rrca
        rrca
.paper: and 15
        pop bc
        ret

; A = a byte -> A = its bits set (C, E used; HL, B, D kept)
.bits:  push hl
        ld h, high NibBits
        ld c, a
        and 15
        or low NibBits
        ld l, a
        ld e, (hl)
        ld a, c
        rrca
        rrca
        rrca
        rrca
        and 15
        or low NibBits
        ld l, a
        ld a, (hl)
        add a, e
        pop hl
        ret

        ALIGN 16                ; (within one page: .bits)
NibBits:        db 0, 1, 1, 2, 1, 2, 2, 3, 1, 2, 2, 3, 2, 3, 3, 4
