; ---------------------------------------------------------------------------
; CPC: the rear tyres' tread rolls, as the Spectrum's (src/tyres.asm)
;
; The Spider's tyres (tools/cpc_illustration.py spider) show on its lines
; 27-29, the tread on 27; their Mode 0 bytes 2, 3, 12 and 13 there are
; opaque and the same in every steering pose (tools/cpc_art.py car_code:
; CTyreTread, CTyrePlain). The tread moves in the VSYNC interrupt, on the
; screen on show, by the speed each TV frame, a row each CTYRE_STEP depth
; units (as fast as the Spectrum's), still when the car stops. Only while
; the game runs (a frame shown in the last 8 TV frames), in a steering pose
; (the smoke hides the tyres), when the tread has moved or a new frame was
; shown, and while the RAM configuration the main code has is known
; (CRamNow: CpcSelect's; $FF while the disc, the front end or a display
; reset sets its own): the screen on show is put at $4000 for the 12
; bytes, then CRamNow again. The interrupt comes in the border, long
; before the raster reaches the car.
; ---------------------------------------------------------------------------
CTYRE_STEP      EQU 21          ; depth units a row (src/tyres.asm TYRE_STEP)

; From the interrupt at VSYNC (AF, BC, DE, HL saved there)
CpcTyreTick:
        ld a, (CFrontOn)        ; the game running
        or a
        ret nz
        ld a, (FrameCount)
        ld hl, LastFlip
        sub (hl)
        cp 8
        ret nc
        ld a, (Speed)           ; on by the speed
        ld hl, CTyreAcc
        add a, (hl)
        ld (hl), a
        sub CTYRE_STEP
        jr c, .same
        ld (hl), a
        inc hl                  ; (CTyreRow) up a row: 2, 1, 0, 2 ...
        dec (hl)
        jp p, .same
        ld (hl), 2
.same:  ld a, (CTyrePose)       ; a steering pose on show
        cp 3
        ret nc
        ld a, (CRamNow)         ; the main code's configuration known
        inc a
        ret z
        ld a, (CTyreRow)        ; moved, or a new frame shown
        ld hl, CTyreShown
        cp (hl)
        ret z
        ld (hl), a
        ld e, a                 ; E: the tyres' line with the tread (0-2)
        ld a, (CpcHidden)       ; the screen on show at $4000
        xor 1
        add a, a
        or RAM_A
        ld bc, GA_PORT
        out (c), a
        ld hl, SCR + (CAR_ROW + CTYRE_Y / 8) * SCR_ROW + CAR_COL * 2 + (CTYRE_Y & 7) * SCR_LINE + 2
        ld d, 3
.ln:    push hl
        ld bc, CTyrePlain
        ld a, e
        or a
        jr nz, .b
        ld bc, CTyreTread
.b:     ld a, (bc)              ; bytes 2, 3, 12, 13
        ld (hl), a
        inc bc
        inc l
        ld a, (bc)
        ld (hl), a
        inc bc
        ld a, l
        add a, 9
        ld l, a
        ld a, (bc)
        ld (hl), a
        inc bc
        inc l
        ld a, (bc)
        ld (hl), a
        pop hl
        ld a, h                 ; the next line
        add a, high SCR_LINE
        ld h, a
        dec e
        dec d
        jr nz, .ln
        ld a, (CRamNow)         ; the main code's configuration again
        ld b, high GA_PORT
        out (c), a
        ret
        ASSERT CTYRE_Y / 8 == (CTYRE_Y + 2) / 8
        ASSERT low (SCR + (CAR_ROW + CTYRE_Y / 8) * SCR_ROW + CAR_COL * 2 + 13) > low (SCR + (CAR_ROW + CTYRE_Y / 8) * SCR_ROW + CAR_COL * 2)

CTyreAcc:       db 0            ; depth units towards the next row
CTyreRow:       db 0            ; the tyres' line with the tread (0-2: 27-29)
        ASSERT CTyreRow == CTyreAcc + 1
CTyreShown:     db $FF          ; as last written ($FF: a new frame on show)
CTyrePose:      db $FF          ; the pose on show (CpcShow)
CRamNow:        db $FF          ; the main code's RAM configuration ($FF: not
                                ; known: CpcSelect's, else its own)
