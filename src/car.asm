; ---------------------------------------------------------------------------
; Player car: always centred at the bottom of the screen (the camera follows
; it), so it owns a fixed 8x4-cell block (columns 12-19, rows 20-23). It
; writes its own bitmap and attributes there every frame: no masking, no
; shifting and no attribute clash. Frames: 0 straight, 1 left, 2 right.
; ---------------------------------------------------------------------------
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
        cp 1 << IN_LEFT
        jr nz, .notL
        ld hl, CarGfx + CAR_FRAME
.notL:  cp 1 << IN_RIGHT
        jr nz, .notR
        ld hl, CarGfx + 2 * CAR_FRAME
.notR:
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
        ; attributes. The top cell row is the open cockpit: its paper is
        ; whatever lies underneath (grass, kerb or road, from the road
        ; renderer's row state), with white ink for heads and screen frame.
        push hl
        ld a, (AttrHi)
        add a, (CAR_ROW * 32) >> 8
        ld d, a
        ld e, low (CAR_ROW * 32) + CAR_COL
        ld a, (StatePage)
        add a, 2
        ld h, a
        ld l, (CAR_ROW - ROAD_ROW0) * 4
        ld a, (hl)
        ld (.ca + 1), a
        inc l
        ld a, (hl)
        ld (.cb + 1), a
        inc l
        ld a, (hl)
        ld (.cc + 1), a
        inc l
        ld a, (hl)
        ld (.cd + 1), a
        ld l, $80 + CAR_ROW - ROAD_ROW0
        ld a, (hl)
        or a
        ld bc, (ATTR_GRASS_L << 8) | ATTR_KERB_L
        jr z, .light
        ld bc, (ATTR_GRASS_D << 8) | ATTR_KERB_D
.light: ld l, CAR_COL           ; L = column
.cell:  ld a, l
.ca:    cp 0
        ld h, b                 ; grass
        jr c, .type
.cb:    cp 0
        ld h, c                 ; kerb
        jr c, .type
.cc:    cp 0
        ld h, ATTR_ROAD
        jr c, .type
.cd:    cp 0
        ld h, c
        jr c, .type
        ld h, b
.type:  ld a, h
        and %01111000           ; keep bright + paper
        cp %01111000            ; bright white paper?
        jr z, .blackInk
        or 7                    ; white ink
.blackInk:
        ld (de), a
        inc e
        inc l
        ld a, l
        cp CAR_COL + CAR_W
        jr nz, .cell
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
