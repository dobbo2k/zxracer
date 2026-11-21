; ---------------------------------------------------------------------------
; Einstein: the road in Graphics II (docs/port_einstein.md section 5)
;
; From pass 1's tables (src/road.asm: edges per line in DEPage, the centre
; line in LaneX, bands in Band), per character row 12-23, as the Spectrum's
; DrawRoadRow: cells [0,a) grass, [a,b) kerb, [b,c) road, [c,d) kerb,
; [d,32) grass, the row's colours from the band of its middle line.
;
; Solid cells cost one name byte: names 0-15 are solid TMS colours. Only a
; kerb cell with the road's edge in it, or a road cell with the centre line,
; needs a pattern: the row's next slot, 8 bytes of pixels (set: road or the
; centre line) and one colour byte for all 8 lines. A slot is sent to VRAM
; only when it differs from what VRAM holds (SlotShadow): the slots are
; handed out in the same order each frame, so a straight road sends nothing.
;
; Not yet: the fork's second road, tunnel walls' lamps, the hills' per-line
; bands (the row takes its middle line's, as the Spectrum does).
; ---------------------------------------------------------------------------

; Every road row into NameBuf, changed slots into SlotShadow and DirtyList
; A row is drawn again only if its bands moved (the band bytes of its four
; line pairs) or, pass 1 having run (EinShape), its shape did: what its
; cells come from (EinRowSame). EinForce: every row (a display reset, in or
; out of a tunnel).
EinDraw:
        ld hl, DirtyList
        ld (EDirtyEnd), hl
        xor a
        ld (DirtyN), a
        ld (ERow), a
        ld a, (TunInside)       ; (in or out of a tunnel: every row, for the lamps)
        ld hl, ELastTun
        cp (hl)
        jr z, .tun
        ld (hl), a
        ld a, 1
        ld (EinForce), a
.tun:
        ld a, (PalRoad)         ; (the road's colours, for silhouettes)
        push af
        call AttrPaper
        ld (ERoadPaperT), a
        pop af
        call AttrInk
        ld (ERoadInkT), a
        call EinColourSets
        call EinPanoCompose     ; the panorama's rows (src/einstein/sprites.asm)
.lp:    ld a, (ERow)            ; the row's bands as last drawn
        add a, a
        add a, a
        add a, low ERowBands
        ld e, a
        ld a, high ERowBands
        adc a, 0
        ld d, a
        ld a, (ERow)            ; and now
        add a, a
        add a, a
        add a, a
        add a, low Band
        ld l, a
        ld h, high Band
        ld c, 0                 ; C: draw it
        ld b, 4
.bd:    ld a, (de)
        cp (hl)
        jr z, .bs
        ld a, (hl)
        ld (de), a
        ld c, 1
.bs:    inc de
        inc l
        inc l
        djnz .bd
        ld a, (EinShape)        ; pass 1 ran: has the row's shape changed?
        or a
        jr z, .drawn
        ld a, c
        or a
        jr nz, .inval
        push bc
        call EinRowSame
        pop bc
        jr z, .drawn
        ld c, 1
        jr .drawn
.inval: ld a, (ERow)            ; drawn for its bands anyway: its shape is
        add a, low ERowFk       ; checked in full next time (not stored now)
        ld l, a
        ld a, high ERowFk
        adc a, 0
        ld h, a
        ld (hl), 1
.drawn: ld a, c
        or a
        call nz, EinRow
        call EinRoadCompose     ; then its silhouettes and the car
        ld hl, ERow
        inc (hl)
        ld a, (hl)
        cp 24 - ROAD_ROW0
        jr nz, .lp
        xor a
        ld (EinShape), a
        ld (EinForce), a
        ret

; The row (ERow): has what its cells come from changed since it was drawn?
; Its 4 line pairs' D, E, centre line and depth line, its last line's D, E
; and depth line (ERowSig, 20 bytes a row). Z: the same; NZ: changed (and
; stored), or a fork row or the first after one (ERowFk), or EinForce.
SIG_SIZE        EQU 20
EinRowSame:
        ld a, (ERow)            ; a fork row: always (and the next time)
        ld e, a
        add a, low RowFork
        ld l, a
        ld h, high RowFork
        ld a, (hl)
        ld hl, ERowFk
        ld d, 0
        add hl, de
        ld c, (hl)              ; C: changed (drawn as a fork last time)
        ld (hl), a
        or a
        ret nz
        ld a, (EinForce)        ; (or forced)
        or c
        ld c, a
        call .sig               ; DE = its signature, L = its top line (C kept)
        ld a, c
        or a
        jr nz, .store
        push de
        push hl
        ld b, 4                 ; compared to the first difference
.p:     ld h, high DEPage
        ld a, (de)
        cp (hl)
        jr nz, .diff
        inc de
        set 7, l
        ld a, (de)
        cp (hl)
        jr nz, .diff
        inc de
        res 7, l
        ld h, high LaneX
        ld a, (de)
        cp (hl)
        jr nz, .diff
        inc de
        set 7, l
        ld h, high SrcLine
        ld a, (de)
        cp (hl)
        jr nz, .diff
        inc de
        res 7, l
        inc l
        inc l
        djnz .p
        dec l                   ; the last line
        ld h, high DEPage
        ld a, (de)
        cp (hl)
        jr nz, .diff
        inc de
        set 7, l
        ld a, (de)
        cp (hl)
        jr nz, .diff
        inc de
        ld h, high SrcLine
        ld a, (de)
        cp (hl)
        pop hl
        pop de
        ret z                   ; the same
        jr .store
.diff:  pop hl
        pop de
.store: ld b, 4                 ; changed: stored
.s:     ld h, high DEPage
        ld a, (hl)
        ld (de), a
        inc de
        set 7, l
        ld a, (hl)
        ld (de), a
        inc de
        res 7, l
        ld h, high LaneX
        ld a, (hl)
        ld (de), a
        inc de
        set 7, l
        ld h, high SrcLine
        ld a, (hl)
        ld (de), a
        inc de
        res 7, l
        inc l
        inc l
        djnz .s
        dec l
        ld h, high DEPage
        ld a, (hl)
        ld (de), a
        inc de
        set 7, l
        ld a, (hl)
        ld (de), a
        inc de
        ld h, high SrcLine
        ld a, (hl)
        ld (de), a
        or 1                    ; (NZ)
        ret
; -> DE = ERowSig + ERow * 20, L = the row's top line
.sig:   ld a, (ERow)
        add a, a
        add a, a
        ld l, a                 ; x 4
        add a, a
        add a, a                ; x 16
        add a, l                ; x 20
        add a, low ERowSig
        ld e, a
        ld a, high ERowSig
        adc a, 0
        ld d, a
        ld a, l
        add a, a                ; the top line: row * 8
        ld l, a
        ret

EinRow:
        ld a, (ERow)
        add a, a
        add a, a
        add a, a
        ld (EI), a              ; the row's top line
        call EinRowSlots
        xor a
        ld (ESlotN), a
        ld a, (ESlotMax)        ; the centre line's slots from the row's last down
        ld (ESlotTop), a
        jr EinRowBase

; The row's slots (ERow): the first (a SlotShadow index) and how many
EinRowSlots:
        ld a, (ERow)
        cp 4
        jr nc, .t2
        add a, a
        add a, a                ; x 4
        ld b, a
        add a, a                ; x 8
        add a, b                ; x 12 (SLOTS_T1)
        ASSERT SLOTS_T1 == 12
        ld (ESlot0), a
        add a, SLOT_FIRST       ; (the middle third's names)
        ld b, SLOTS_T1
        jr .ts
.t2:    sub 4
        add a, a
        add a, a
        add a, a                ; x 8
        ld b, a
        add a, a                ; x 16
        add a, b                ; x 24 (SLOTS_T2)
        ASSERT SLOTS_T2 == 24
        add a, 4 * SLOTS_T1
        ld (ESlot0), a
        add a, SLOT_FIRST - 4 * SLOTS_T1    ; (the bottom third's names)
        ld b, SLOTS_T2
.ts:    ld (ESlotName0), a
        ld a, b
        ld (ESlotMax), a
        ld a, (ESlot0)          ; SlotShadow + ESlot0 * 9
        ld l, a
        ld h, 0
        ld d, h
        ld e, l
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, de
        ld de, SlotShadow
        add hl, de
        ld (ESlotPtr), hl
        ret

EinRowBase:
        ; its names in BaseNames (rows from PANO_ROW0)
        ld a, (ERow)
        add a, ROAD_ROW0 - PANO_ROW0
        ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ld de, BaseNames
        add hl, de
        ld (ERowPtr), hl
        ld a, (ERow)            ; (its names to be sent)
        ld e, a
        ld d, 0
        ld hl, ERowDrawn + ROAD_ROW0
        add hl, de
        ld (hl), 1
        call EinRowRanges
        call EinRowColours
        ; ---- names: grass, kerb, road, kerb, grass
        ld hl, (ERowPtr)
        ld a, (ERA)
        ld b, a
        ld a, (ECG)
        call EinFillRun
        ld a, (ERA)
        ld c, a
        ld a, (ERB)
        sub c
        ld b, a
        ld a, (ECK)
        call EinFillRun
        ld a, (ERB)
        ld c, a
        ld a, (ERC)
        sub c
        ld b, a
        ld a, (ECR)
        call EinFillRun
        ld a, (ERC)
        ld c, a
        ld a, (ERD)
        sub c
        ld b, a
        ld a, (ECK)
        call EinFillRun
        ld a, (ERD)
        neg
        add a, 32
        ld b, a
        ld a, (ECG)
        call EinFillRun
        ; ---- a tunnel's light band, inside it: lamps on the walls beside
        ; the kerbs (as src/road.asm RowAttrs)
        ld a, (ERBand)
        cp $80
        jr nz, .noLamp
        ld a, (TunInside)
        or a
        jr z, .noLamp
        ld a, TUN_LAMP
        call AttrPaper
        ld e, a
        ld hl, (ERowPtr)
        ld a, (ERA)
        or a
        jr z, .lr
        dec a
        call .lamp
.lr:    ld a, (ERD)
        cp 32
        call c, .lamp
        jr .noLamp
.lamp:  push hl                 ; (A = the cell, E = the lamp's name)
        add a, l
        ld l, a
        jr nc, .lh
        inc h
.lh:    ld (hl), e
        pop hl
        ret
.noLamp:
        ; ---- both of the fork's branches on the row: its own way
        ld a, (ERow)
        add a, low RowFork
        ld l, a
        ld h, high RowFork
        ld a, (hl)
        or a
        jr z, .one
        call EinForkCells
        jr .slotsUsed
.one:   ; ---- the kerb cells, then the centre line
        call EinLineEdges
        ; kerb cells left of every line's road are plain kerb, as named: the
        ; masks only from the leftmost D cell, and up to the rightmost E cell
        ld a, (EDMin)
        ld hl, ERA
        cp (hl)
        jr nc, .l0
        ld a, (hl)
.l0:    ld (ECol), a
        ld a, (ERB)
        ld (EColEnd), a
        call EinKerbCells
        ld a, (ERC)
        ld (ECol), a
        ld a, (EEMax)
        inc a
        ld hl, ERD
        cp (hl)
        jr c, .r0
        ld a, (hl)
.r0:    ld (EColEnd), a
        call EinKerbCells
        call EinCentreLine
.slotsUsed:
        ld a, (ERow)            ; the row's slots in use: the road's, the
        ld e, a                 ; centre line's (silhouettes take those between)
        ld d, 0
        ld hl, ERowLo
        add hl, de
        ld a, (ESlotN)
        ld (hl), a
        ld hl, ERowHi
        add hl, de
        ld a, (ESlotTop)
        ld (hl), a
        ld a, (ERow)            ; the car's rows: its attributes again, and
        cp CAR_ROW - ROAD_ROW0  ; its names over the road's
        ret c
        ld a, 1
        ld (CarAttrDirty), a
        ld a, (ERow)
        add a, ROAD_ROW0
        ld b, a
        ld hl, (ERowPtr)
        call EinCarNames
        ld a, (ERow)
        cp CAR_ROW - ROAD_ROW0
        ret nz
; Row 20: the attributes under the car's open cockpit (columns 12-19, as
; src/fork.asm SaveCockpit keeps them for DrawCar)
EinCockpit:
        ld de, (high StateB1 + 2) * 256 + COCKPIT
        ld c, CAR_COL
.c:     ld a, c
        ld hl, ERA
        cp (hl)
        ld a, (EAG)
        jr c, .put              ; grass
        ld a, c
        ld hl, ERB
        cp (hl)
        ld a, (EAK)
        jr c, .put              ; kerb
        ld a, c
        ld hl, ERC
        cp (hl)
        ld a, (PalRoad)
        jr c, .put              ; road
        ld a, c
        ld hl, ERD
        cp (hl)
        ld a, (EAK)
        jr c, .put              ; kerb
        ld a, (EAG)             ; grass
.put:   ld (de), a
        inc e
        inc c
        ld a, c
        cp CAR_COL + CAR_W
        jr nz, .c
        ret

; A = value, B = count (0-32), HL = destination in a row of BaseNames
; (32-aligned: L advances, H stays): the unrolled fill (src/screen.asm)
EinFillRun      EQU FillA

; ---------------------------------------------------------------------------
; The row's cell ranges ERA-ERD and band, as src/road.asm DrawRoadRow: from
; the edges of its top line and its bottom line, the kerb as wide as the
; depth lines shown.
EinRowRanges:
        ld a, (EI)
        ld l, a
.pg1:   ld h, high DEPage       ; (patched: DE2Page for a fork's right branch)
        ld b, (hl)              ; D0
        set 7, l
        ld c, (hl)              ; E0
        ld h, high SrcLine      ; kerb widths of the depth lines shown
        ld e, (hl)
        ld a, l
        add a, 7
        ld l, a
        ld d, (hl)
        push hl
        ld h, high RoadRW
        ld a, e
        or $80
        ld l, a
        ld a, (hl)
        ld (ERW0), a
        ld a, d
        or $80
        ld l, a
        ld a, (hl)
        ld (ERW1), a
        pop hl
.pg2:   ld h, high DEPage
        ld e, (hl)              ; E1
        res 7, l
        ld d, (hl)              ; D1
        ; a line without road (D > E) borrows the other line's edges
        ld a, c
        cp b
        jr nc, .t0
        ld b, d
        ld c, e
        ld a, (ERW1)
        ld (ERW0), a
.t0:    ld a, e
        cp d
        jr nc, .t1
        ld d, b
        ld e, c
        ld a, (ERW0)
        ld (ERW1), a
.t1:    ld a, c
        cp b
        jr nc, .haveRoad
        xor a                   ; no road on this row: all grass
        ld (ERA), a
        ld (ERB), a
        ld (ERC), a
        ld (ERD), a
        jr .band
.haveRoad:
        ; a = min(D - RW) >> 3 (clamped at 0)
        ld a, (ERW0)
        ld h, a
        ld a, b
        sub h
        jr nc, .a0
        xor a
.a0:    ld l, a
        ld a, (ERW1)
        ld h, a
        ld a, d
        sub h
        jr nc, .a1
        xor a
.a1:    cp l
        jr c, .a2
        ld a, l
.a2:    rrca
        rrca
        rrca
        and 31
        ld (ERA), a
        ; b = max(D) >> 3 + 1
        ld a, b
        cp d
        jr nc, .b0
        ld a, d
.b0:    rrca
        rrca
        rrca
        and 31
        ld l, a
        inc a
        ld (ERB), a
        ; c = min(E) >> 3, at least b
        ld a, c
        cp e
        jr c, .c0
        ld a, e
.c0:    rrca
        rrca
        rrca
        and 31
        ld l, a
        ld a, (ERB)
        cp l
        jr nc, .c2
        ld a, l
.c2:    ld (ERC), a
        ; d = max(E + RW) >> 3 + 1 (clamped at 255)
        ld a, (ERW0)
        add a, c
        jr nc, .d0
        ld a, 255
.d0:    ld l, a
        ld a, (ERW1)
        add a, e
        jr nc, .d1
        ld a, 255
.d1:    cp l
        jr nc, .d2
        ld a, l
.d2:    rrca
        rrca
        rrca
        and 31
        inc a
        ld l, a
        ld a, (ERC)
        cp l
        jr nc, .d3
        ld a, l
.d3:    ld (ERD), a
.band:  ; the band of the row's middle line
        ld a, (EI)
        add a, low Band + 4
        ld l, a
        ld h, high Band
        ld a, (hl)
        ld (ERBand), a
        ret

; The row's colours from its band (as src/road.asm RowAttrs): ECG grass,
; ECK kerb, ECR road (TMS colours), EKC a kerb cell's colour byte (the road
; over the kerb), ELC a centre-line cell's (white over the road)
EinRowColours:
        ld a, (ERBand)          ; its set: tunnel (bit 7), dark (bit 6)
        rlca
        rlca
        and 3
        ld l, a
        add a, a
        add a, a
        add a, a
        sub l                   ; x 7
        add a, low ERowSets
        ld l, a
        ld a, high ERowSets
        adc a, 0
        ld h, a
        ld de, EAG
        ld bc, 7
        ldir
        ret

; A frame's 4 colour sets (ERowSets: open / tunnel, light / dark bands)
EinColourSets:
        ld de, ERowSets
        xor a
.set:   push af
        push de
        ld (ERBand), a
        call EinRowColour
        pop de
        ld hl, EAG
        ld bc, 7
        ldir
        pop af
        add a, $40
        jr nc, .set
        ret

; ERBand -> the row's colours (EAG ... ELC)
EinRowColour:
        ld a, (ERBand)
        ld bc, (PalGrassL)      ; C = light grass, B = dark grass
        ld de, (PalKerbL)       ; E = light kerb, D = dark kerb
        add a, a                ; carry: in a tunnel; zero: a light band
        jr nc, .open
        ld bc, (TunWall)        ; (src/tunnel.asm)
        ld de, (TunKerbs)
.open:  jr z, .gl
        ld c, b
        ld e, d
.gl:    ld a, c
        ld (EAG), a             ; (the attributes, for the cockpit)
        ld a, e
        ld (EAK), a
        push af
        ld a, c
        call AttrPaper
        ld (ECG), a
        pop af
        call AttrPaper
        ld (ECK), a
        ld a, (PalRoad)
        call AttrPaper
        ld (ECR), a
        rlca
        rlca
        rlca
        rlca
        ld hl, ECK
        or (hl)
        ld (EKC), a
        ld a, (PalRoad)
        call AttrInk
        rlca
        rlca
        rlca
        rlca
        ld hl, ECR
        or (hl)
        ld (ELC), a
        ret

; ---------------------------------------------------------------------------
; The kerb cells ECol .. EColEnd - 1: the road's pixels in each, per line.
; A cell with none stays solid kerb, one that is all road becomes solid road.
EinKerbCells:
.col:   ld a, (ECol)
        ld hl, EColEnd
        cp (hl)
        ret nc
        call EinCellMasks
        call EinKerbName
        ld hl, ECol
        inc (hl)
        jr .col

; EPat = the road's pixels in kerb cell ECol: no road, it stays kerb (as
; named); all road, solid road; else a slot
EinKerbName:
        ld hl, EPat             ; all clear, all set, or mixed? (its line
        ld a, (hl)              ; pairs: lines 0, 2, 4, 6)
        ld c, a
        ld d, a
        DUP 3
        inc l
        inc l
        ld a, (hl)
        or c
        ld c, a
        ld a, (hl)
        and d
        ld d, a
        EDUP
        ld a, c
        or a
        ret z                   ; no road in it: kerb, as named
        ld a, (ECR)
        inc d
        jr z, .name             ; all road
        ld a, (EKC)
        call EinCommitSlot
        cp $FF
        ret z                   ; (the row's slots are all used)
.name:  ld e, a
        ld a, (ECol)
        ld hl, (ERowPtr)
        add a, l
        ld l, a
        jr nc, .nm
        inc h
.nm:    ld (hl), e
        ret

; The row's line pairs, as the Spectrum draws them (both lines of a pair
; alike, from the even one): per pair its first road pixel's cell and that
; byte's mask, its last's cell and mask (ELines, 4 bytes a pair; no road:
; the first cell $FF, so every cell is left of it). Also the leftmost D
; cell (EDMin) and the rightmost E cell (EEMax).
EinLineEdges:
        ld a, $FF
        ld (EDMin), a
        xor a
        ld (EEMax), a
        ld a, (EI)
        ld l, a
.pg:    ld h, high DEPage       ; (patched for a fork's right branch: DE2Page,
.out:   ld de, ELines           ; ELines2)
        ld b, 4
.ln:    ld a, (hl)              ; D
        set 7, l
        ld c, (hl)              ; E
        res 7, l
        inc l
        inc l
        push hl
        cp c
        jr z, .road
        jr c, .road
        ld a, $FF               ; no road on the pair
        ld (de), a
        inc de
        inc de
        inc de
        inc de
        jr .next
.road:  ld l, a
        rrca
        rrca
        rrca
        and 31
        ld (de), a              ; D's cell
        inc de
        ld h, a
        ld a, (EDMin)
        cp h
        jr c, .dmin
        ld a, h
        ld (EDMin), a
.dmin:
        ld a, l
        and 7
        add a, low RMask
        ld l, a
        ld h, high RMask
        ld a, (hl)
        ld (de), a              ; its mask: D and right of it
        inc de
        ld a, c
        rrca
        rrca
        rrca
        and 31
        ld (de), a              ; E's cell
        inc de
        ld h, a
        ld a, (EEMax)
        cp h
        jr nc, .emax
        ld a, h
        ld (EEMax), a
.emax:
        ld a, c
        and 7
        add a, low LMaskIncl
        ld l, a
        ld h, high LMaskIncl
        ld a, (hl)
        ld (de), a              ; its mask: E and left of it
        inc de
.next:  pop hl
        dec b
        jp nz, .ln
        ret

; EPat = the road's pixels in cell ECol, on the row's 8 lines (in pairs)
EinCellMasks:
        ld a, (ECol)
        ld c, a
.tab:   ld hl, ELines           ; (patched: ELines2)
        ld de, EPat
        ld b, 4
.ln:    ld a, c
        cp (hl)                 ; D's cell
        jr c, .zero4            ; left of the road (or none on the pair)
        jr z, .atD
        inc l
        inc l
        cp (hl)                 ; E's cell
        jr c, .full             ; between: all road
        jr z, .atE
        xor a                   ; right of the road
        jr .put2
.full:  ld a, $FF
.put2:  inc l
        inc l
.put:   ld (de), a
        inc e
        ld (de), a
        inc e
        djnz .ln
        ret
.atE:   inc l
        ld a, (hl)              ; E's mask
        inc l
        jr .put
.zero4: xor a
        inc l
        inc l
        jr .put2
.atD:   inc l
        ld a, (hl)              ; D's mask
        inc l
        ex af, af'
        ld a, c
        cp (hl)                 ; E's cell too?
        jr nz, .dOnly
        ex af, af'
        inc l
        and (hl)                ; and its mask
        inc l
        jr .put
.dOnly: ex af, af'
        jr .put2

; ---------------------------------------------------------------------------
; A row with both of the fork's branches on it (RowFork; their spans in
; DEPage and DE2Page, as src/fork.asm DrawForkRow takes them). The left
; branch's cells are named already; the right's go over them (its kerbs
; not over road), then every kerb cell gets both branches' road pixels.
; No centre line on such a row (as on the Spectrum).
EinForkCells:
        ld hl, ERA              ; the left branch's ranges
        ld de, EFA
        ld bc, 4
        ldir
        ld a, (ERBand)
        push af
        ld a, high DE2Page      ; the right branch's
        ld (EinRowRanges.pg1 + 1), a
        ld (EinRowRanges.pg2 + 1), a
        call EinRowRanges
        ld a, high DEPage
        ld (EinRowRanges.pg1 + 1), a
        ld (EinRowRanges.pg2 + 1), a
        pop af
        ld (ERBand), a
        ; ---- its names: kerb (not over road), road, kerb (not over road)
        ld a, (ERA)
        ld c, a
        ld a, (ERB)
        call .kerbs
        ld a, (ERB)
        ld c, a
        ld a, (ERC)
        sub c
        jr z, .k2
        ld b, a
        call .ptr
        ld a, (ECR)
        call EinFillRun
.k2:    ld a, (ERC)
        ld c, a
        ld a, (ERD)
        call .kerbs
        ; ---- both branches' line pairs
        call EinLineEdges
        ld a, high DE2Page
        ld (EinLineEdges.pg + 1), a
        ld hl, ELines2
        ld (EinLineEdges.out + 1), hl
        call EinLineEdges
        ld a, high DEPage
        ld (EinLineEdges.pg + 1), a
        ld hl, ELines
        ld (EinLineEdges.out + 1), hl
        ; ---- every kerb cell, from the leftmost range to the rightmost
        ld a, (EFA)
        ld hl, ERA
        cp (hl)
        jr c, .lo
        ld a, (hl)
.lo:    ld (ECol), a
        ld a, (EFA + 3)
        ld hl, ERD
        cp (hl)
        jr nc, .hi
        ld a, (hl)
.hi:    ld (EColEnd), a
.cell:  ld a, (ECol)
        ld hl, EColEnd
        cp (hl)
        jr nc, .done
        ld hl, (ERowPtr)        ; only cells named kerb
        add a, l
        ld l, a
        jr nc, .h
        inc h
.h:     ld a, (ECK)
        cp (hl)
        jr nz, .next
        call EinCellMasks       ; the left branch's pixels
        ld hl, EPat
        ld de, EPat2
        ld bc, 8
        ldir
        ld hl, ELines2          ; and the right's
        ld (EinCellMasks.tab + 1), hl
        call EinCellMasks
        ld hl, ELines
        ld (EinCellMasks.tab + 1), hl
        ld hl, EPat
        ld de, EPat2
        ld b, 8
.or:    ld a, (de)
        or (hl)
        ld (hl), a
        inc hl
        inc de
        djnz .or
        call EinKerbName
.next:  ld hl, ECol
        inc (hl)
        jr .cell
.done:  ld hl, EFA              ; (the left branch's ranges again: the cockpit)
        ld de, ERA
        ld bc, 4
        ldir
        ret
; C = first cell, A = end: kerb, but not over road
.kerbs: sub c
        ret z
        ret c
        ld b, a
        call .ptr
.kc:    ld a, (ECR)
        cp (hl)
        jr z, .kn
        ld a, (ECK)
        ld (hl), a
.kn:    inc hl
        djnz .kc
        ret
; C = a cell -> HL = its name
.ptr:   ld hl, (ERowPtr)
        ld a, l
        add a, c
        ld l, a
        ret nc
        inc h
        ret

; ---------------------------------------------------------------------------
; The centre line (light bands only, in road cells [b, c-1) as on the
; Spectrum), per line pair: its cell and the two bytes (ECL, ECM1, ECM2),
; the leftmost and rightmost of those cells; then each cell from the
; leftmost to one past the rightmost built once and given a slot if the
; line is in it.
EinCentreLine:
        ld a, $FF
        ld (ECLo), a
        xor a
        ld (ECHi), a
        ld a, (EI)
        ld c, a                 ; C = the pair's line
        ld ix, ECL
        ld b, 4
.cl:    ld (ix + 0), $FF
        ld a, c
        add a, low Band
        ld l, a
        ld h, high Band
        bit 6, (hl)             ; (STRIPE_BIT: a dark band)
        jr nz, .none
        ld l, c
        ld h, high LaneX
        ld a, (hl)
        cp $FF
        jr z, .none
        ld e, a                 ; E = x
        rrca
        rrca
        rrca
        and 31
        ld d, a                 ; D = its cell
        ld hl, ERB
        cp (hl)
        jr c, .none
        ld a, (ERC)
        dec a
        cp d
        jr c, .none
        jr z, .none
        ld (ix + 0), d
        ld a, (ECLo)
        cp d
        jr c, .lo
        ld a, d
        ld (ECLo), a
.lo:    ld a, (ECHi)
        cp d
        jr nc, .hi
        ld a, d
        ld (ECHi), a
.hi:    ld l, c                 ; width: LaneW of the depth line shown
        set 7, l
        ld h, high SrcLine
        ld a, (hl)
        or $80
        ld l, a
        ld h, high LaneW
        ld a, (hl)
        add a, a
        add a, a
        add a, a
        ld d, a
        ld a, e
        and 7
        add a, d
        add a, low LaneM1
        ld l, a
        ld h, high LaneM1
        ld a, (hl)
        ld (ix + 4), a
        ld a, l
        add a, low LaneM2 - low LaneM1
        ld l, a
        ld a, (hl)
        ld (ix + 8), a
.none:  inc ix
        inc c
        inc c
        djnz .cl
        ld a, (ECLo)            ; the cells, leftmost to rightmost + 1
        cp $FF
        ret z
.cell:  ld (ECol), a
        call EinCentreCell
        ld a, (ECHi)
        inc a
        ld hl, ECol
        cp (hl)
        ret z
        ld a, (hl)
        inc a
        jr .cell

; ECol: the centre line's pixels in it, per pair (the first byte if the
; pair's cell is this one, the second if it is the one before); a slot if
; there are any
EinCentreCell:
        ld a, (ECol)
        ld c, a
        ld hl, ECL
        ld de, EPat
        ld b, 4
        ld ixl, 0               ; (any pixels)
.ln:    ld a, (hl)
        cp c
        jr z, .m1
        inc a
        cp c
        jr z, .m2
        xor a
        jr .put
.m1:    push hl
        inc hl
        inc hl
        inc hl
        inc hl
        ld a, (hl)
        pop hl
        jr .put
.m2:    push hl
        ld a, l
        add a, 8
        ld l, a
        jr nc, .m2h
        inc h
.m2h:   ld a, (hl)
        pop hl
.put:   ld (de), a
        inc de
        ld (de), a
        inc de
        inc hl
        push af
        or ixl
        ld ixl, a
        pop af
        djnz .ln
        ld a, ixl
        or a
        ret z                   ; none of it in this cell: plain road
        ld a, (ELC)
        call EinCommitTop
        cp $FF
        ret z
        ld e, a
        ld a, (ECol)
        ld hl, (ERowPtr)
        add a, l
        ld l, a
        jr nc, .nm
        inc h
.nm:    ld (hl), e
        ret

; ---------------------------------------------------------------------------
; EPat (8 pattern bytes) and A (the colour byte) into the row's next slot:
; noted in DirtyList if VRAM does not already hold them.
; -> A = the slot's name ($FF: the row's slots are all used)
EinCommitSlot:
        ld c, a
        ld a, (ESlotN)          ; the next kerb slot, below the centre line's
        ld hl, ESlotTop
        cp (hl)
        jr c, .ok
        ld a, $FF
        ret
.ok:    ld b, a
        inc a
        ld (ESlotN), a
        jr EinCommitAt
; the same, the next of the centre line's slots (from the row's last down)
EinCommitTop:
        ld c, a
        ld a, (ESlotN)
        ld hl, ESlotTop
        cp (hl)
        jr c, .ok
        ld a, $FF
        ret
.ok:    dec (hl)
        ld b, (hl)
; B = the slot in the row, C = the colour -> A = its name
EinCommitAt:
        ld a, b                 ; HL = its SlotShadow bytes
        add a, a
        add a, a
        add a, a
        add a, b                ; x 9 (SLOT_SIZE; a row's 24 slots: < 256)
        ASSERT SLOT_SIZE == 9
        ld hl, (ESlotPtr)
        add a, l
        ld l, a
        jr nc, .h
        inc h
.h:     push hl
        ld de, EPat             ; the same pixels? (unrolled)
        DUP 7
        ld a, (de)
        cp (hl)
        jr nz, .newPat
        inc hl
        inc e
        EDUP
        ld a, (de)
        cp (hl)
        jr nz, .newPat
        inc hl
        ld a, (hl)              ; the same pixels: the same colour?
        cp c
        jr z, .same
        ld (hl), c
        ld e, 2                 ; the colour only
        jr .dirty
.newPat:
        pop de
        push de
        ld hl, EPat
        push bc                 ; (LDI spends BC)
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        pop bc
        ex de, hl
        ld a, (hl)
        ld (hl), c
        cp c
        ld e, 1                 ; the pixels
        jr z, .dirty
        ld e, 3                 ; and the colour
.dirty: ld a, (ERow)            ; the row, for RequestFlip's order
        add a, a
        add a, a
        or e
        ld e, a
        ld a, (ESlot0)          ; (slot, what) onto DirtyList (each slot at
        add a, b                ; most once a frame: it never fills)
        ld hl, (EDirtyEnd)
        ld (hl), a
        inc hl
        ld (hl), e
        inc hl
        ld (EDirtyEnd), hl
        ld hl, DirtyN
        inc (hl)
.same:  pop hl
        ld a, (ESlotName0)      ; its name
        add a, b
        ret

; ---------------------------------------------------------------------------
ERow:           db 0            ; road row 0-11 (screen row 12-23)
EI:             db 0            ; its top line
ERowPtr:        dw 0            ; its names in NameBuf
ESlot0:         db 0            ; its first slot, how many it has, how many used
ESlotMax:       db 0
ESlotN:         db 0
ESlotTop:       db 0            ; the centre line's lowest slot so far
ESlotPtr:       dw 0            ; its first slot's bytes in SlotShadow
ESlotName0:     db 0            ; its first slot's name
EDirtyEnd:      dw 0            ; DirtyList's end
ERW0:           db 0            ; kerb widths of its top and bottom lines
ERW1:           db 0
ERA:            db 0            ; cell ranges
ERB:            db 0
ERC:            db 0
ERD:            db 0
ERBand:         db 0
ERowSets:       ds 4 * 7        ; EAG ... ELC for each band (EinColourSets)
EAG:            db 0            ; attributes: grass, kerb
EAK:            db 0
ECG:            db 0            ; colours (TMS): grass, kerb, road
ECK:            db 0
ECR:            db 0
EKC:            db 0            ; colour bytes: a kerb cell, a centre-line cell
ELC:            db 0
ECol:           db 0
EColEnd:        db 0
EX0:            db 0
ELine:          db 0
        ASSERT high EPat == high (EPat + 7)   ; (EinKerbName steps L)
EPat:           ds 8
        ASSERT high EPat == high (EPat + 7)
EFA:            ds 4            ; a fork row: the left branch's cell ranges
EPat2:          ds 8
ELines2:        ds 4 * 4        ; the right branch's line pairs
        ASSERT high ELines2 == high (ELines2 + 15)
EDMin:          db 0
EEMax:          db 0
ELines:         ds 4 * 4        ; per pair: D's cell and mask, E's cell and mask
        ASSERT high ELines == high (ELines + 15)
ECL:            ds 4            ; centre line per pair: cell ($FF: none),
ECM1:           ds 4            ; its first byte,
ECM2:           ds 4            ; its second
ECLo:           db 0            ; the centre line's leftmost and rightmost cells
ECHi:           db 0
DirtyN:         db 0
EinShape:       db 1            ; pass 1 ran: rows whose shape changed again
EinForce:       db 1            ; every row again
ELastTun:       db 0

ERowBands:      ds 4 * 12       ; per row, the bands it was drawn with
ERowDrawn:      ds 24           ; per screen row: its names to be sent
