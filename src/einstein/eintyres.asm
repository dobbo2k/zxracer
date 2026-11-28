; ---------------------------------------------------------------------------
; Einstein: the rear tyres' tread rolls, as the Spectrum's (src/tyres.asm)
;
; In the Spider's art (tools/einstein_illustration.py spider) the rear
; tyres are the bottom row's cells 0-1 and 6-7 (the bottom third's patterns
; CAR_PAT + 24, 25, 30, 31), their tread on the cells' line 3, a plain line
; under it. The tread moves in the 50 Hz interrupt, by the speed each TV
; frame, a row each ETYRE_STEP depth units (as fast as the Spectrum's:
; nearly a row every TV frame at full speed), still when the car stops.
;
; Its three phases are patterns of their own, made ready: 12 from TYRE_PAT
; (tyre cell k's phase p is TYRE_PAT + 3k + p), each the pose's cell with
; lines 2-6 its tread line or its plain one, two tread lines three apart,
; and its colours (ECarCol: the ground's paper where the art has none). A
; step of the tread only points the four cells' names at the next phase (4
; names, about 250 T). The main loop makes the 12 in RAM (ETyreSet) when the
; pose or the tyres' colours change (EinTyrePrep);
; the upload sends them first, in the blank (EinTyreSend; when only the
; colours changed, as the road's bands pass under the tyres, the colours
; alone), and after the car's cells puts the names right for the pose it
; shows (EinTyreShow): the tread's, or in a smoke pose (the smoke hides
; the tyres) the car's own. Only while the
; game runs (a frame sent in the last ETYRE_LIVE TV frames).
;
; Spread over the room there was: EinTyreTick at the platform code's end
; (part 1), the making at the theme cache's end (2: EIN_TAIL, which no
; theme pack reaches), the names and the sending in the ScrLo and ScrHi
; table pages' holes (3, 4), ETyrePair after the data in the ZPage page's
; (5); all but 1 and 2 from src/holes.asm. ETyreSet is with the Einstein's
; buffers (src/einstein/platform.asm).
; ---------------------------------------------------------------------------
        IF TYRE_PART == 1
ETYRE_STEP      EQU 21          ; depth units a row (src/tyres.asm TYRE_STEP)
ETYRE_LIVE      EQU 8           ; TV frames since the last frame sent

; From the interrupt, each TV frame: the tread on by the speed, its names
; pointed at the phase if it moved (A, BC, DE, HL spent)
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
        jp EinTyreNames         ; (the shown pose's names at this phase)

        ELSEIF TYRE_PART == 2
        MACRO TPUT r2, r3, r4, r5, r6
        ld (hl), b              ; lines 0 and 1 as drawn
        inc hl
        ld (hl), c
        inc hl
        ld (hl), r2             ; lines 2-6: the tread (D) or plain (E)
        inc hl
        ld (hl), r3
        inc hl
        ld (hl), r4
        inc hl
        ld (hl), r5
        inc hl
        ld (hl), r6
        inc hl
        ld (hl), a              ; line 7 as drawn
        inc hl
        ENDM

; After EinCarGroundSync (the pose being built, its colours made): the 12
; tread patterns made again in ETyreSet if the pose or the tyres' colours
; changed (A, BC, DE, HL, IY spent)
EinTyrePrep:
        ld a, (CarShownB)       ; a steering pose (smoke: the tyres hidden)
        cp 3
        ret nc
        ld b, 3                 ; a new pose: pixels and colours (EinCarSync
        ld a, (ECarRuns + 1)    ; tests the high byte)
        or a
        jr nz, .make
        dec b                   ; or the tyres' cells coloured again: colours
        dec b
        ld a, (ECarSend + 3)    ; (bit k: column CAR_COL + k)
        and %11000011
        ret z
.make:  ld a, (ETyreNew)
        or b
        ld (ETyreNew), a
        ld hl, ETyreSet         ; cells 0, 1, 6 and 7 of the bottom row
        ld c, 24
        call .cell
        inc c
        call .cell
        ld c, 30
        call .cell
        inc c
; C = the car cell (24-31), HL = its three phases' pixels in ETyreSet (their
; colours 96 on) (HL advances 24, C kept)
.cell:  push bc
        push hl
        ld a, c
        add a, a
        add a, a
        add a, a
        ld c, a
        ld b, 0                 ; BC: 8 x the cell
        ld a, (ETyreNew)        ; (the pixels too?)
        and 2
        jr z, .col
        push bc
        ld iy, (EinCarSync.base + 1)    ; (the pose's pixels: its cells on)
        add iy, bc
        call EinTyreMake
        pop bc
.col:   ld iy, ECarCol
        add iy, bc
        pop hl
        push hl
        ld de, 96
        add hl, de
        call EinTyreMake
        pop hl
        ld de, 24
        add hl, de
        pop bc
        ret

; IY = a cell's 8 source bytes (pixels or colours), HL = 24 bytes out: its
; three phases, lines 2-6 each its line 3 (the tread) or 4 (plain): phase 0
; the tread on lines 2 and 5, phase 1 on 3 and 6, phase 2 on 4 (HL
; advances 24; A, BC, DE spent)
EinTyreMake:
        ld b, (iy + 0)
        ld c, (iy + 1)
        ld d, (iy + 3)
        ld e, (iy + 4)
        ld a, (iy + 7)
        TPUT d, e, e, d, e
        TPUT e, d, e, e, d
        TPUT e, e, d, e, e
        ret
        ASSERT TYRE_PAT == GROUND_PAT + 2 && TYRE_PAT + 12 <= CAR_PAT

        ELSEIF TYRE_PART == 3
; The tyres' four names for the pose the screen shows (ETyrePose): the
; tread's patterns at its phase, or in a smoke pose the car's own (A, BC,
; DE, H spent)
EinTyreNames:
        ld a, (ETyrePhase)
        ld (ETyreShown), a
        add a, TYRE_PAT         ; C, B: cells 0 and 6's names, H: on to 1, 7
        ld c, a
        add a, 6
        ld b, a
        ld h, 3
        ld a, (ETyrePose)
        cp 3
        jr c, .put
        ld bc, (CAR_PAT + 30) * 256 + CAR_PAT + 24
        ld h, 1
.put:   ld de, VRAM_NAMES + (CAR_ROW + 3) * 32 + CAR_COL
        call ETyrePair
        ld c, b
        ld e, low (VRAM_NAMES + (CAR_ROW + 3) * 32 + CAR_COL + 6)
        jp ETyrePair
        ASSERT high (VRAM_NAMES + (CAR_ROW + 3) * 32 + CAR_COL) == high (VRAM_NAMES + (CAR_ROW + 3) * 32 + CAR_COL + 7)

        ELSEIF TYRE_PART == 4
; At the upload's start, in the blank (at full speed, far from the car's
; rows): the 12 patterns' pixels and colours, or colours alone, if made
; again (ETyreNew bit 1, bit 0) (A, BC, DE, HL spent)
EinTyreSend:
        ld hl, ETyreNew
        ld a, (hl)
        ld (hl), 0
        rra
        ret nc
        rra
        ld hl, ETyreSet + 96
        jr nc, .col
        ld hl, ETyreSet
        ld de, VRAM_PAT + $1000 + TYRE_PAT * 8
        ld b, 96
        call EinWrite           ; (HL: ETyreSet + 96)
.col:   ld de, VRAM_COL + $1000 + TYRE_PAT * 8
        ld b, 96
        jp EinWrite

; After EinCarSync: the names for the pose now shown
EinTyreShow:
        ld a, (CarShownB)
        ld (ETyrePose), a
        jp EinTyreNames

        ELSE
; DE = a name's VRAM address, C = its name, H = on to the next's: both,
; 32 T apart (the picture may be on) (A spent)
ETyrePair:
        call VdpAddr
        ld a, c
        out (EIN_VDP_DATA), a
        add a, h
        push af
        pop af
        out (EIN_VDP_DATA), a
        ret
        ENDIF
