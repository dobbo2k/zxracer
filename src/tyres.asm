; ---------------------------------------------------------------------------
; Rolling tyres: the rear tyres' tread (the dashed row under the rear lights)
; rolls up their faces as the car moves, a row per 64 depth units travelled
; (at most one a frame: about 16 rows a second at full speed, so the faster
; the car, the faster the tread). There are two tread rows, three rows apart,
; in the tyres' six pixel rows (26-31).
;
; After DrawCar, every frame, the tyres' bytes (the car's columns 0-1 and
; 6-7, where tools/make_car.py keeps the tread) are written from the frame's
; own tread and plain rows: so both buffers stay right whether or not DrawCar
; redrew the car. Only the steering frames: the smoke frames' smoke hides the
; tyres. Lives in the gap between the lookup tables and the panorama's chain.
; ---------------------------------------------------------------------------
TYRE_TOP        EQU 2               ; the bottom part's first tyre row (pixel row 26)
TREAD_LINE      EQU 3               ; ... its tread row (27)
PLAIN_LINE      EQU 4               ; ... a plain one (28)

DrawTyres:
        call DrawCar
        ld hl, (Pos)            ; H = distance / 64
        add hl, hl
        add hl, hl
        ld a, (TyreLast)
        cp h
        jr z, .draw
        ld a, h
        ld (TyreLast), a
        ld a, (TyrePhase)       ; moved on: the tread rolls up a row
        dec a
        jp p, .ph
        ld a, 2
.ph:    ld (TyrePhase), a
.draw:  ld hl, (CarShown)
        ld a, (hl)              ; the frame on show in this buffer
        cp 3
        ret nc
        ld ix, (CarBotSrc)
        ld a, (BufHiOr)         ; HL -> pixel row 26 of the car's columns
        or $40 | ((CAR_ROW + 3) & $18) | TYRE_TOP
        ld h, a
        ld l, (((CAR_ROW + 3) & 7) << 5) + CAR_COL
        ld a, (TyrePhase)
        ld c, a                 ; C = rows to the next tread row
        ld b, 8 - TYRE_TOP
.row:   ld de, TREAD_LINE * CAR_W
        ld a, c
        or a
        jr z, .src
        ld e, PLAIN_LINE * CAR_W
.src:   push ix
        add ix, de
        ld a, (ix + 0)
        ld (hl), a
        inc l
        ld a, (ix + 1)
        ld (hl), a
        ld a, l
        add a, 5
        ld l, a
        ld a, (ix + 6)
        ld (hl), a
        inc l
        ld a, (ix + 7)
        ld (hl), a
        ld a, l
        sub 7
        ld l, a
        pop ix
        inc h                   ; the next pixel row
        dec c
        jp p, .next
        ld c, 2
.next:  djnz .row
        ret

TyreLast:       db 0            ; distance / 64 when the tread last moved
TyrePhase:      db 1            ; 0-2: the first tread row (1: as drawn, row 27)
