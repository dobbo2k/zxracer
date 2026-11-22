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
; A row is drawn again only if its bands moved (those of its lines 0 and 4,
; the only ones it uses: its colours are its middle line's, its dashes
; lines 0 and 4's) or, pass 1 having run (EinShape), its shape did: what
; its cells come from (EinRowSame). EinForce: every row (a display reset,
; in or out of a tunnel).
EinDraw:
        ld hl, DirtyList
        ld (EDirtyEnd), hl
        ld hl, EDirtyRowN       ; (no slot changed yet)
        ld b, 12
        xor a
.dz:    ld (hl), a
        inc hl
        djnz .dz
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
        ld b, 2
.bd:    ld a, (de)
        cp (hl)
        jr z, .bs
        ld a, (hl)
        ld (de), a
        ld c, 1
.bs:    inc de
        inc l
        inc l
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
        ld a, (ERow)            ; then its silhouettes and the portal, if any
        add a, ROAD_ROW0        ; cover it now or did last frame (EMaskU)
        add a, a
        add a, a
        add a, low EMaskU
        ld l, a
        ld a, high EMaskU
        adc a, 0
        ld h, a
        call EinMaskAny
        call nz, EinRoadCompose
        ld hl, ERow
        inc (hl)
        ld a, (hl)
        cp 24 - ROAD_ROW0
        jr nz, .lp
        xor a
        ld (EinShape), a
        ld (EinForce), a
        jp EinDashFinish        ; the centre line's sprites

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
        call EinRowFast         ; the ready-made way, if it can be
        jp c, EinRowBase        ; (or the exact way)
        jp nz, EinRowBase.slotsUsed     ; (a sloped row: EinSlopeRow drew it)
        ld a, 1
        ld (EStatic), a
        call EinDashRow
        jp EinRowBase.allSil

; The row's slots all free (ESlotN 0, ESlotTop its count), the road's taken
; first, then its silhouettes': a light band's from the bottom up, a dark
; band's from the top down (EDown). So a slot keeps its colours (the kerb's,
; light or dark) while bands pass, and only its pixels change.
EinSlotRange:
        xor a
        ld (ESlotN), a
        ld a, (ERow)
        cp 4
        ld a, SLOTS_T1
        jr c, .t1
        ld a, SLOTS_T2
.t1:    ld (ESlotTop), a
        ld a, (ERBand)
        and $40
        rlca
        rlca
        ld (EDown), a
        ret

; The row's slots (ERow): their bytes in SlotShadow and the first's name
; (ERowSlotTab)
EinRowSlots:
        ld a, (ERow)
        ld l, a
        add a, a
        add a, l                ; x 3
        add a, low ERowSlotTab
        ld l, a
        ld a, high ERowSlotTab
        adc a, 0
        ld h, a
        ld de, ESlotPtr
        ldi
        ldi
        ldi
        ret
ERowSlotTab:                    ; per row: ESlotPtr, ESlotName0
k       DEFL 0
        DUP 4                   ; rows 12-15: the middle third's
        dw SlotShadow + k * SLOTS_T1 * SLOT_SIZE
        db SLOT_FIRST + k * SLOTS_T1
k       DEFL k + 1
        EDUP
k       DEFL 0
        DUP 8                   ; rows 16-23: the bottom third's
        dw SlotShadow + (4 * SLOTS_T1 + k * SLOTS_T2) * SLOT_SIZE
        db SLOT_FIRST + k * SLOTS_T2
k       DEFL k + 1
        EDUP

; The row's names in BaseNames (ERowPtr; to be sent) from its ranges, in its
; band's colours (EinRowColours): grass, kerb, road, kerb, grass
EinRowNames:
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
        call EinRowColours
        ld hl, (ERowPtr)
        ld a, (ERA)
        ld b, a
        ld a, (ECG)
        call EinGroundName
        ld (.g2 + 1), a         ; (the same on the right)
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
.g2:    ld a, 0
        jp EinFillRun

EinRowBase:
        ld a, (ESloped)         ; (a sloped row: its ranges made, the exact way)
        or a
        jr z, .ranges
        xor a
        ld (ESloped), a
        ld (EStatic), a
        jr .ranged
.ranges:
        call EinRowRanges
        call EinStaticRanges    ; (rows 16-23: ready-made edges, ERB / ERC moved)
.ranged:
        call EinRowNames
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
        ld a, (EStatic)         ; ---- the ready-made patterns
        or a
        jr z, .exact
        call EinStaticCells
        call EinDashRow
.allSil:
        call EinSlotRange       ; (no slot of the road's: all the row's for
        jr .slotsUsed           ; silhouettes)
.exact: call EinRowSlots        ; ---- the exact way: the row's slots
        call EinSlotRange
        ; ---- both of the fork's branches on the row: its own way
        ld a, (ERow)
        add a, low RowFork
        ld l, a
        ld h, high RowFork
        ld a, (hl)
        or a
        jr z, .one
        call EinForkCells
        call EinDashNone        ; (no centre line on a fork's row)
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
        call EinDashRow
.slotsUsed:
        ld a, (ESlotN)          ; the row's slots in use: the road's (silhouettes
        ld (ERowLoNow), a       ; take the rest, on from them; bit 7 of
        ld a, (EDown)           ; ERowHi: from the top down)
        rrca
        ld hl, ESlotTop
        or (hl)
        ld (ERowHiNow), a
.slotsSet:
        ld a, (ERow)
        ld e, a
        ld d, 0
        ld hl, ERowLo
        add hl, de
        ld a, (ERowLoNow)
        ld (hl), a
        ld hl, ERowHi
        add hl, de
        ld a, (ERowHiNow)
        ld (hl), a
        ld a, (ERow)            ; the car's rows: its attributes again, and
        cp CAR_ROW - ROAD_ROW0  ; its names over the road's
        ret c
        ld a, (ERow)
        add a, ROAD_ROW0
        ld b, a
        ld hl, (ERowPtr)
        jp EinCarNames

; ---------------------------------------------------------------------------
; A row (not a fork's, nor a tunnel's, nor one whose road is in one cell):
; the kerb's edges from ready-made patterns (EinStaticInit). Each edge is
; upright in the row, at the mean of its top and bottom lines' (the exact
; way: a slope of 2-line steps). A kerb edge's cell is one name: nothing is
; sent but the names.
; After EinRowRanges: EStatic, and if set, ERB / ERC for the edges' cells.
; In rows 16-23 an edge whose top and bottom lines are more than EIN_SLOPE
; pixels apart is drawn the exact way instead (EinRowFast too).
        IFNDEF EIN_SLOPE        ; (-D: other thresholds, for measuring)
EIN_SLOPE       EQU 4
        ENDIF
        ASSERT 2 * EIN_SLOPE + 1 < 256
EinStaticRanges:
        xor a
        ld (EStatic), a
        ld a, (ERBand)
        rla
        ret c                   ; (a tunnel's row: its walls' colours, the exact way)
        ld a, (ERow)
        add a, low RowFork
        ld l, a
        ld h, high RowFork
        ld a, (hl)
        or a
        ret nz                  ; (a fork's row: its own way)
        ld a, (ERD)
        or a
        jr z, .take             ; no road: all grass
        ld bc, (ERDE0)          ; B = D0, C = E0
        ld de, (ERDE1)          ; D = D1, E = E1
        ld a, (ERow)
        cp 4
        jr c, .mean
        ld a, b
        sub d
        add a, EIN_SLOPE
        cp 2 * EIN_SLOPE + 1
        ret nc
        ld a, c
        sub e
        add a, EIN_SLOPE
        cp 2 * EIN_SLOPE + 1
        ret nc
.mean:  ld a, b
        add a, d
        rra                     ; (the carry: the sum's bit 8)
        ld (EDm), a
        rrca
        rrca
        rrca
        and 31
        ld b, a                 ; B = the left edge's cell
        ld a, c
        add a, e
        rra
        ld (EEm), a
        rrca
        rrca
        rrca
        and 31                  ; the right edge's
        cp b
        ret z                   ; (both in one cell: the exact way)
        ret c
        ld (ERC), a             ; kerb from the right edge's cell
        ld a, b
        inc a
        ld (ERB), a             ; kerb to the left edge's cell
.take:  ld a, 1
        ld (EStatic), a
        ret

; The names of the edges' cells (after the row's fill: [ERA, ERB) and
; [ERC, ERD) kerb)
EinStaticCells:
        ld a, (ERD)
        or a
        ret z                   ; (no road)
        ld c, KERB_T2           ; C: the set's first (7 left edges, 7 right):
        ld a, (ERow)            ; the row's third's,
        cp 4
        jr nc, .t2
        ld c, KERB_T1
.t2:    ld a, (ERBand)          ; light or dark
        and $40
        jr z, .lt
        ld a, c
        add a, 14
        ld c, a
.lt:
        ld hl, (ERowPtr)        ; (32-aligned: a column is L's low bits)
        ld a, (EDm)             ; the left edge: road from pixel D & 7 on
        ld b, a
        rrca
        rrca
        rrca
        and 31
        or l
        ld l, a
        ld a, b
        and 7
        ld a, (ECR)             ; (from pixel 0: all road)
        jr z, .l
        ld a, b
        and 7
        dec a
        add a, c
.l:     ld (hl), a
        ld a, (EEm)             ; the right edge: road to pixel E & 7
        ld b, a
        rrca
        rrca
        rrca
        and 31
        ld e, a
        ld a, l
        and $E0
        or e
        ld l, a
        ld a, b
        and 7
        cp 7
        ld a, (ECR)             ; (to pixel 7: all road)
        jr z, .r
        ld a, b
        and 7
        add a, 7
        add a, c
.r:     ld (hl), a
        ret

EStatByte:      ds KERB_N       ; per ready-made pattern: its byte,
EStatCol:       ds KERB_N       ; its colour byte

; ---------------------------------------------------------------------------
; A road row (ERow; EI its top line) the ready-made way, if it can be (not a
; tunnel's row, nor a fork's, nor one whose road fits in one cell): its
; ranges, colours, names and kerb edges in one pass, as EinRowRanges,
; EinStaticRanges, EinRowColours, EinRowBase and EinStaticCells do them.
; Carry: it can't (EinRowBase: the exact way).
EinRowFast:
        ld a, (EI)
        ld c, a                 ; C: the top line
        add a, low Band + 4     ; the band of its middle line
        ld l, a
        ld h, high Band
        ld a, (hl)
        ld (ERBand), a
        add a, a
        ret c                   ; (a tunnel's row)
        ld a, (ERow)
        add a, low RowFork
        ld l, a
        ld h, high RowFork
        ld a, (hl)
        or a
        scf
        ret nz                  ; (a fork's)
        ld l, c                 ; ---- the top and bottom lines' edges
        ld h, high DEPage
        ld b, (hl)              ; B: D0
        set 7, l
        ld e, (hl)              ; E: E0
        ld h, high SrcLine      ; (their kerb widths: of the depth lines shown)
        ld a, (hl)
        or $80
        ld (.rw0 + 1), a
        ld a, l
        add a, 7
        ld l, a
        ld a, (hl)
        or $80
        ld (.rw1 + 1), a
        ld h, high DEPage
        ld d, (hl)              ; D: E1
        res 7, l
        ld c, (hl)              ; C: D1
        ld h, high RoadRW
.rw0:   ld l, 0
        ld a, (hl)
        ld (ERW0), a
.rw1:   ld l, 0
        ld a, (hl)
        ld (ERW1), a
        ld a, e                 ; a line without road borrows the other's
        cp b
        jr nc, .t0
        ld b, c
        ld e, d
        ld a, (ERW1)
        ld (ERW0), a
.t0:    ld a, d
        cp c
        jr nc, .t1
        ld c, b
        ld d, e
        ld a, (ERW0)
        ld (ERW1), a
.t1:    ld a, e
        cp b
        jp c, .grass            ; (no road on the row)
        ld a, (ERW0)            ; ---- [a, d): a = min(D - RW) >> 3 (at least 0)
        ld l, a
        ld a, b
        sub l
        jr nc, .a0
        xor a
.a0:    ld l, a
        ld a, (ERW1)
        ld h, a
        ld a, c
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
        ld a, (ERW0)            ; d = max(E + RW) >> 3 + 1 (at most 255)
        add a, e
        jr nc, .d0
        ld a, 255
.d0:    ld l, a
        ld a, (ERW1)
        add a, d
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
        ld (ERD), a
        ld a, (ERow)            ; ---- rows 16-23: an edge sloping more than 4
        cp 4                    ; pixels is drawn the exact way (its slope in
        jr c, .mean             ; 2-line steps)
        ld a, b
        sub c
        add a, EIN_SLOPE
        cp 2 * EIN_SLOPE + 1
        jr nc, .sloped
        ld a, e
        sub d
        add a, EIN_SLOPE
        cp 2 * EIN_SLOPE + 1
        jr c, .mean
.sloped:                        ; (its ranges as EinRowRanges makes them: b =
        ld a, b                 ; max(D) >> 3 + 1, c = max(b, min(E) >> 3), d
        cp c                    ; at least c; a as here)
        jr nc, .s0
        ld a, c
.s0:    rrca
        rrca
        rrca
        and 31
        inc a
        ld (ERB), a
        ld l, a
        ld a, e
        cp d
        jr c, .s1
        ld a, d
.s1:    rrca
        rrca
        rrca
        and 31
        cp l
        jr nc, .s2
        ld a, l
.s2:    ld (ERC), a
        ld hl, ERD
        cp (hl)
        jr c, .s3
        ld (hl), a
.s3:    jp EinSlopeRow          ; (src/einstein/slope.asm)
.mean:  ld a, b                 ; ---- the edges: the lines' mean
        add a, c
        rra
        ld (EDm), a
        rrca
        rrca
        rrca
        and 31
        ld h, a                 ; H: the left edge's cell
        ld a, e
        add a, d
        rra
        ld (EEm), a
        rrca
        rrca
        rrca
        and 31
        ld l, a                 ; L: the right edge's
        sub h
        ret c                   ; (both in one cell: the exact way; carry,
        scf                     ; or Z then carry set)
        ret z
        ld a, h
        inc a
        ld (ERB), a             ; kerb to the left edge's cell
        ld a, l
        ld (ERC), a             ; and from the right edge's
        call .start             ; ---- the names: HL, IX (its colours)
        ld a, (ERA)             ; grass
        ld b, a
        ld a, (ix + 2)
        call EinGroundName
        ld (.g2 + 1), a         ; (the same on the right)
        call EinFillRun
        ld a, (ERB)             ; kerb, to the left edge's cell
        dec a
        ld c, a
        ld a, (ERA)
        neg
        add a, c
        ld b, a
        ld a, (ix + 3)
        call EinFillRun
        ld a, (EDm)             ; the left edge: road from pixel D & 7 on
        and 7
        ld a, (ix + 4)          ; (from 0: all road)
        jr z, .l
        ld a, (EDm)
        and 7
        add a, (iy + 0)         ; (the set's first, less one)
.l:     ld (hl), a
        inc l
        ld a, (ERB)             ; road
        ld c, a
        ld a, (ERC)
        sub c
        ld b, a
        ld a, (ix + 4)
        call EinFillRun
        ld a, (EEm)             ; the right edge: road to pixel E & 7
        and 7
        cp 7
        ld a, (ix + 4)          ; (to 7: all road)
        jr z, .r
        ld a, (EEm)
        and 7
        add a, (iy + 1)         ; (the set's right edges)
.r:     ld (hl), a
        inc l
        ld a, (ERC)             ; kerb
        inc a
        ld c, a
        ld a, (ERD)
        sub c
        ld b, a
        ld a, (ix + 3)
        call EinFillRun
        ld a, (ERD)             ; grass
        neg
        add a, 32
        ld b, a
.g2:    ld a, 0
        call EinFillRun
        pop iy
        xor a                   ; (done: Z, no carry)
        ret
.grass: xor a                   ; no road: all grass
        ld (ERA), a
        ld (ERB), a
        ld (ERC), a
        ld (ERD), a
        call .start
        ld b, 32
        ld a, (ix + 2)
        call EinGroundName
        call EinFillRun
        pop iy
        xor a
        ret
; -> HL: its names (BaseNames), marked to be sent; IX: its colour set
; (ERowSets); IY: its kerb edges' names (less one, then the right's
; first: EFastK); IY pushed (the caller pops it)
.start: pop de                  ; (the return)
        push iy
        push de
        ld a, (ERow)
        ld e, a
        ld d, 0
        ld hl, ERowDrawn + ROAD_ROW0
        add hl, de
        ld (hl), 1
        add a, ROAD_ROW0 - PANO_ROW0
        rrca                    ; x 32: BaseNames + (row - 10) * 32
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
        ld (ERowPtr), hl
        ld a, (ERBand)          ; its set: light or dark (not a tunnel's here)
        and $40
        ld ix, ERowSets
        ld de, EFastK
        jr z, .lt
        ld ix, ERowSets + 7
        ld de, EFastK + 4
.lt:    ld a, (ERow)
        cp 4
        jr nc, .t2
        inc de
        inc de
.t2:    push de
        pop iy
        ret
EFastK:                         ; per third and set: its left edges' first
        db KERB_T2 - 1, KERB_T2 + 7, KERB_T1 - 1, KERB_T1 + 7          ; (less
        db KERB_T2 + 13, KERB_T2 + 21, KERB_T1 + 13, KERB_T1 + 21      ; one),
                                ; its right edges' first: light, then dark

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
        ld (ERDE0), bc          ; (the top and bottom lines' edges: EinStaticRanges)
        ld (ERDE1), de
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
; The kerb cells ECol .. EColEnd - 1 (a row that is not a fork's): the
; road's pixels in each, per line pair (as EinCellMasks, into EPat). A cell
; with none stays solid kerb, one that is all road becomes solid road, the
; rest take a slot (as EinKerbName). In one pass.
EinKerbCells:
        ld a, (ECol)
        ld c, a                 ; C: the cell
.col:   ld a, (EColEnd)
        cp c
        ret z
        ret c
        push bc
        ld hl, ELines
        ld de, EPat
        ld b, 4
.ln:    ld a, c                 ; ---- per line pair (EinCellMasks' rule)
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
        ld hl, EPat             ; ---- none, all or some road? (E: any, D: all)
        ld a, (hl)
        ld e, a
        ld d, a
        DUP 3
        inc l
        inc l
        ld a, (hl)
        or e
        ld e, a
        ld a, (hl)
        and d
        ld d, a
        EDUP
        pop bc
        ld a, e
        or a
        jr z, .next             ; no road in it: kerb, as named
        ld a, (ECR)
        inc d
        jr z, .name             ; all road
        push bc
        ld a, (EKC)
        call EinCommitSlot
        pop bc
        cp $FF
        jr z, .next             ; (the row's slots are all used)
.name:  ld e, a
        ld hl, (ERowPtr)
        ld a, l
        add a, c
        ld l, a
        jr nc, .nm
        inc h
.nm:    ld (hl), e
.next:  inc c
        jr .col
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
; EPat (8 pattern bytes) and A (the colour byte) into the row's next slot:
; noted in DirtyList if VRAM does not already hold them.
; -> A = the slot's name ($FF: the row's slots are all used)
EinCommitSlot:
        ld c, a
        ld hl, ESlotN           ; the next free slot: [ESlotN, ESlotTop)
        ld a, (ESlotTop)
        sub (hl)
        jr z, .full
        ld a, (EDown)
        or a
        jr nz, .down
        ld b, (hl)              ; from the bottom up
        inc (hl)
        jr EinCommitAt
.down:  ld hl, ESlotTop         ; from the top down
        dec (hl)
        ld b, (hl)
        jr EinCommitAt
.full:  ld a, $FF
        ret
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
.dirty: ld a, e                 ; (the slot in the row, what: bits 6, 7) onto
        rrca                    ; DirtyList, counted for the row (each slot at
        rrca                    ; most once a frame: it never fills; the rows
        or b                    ; in order: EinUpload's)
        ld hl, (EDirtyEnd)
        ld (hl), a
        inc hl
        ld (EDirtyEnd), hl
        ld a, (ERow)
        add a, low EDirtyRowN
        ld l, a
        ld a, high EDirtyRowN
        adc a, 0
        ld h, a
        inc (hl)
.same:  pop hl
        ld a, (ESlotName0)      ; its name
        add a, b
        ret

; ---------------------------------------------------------------------------
ERow:           db 0            ; road row 0-11 (screen row 12-23)
EI:             db 0            ; its top line
ERowPtr:        dw 0            ; its names in NameBuf
ESlotPtr:       dw 0            ; its slots' bytes in SlotShadow, the first's
ESlotName0:     db 0            ; name (in this order: EinRowSlots)
ESlotN:         db 0            ; how many used
ERowLoNow:      db 0            ; (EinRowBase: the row's ERowLo, ERowHi)
ERowHiNow:      db 0
ESlotTop:       db 0            ; (the free slots: ESlotN .. ESlotTop - 1)
EDown:          db 0            ; 1: taken from the top down (EinSlotRange)
ESloped:        db 0            ; EinRowFast made a sloped row's ranges
EDirtyEnd:      dw 0            ; DirtyList's end
ERW0:           db 0            ; kerb widths of its top and bottom lines
ERW1:           db 0
ERDE0:          dw 0            ; the top line's E, D; the bottom line's
ERDE1:          dw 0
EStatic:        db 0            ; the row drawn with the ready-made patterns
EDm:            db 0            ; then: its edges (the mean of the two lines')
EEm:            db 0
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
        ALIGN 64                ; (EPat .. ELines: 54 bytes, no page crossed)
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
EinShape:       db 1            ; pass 1 ran: rows whose shape changed again
EinForce:       db 1            ; every row again
ELastTun:       db 0

ERowBands:      ds 2 * 12       ; per row, the bands of its lines 0 and 4 as drawn
ERowDrawn:      ds 24           ; per screen row: its names to be sent
