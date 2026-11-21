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
        call EinRowSlots
        xor a
        ld (ESlotN), a
        ld a, (ESlotMax)        ; the centre line's slots from the row's last down
        ld (ESlotTop), a
        jr EinRowBase

; The row's slots (ERow): the first (a SlotShadow index), how many, the
; first's bytes in SlotShadow and its name (ERowSlotTab)
EinRowSlots:
        ld a, (ERow)
        ld l, a
        add a, a
        add a, a
        add a, l                ; x 5
        add a, low ERowSlotTab
        ld l, a
        ld a, high ERowSlotTab
        adc a, 0
        ld h, a
        ld de, ESlot0
        ldi
        ldi
        ldi
        ldi
        ldi
        ret
ERowSlotTab:                    ; per row: ESlot0, ESlotMax, ESlotPtr, ESlotName0
        db 0 * SLOTS_T1, SLOTS_T1
        dw SlotShadow + 0 * SLOTS_T1 * SLOT_SIZE
        db SLOT_FIRST + 0 * SLOTS_T1
        db 1 * SLOTS_T1, SLOTS_T1
        dw SlotShadow + 1 * SLOTS_T1 * SLOT_SIZE
        db SLOT_FIRST + 1 * SLOTS_T1
        db 2 * SLOTS_T1, SLOTS_T1
        dw SlotShadow + 2 * SLOTS_T1 * SLOT_SIZE
        db SLOT_FIRST + 2 * SLOTS_T1
        db 3 * SLOTS_T1, SLOTS_T1
        dw SlotShadow + 3 * SLOTS_T1 * SLOT_SIZE
        db SLOT_FIRST + 3 * SLOTS_T1
        db 4 * SLOTS_T1 + 0 * SLOTS_T2, SLOTS_T2
        dw SlotShadow + (4 * SLOTS_T1 + 0 * SLOTS_T2) * SLOT_SIZE
        db SLOT_FIRST + 0 * SLOTS_T2
        db 4 * SLOTS_T1 + 1 * SLOTS_T2, SLOTS_T2
        dw SlotShadow + (4 * SLOTS_T1 + 1 * SLOTS_T2) * SLOT_SIZE
        db SLOT_FIRST + 1 * SLOTS_T2
        db 4 * SLOTS_T1 + 2 * SLOTS_T2, SLOTS_T2
        dw SlotShadow + (4 * SLOTS_T1 + 2 * SLOTS_T2) * SLOT_SIZE
        db SLOT_FIRST + 2 * SLOTS_T2
        db 4 * SLOTS_T1 + 3 * SLOTS_T2, SLOTS_T2
        dw SlotShadow + (4 * SLOTS_T1 + 3 * SLOTS_T2) * SLOT_SIZE
        db SLOT_FIRST + 3 * SLOTS_T2
        db 4 * SLOTS_T1 + 4 * SLOTS_T2, SLOTS_T2
        dw SlotShadow + (4 * SLOTS_T1 + 4 * SLOTS_T2) * SLOT_SIZE
        db SLOT_FIRST + 4 * SLOTS_T2
        db 4 * SLOTS_T1 + 5 * SLOTS_T2, SLOTS_T2
        dw SlotShadow + (4 * SLOTS_T1 + 5 * SLOTS_T2) * SLOT_SIZE
        db SLOT_FIRST + 5 * SLOTS_T2
        db 4 * SLOTS_T1 + 6 * SLOTS_T2, SLOTS_T2
        dw SlotShadow + (4 * SLOTS_T1 + 6 * SLOTS_T2) * SLOT_SIZE
        db SLOT_FIRST + 6 * SLOTS_T2
        db 4 * SLOTS_T1 + 7 * SLOTS_T2, SLOTS_T2
        dw SlotShadow + (4 * SLOTS_T1 + 7 * SLOTS_T2) * SLOT_SIZE
        db SLOT_FIRST + 7 * SLOTS_T2

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
        call EinStaticRanges    ; (rows 16-23: ready-made edges, ERB / ERC moved)
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
        ld a, (EStatic)         ; ---- rows 16-23: the ready-made patterns
        or a
        jr z, .exact
        call EinStaticCells
        call EinDashRow
        jr .slotsUsed
.exact: ; ---- both of the fork's branches on the row: its own way
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

; ---------------------------------------------------------------------------
; A row (not a fork's, nor a tunnel's, nor one whose road is in one cell):
; the kerb's edges from ready-made patterns (EinStaticInit). Each edge is
; upright in the row, at the mean of its top and bottom lines' (the exact
; way: a slope of 2-line steps). A kerb edge's cell is one name: nothing is
; sent but the names.
; After EinRowRanges: EStatic, and if set, ERB / ERC for the edges' cells.
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
        ld a, b
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

; The ready-made kerb edges into VRAM, the middle and bottom thirds (the
; display off, at a display reset: the stage's colours), and their pixels
; and colours for silhouettes (EStatByte, EStatCol)
EinStaticInit:
        call EinColourSets
        ld b, 0                 ; ---- the open road's light and dark kerb
        ld c, 0                 ; C: the pattern (0 .. KERB_N - 1)
.set:   ld a, b                 ; its colour byte: EKC
        add a, a
        add a, a
        add a, a
        sub b
        add a, low (ERowSets + 5)
        ld l, a
        ld a, high (ERowSets + 5)
        adc a, 0
        ld h, a
        ld a, (hl)
        ld (EStatC), a
        ld e, $7F               ; left edges: road from pixel 1 .. 7
.le:    ld a, e
        call .put
        srl e
        jr nz, .le
        ld e, $80               ; right edges: road to pixel 0 .. 6
.re:    ld a, e
        call .put
        sra e
        ld a, e
        inc a
        jr nz, .re
        inc b
        ld a, b
        cp 2
        jr nz, .set
        ret
; A = the pattern's byte (on all 8 lines), EStatC its colour: pattern C of
; both thirds (C then the next); BC, DE kept
.put:   push bc
        push de
        ld (EStatB), a
        ld l, c
        ld h, 0
        ld de, EStatByte
        add hl, de
        ld (hl), a
        ld de, EStatCol - EStatByte
        add hl, de
        ld a, (EStatC)
        ld (hl), a
        ld a, c
        add a, KERB_T1          ; the middle third's
        ld bc, VRAM_PAT + $800
        call .one
        pop de
        pop bc
        push bc
        push de
        ld a, c
        add a, KERB_T2          ; the bottom third's
        ld bc, VRAM_PAT + $1000
        call .one
        pop de
        pop bc
        inc c
        ret
; A = name, BC = its third: its 8 bytes (EStatB) and colours (EStatC)
.one:   ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, bc
        ex de, hl
        push de
        ld a, (EStatB)
        ld l, a
        ld bc, 8
        call VdpFill
        pop de
        ld a, d
        add a, high VRAM_COL
        ld d, a
        ld a, (EStatC)
        ld l, a
        ld bc, 8
        jp VdpFill

EStatC:         db 0
EStatB:         db 0
EStatByte:      ds KERB_N       ; per ready-made pattern: its byte,
EStatCol:       ds KERB_N       ; its colour byte

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
; The centre line: a 16x16 sprite a road row (sprite k for row 12 + k, its
; patterns 4k on; the top two quarters used), so its pixels are exact at
; any x and cost no slot. Per row drawn (EinDashRow): the dashes of its
; line pairs 0 and 2, each for 4 lines (light bands only, in road cells
; [b, c-1) as the Spectrum), from its leftmost dash pixel, the cells the
; car, a silhouette or a tunnel's mouth covers taken out. A row not drawn
; again is done again only if what covers it changed (EinDashFinish). What
; changed is sent at the start of the next vertical blank (EinDashSend).
EinDashRow:
        ld a, (ERow)
        ld e, a
        ld d, 0
        ld hl, EDashNew
        add hl, de
        ld (hl), 1
        ld hl, EDashB
        add hl, de
        ld a, (ERB)
        ld (hl), a
        ld hl, EDashC
        add hl, de
        ld a, (ERC)
        ld (hl), a
EinDashRedo:                    ; (ERow, EI, ERB, ERC)
        ld a, (ERC)             ; its x in [ERB * 8, (ERC - 1) * 8)
        sub 1
        jp c, .none             ; (no road on the row)
        ld hl, ERB
        cp (hl)
        jp c, .none
        jp z, .none
        add a, a
        add a, a
        add a, a
        ld e, a                 ; E: the end
        ld a, (hl)
        add a, a
        add a, a
        add a, a
        ld d, a                 ; D: the start
        ld a, (EI)
        ld c, a                 ; C: the line (pairs 0 and 2)
        ld hl, EDashP
        ld b, $FF               ; B: the leftmost x
        call .pair
        ld a, c
        add a, 4
        ld c, a
        call .pair
        ld a, b
        cp $FF
        jp z, .none
        ld (EDashXk), a
        call EinDashHideRow     ; (EDashHideNow, EDashHideAny: B kept)
        ld de, $FFFF            ; D, E: the left and right bytes' masks
        ld a, (EDashHideAny)
        or a
        jr z, .full
        ld a, b                 ; the three cells under its 16 pixels
        rrca
        rrca
        rrca
        and 31
        ld c, a
        call .cell
        ld d, a
        inc c
        call .cell
        ld e, a
        inc c
        call .cell
        ld l, a                 ; D E L, shifted left by x & 7
        ld a, b
        and 7
        jr z, .full
        ld b, a
.sh:    sla l
        rl e
        rl d
        djnz .sh
.full:  ld a, d
        ld (EDashML), a
        ld a, e
        ld (EDashMR), a
        ld hl, EDashP           ; ---- its 4 bytes into EDashV
        ld de, EDashV
        call .pat
        call .pat
        ld hl, EDashV           ; any shown?
        ld a, (hl)
        inc hl
        or (hl)
        inc hl
        or (hl)
        inc hl
        or (hl)
        ld (EDashAnyB), a
        ld a, (ERow)            ; ---- against VRAM's
        add a, a
        add a, a
        ld l, a
        ld h, 0
        ld bc, EDashOut
        add hl, bc
        ld de, EDashV
        ld b, 4
.cmp:   ld a, (de)
        cp (hl)
        jr nz, .diff
        inc de
        inc hl
        djnz .cmp
        jr .same
.diff:  ld (hl), a              ; (the rest copied)
        inc de
        inc hl
        djnz .cp
        jr .sent
.cp:    ld a, (de)
        ld (hl), a
        inc de
        inc hl
        djnz .cp
.sent:  ld a, (ERow)            ; its sprite's bytes: EDashQ + row * 32
        ld l, a                 ; (lines 0-7 left, 8 clear, 0-7 right)
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ld de, EDashQ
        add hl, de
        ld de, (EDashV)         ; E: lines 0-3 left, D: right
        ld bc, (EDashV + 2)     ; C: 4-7 left, B: right
        ld (hl), e
        inc l
        ld (hl), e
        inc l
        ld (hl), e
        inc l
        ld (hl), e
        inc l
        ld (hl), c
        inc l
        ld (hl), c
        inc l
        ld (hl), c
        inc l
        ld (hl), c
        ld a, l
        add a, 9
        ld l, a
        ld (hl), d
        inc l
        ld (hl), d
        inc l
        ld (hl), d
        inc l
        ld (hl), d
        inc l
        ld (hl), b
        inc l
        ld (hl), b
        inc l
        ld (hl), b
        inc l
        ld (hl), b
        ld a, (ERow)
        ld c, a
        ld b, 0
        ld hl, EDashSend
        add hl, bc
        ld (hl), 1
        ld a, 1
        ld (EDashAny2), a
.same:  ld a, (ERow)            ; ---- where it is, and what hides it
        ld c, a
        ld b, 0
        ld hl, EDashX
        add hl, bc
        ld a, (EDashXk)
        ld (hl), a
        ld a, (EDashAnyB)
        or a
        jr z, .hide
        ld a, (ERow)
        add a, ROAD_ROW0
        add a, a
        add a, a
        add a, a
        dec a                   ; Y: the line above its top
        ld d, a
        ld a, (EDashXk)
        ld e, a
        jr .attr
.none:  ld a, (ERow)
        ld c, a
        ld b, 0
        ld hl, EDashX
        add hl, bc
        ld (hl), $FF
.hide:  ld de, 192 * 256        ; (below the picture)
.attr:  ld a, (ERow)
        add a, a
        add a, a
        ld c, a
        ld b, 0
        ld hl, EDashAttr
        add hl, bc
        ld a, (hl)
        cp d
        jr nz, .newA
        inc hl
        ld a, (hl)
        cp e
        jr nz, .newA1
        inc hl
        inc hl
        ld a, (ERoadInkT)       ; (its colour: the road's ink)
        cp (hl)
        ret z
        jr .newA3
.newA:  ld (hl), d
        inc hl
.newA1: ld (hl), e
        inc hl
        inc hl
.newA3: ld a, (ERoadInkT)
        ld (hl), a
        ld a, 1
        ld (EDashAttrNew), a
        ret
; C = the line, D/E = the start / end of its x, B = the leftmost so far,
; HL = its x and width (x 8) to be noted ($FF: none)
.pair:  push hl
        ld a, c
        add a, low Band
        ld l, a
        ld h, high Band
        bit 6, (hl)             ; (STRIPE_BIT: a dark band)
        jr nz, .pn
        ld l, c
        ld h, high LaneX
        ld a, (hl)              ; ($FF, none: past the end)
        cp d
        jr c, .pn
        cp e
        jr nc, .pn
        cp b
        jr nc, .pw
        ld b, a
.pw:    ex af, af'
        set 7, l                ; width: LaneW of the depth line shown
        ld h, high SrcLine
        ld a, (hl)
        or $80
        ld l, a
        ld h, high LaneW
        ld a, (hl)
        add a, a
        add a, a
        add a, a
        pop hl
        ex af, af'
        ld (hl), a
        inc hl
        ex af, af'
        ld (hl), a
        inc hl
        ret
.pn:    pop hl
        ld (hl), $FF
        inc hl
        inc hl
        ret
; HL = a pair's x and width: its 4 lines' left and right bytes, masked,
; into DE (then DE on 2)
.pat:   ld a, (EDashXk)
        ld c, a
        ld a, (hl)
        inc hl
        cp $FF
        jr z, .p0
        sub c                   ; its offset from the leftmost
        cp 8
        jr nc, .pfar
        add a, (hl)             ; + width x 8
        inc hl
        push hl
        add a, low LaneM1
        ld l, a
        ld h, high LaneM1
        ld c, (hl)              ; C: left
        add a, low LaneM2 - low LaneM1
        ld l, a
        ld b, (hl)              ; B: right
        jr .pm
.pfar:  sub 8                   ; (8 or more on: its first byte on the right)
        add a, (hl)
        inc hl
        push hl
        add a, low LaneM1
        ld l, a
        ld h, high LaneM1
        ld b, (hl)
        ld c, 0
        jr .pm
.p0:    inc hl
        push hl
        ld bc, 0
.pm:    ld a, (EDashML)
        and c
        ld (de), a
        inc de
        ld a, (EDashMR)
        and b
        ld (de), a
        inc de
        pop hl
        ret
; C = a cell -> A: its pixels' mask, FF if shown, 0 if hidden (or past 31)
.cell:  ld a, c
        cp 32
        ld a, 0
        ret nc
        push hl
        push de
        ld a, c
        rrca
        rrca
        rrca
        and 3
        add a, low EDashHideNow
        ld l, a
        ld a, high EDashHideNow
        adc a, 0
        ld h, a
        ld a, c
        and 7
        add a, low EBitTab
        ld e, a
        ld a, high EBitTab
        adc a, 0
        ld d, a
        ld a, (de)
        and (hl)
        pop de
        pop hl
        ld a, 0
        ret nz
        dec a
        ret

; The row (ERow): no centre line
EinDashNone:
        ld a, (ERow)
        ld e, a
        ld d, 0
        ld hl, EDashNew
        add hl, de
        ld (hl), 1
        jp EinDashRedo.none

; ERow -> EDashHideNow: its cells this frame's silhouettes, the portal or
; the car cover; EDashHideAny: any
EinDashHideRow:
        ld a, (ERow)
        add a, ROAD_ROW0
        add a, a
        add a, a                ; x MASK_ROW
        ld e, a
        ld d, 0
        ld hl, EMaskN
        add hl, de
        push hl
        ld hl, EMaskP
        add hl, de
        ex de, hl
        pop hl
        ld bc, EDashHideNow
        ld a, (de)
        or (hl)
        ld (bc), a
        inc hl
        inc de
        inc bc
        ld a, (de)
        or (hl)
        ld (bc), a
        inc hl
        inc de
        inc bc
        ld a, (de)
        or (hl)
        ld (bc), a
        inc hl
        inc de
        inc bc
        ld a, (de)
        or (hl)
        ld (bc), a
        ld a, (ERow)            ; the car's (rows 20-23: columns 12-19)
        cp CAR_ROW - ROAD_ROW0
        jr c, .any
        ASSERT (CAR_COL & 7) == 4 && CAR_W == 8
        ld hl, EDashHideNow + CAR_COL / 8
        ld a, (hl)
        or $F0
        ld (hl), a
        inc hl
        ld a, (hl)
        or $0F
        ld (hl), a
.any:   ld hl, EDashHideNow
        ld a, (hl)
        inc hl
        or (hl)
        inc hl
        or (hl)
        inc hl
        or (hl)
        ld (EDashHideAny), a
        ret

; Each frame, after the rows: a row not drawn again that something covers
; now or covered last frame is done again
EinDashFinish:
        xor a
.row:   ld (ERow), a
        ld e, a
        ld d, 0
        ld hl, EDashNew
        add hl, de
        ld a, (hl)
        ld (hl), 0
        or a
        jr nz, .next            ; (done as it was drawn)
        ld hl, EDashX
        add hl, de
        ld a, (hl)
        cp $FF
        jr z, .next             ; (none: nothing to hide)
        ld a, (ERow)            ; anything over it now or last frame?
        add a, ROAD_ROW0        ; (silhouettes: EMaskU; the portal: EMaskP,
        add a, a                ; EMaskPOld)
        add a, a
        ld e, a
        ld d, 0
        ld hl, EMaskU
        add hl, de
        call EinMaskAny
        jr nz, .redo
        ld hl, EMaskP
        add hl, de
        call EinMaskAny
        jr nz, .redo
        ld hl, EMaskPOld
        add hl, de
        call EinMaskAny
        jr z, .next
.redo:  ld a, (ERow)            ; its line, its range as drawn
        ld e, a
        ld d, 0
        add a, a
        add a, a
        add a, a
        ld (EI), a
        ld hl, EDashB
        add hl, de
        ld a, (hl)
        ld (ERB), a
        ld hl, EDashC
        add hl, de
        ld a, (hl)
        ld (ERC), a
        call EinDashRedo
.next:  ld a, (ERow)
        inc a
        cp 12
        jr nz, .row
        ret

; In the vertical blank (EinUpload): the sprites' patterns and attributes
; that changed
EinDashSend:
        ld a, (EDashAny2)
        or a
        jr z, .attr
        xor a
        ld (EDashAny2), a
        ld c, 0
.k:     ld b, 0
        ld hl, EDashSend
        add hl, bc
        ld a, (hl)
        or a
        jr z, .nk
        ld (hl), 0
        push bc
        ld l, c                 ; EDashQ + k * 32 -> VRAM_SPRPAT + k * 32:
        ld h, b                 ; its first 24 bytes (the right quarter's
        add hl, hl              ; top the last 8)
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        push hl
        ld de, VRAM_SPRPAT
        add hl, de
        ex de, hl
        pop hl
        ld bc, EDashQ
        add hl, bc
        ld b, 24
        call EinWrite
        pop bc
.nk:    inc c
        ld a, c
        cp 12
        jr nz, .k
.attr:  ld a, (EDashAttrNew)
        or a
        ret z
        xor a
        ld (EDashAttrNew), a
        ld hl, EDashAttr
        ld de, VRAM_SPRATTR
        ld b, 12 * 4 + 1
        jp EinWrite

; At a display reset (VRAM cleared): every row's sprite hidden, its
; patterns clear; the attributes sent
EinDashReset:
        ld hl, EDashX
        ld b, 12
.x:     ld (hl), $FF
        inc hl
        djnz .x
        ld hl, EDashNew         ; (and EDashB, C, Send, Out, Q)
        ld de, EDashNew + 1
        ld bc, EDashAttr - EDashNew - 1
        ld (hl), 0
        ldir
        ld hl, EDashAttr
        ld b, 0
.a:     ld (hl), 192            ; Y: below the picture
        inc hl
        ld (hl), 0
        inc hl
        ld (hl), b              ; pattern 4k
        inc hl
        ld (hl), 15
        inc hl
        ld a, b
        add a, 4
        ld b, a
        cp 12 * 4
        jr nz, .a
        ld (hl), $D0            ; (no more sprites)
        xor a
        ld (EDashAny2), a
        inc a
        ld (EDashAttrNew), a
        ret

EDashP:         ds 4            ; pairs 0 and 2: x ($FF: none), width x 8
EDashXk:        db 0
EDashML:        db 0            ; the masks of its left and right bytes
EDashMR:        db 0
EDashAnyB:      db 0            ; any of its pixels shown
EDashAny2:      db 0            ; any row's patterns to be sent
EDashAttrNew:   db 0            ; the attributes to be sent
EDashHideAny:   db 0
EDashHideNow:   ds 4
EDashV:         ds 4            ; a row's bytes: lines 0-3 left, right; 4-7
        ASSERT MASK_ROW == 4

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
ESlot0:         db 0            ; its first slot, how many it has, the first's
ESlotMax:       db 0            ; bytes in SlotShadow, its name (in this order:
ESlotPtr:       dw 0            ; EinRowSlots)
ESlotName0:     db 0
ESlotN:         db 0            ; how many used
ESlotTop:       db 0            ; (the slots from the row's last down: free)
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
DirtyN:         db 0
EinShape:       db 1            ; pass 1 ran: rows whose shape changed again
EinForce:       db 1            ; every row again
ELastTun:       db 0

ERowBands:      ds 4 * 12       ; per row, the bands it was drawn with
ERowDrawn:      ds 24           ; per screen row: its names to be sent
