; ---------------------------------------------------------------------------
; Einstein: the ground under an object, in a road cell of two colours (a
; ready-made kerb edge, or a slot drawn the exact way). EinSprCell draws an
; object's silhouette in its own ink over one ground colour, as over a solid
; cell, so traffic and scenery keep their colours wherever they are (on the
; Spectrum, and here at first, they took the cell's ink and changed colour
; as they crossed a kerb). Graphics II has two colours a line: the cell's
; other colour is lost under and around the object, so the one more of its
; pixels show is kept.
; In bank 2's code: the platform code below $4000 is full.
; ---------------------------------------------------------------------------

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
