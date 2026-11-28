; Expand each type's distinct sizes and rebuild the nine-entry renderer
; directory. During a checkpoint the blank screen is the scratch buffer.
; HL = packed group, DE = its final cache address.
ExpandScenery:
        push de
        ld de, SCRATCH
        call Unpack
        ld (.end + 1), de
        pop de
        ld hl, SCRATCH
.type:  ld (.group + 1), de
        ld a, (hl)
        inc hl
        ld (.count + 1), a
        ld (.map + 2), hl
        ld bc, SCN_SIZES
        add hl, bc
        ex de, hl
        ld c, SCN_SIZES * 5
        add hl, bc
        ex de, hl
        ld iy, VARIANTS
.size:  ld c, (hl)              ; unpadded width
        inc hl
        ld b, (hl)
        inc hl
        ld (iy + 1), b
        ld (iy + 4), e
        ld (iy + 5), d
        ld a, (hl)
        inc hl
        dec a
        jr z, .single
        inc c
        ld a, 4
.single:
        ld (iy + 0), c
        ld (iy + 2), a
        ld (iy + 3), 0
        push de
        or a
        jr z, .column
        dec c                   ; source has no padding column
.column:
        push de
        ld b, (iy + 1)
.pixel: ld a, (hl)
        inc hl
        ld (de), a
        ld a, (iy + 0)
        add a, e
        ld e, a
        jr nc, .down
        inc d
.down:  djnz .pixel
        pop de
        inc de
        dec c
        jr nz, .column
        ld a, (iy + 2)
        or a
        jr z, .columnsDone
        ld b, (iy + 1)
.pad:   xor a
        ld (de), a
        ld a, (iy + 0)
        add a, e
        ld e, a
        jr nc, .padDown
        inc d
.padDown:
        djnz .pad
.columnsDone:
        pop de                  ; first offset's start
        push hl                 ; next source size
        ld bc, 0
        ld c, (iy + 0)
        ld a, (iy + 1)
        ld hl, 0
.length:
        add hl, bc
        dec a
        jr nz, .length
        ld (iy + 6), l
        ld (iy + 7), h
        add hl, de
        ex de, hl
        ld a, (iy + 2)
        or a
        jr z, .indexed
        ld l, (iy + 6)
        ld h, (iy + 7)
        ex de, hl
        ld c, e
        ld b, d
        ld d, h
        ld e, l
        or a
        sbc hl, bc
                                ; HL = previous offset, DE = next offset
        push de
        ldir
        pop hl
        ld a, 4
.bit:   push af
        push hl
        ld b, (iy + 1)
.line:  ld c, (iy + 0)
        or a
.byte:  rr (hl)
        inc hl
        dec c
        jr nz, .byte
        djnz .line
        pop hl
        pop af
        dec a
        jr nz, .bit
.indexed:
        pop hl
        ld bc, 8
        add iy, bc
.count: ld a, 0
        dec a
        ld (.count + 1), a
        jp nz, .size
        push de
        push hl
.group: ld de, 0
.map:   ld ix, 0
        ld a, SCN_SIZES
.entry: push af
        ld a, (ix + 0)
        inc ix
        add a, a
        add a, a
        add a, a
        add a, low VARIANTS
        ld l, a
        ld h, high VARIANTS
        ld c, (hl)              ; width
        inc hl
        inc hl
        ld a, (hl)
        rlca
        rlca
        rlca
        rlca
        or c
        ld (de), a
        inc de
        dec hl
        ldi                     ; height
        inc hl
        inc hl
        ldi                     ; address
        ldi
        ldi                     ; shift stride (ignored for unshifted sprites)
        pop af
        dec a
        jr nz, .entry
        pop hl
        pop de
.end:   ld bc, 0
        or a
        sbc hl, bc
        ret z
        add hl, bc
        jp .type
