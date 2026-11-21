; ---------------------------------------------------------------------------
; Rolling tyres: the rear tyres' tread (the dashed row under the rear lights)
; rolls up their faces as the car moves. There are two tread rows, three
; rows apart, in the tyres' six pixel rows (26-31): three positions.
;
; The game draws a frame every 3 TV frames, too slowly to show a fast tread
; (a step of two rows looks like one row backwards), so the tread moves in
; the 50 Hz interrupt, on the buffer on show: by the speed each TV frame, a
; row per TYRE_STEP depth units, up to nearly a row every TV frame at full
; speed (about 48 rows a second), slower as the car slows, still when it
; stops.
;
; The interrupt only writes over a tyre: while the game loop runs (a flip in
; the last TYRE_LIVE frames: not while paused), with the game's paging (bank
; 7 at $C000), in a steering frame (the smoke frames' smoke hides the tyres),
; and only if every tyre row on screen already starts as that frame's tread or
; plain row. So it never draws into a picture of the front end or a loading
; screen. It writes the tyres' bytes (the car's columns 0-1 and 6-7, where
; tools/make_car.py keeps the tread), long before the beam reaches them.
; Lives in the gap between the lookup tables and the panorama's chain.
; ---------------------------------------------------------------------------
TYRE_TOP        EQU 2               ; the bottom part's first tyre row (pixel row 26)
TREAD_LINE      EQU 3               ; ... its tread row (27)
PLAIN_LINE      EQU 4               ; ... a plain one (28)
TYRE_STEP       EQU 21              ; depth units a row (MAX_SPEED 20 a TV frame)
TYRE_LIVE       EQU 8               ; TV frames since the game's last flip

; From the interrupt (instead of SoundTick, which it ends with): AF, BC, DE
; and HL are saved there.
TyreTick:
        ld a, (FrameCount)      ; the game loop is running
        ld hl, LastFlip
        sub (hl)
        cp TYRE_LIVE
        jp nc, SoundTick
        ld a, (Port7FFD)        ; with the game's paging
        and ~P7FFD_SHADOW
        cp P7FFD_ROM48 | 7
        jp nz, SoundTick
        ld a, (Speed)           ; roll on by the speed
        ld hl, TyreAcc
        add a, (hl)
        cp TYRE_STEP
        jr c, .acc
        sub TYRE_STEP           ; (at most a row: Speed < TYRE_STEP)
        ld (hl), a
        ld a, (TyrePhase)       ; the tread rolls up a row
        dec a
        jp p, .ph
        ld a, 2
.ph:    ld (TyrePhase), a
        jr .shown
.acc:   ld (hl), a
.shown: ld a, (Port7FFD)        ; the buffer on show and its car's frame
        and P7FFD_SHADOW
        ld hl, CarShownA
        ld d, $40 | ((CAR_ROW + 3) & $18) | TYRE_TOP
        jr z, .bufA
        ld hl, CarShownB
        ld d, $C0 | ((CAR_ROW + 3) & $18) | TYRE_TOP
.bufA:  ld e, (((CAR_ROW + 3) & 7) << 5) + CAR_COL
        ld a, (hl)
        cp 3
        jp nc, SoundTick        ; (smoke, or $FF: none yet)
        add a, a                ; its bottom part's tread row
        add a, a
        add a, low (CarGfxFrames + 2)
        ld l, a
        adc a, high (CarGfxFrames + 2)
        sub l
        ld h, a
        ld a, (hl)
        inc hl
        ld h, (hl)
        ld l, a
        ld bc, TREAD_LINE * CAR_W
        add hl, bc
        push ix
        push hl
        pop ix                  ; IX = the tread row, IX + 8 a plain row
        ex de, hl               ; HL -> pixel row 26 of the car's columns
        push hl
        ld b, 8 - TYRE_TOP      ; a tyre there? Each row's first byte is
.chk:   ld a, (hl)              ; the tread's or a plain row's
        cp (ix + 0)
        jr z, .chkOk
        cp (ix + CAR_W)
        jr nz, .none
.chkOk: inc h
        djnz .chk
        pop hl
        ld a, (TyrePhase)
        ld c, a                 ; C = rows to the next tread row
        ld b, 8 - TYRE_TOP
.row:   push ix
        ld a, c
        or a
        jr z, .src
        ld de, (PLAIN_LINE - TREAD_LINE) * CAR_W
        add ix, de
.src:   ld a, (ix + 0)
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
        pop ix
        jp SoundTick
.none:  pop hl
        pop ix
        jp SoundTick

TyreAcc:        db 0            ; depth units towards the next row
TyrePhase:      db 1            ; 0-2: the first tread row (1: as drawn, row 27)
