; ---------------------------------------------------------------------------
; Player car: always centred at the bottom of the screen (the camera follows
; it), so it owns a fixed 8x4-cell block (columns 12-19, rows 20-23). It
; writes its own bitmap and attributes there every frame: no masking, no
; shifting and no attribute clash. Frames: 0 straight, 1 left, 2 right.
; ---------------------------------------------------------------------------
        IFNDEF CAR_ALWAYS
CAR_ALWAYS      EQU 0               ; 1: redraw every frame (for verification)
        ENDIF
CAR_COL         EQU 12
CAR_ROW         EQU 20
CAR_W           EQU 8               ; bytes (must match the car_data.asm built from car.png)
CAR_H           EQU 32
CAR_FRAME       EQU CAR_W * CAR_H + CAR_W * CAR_H / 8

DrawCar:
        ld a, (Input)
        and (1 << IN_LEFT) | (1 << IN_RIGHT)
        ld b, a
        ld a, (CrashTimer)      ; spinning after a crash
        or a
        ld a, b
        jr z, .frame
        ld a, (FrameCount)
        and 4
        ld a, 1 << IN_LEFT
        jr z, .frame
        ld a, 1 << IN_RIGHT
.frame:
        ld hl, CarGfx
        ld c, 0
        cp 1 << IN_LEFT
        jr nz, .notL
        ld hl, CarGfx + CAR_FRAME
        ld c, 1
.notL:  cp 1 << IN_RIGHT
        jr nz, .notR
        ld hl, CarGfx + 2 * CAR_FRAME
        ld c, 2
.notR:  ; skip the redraw if this buffer already shows this frame and nothing
        ; has written into the car's block since
        ld de, (CarShown)
        ld a, (de)
        cp c
        jr nz, .draw
        ld a, (CarDirty)
        or a
        jr nz, .draw
        IF CAR_ALWAYS
        jr .draw
        ENDIF
        ld a, (CarAttrDirty)
        or a
        ret z
        ld bc, CAR_W * CAR_H
        add hl, bc              ; bitmap unchanged: attributes only
        jp .attrs
.draw:  ld a, c
        ld (de), a
        xor a
        ld (CarDirty), a
        ; bitmap: rows 20-23 lie in the bottom third ($5000), line k of a
        ; cell row is 256 bytes after line 0
        ld a, (BufHiOr)
        or $40 | (CAR_ROW & $18)
        ld d, a
        ld e, ((CAR_ROW & 7) << 5) + CAR_COL
        ld ixl, 4
.row:   push de
        DUP 8
        DUP CAR_W
        ldi
        EDUP
        ld a, e
        sub CAR_W
        ld e, a
        inc d
        EDUP
        pop de
        ld a, e
        add a, 32
        ld e, a
        dec ixl
        jp nz, .row
.attrs: xor a
        ld (CarAttrDirty), a
        ; attributes. The top cell row is the open cockpit: its paper is
        ; whatever lies underneath (grass, kerb or road: the road renderer
        ; keeps a copy of those attributes), with white ink for heads and
        ; screen frame.
        push hl
        ld a, (AttrHi)
        add a, (CAR_ROW * 32) >> 8
        ld d, a
        ld e, low (CAR_ROW * 32) + CAR_COL
        ld a, (StatePage)
        add a, 2
        ld h, a
        ld l, COCKPIT
        ld b, CAR_W
.cell:  ld a, (hl)
        and %01111000           ; keep bright + paper
        cp %01111000            ; bright white paper?
        jr z, .blackInk
        or 7                    ; white ink
.blackInk:
        ld (de), a
        inc e
        inc l
        djnz .cell
        pop hl
        ld bc, CAR_W         ; skip the sprite's own top-row attributes
        add hl, bc
        ld a, e
        add a, 32 - CAR_W
        ld e, a
        ld ixl, 3
.attr:  DUP CAR_W
        ldi
        EDUP
        ld a, e
        add a, 32 - CAR_W
        ld e, a
        dec ixl
        jr nz, .attr
        ret
