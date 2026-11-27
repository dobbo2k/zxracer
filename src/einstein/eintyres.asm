; ---------------------------------------------------------------------------
; Einstein: the rear tyres' tread rolls, as the Spectrum's (src/tyres.asm)
;
; In the Spider's art (tools/einstein_illustration.py spider) the rear
; tyres are the bottom row's cells 0-1 and 6-7 (the bottom third's patterns
; CAR_PAT + 24, 25, 30, 31), their tread on the cells' line 3, a plain line
; under it. The tread moves in the 50 Hz interrupt, by the speed each TV
; frame, a row each ETYRE_STEP depth units (as fast as the Spectrum's:
; nearly a row every TV frame at full speed), still when the car stops: the
; tyres' lines 2-6 get the shown pose's tread line or its plain one, two
; tread lines three apart, with their colours (the art's ink; where its
; paper is clear, the ground's, as EinCarSync gives it). Only while the game
; runs (a frame sent in the last ETYRE_LIVE TV frames), in a steering pose
; (the smoke hides the tyres), and only when the tread has moved or the
; car's cells were sent again (EinUpload: then after them, under the car's
; raster hold, src/einstein/rowhold.asm).
; EinTyreTick at the platform code's end, the drawing at the theme cache's
; end (EIN_TAIL: no theme pack reaches it), the data in a table page's hole
; (src/holes.asm): nowhere else had room.
; ---------------------------------------------------------------------------
        IF TYRE_PART == 1
ETYRE_STEP      EQU 21          ; depth units a row (src/tyres.asm TYRE_STEP)
ETYRE_LIVE      EQU 8           ; TV frames since the last frame sent

; From the interrupt, each TV frame: the tread on by the speed, drawn if it
; moved (A, BC, DE, HL spent)
EinTyreTick:
        ld a, (EFrontOn)        ; the game running (not the front end, nor a
        or a                    ; display reset: CarShownB $FF)
        ret nz
        ld a, (CarShownB)
        cp 3
        ret nc
        ld a, (FrameCount)
        ld hl, LastFlip
        sub (hl)
        cp ETYRE_LIVE
        ret nc
        ld a, (Speed)
        ld hl, ETyreAcc
        add a, (hl)
        ld (hl), a
        sub ETYRE_STEP
        jr c, .same
        ld (hl), a
        inc hl                  ; (ETyrePhase) up a row: 2, 1, 0, 2 ...
        dec (hl)
        jp p, .same
        ld (hl), 2
.same:  ld a, (ETyrePhase)
        ld hl, ETyreShown
        cp (hl)
        ret z
        jp EinTyreDraw          ; (the shown pose's tyres at this phase)
        ELSE

; The tyres drawn at the current phase in the pose the screen shows
; (ETyrePose: EinUpload) (A, BC, DE, HL, IX, IY spent)
EinTyreDraw:
        ld a, (ETyrePose)       ; a steering pose (0-2: smoke 3-6, $FF none)
        cp 3
        ret nc
        add a, a                ; its bottom row (EinCarFrames: its top, its
        add a, a                ; base: pixels, then inks 64 on)
        add a, a
        add a, low (EinCarFrames + 2)
        ld l, a
        adc a, high (EinCarFrames + 2)
        sub l
        ld h, a
        ld a, (hl)
        inc hl
        ld h, (hl)
        ld l, a
        ld (EinTyreCell.base + 1), hl
        ld a, (ETyrePhase)      ; its lines' sources at this phase
        ld (ETyreShown), a
        ld e, a
        add a, a
        add a, a
        add a, e
        add a, low ETyreLines
        ld l, a
        adc a, high ETyreLines
        sub l
        ld h, a
        ld (EinTyreCell.lines + 2), hl
        ld b, 0                 ; its cells 0, 1, 6 and 7
        call EinTyreCell
        inc b
        call EinTyreCell
        ld b, 6
        call EinTyreCell
        inc b

; B = a cell of the car's bottom row: its lines 2-6, pixels and colours,
; each the pose's tread line (3) or its plain one (4) (B kept)
EinTyreCell:
        push bc
        ld a, b                 ; HL = the cell's pixels
        add a, a
        add a, a
        add a, a
        ld e, a
        ld d, 0
.base:  ld hl, 0                ; (patched: the pose's bottom row)
        add hl, de
        push de                 ; (E: 8 x the cell)
        ld a, b                 ; its ground's paper (ECarGround)
        add a, low (ECarGround + 24)
        ld e, a
        adc a, high (ECarGround + 24)
        sub e
        ld d, a
        ld a, (de)
        ld (.gnd + 1), a
.lines: ld ix, 0                ; (patched: ETyreLines at the phase)
        ld iy, ETyreBuf         ; (pixels, then colours 5 on)
        ld b, 5
        ld de, 64
.ln:    push hl
        ld a, (ix + 0)
        inc ix
        add a, l
        ld l, a
        jr nc, .h
        inc h
.h:     ld a, (hl)
        ld (iy + 0), a
        add hl, de
        ld a, (hl)
        and 15
        ld a, (hl)
        jr nz, .ink
.gnd:   or 0                    ; (patched: the ground's paper)
.ink:   ld (iy + 5), a
        inc iy
        pop hl
        djnz .ln
        pop de                  ; ---- into VRAM: the cell's lines 2-6
        ld a, e
        add a, low (CAR_PAT * 8 + 24 * 8 + 2)
        ld e, a
        ld d, high (VRAM_PAT + $1000 + CAR_PAT * 8 + 24 * 8)
        push de
        ld hl, ETyreBuf
        ld b, 5
        call EinWrite
        pop de
        set 5, d                ; (the colours: VRAM_COL, $2000 on)
        ld b, 5
        call EinWrite           ; (HL: ETyreBuf + 5)
        pop bc
        ret
        ASSERT (CAR_PAT * 8 + 24 * 8 + 7 * 8 + 6) < 256 * ((CAR_PAT * 8 + 24 * 8) / 256 + 1)
        ASSERT VRAM_COL == VRAM_PAT + $2000
        ENDIF
