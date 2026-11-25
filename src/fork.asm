; ---------------------------------------------------------------------------
; The road fork at the end of a stage.
;
; From SPLIT_LEN before the end of the stage (ForkZ) the road divides: each
; branch's centre moves out from the old centre line by dx(d) = d^2 / 65536
; world units, d = depth past the split. While the branches overlap the
; road just gets wider; then a grass median opens between them and they
; part. The car is carried along the branch it is on (ForkPlayer), traffic
; follows the branch its lane is on, and the checkpoint takes the branch the
; car is on and re-centres the car on the new stage's road.
;
; Rendering, per line pair (pass 1, ForkLine): the road centre cx (CXLo/Hi,
; for the scenery) and up to two spans: D/E as usual, plus the right branch
; in RoadD2/E2 when both branches are on screen. A row with two spans on any
; of its lines (RowFork) is drawn by DrawForkRow; every other row, with one
; branch or the widening road, goes through the normal incremental renderer.
; ---------------------------------------------------------------------------

        MACRO COL               ; A = pixel x -> cell column
        rrca
        rrca
        rrca
        and 31
        ENDM

        ; A = D, C = E of a span on screen: patch DrawForkRow's test for it
        ; (cell at screen low byte X is inside iff X - (colD + BL) <= W)
        MACRO SPANK sub_, w_, v_, d_, e_
        ld b, a
        and 7
        add a, low RMask
        ld l, a
        ld h, high RMask
        ld a, (hl)
        ld (d_ + 1), a          ; left-edge mask
        ld a, c
        and 7
        add a, low LMaskIncl
        ld l, a
        ld a, (hl)
        ld (e_ + 1), a          ; right-edge mask
        ld l, a
        ld a, b
        COL
        ld h, a                 ; colD
        ld a, (ForkBL)
        add a, h
        ld (sub_ + 1), a
        ld a, c
        COL
        sub h                   ; W = colE - colD
        ld (v_ + 1), a
        inc a
        ld (w_ + 1), a
        sub 2                   ; both edges in one cell: both masks
        sbc a, a
        cpl
        or l
        ld l, a
        ld a, (d_ + 1)
        and l
        ld (d_ + 1), a
        ENDM

COCKPIT         EQU $60             ; in the row state page (SaveCockpit)
SpanBuf         EQU CXPage + $60    ; DrawForkRow: per line pair D1 E1 D2 E2 RW
ForkList        EQU CXPage + $E0    ; DrawForkRow: cells to write (32 bytes)

; Per frame, before pass 1: which lines lie past the split (lines
; 0 .. ForkLim - 1) and the constants ForkLine needs. A branch's offset on
; screen line i (k = i + 1, Z = 12288 / k, FD = depth of the split) is
;   dx(Z - FD) * k / 96 = 24 / k - FD / 256 + C1 * k,  C1 = FD^2 / 6291456
; so going up the screen it is ForkT1[i] (24 / k) plus an accumulator that
; starts at C1 * k - FD / 256 and drops by 2 * C1 every line pair.
ForkFrame:
        xor a
        ld (ForkLim), a
        ld a, (HasFork)
        or a
        ret z
        ld hl, (ForkZ)
        ld de, (Pos)
        or a
        sbc hl, de              ; FD
        ld (ForkFD), hl
        jr c, .all              ; passed it: every line
        jr z, .all
        ex de, hl
        inc de
        call ZLine              ; last line with Z >= FD + 1 ($FF: none)
        inc a
        ld (ForkLim), a
        cp 2
        ret c                   ; (no line pair)
        jr .consts
.all:   ld a, ROAD_LINES
        ld (ForkLim), a
.consts:
        ; C1 = FD^2 / 24576 in 8.8 = (FD^2 >> 13) / 3
        ld hl, (ForkFD)
        call AbsHL
        ld b, h
        ld c, l
        ld d, h
        ld e, l
        call Mul16              ; DE:HL = FD^2
        ld a, h
        rlca
        rlca
        rlca
        and 7
        ex de, hl
        add hl, hl
        add hl, hl
        add hl, hl
        or l
        ld l, a
        ld b, h
        ld c, l
        ld de, 21846            ; / 3
        call Mul16              ; DE = C1
        ld h, d
        ld l, e
        add hl, hl
        ld (Fk2C1), hl
        ; accumulator for the first fork line pair (k = ForkLim & $FE):
        ; C1 * k - FD (16.8) + 0.5
        ld a, (ForkLim)
        and $FE
        ld c, a
        ld b, 0
        call Mul16              ; E:H:L = C1 * k
        ld bc, (ForkFD)
        ld a, b
        rla
        sbc a, a
        ld d, a                 ; FD's sign extension
        or a
        sbc hl, bc
        ld a, e
        sbc a, d
        ld bc, $80
        add hl, bc
        adc a, 0
        ld (FkAcc), hl
        ld (FkAcc + 2), a
        ret

; DE:HL = BC * DE (unsigned)
Mul16:  ld hl, 0
        ld a, 16
.l:     add hl, hl
        rl e
        rl d
        jr nc, .n
        add hl, bc
        jr nc, .n
        inc de
.n:     dec a
        jr nz, .l
        ret

; HL = depth past the split (>= 0) -> A = dx / 4 (DxTab: for the traffic)
DxOf:   ld a, h
        cp $40
        ld a, $FF
        jr nc, .big
        add hl, hl
        add hl, hl
        ld a, h
.big:   ld l, a
        ld h, high DxTab
        ld a, (hl)
        ret

; Pass 1, odd line past the split. Alternate set active, L = line,
; IX = cx (16-bit). Ends at RoadPass1.store with D, E = the first span and
; C = no centre line. Only the alternate set, AF and the temps are used.
ForkLine:
        set 7, l
        ; off = ForkT1 + accumulator (rounded)
        ld h, high ForkT1
        ld a, (FkAcc)
        add a, (hl)
        dec l
        ld a, (FkAcc + 1)
        adc a, (hl)
        ld c, a
        ld a, (FkAcc + 2)
        adc a, 0
        ld b, a                 ; BC = off
        inc l
        res 7, l
        push hl
        ld hl, (FkAcc)          ; next line pair up
        ld de, (Fk2C1)
        or a
        sbc hl, de
        ld (FkAcc), hl
        ld a, (FkAcc + 2)
        sbc a, 0
        ld (FkAcc + 2), a
        pop hl
        bit 7, b
        jr z, .pos
        ld bc, 0
.pos:
        ld h, high X1Page
        ld e, (hl)
        ld d, 0                 ; DE = road half-width
        ld a, b
        or a
        jr nz, .split
        ld a, c
        cp e
        jr nc, .split
        ; the branches overlap: one wide road
        push hl
        ex de, hl
        add hl, bc
        ld b, h
        ld c, l
        push ix
        pop hl
        call Span
        pop hl
        jr .one
.split: ld (FkOff), bc
        ld (FkX1), de
        push hl
        push ix
        pop hl
        or a
        sbc hl, bc
        ld b, d
        ld c, e
        call Span               ; left branch
        push de
        push ix
        pop hl
        ld bc, (FkOff)
        add hl, bc
        ld bc, (FkX1)
        call Span               ; right branch
        pop bc                  ; B, C = left branch D, E
        pop hl
        ld a, c
        cp b
        jr c, .one              ; left branch off screen: D, E = right (or none)
        ld a, e
        cp d
        jr c, .left             ; right branch off screen
        ; both on screen: the right branch is the second span
        ld a, d
        ld (FkD2), a
        ld a, e
        ld (FkE2), a
        ld d, b
        ld e, c
        jr .done
.left:  ld d, b
        ld e, c
.one:   ld a, $FF               ; no second span
        ld (FkD2), a
        xor a
        ld (FkE2), a
.done:  ld c, $FF               ; no centre line past the split
        jp RoadPass1.store

; Pass 1 store, fork in view: the second span (FkD2, FkE2) on screen lines
; L, L + 1 (L even), and the row's flag if it is on screen. Keeps all but H.
ForkPair:
        push af
        push de
        ld de, (FkD2)           ; E = D2, D = E2
        ld h, high DE2Page
        ld (hl), e
        inc l
        ld (hl), e
        set 7, l
        ld (hl), d
        dec l
        ld (hl), d
        res 7, l
        ld a, d
        cp e
        jr c, .none
        ld a, l
        COL
        add a, low RowFork
        push hl
        ld l, a
        ld (hl), 1              ; this row needs DrawForkRow
        pop hl
.none:  pop de
        pop af
        ret

; HL = centre, BC = half-width -> D, E = first / last pixel on screen
; (D = $FF, E = 0: none)
Span:   push hl
        or a
        sbc hl, bc
        jp m, .d0
        ld a, h
        or a
        jr nz, .none1           ; starts right of the screen
        ld d, l
        jr .e
.d0:    ld d, 0
.e:     pop hl
        add hl, bc
        dec hl
        bit 7, h
        jr nz, .none            ; ends left of the screen
        ld a, h
        or a
        ld e, l
        ret z
        ld e, 255
        ret
.none1: pop hl
.none:  ld de, $FF00
        ret

        IFNDEF NATIVE_GFX       ; (the Spectrum's drawing: not in the Einstein's or the CPC's)
; --------------------------------------------------------------------------
; A row with both branches on screen. Every cell is classified from the
; line pairs' spans (grass, road; kerb where an edge passes), the attributes
; are written, and the bitmap is written only in this row's kerb cells and
; in the cells that were kerb before (found by their attributes: kerb
; colours are never grass or road colours) - everything else is already 0.
DrawForkRow:
        ; ---- the spans of the row's 4 line pairs -> SpanBuf (8 bytes each)
        ld a, (CurI)
        ld c, a
        ld de, SpanBuf
        ld b, 4
.gather:
        ld l, c
        ld h, high DEPage
        ld a, (hl)
        ld (de), a              ; D1
        inc e
        set 7, l
        ld a, (hl)
        ld (de), a              ; E1
        inc e
        ld h, high SrcLine      ; kerb width of the depth line shown
        ld a, (hl)
        or $80
        push hl
        ld l, a
        ld h, high RoadRW
        ld a, (hl)
        ld (.rw + 1), a
        pop hl
        ld h, high DE2Page
        res 7, l
        ld a, (hl)
        ld (de), a              ; D2
        inc e
        set 7, l
        ld a, (hl)              ; E2
        ld (de), a
        inc e
.rw:    ld a, 0
        ld (de), a
        ld a, e
        add a, 4
        ld e, a
        inc c
        inc c
        djnz .gather
        ; ---- the row's colours (light or dark band)
        ld a, (CurI)
        add a, low Band + 4
        ld l, a
        ld h, high Band
        ld a, (hl)
        and STRIPE_BIT
        ld a, (PalGrassL)
        ld b, a
        ld a, (PalKerbL)
        ld c, a
        jr z, .light
        ld a, (PalGrassD)
        ld b, a
        ld a, (PalKerbD)
        ld c, a
.light: ld a, c
        ld (KerbCells.lf + 1), a
        ld (KerbCells.rf + 1), a
        ld (.ak + 1), a
        ld a, (PalRoad)
        ld (RoadCells.ar + 1), a
        ld a, (PalKerbL)
        ld (.o1 + 1), a
        ld a, (PalKerbD)
        ld (.o2 + 1), a
        ; ---- each cell's new attribute: grass, road (cells inside a span on
        ;      the top and the bottom pair), kerb (cells an edge or its kerb
        ;      touches)
        ld hl, ForkCls
        ld a, b
        ld b, 32
        call FillA
        ld hl, SpanBuf
        call .roadPair
        ld hl, SpanBuf + 24
        call .roadPair
        ld ix, SpanBuf
        ld h, high ForkCls
        ld b, 4
.kp:    push bc
        ld d, (ix + 0)
        ld e, (ix + 1)
        ld c, (ix + 4)          ; RW
        call KerbCells
        ld d, (ix + 2)
        ld e, (ix + 3)
        call KerbCells
        ld de, 8
        add ix, de
        pop bc
        djnz .kp

        ; ---- old centre lines on the row's lines go (as in DrawRoadLine)
        ld a, (CurRow)
        ld b, a
        and 7
        rrca
        rrca
        rrca
        ld (ForkBL), a          ; row's low address byte
        ld a, b
        and $18
        or $40
        ld hl, BufHiOr
        or (hl)
        ld (ForkBH), a          ; row's first line high byte
        ld a, (StatePage)
        inc a
        ld h, a
        ld a, (CurI)
        ld l, a
        ld a, (ForkBH)
        ld d, a
        ld b, 4
.lanes: ld a, (hl)
        cp $FF
        jr z, .noLane
        ld (hl), $FF
        COL
        push hl
        ld hl, ForkBL
        add a, (hl)
        ld e, a
        xor a
        ld (de), a
        inc e
        ld (de), a
        inc d
        ld (de), a
        dec e
        ld (de), a
        dec d
        pop hl
.noLane:
        inc l
        inc l
        inc d
        inc d
        djnz .lanes

        ; ---- attributes, and the lists of cells to write: kerb cells up
        ;      from ForkList, cells that were kerb and are not down from the
        ;      top of it (as screen low bytes)
        ld a, (ForkBL)
        sub low ForkCls
        ld (.bo + 1), a
        ld (.bo2 + 1), a
        ld a, (CurRow)
        ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ld a, (AttrHi)
        add a, h
        ld h, a                 ; HL = the row's attributes
        ld de, ForkCls
        exx
        ld hl, ForkList
        ld de, ForkList + 31
        exx
        ld b, 32
.cell:  ld a, (de)              ; new attribute
        ld c, (hl)              ; old
        ld (hl), a
.ak:    cp 0                    ; kerb?
        jr z, .kerb
        ld a, c
.o1:    cp 0                    ; was kerb?
        jr z, .clr
.o2:    cp 0
        jr nz, .nx
.clr:   ld a, e
.bo:    add a, 0
        exx
        ld (de), a
        dec e
        exx
        jr .nx
.kerb:  ld a, e
.bo2:   add a, 0
        exx
        ld (hl), a
        inc l
        exx
.nx:    inc l
        inc e
        djnz .cell
        exx
        ld a, l
        sub low ForkList
        ld (ForkNK), a
        ld a, low ForkList + 31
        sub e
        ld (ForkNC), a
        exx
        ; the car's open cockpit takes the colours of what lies under it
        ld a, (CurRow)
        cp CAR_ROW
        jr c, .bitmap
        call z, SaveCockpit
        ld a, 1
        ld (CarDirty), a
        ld (CarAttrDirty), a

.bitmap:
        ; ---- per line pair: write the listed cells on both lines
        ld a, (ForkBH)
        ld d, a
        ld ix, SpanBuf
        ld b, 4
.pair:  push bc
        push de
        ld c, (ix + 1)
        ld a, (ix + 0)
        cp c
        jr z, .k1
        jr nc, .n1
.k1:    SPANK .sub1, .w1, .v1, .d1, .e1
        jr .k1d
.n1:    xor a
        ld (.w1 + 1), a         ; no span: never inside
.k1d:   ld c, (ix + 3)
        ld a, (ix + 2)
        cp c
        jr z, .k2
        jr nc, .n2
.k2:    SPANK .sub2, .w2, .v2, .d2, .e2s
        jr .k2d
.n2:    xor a
        ld (.w2 + 1), a
.k2d:   pop de
        ld a, (ForkNC)          ; cells to clear
        or a
        jr z, .noClr
        ld b, a
        ld hl, ForkList + 31
        xor a
.cl:    ld e, (hl)
        dec l
        ld (de), a
        inc d
        ld (de), a
        dec d
        djnz .cl
.noClr: ld a, (ForkNK)          ; kerb cells
        or a
        jr z, .pDone
        ld b, a
        ld hl, ForkList
.kl:    ld e, (hl)
        inc l
        ld a, e
.sub1:  sub 0                   ; span 1
.w1:    cp 0
        jr nc, .o1n
        or a
        jr z, .d1
.v1:    cp 0
        jr z, .e1
        ld a, $FF
        jr .g1
.d1:    ld a, 0
        jr .g1
.e1:    ld a, 0
        jr .g1
.o1n:   xor a
.g1:    ld c, a
        ld a, e
.sub2:  sub 0                   ; span 2
.w2:    cp 0
        jr nc, .o2n
        or a
        jr z, .d2
.v2:    cp 0
        jr z, .e2s
        ld a, $FF
        jr .g2
.d2:    ld a, 0
        jr .g2
.e2s:   ld a, 0
        jr .g2
.o2n:   xor a
.g2:    or c
        ld (de), a
        inc d
        ld (de), a
        dec d
        djnz .kl
.pDone: ld bc, 8
        add ix, bc
        inc d
        inc d
        pop bc
        dec b
        jp nz, .pair

        ; ---- row state: drawn by DrawForkRow on this buffer
        ld a, (StatePage)
        add a, 2
        ld h, a
        ld a, (CurRow)
        sub ROAD_ROW0
        add a, $40
        ld l, a
        ld (hl), 1
        ld a, (CurI)
        add a, 8
        ld (CurI), a
        ret

; HL = span entry: fill road cells [(D + 7) >> 3, (E + 1) >> 3) of both spans
.roadPair:
        ld d, (hl)
        inc l
        ld e, (hl)
        inc l
        push hl
        call RoadCells
        pop hl
        ld d, (hl)
        inc l
        ld e, (hl)
RoadCells:
        ld a, e
        cp d
        ret c                   ; no span
        ld a, d
        add a, 7
        ret c
        COL
        ld c, a
        ld a, e
        inc a
        ld b, 32
        jr z, .e32
        COL
        ld b, a
.e32:   ld a, b
        sub c
        ret z
        ret c
        ld b, a
        ld a, c
        add a, low ForkCls
        ld l, a
        ld h, high ForkCls
.ar:    ld a, 0                 ; road attribute (patched)
        jp FillA

; D, E = span, C = kerb width, H = high ForkCls: kerb cells around both
; edges
KerbCells:
        ld a, e
        cp d
        ret c
        ld a, d                 ; [(D - RW) >> 3, D >> 3]
        sub c
        jr nc, .l0
        xor a
.l0:    COL
        add a, low ForkCls
        ld l, a
        ld a, d
        COL
        add a, low ForkCls + 1
        sub l
        ld b, a
.lf:    ld (hl), 0                ; kerb attribute (patched)
        inc l
        djnz .lf
        ld a, e                 ; [E >> 3, (E + RW) >> 3]
        COL
        add a, low ForkCls
        ld l, a
        ld a, e
        add a, c
        jr nc, .r0
        ld a, 255
.r0:    COL
        add a, low ForkCls + 1
        sub l
        ld b, a
.rf:    ld (hl), 0
        inc l
        djnz .rf
        ret

; Row 20's attributes under the car's open cockpit (columns 12-19), kept per
; buffer for DrawCar.
SaveCockpit:
        push hl
        push de
        push bc
        ld a, (AttrHi)
        add a, (CAR_ROW * 32) >> 8
        ld h, a
        ld l, low (CAR_ROW * 32) + CAR_COL
        ld a, (StatePage)
        add a, 2
        ld d, a
        ld e, COCKPIT
        ld bc, CAR_W
        ldir
        pop bc
        pop de
        pop hl
        ret

; A row DrawForkRow drew goes back to the normal renderer: clear the kerb
; cells it left (found by their attributes) on all 8 lines.
ClearKerbCells:
        ld a, (PalKerbL)
        ld (.k1 + 1), a
        ld a, (PalKerbD)
        ld (.k2 + 1), a
        ld a, (CurRow)
        ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ld a, (AttrHi)
        add a, h
        ld h, a
        ld a, (CurRow)
        ld b, a
        and 7
        rrca
        rrca
        rrca
        ld e, a
        ld a, b
        and $18
        or $40
        ld b, a
        ld a, (BufHiOr)
        or b
        ld d, a
        ld b, 32
.cell:  ld a, (hl)
.k1:    cp 0
        jr z, .clr
.k2:    cp 0
        jr nz, .nx
.clr:   ld c, d
        xor a
        DUP 7
        ld (de), a
        inc d
        EDUP
        ld (de), a
        ld d, c
.nx:    inc l
        inc e
        djnz .cell
        ret

        ENDIF
; --------------------------------------------------------------------------
; Player: after the position update. PlayerDx = dx at the car (0 before the
; split); the car moves out with its branch.
ForkPlayer:
        ld hl, 0
        ld a, (HasFork)
        or a
        jr z, .set
        ld hl, (Pos)
        ld de, Z_NEAR_LINE
        add hl, de
        ld de, (ForkZ)
        or a
        sbc hl, de
        jr c, .zero
        ld b, h
        ld c, l
        ld d, h
        ld e, l
        call Mul16
        ex de, hl               ; dx = d^2 >> 16
        jr .set
.zero:  ld hl, 0
.set:   ld de, (PlayerDx)
        ld (PlayerDx), hl
        or a
        sbc hl, de
        ex de, hl               ; DE = how far the branch moved out
        ld hl, (PlayerX)
        bit 7, h
        jr nz, .left
        add hl, de
        ld (PlayerX), hl
        ret
.left:  or a
        sbc hl, de
        ld (PlayerX), hl
        ret
Z_NEAR_LINE     EQU 128             ; depth of the bottom line

; A = x / 4 of the traffic car at IX: its lane, moved out with its branch.
; Preserves BC, DE, HL.
CarX:   ld a, (HasFork)
        or a
        ld a, (ix + 2)
        ret z
        push hl
        push de
        ld l, (ix + 0)
        ld h, (ix + 1)
        ld de, (ForkZ)
        or a
        sbc hl, de
        ld a, (ix + 2)
        jr c, .out              ; before the split
        call DxOf
        ld e, a
        ld a, (ix + 2)
        bit 7, a
        jr nz, .neg
        add a, e
        jr c, .max
        cp 128
        jr c, .out
.max:   ld a, 127
        jr .out
.neg:   add a, 127
        cp e
        jr c, .min
        sub e
        sub 127
        jr .out
.min:   ld a, -127
.out:   pop de
        pop hl
        ret

; HL = |HL|
AbsHL:  bit 7, h
        ret z
NegHL:  xor a
        sub l
        ld l, a
        sbc a, a
        sub h
        ld h, a
        ret
