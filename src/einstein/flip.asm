; ---------------------------------------------------------------------------
; Einstein: frames into VRAM
;
; The Spectrum draws into a hidden screen and flips. Here the frame is built
; in RAM (EinDraw: NameBuf, SlotShadow), RequestFlip marks it ready, and
; the interrupt sends it at the start of a vertical blank (EinUpload): row
; by row, the row's changed slots, then its names if it was drawn again;
; then the car's and the sky's cells. Writes go at full speed while the
; blank's budget lasts, paced (32 T) after, so none is ever lost.
; ---------------------------------------------------------------------------

; The Spectrum's per-buffer pointers, for the parts of its drawing code
; that still run: all at buffer B, whose screen ($C000) is not shown here.
SelectBackBuffer:
        ld a, $80
        ld (BufHiOr), a
        ld (RunCommand.bufOr + 1), a
        ld hl, CmdListB
        ld (CmdList), hl
        ld hl, PanoLastB
        ld (PanoLast), hl
        ld hl, MsgLastB
        ld (MsgLast), hl
        ld hl, HudCacheB
        ld (HudCache), hl
        ld hl, CarShownB
        ld (CarShown), hl
        ld a, high StateB1
        ld (StatePage), a
        ld a, $D8
        ld (AttrHi), a
        ret

GameFrames:     dw 0

; Until the frame asked for has gone into VRAM (before touching what it is
; sent from: NameBuf, the slots, screen B)
WaitFlip:
.w:     ld a, (FlipPending)
        or a
        ret z
        halt
        jr .w

; This frame is ready: the interrupt sends it at the start of a vertical
; blank, at least MIN_FRAMES after the last (the Spectrum's steady 16.7
; fps). The next frame's logic runs meanwhile.
RequestFlip:
        ld hl, (GameFrames)     ; (for the tests: game frames drawn)
        inc hl
        ld (GameFrames), hl
        ld a, 1
        ld (FlipPending), a
        ret

; From the interrupt, at most 1 ms into a vertical blank: VRAM at full
; speed, the picture not being drawn. Row by row, the row's changed slots
; and then its names, so a row never shows new names over old patterns.
EinUpload:
        ld a, (ELongWait)       ; (timed: the CTC's wait started as the frame
        ld (EBudget), a         ; was seen; else paced)
        ld (EHoldOn), a         ; (and each row kept out of the raster's way:
        ld hl, 0                ; src/einstein/rowhold.asm)
        ld (EHoldBase), hl
        dec l
        ld a, l
        ld (EHoldLast), a
        ld hl, DirtyList
        ld (EDirtyPtr), hl
        IFDEF EIN_DASH
        call EinDashSend        ; (the centre line's sprites)
        ENDIF
        call EinPanoSend        ; (the panorama's cells under silhouettes)
        call EinTyreSend        ; (the tyres' tread: src/einstein/eintyres.asm)
        call EinHoldPlan        ; (which rows could meet the raster: rowhold.asm)
        ld c, MIRROR_ROWS       ; (the panorama's and the road's rows)
.row:   push bc
        call EinRowHold         ; (not while the raster could reach it)
        ld a, c                 ; a road row's changed slots: EDirtyRowN of
        sub ROAD_ROW0           ; them, next in DirtyList
        jr c, .names
        ld e, a
        add a, low EDirtyRowN
        ld l, a
        ld a, high EDirtyRowN
        adc a, 0
        ld h, a
        ld a, (hl)
        or a
        jr z, .names
        ld b, a
        call EinSlotBase
        ld hl, (EDirtyPtr)
        push bc                 ; scan the row once for each changed plane
        push hl
        ld c, $40
        call EinSlotRuns
        pop hl
        pop bc
        push bc
        ld c, $80
        call EinSlotRuns
        pop bc
        ld (EDirtyPtr), hl
.names: ld a, c                 ; then its names, if it was drawn again
        add a, low ERowDrawn
        ld l, a
        ld a, high ERowDrawn
        adc a, 0
        ld h, a
        ld a, (hl)
        or a
        jr z, .next
        ld (hl), 0
        ld l, c                 ; VRAM_NAMES + row * 32, from NameBuf's row (2:
        ld h, 0                 ; put together) or BaseNames' (1)
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        push hl
        ld de, VRAM_NAMES
        add hl, de
        ex de, hl
        pop hl
        ld bc, NameBuf
        dec a
        jr nz, .nb
        ld bc, BaseNames - PANO_ROW0 * 32
.nb:    add hl, bc
        ld b, 32
        call EinWrite
.next:  pop bc
        inc c
        ld a, c
        cp 24
        jr nz, .row
        call EinCarHold         ; (not while the raster could reach it)
        call EinCarSync         ; ---- the car's cells
        call EinTyreShow        ; (its tyres' names)
        jp EinMirror            ; ---- the sky's cells written


; The writes in the vertical blank (30,830 T) go at full speed while it
; lasts, by the clock: the interrupt saw the frame at most 1 ms (and its own
; few hundred T) into the blank, and started the CTC's 16 ms wait then
; (src/einstein/boot.asm), a count each 256 T down from 250. A write starts
; at full speed only while the count leaves it time at 32 T a byte before
; BLANK_END (100 counts, 25,600 T: the blank's 26,600 T after the latest
; start, less a margin). Past it, writes are paced (32 T), safe in the
; picture. A frame seen at the first poll after a wait (late, by an unknown
; time: no wait started) is sent paced.
BLANK_END       EQU 250 - 100

; B = bytes about to be written (B, C, DE, HL kept): carry, write them paced.
; EBudget: 0 paced, 1 timed (EinUpload), else any speed (the display off).
EinSpend:
        ld a, (EBudget)
        cp 1
        jr z, .timed
        sub 1                   ; (0: carry)
        ret
.timed: ld a, b                 ; at least BLANK_END + 1 + B / 8 counts left
        rrca
        rrca
        rrca
        and 31
        add a, BLANK_END + 1
        ld (.need + 1), a
        in a, (EIN_CTC2)
.need:  cp 0
        ret nc
        xor a                   ; past it: paced from now on (the count goes
        ld (EBudget), a         ; on down, and from 0 starts again at 250)
        scf
        ret

; HL = source, DE = VRAM address, B = count (1-255): fast while the budget
; lasts, else paced. HL advances.
EinWrite:
        call EinSpend
        jp c, VdpWrite
        call VdpAddr
        ld c, EIN_VDP_DATA
.chunk: ld a, b                 ; (the unrolled OUTIs: 16 T a byte, 32 at a
        sub 33                  ; time, src/main.asm)
        jr c, .tail
        call OutiEnd - 64
        jr .chunk
.tail:  add a, 33               ; (1-32 left)
        add a, a
        neg
        ld (.jp + 1), a
.jp:    jp OutiEnd - 256        ; (low byte patched: OutiEnd - 2 * B)
        ASSERT low OutiEnd == 0

; DE = VRAM address, B = count (1-255), L = value: as EinWrite
EinFill:
        call EinSpend
        jr c, .paced
        call VdpAddr
        ld a, l
        ld c, EIN_VDP_DATA
.f:     out (c), a
        djnz .f
        ret
.paced: call VdpAddr            ; (paced: 37 T a byte)
        ld a, l
        ld c, EIN_VDP_DATA
.p:     out (c), a
        nop
        nop
        nop
        djnz .p
        ret

EBudget:        dw 0
EDirtyPtr:      dw 0
ERowShadow:     dw 0            ; (EinSlotBase: the row's first slot's bytes in
ERowVram:       dw 0            ; SlotShadow, its pattern's VRAM address)

; E = road row (0-11): its first slot's bytes and VRAM address (ERowSlotTab:
; ESlotPtr, ESlotName0), for EinSendRun. BC kept.
EinSlotBase:
        ld a, e
        add a, a
        add a, e                ; (x 3)
        add a, low ERowSlotTab
        ld l, a
        ld a, high ERowSlotTab
        adc a, 0
        ld h, a
        ld a, (hl)
        inc hl
        ld (ERowShadow), a
        ld a, (hl)
        inc hl
        ld (ERowShadow + 1), a
        ld l, (hl)
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        ld a, e                 ; (rows 12-15: the middle third; on: the bottom)
        cp 4
        ld a, high (VRAM_PAT + $800)
        jr c, .t
        ld a, high (VRAM_PAT + $1000)
.t:     add a, h
        ld h, a
        ld (ERowVram), hl
        ret

; HL walks B dirty entries for plane C. Slots are unique in a row but
; can be allocated from either end. Stream each run lowest address first.
EinSlotRuns:
.find:  ld a, (hl)
        inc hl
        and c
        jr nz, .first
        djnz .find
        ret
.first: dec hl
        ld a, (hl)
        inc hl
        and 31
        ld d, a                 ; lowest and highest slot in the run
        ld e, a
.more:  dec b
        jr z, .send
        ld a, (hl)
        and c
        jr z, .consume
        ld a, (hl)
        and 31
        inc a
        cp d
        jr z, .lower
        sub 2
        cp e
        jr nz, .send
        inc e
.consume:
        inc hl
        jr .more
.lower: dec d
        jr .consume
.send:  push bc
        push hl
        call EinSendRun
        pop hl
        pop bc
        inc b
        djnz .find
        ret

; D..E inclusive, C = pixel ($40) or colour ($80) plane.
EinSendRun:
        ld a, e
        sub d
        inc a
        ld (.count + 1), a
        ld b, d
        ld a, d
        add a, a
        add a, a
        add a, a
        ld e, a
        ld d, 0
        ld hl, (ERowVram)
        add hl, de
        ex de, hl               ; DE = first VRAM tile
        add a, b
        IFDEF EIN_KERB
        add a, b
        add a, b
        ENDIF
        ld hl, (ERowShadow)
        add a, l
        ld l, a
        jr nc, .address
        inc h
.address:
        bit 7, c
        jr z, .addrSet
        ld a, d
        add a, high VRAM_COL
        ld d, a
        ld a, l
        add a, 8
        ld l, a
        jr nc, .addrSet
        inc h
.addrSet:
        call VdpAddr
.count: ld d, 0                 ; tiles remaining
        ld a, d
        add a, a
        add a, a
        add a, a
        bit 7, c
        jr nz, .colours
        ld b, a
        call EinSpend
        ld c, EIN_VDP_DATA
        jr c, .pacedPixels
        MACRO PIXEL_RUN paced
        DUP 8
        outi
        IF paced
        nop
        nop
        nop
        nop
        ENDIF
        EDUP
        DUP SLOT_SIZE - 8
        inc hl
        EDUP
        dec d
        ENDM
.pixels:
        PIXEL_RUN 0
        jr nz, .pixels
        ret
.pacedPixels:
        PIXEL_RUN 1
        jr nz, .pacedPixels
        ret

.colours:
        add a, a                ; reserve 512 T/tile for mixed inks and stride
        jr nc, .colourBudget
        xor a                   ; long run: stay paced even if the CTC wraps
        ld (EBudget), a
        jr .pacedColours
.colourBudget:
        ld b, a
        call EinSpend
        jr c, .pacedColours
        MACRO COLOUR_RUN paced, solid, advance
        IFDEF EIN_KERB
        inc hl
        ld a, (hl)
        dec hl
        or a
        jr z, solid
        push hl
        call EinSendCols        ; mixed inks already have display-safe timing
        pop hl
        jr advance
solid:
        ENDIF
        ld a, (hl)
        DUP 8
        out (EIN_VDP_DATA), a
        IF paced
        DUP 6
        nop
        EDUP
        ENDIF
        EDUP
advance:
        ld bc, SLOT_SIZE
        add hl, bc
        dec d
        ENDM
.fastColours:
        COLOUR_RUN 0, .solidFast, .advanceFast
        jr nz, .fastColours
        ret
.pacedColours:
        COLOUR_RUN 1, .solidPaced, .advancePaced
        jr nz, .pacedColours
        ret

; ---------------------------------------------------------------------------
; The display afresh (the end of OvResetDisplay, at a new stage, once the
; Spectrum's code has made screen B afresh): with the display off, VRAM
; cleared; the solid cells 0-15 in the middle and bottom thirds; the sky's
; rows mirrored, the panorama's patterns; the names: the sky's, the
; panorama's, grass below; no slot in use.
EinResetDisplay:
        di                      ; (the interrupt reads the VDP's status)
        ld hl, BaseNames
        ld de, NameBuf
EinArtLength: ld bc, 0
        ldir
        ld hl, NameBuf + 9
        ld de, ESkyPixels
        call UnLZ
        ld de, ESkyInks
        call UnLZ
        ld de, PANO_CACHE
        call UnLZ
        ld de, EObjectInks
        call UnLZ
        xor a                   ; the packed stream may span the old object list
        ld (CmdListB), a
        inc a
        ld (EOvClobbered), a
        call EinFrontOff        ; the game's display again
        call VdpInit            ; (a disc read may have let MOS at the VDP)
        call VdpOff
        ld hl, $7FFF            ; (the display off: any speed)
        ld (EBudget), hl
        ld de, 0                ; all of VRAM: 0
        ld bc, $4000
        ld l, 0
        call VdpFill
        ld de, VRAM_SPRATTR     ; no sprites
        ld bc, 1
        ld l, $D0
        call VdpFill
        ld de, VRAM_COL + $800  ; the solid cells' colours
        call .solids
        ld de, VRAM_COL + $1000
        call .solids
        call EinGroundInit
        call EinStaticInit      ; the bottom third's ready-made patterns
        IFDEF EIN_DASH
        call EinDashReset       ; the centre line's sprites
        ld hl, EDashAttr
        ld de, VRAM_SPRATTR
        ld b, 12 * 4
        call VdpWrite
        call EinTailLamps
        xor a
        ld (EDashAttrNew), a
        ELSE
        call EinTailLamps       ; (the only sprites)
        ENDIF
        call EinMirrorAll
        call EinPanoUpload
        ; the names: rows 0-7 the top third's patterns in order, rows 8-9
        ; the middle third's from SKY_PAT_T1, the panorama, grass
        ld hl, NameBuf
        xor a
.n0:    ld (hl), a
        inc hl
        inc a
        jr nz, .n0
        ld a, SKY_PAT_T1
.n1:    ld (hl), a
        inc hl
        inc a
        cp SKY_PAT_T1 + 64
        jr nz, .n1
        ld a, (HorizonX + 1)
        call EinHorizonNow
        ld hl, BaseNames + (ROAD_ROW0 - PANO_ROW0) * 32
        ld a, (PalGrassL)
        ld b, (24 - ROAD_ROW0) * 32 / 2
        call .fill
        ld a, (PalGrassL)
        ld b, (24 - ROAD_ROW0) * 32 / 2
        call .fill
        ld b, CAR_ROW           ; the car's names (they stay)
.cn:    push bc
        ld a, b
        sub PANO_ROW0
        rrca
        rrca
        rrca
        ld l, a
        and $E0
        ld e, a
        ld a, l
        and 3
        ld d, a
        ld hl, BaseNames
        add hl, de
        call EinCarNames
        pop bc
        inc b
        ld a, b
        cp 24
        jr nz, .cn
        ld hl, BaseNames
        ld de, NameBuf + PANO_ROW0 * 32
        ld bc, (24 - PANO_ROW0) * 32
        ldir
        ld hl, EMaskN           ; no silhouettes on show (N and U, and their
        ld de, EMaskN + 1       ; rows' bits)
        ld bc, 2 * 24 * MASK_ROW - 1
        ASSERT EMaskU == EMaskN + 24 * MASK_ROW
        ld (hl), 0
        ldir
        ld hl, ENRows
        ld b, 6
.rz:    ld (hl), 0
        inc hl
        djnz .rz
        xor a
        ld (EPanoN), a
        call EinPortalReset
        ld hl, NameBuf          ; (the display is off: any speed would do)
        ld de, VRAM_NAMES
        ld b, 0
        call VdpWrite
        ld de, VRAM_NAMES + 256
        ld b, 0
        call VdpWrite
        ld de, VRAM_NAMES + 512
        ld b, 0
        call VdpWrite
        ld hl, ERowDrawn        ; (all sent)
        ld b, 24
.d:     ld (hl), 0
        inc hl
        djnz .d
        ld a, $FF
        ld (CarShownB), a
        ld hl, SlotShadow       ; the slots: as VRAM, all clear
        ld de, SlotShadow + 1
        ld bc, N_SLOTS * SLOT_SIZE - 1
        ld (hl), 0
        ldir
        ld a, 1                 ; (no slot changed: EinDraw starts the list)
        ld (EinShape), a        ; every row to be drawn
        ld (EinForce), a
        call VdpOn
        ei
        ret
; A = attribute: its paper's solid name, B times from HL
.fill:  call AttrPaper
.f:     ld (hl), a
        inc hl
        djnz .f
        ret
; DE = a third's colours: solid cell k has colour k behind clear pixels
.solids:
        call VdpAddr
        ld b, 0
.s:     ld a, b
        rrca
        rrca
        rrca
        and 15
        out (EIN_VDP_DATA), a   ; (the display is off)
        inc b
        ld a, b
        cp 128
        jr nz, .s
        ret
