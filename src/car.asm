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
CAR_TOP_PX      EQU CAR_W * 24          ; a frame's top part: 3 cell rows of bitmap, then attributes
CAR_BOT_PX      EQU CAR_W * 8           ; its bottom part: 1 cell row, likewise
; Frames (assets/gfx/car.png): 0 straight, 1 left, 2 right, 3-4 drifting
; left with tyre smoke (two puffs), 5-6 drifting right. Each frame is a top
; and a bottom part (CarGfxFrames): the two puffs differ only in the bottom
; row, so they share their top part.

; -> C = the frame to show: spinning after a crash, else the steering; on a
; fast bend without steering the car yaws into it, and near the grip limit
; its rear tyres smoke (two puffs in turn)
CarFrame:
        ld a, (CrashTimer)
        or a
        jr z, .drive
        ld a, (Spin)            ; spinning out: slewing both ways, smoking
        or a
        jr z, .wreck
        ld a, (FrameCount)
        and 6                   ; 0, 2, 4, 6
        rrca
        ld c, a                 ; 0-3
        and 1
        ld b, a                 ; the puff
        ld a, c
        and 2                   ; 0 / 2: left / right
        add a, 3
        add a, b
        ld c, a                 ; 3-6
        ret
.wreck: ld a, (FrameCount)
        and 4
        ld c, 1
        ret z
        inc c
        ret
.drive: ld a, (Input)
        and (1 << IN_LEFT) | (1 << IN_RIGHT)
        ld c, 0
        cp 1 << IN_LEFT
        jr nz, .nl
        ld c, 1
.nl:    cp 1 << IN_RIGHT
        jr nz, .nr
        ld c, 2
.nr:    ld hl, (LatF)           ; how hard the bend pulls
        call AbsHL
        ld de, DRIFT_LOOK
        or a
        sbc hl, de
        ret c
        ld a, c
        or a
        jr nz, .lean
        ld a, (SegCurve)        ; no steering: into the bend
        rlca
        ld c, 2
        jr nc, .lean
        ld c, 1
.lean:  ld de, SMOKE_AT - DRIFT_LOOK
        or a
        sbc hl, de
        ret c
        ld a, c                 ; smoke: 3-4 left, 5-6 right
        add a, a
        inc a
        ld c, a
        ld a, (FrameCount)
        and 4
        ret z
        inc c
        ret


DRIFT_LOOK      EQU 40              ; |P| (the bend's push): the car yaws into the bend
SMOKE_AT        EQU 72              ; ... and its rear tyres smoke (past what steering holds)

DrawCar:
        call CarFrame           ; C = frame
        ld a, c                 ; frames 3-6 (smoke, spinning): the squeal
        cp 3
        sbc a, a
        cpl
        ld (Squeal), a
        ld a, c
        add a, a
        add a, a
        ld l, a
        ld h, 0
        ld de, CarGfxFrames
        add hl, de
        ld e, (hl)
        inc hl
        ld d, (hl)
        inc hl
        ld (CarTopSrc), de
        ld a, (hl)
        inc hl
        ld h, (hl)
        ld l, a
        ld (CarBotSrc), hl
        ex de, hl               ; HL = its top part
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
        ld bc, CAR_TOP_PX
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
        jp z, .pxDone
        ld a, ixl
        dec a
        jp nz, .row
        ld hl, (CarBotSrc)      ; the last cell row: from the bottom part
        jp .row
.pxDone:
        ld hl, (CarTopSrc)
        ld bc, CAR_TOP_PX
        add hl, bc
.attrs: xor a
        ld (CarAttrDirty), a
        ; attributes. The top cell row is the open cockpit: its paper is
        ; whatever lies underneath (grass, kerb or road: the road renderer
        ; keeps a copy of those attributes), its ink the sprite's (him
        ; white, her yellow) - or black where that matches the paper.
        ld a, (AttrHi)
        add a, (CAR_ROW * 32) >> 8
        ld d, a
        ld e, low (CAR_ROW * 32) + CAR_COL
        ld a, (StatePage)
        add a, 2
        ld b, a
        ld c, COCKPIT           ; BC -> the attributes under the cockpit
        ld ixl, CAR_W
.cell:  ld a, (hl)              ; the sprite's ink
        and 7
        ld (.ink + 1), a
        rlca
        rlca
        rlca
        ld (.pap + 1), a
        ld a, (bc)
        and %01111000           ; bright + paper underneath
        push af
        and %00111000
.pap:   cp 0
        jr nz, .inkOk
        xor a
        ld (.ink + 1), a        ; same colour as the paper: black ink
.inkOk: pop af
.ink:   or 0
        ld (de), a
        inc hl
        inc c
        inc e
        dec ixl
        jr nz, .cell
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
        ret z
        ld a, ixl
        dec a
        jr nz, .attr
        ld hl, (CarBotSrc)      ; the last row: from the bottom part
        ld bc, CAR_BOT_PX
        add hl, bc
        jr .attr
