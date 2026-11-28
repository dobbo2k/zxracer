; B = row, C = column, DE = text: double-height letters over rows B, B+1
TallAt:
.ch:    ld a, (de)
        or a
        ret z
        call TallChar
        inc de
        inc c
        jr .ch

; A = character, B = row, C = column (all kept, and DE): double height
TallChar:
        push de
        push bc
        sub 32
        ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        ld de, Font
        add hl, de
        ex de, hl               ; DE = the glyph
        call CellAddr
        call .half
        inc b
        call CellAddr
        call .half
        pop bc
        pop de
        ret
.half:  push bc
        ld b, 4
.r:     ld a, (de)
        ld (hl), a
        inc h
        ld (hl), a
        inc h
        inc de
        djnz .r
        pop bc
        ret
