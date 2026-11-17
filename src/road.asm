; ---------------------------------------------------------------------------
; Pseudo-3D road renderer
;
; Colour comes from attributes, one set per character row:
;   grass cells  green paper (bright / dark alternate with the bands)
;   kerb cells   white / red paper, black ink - the cells the road edges
;                pass through on that row
;   road cells   black paper, white ink (for the centre line)
; The bitmap only holds:
;   - inside kerb cells, the road's pixels (black ink), so the road edge is
;     pixel-smooth while the kerb colour fills the rest of the cell
;   - the centre line (white ink on road cells, light bands only)
; Grass and road cells are otherwise zero.
;
; Pass 1: per road line i (0 = horizon .. 95 = bottom) the road centre cx
;         (16-bit), the centre-line x and the light/dark band.
; Pass 2: per character row: kerb cell ranges, attributes (only rewritten
;         when they change), then per line: kerb bytes (only if cx moved
;         or the row's ranges changed) and the centre line (only if it moved).
;
; Per-buffer state remembers what each buffer shows, since a buffer is
; redrawn every second frame.
; ---------------------------------------------------------------------------
STRIP_PAD       EQU 12              ; max kerb cells per side per row

DrawRoad:
        ; per-frame constants: state pages and screen high-byte OR
        ld a, (StatePage)
        ld (DrawRoadLine.s1a + 1), a
        ld (DrawRoadLine.s1b + 1), a
        inc a
        ld (DrawRoadLine.s2a + 1), a
        ld (DrawRoadLine.s2b + 1), a
        inc a
        ld (DrawRoadRow.rs1 + 1), a
        ld (DrawRoadRow.rs2 + 1), a
        ld a, (BufHiOr)
        ld (LineAddrIY.bufOr + 1), a

        call RoadPass1

        xor a
        ld (CurI), a
        ld a, ROAD_ROW0
        ld (CurRow), a
        ld b, 24 - ROAD_ROW0
.row:   push bc
        call DrawRoadRow
        ld hl, CurRow
        inc (hl)
        pop bc
        djnz .row
        ret

; --------------------------------------------------------------------------
RoadPass1:
        ; step per line (8.8 signed) = PlayerX / 96 * 256 ~= PlayerX * 2.664
        ld de, (PlayerX)
        ld h, d
        ld l, e
        add hl, hl              ; 2x
        sra d
        rr e
        add hl, de              ; + x/2
        sra d
        rr e
        sra d
        rr e
        add hl, de              ; + x/8
        sra d
        rr e
        sra d
        rr e
        add hl, de              ; + x/32
        sra d
        rr e
        sra d
        rr e
        add hl, de              ; + x/128
        ld a, l
        ld ixl, a               ; step fraction
        ld a, h
        ld e, a
        rlca
        sbc a, a
        ld d, a                 ; DE = step integer part (sign-extended)
        ld hl, 0                ; HL.C = accumulated offset (16.8)
        ld c, l
        ld iy, CXHi             ; (iy-128) = CXLo[i], (iy+0) = CXHi[i]
        ld b, ROAD_LINES
.cx:    ld a, c
        add a, ixl
        ld c, a
        adc hl, de
        ld a, $80               ; cx = 128 - offset
        sub l
        ld (iy - 128), a
        ld a, 0
        sbc a, h
        ld (iy + 0), a
        inc iy
        djnz .cx

        ; bands: bit STRIPE_BIT of (z + position)
        ld a, (Pos)
        ld c, a
        ld hl, ZLo
        ld de, Band
        ld b, ROAD_LINES
.band:  ld a, (hl)
        add a, c
        and STRIPE_BIT
        ld (de), a
        inc l
        inc e
        djnz .band
        ret

; --------------------------------------------------------------------------
; HL = signed pixel x -> A = column + 1, saturated to 0 (x < 0) .. 33 (x > 255)
ColSat: ld a, h
        or a
        jr nz, .out
        ld a, l
        rrca
        rrca
        rrca
        and 31
        inc a
        ret
.out:   ld a, 0
        ret m
        ld a, 33
        ret

; A = line index -> B, C, D, E = biased columns (see ColSat) of the left
; outer edge, first road pixel, last road pixel and right outer edge.
LineCols:
        ld l, a
        ld h, high CXLo
        ld e, (hl)
        set 7, l
        ld d, (hl)              ; DE = cx
        ld h, high RoadX1
        ld c, (hl)              ; C = X1
        res 7, l
        ld h, high RoadW
        ld b, (hl)              ; B = W
        ld a, d
        or a
        jr nz, .slow
        ; fast path: all four edges on screen -> 8-bit maths
        ld a, e
        sub b
        jr c, .slow
        rrca
        rrca
        rrca
        and 31
        inc a
        ld h, a                 ; outer left
        ld a, e
        dec a
        add a, b
        jr c, .slow
        rrca
        rrca
        rrca
        and 31
        inc a
        ld l, a                 ; outer right
        ld a, e
        sub c
        rrca
        rrca
        rrca
        and 31
        inc a
        ld d, a                 ; first road pixel
        ld a, e
        dec a
        add a, c
        rrca
        rrca
        rrca
        and 31
        inc a
        ld c, d
        ld d, a
        ld b, h
        ld e, l
        ret
.slow:  push bc
        ld h, d
        ld l, e
        ld c, b
        ld b, 0
        or a
        sbc hl, bc              ; cx - W
        call ColSat
        ld (LcOL), a
        ld h, d
        ld l, e
        add hl, bc
        dec hl                  ; cx + W - 1
        call ColSat
        ld (LcOR), a
        pop bc
        ld b, 0
        ld h, d
        ld l, e
        or a
        sbc hl, bc              ; cx - X1
        call ColSat
        ld (LcRL), a
        ld h, d
        ld l, e
        add hl, bc
        dec hl                  ; cx + X1 - 1
        call ColSat
        ld e, a
        ld a, (LcOL)
        ld b, a
        ld a, (LcRL)
        ld c, a
        ld a, (LcOR)
        ld d, e
        ld e, a
        ret

; --------------------------------------------------------------------------
DrawRoadRow:
        ; ---- kerb cell ranges from the row's top and bottom lines
        ld a, (CurI)
        add a, 7
        call LineCols
        ld (RowCols), bc
        ld (RowCols + 2), de
        ld a, (CurI)
        call LineCols
        ; lo = min(B), lr = max(C), rr = min(D), ro = max(E)   (biased)
        ld a, (RowCols + 1)
        cp b
        jr nc, .m1
        ld b, a
.m1:    ld a, (RowCols)
        cp c
        jr c, .m2
        ld c, a
.m2:    ld a, (RowCols + 3)
        cp d
        jr nc, .m3
        ld d, a
.m3:    ld a, (RowCols + 2)
        cp e
        jr c, .m4
        ld e, a
.m4:    ; narrow road: some line's first road cell >= another's last
        ld a, c
        cp d
        ld a, 0
        jr c, .m5
        inc a
.m5:    ld (RowMerged), a
        ; a = max(lo, 1) - 1 ; b = clamp(lr, a, 32) ; c = clamp(rr - 1, b, 32) ; d = clamp(ro, c, 32)
        ld a, b
        or a
        jr nz, .k1
        inc a
.k1:    dec a
        ld (RowA), a
        ld h, a
        ld a, c
        call Clamp32
        ld (RowB), a
        ld h, a
        ld a, d
        or a
        jr z, .k2
        dec a
.k2:    call Clamp32
        ld (RowC), a
        ld h, a
        ld a, e
        call Clamp32
        ld (RowD), a

        ; ---- band of the row's middle line
        ld a, (CurI)
        add a, low Band + 4
        ld l, a
        ld h, high Band
        ld a, (hl)
        ld (RowBand), a

        ; ---- compare with what this buffer shows for the row
        ld a, (CurRow)
        sub ROAD_ROW0
        add a, a
        add a, a
        ld l, a                 ; row state: 4 bytes per row, band at +$80
.rs1:   ld h, 0
        xor a
        ld (RowForced), a
        ld de, RowA
        ld b, 4
.cmp:   ld a, (de)
        cp (hl)
        jr nz, .rangesChanged
        inc de
        inc l
        djnz .cmp
        jr .rangesSame
.rangesChanged:
        call StalePieces        ; old kerb cells to clear on each line
        ld a, 1
        ld (RowForced), a
        ld a, (CurRow)
        sub ROAD_ROW0
        add a, a
        add a, a
        ld e, a
.rs2:   ld d, 0
        ld hl, RowA
        ld bc, 4
        ldir
        ex de, hl               ; H = row state page
        jr .attrs
.rangesSame:
        ld a, (CurRow)
        sub ROAD_ROW0
        or $80
        ld l, a
        ld a, (RowBand)
        cp (hl)
        jr z, .lines            ; attributes already correct
.attrs: ld a, (CurRow)
        sub ROAD_ROW0
        or $80
        ld l, a
        ld a, (RowBand)
        ld (hl), a
        call RowAttrs

.lines: ; ---- per-row constants for the line renderer
        ld a, (RowForced)
        ld (DrawRoadLine.forced + 1), a
        ld a, (RowMerged)
        ld (DrawRoadLine.merged + 1), a
        ld a, (RowA)
        ld (DrawRoadLine.ka + 1), a
        ld (DrawRoadLine.ga + 1), a
        ld (DrawRoadLine.gc + 1), a
        add a, STRIP_PAD
        ld (DrawRoadLine.kl + 1), a
        ld a, (RowD)
        ld hl, RowA
        sub (hl)
        ld (DrawRoadLine.gn + 1), a
        ld a, (RowB)
        sub (hl)                ; left kerb width
        call LdiEntry
        ld (DrawRoadLine.lcall + 1), hl
        ld a, (RowC)
        ld (DrawRoadLine.kc + 1), a
        add a, low StripR + STRIP_PAD
        ld (DrawRoadLine.kr + 1), a
        ld a, (RowD)
        ld hl, RowC
        sub (hl)                ; right kerb width
        call LdiEntry
        ld (DrawRoadLine.rcall + 1), hl
        ; centre line cells must satisfy b <= col and col + 1 < c
        ld a, (RowB)
        ld (DrawRoadLine.lb + 1), a
        add a, 2
        ld b, a
        ld a, (RowC)
        dec a
        ld (DrawRoadLine.lc + 1), a
        inc a
        cp b
        jr nc, .laneOk
        ld a, $FF               ; road too narrow for a centre line
        ld (DrawRoadLine.lb + 1), a
.laneOk:
        ld a, (CurI)
        ld c, a
        ld b, 8
.line:  push bc
        call DrawRoadLine
        pop bc
        inc c
        djnz .line
        ld a, c
        ld (CurI), a
        ret

; H = lower bound, A = value -> A = clamp(A, H, 32)
Clamp32:
        cp h
        jr nc, .lo
        ld a, h
.lo:    cp 33
        ret c
        ld a, 32
        ret

; A = width in bytes (clamped to STRIP_PAD) -> HL = LDI chain entry
LdiEntry:
        cp STRIP_PAD + 1
        jr c, .ok
        ld a, STRIP_PAD
.ok:    ld hl, LdiEnd
        or a
        ret z
        add a, a
        neg
        ld l, a
        dec h
        ret

; Write the row's attributes: [0,a) grass, [a,b) kerb, [b,c) road, [c,d) kerb, [d,32) grass
RowAttrs:
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
        ld a, (RowBand)
        or a
        ld a, ATTR_GRASS_L
        ld e, ATTR_KERB_L
        jr z, .gl
        ld a, ATTR_GRASS_D
        ld e, ATTR_KERB_D
.gl:    ld d, a                 ; D = grass, E = kerb
        ld a, (RowA)
        ld b, a
        ld a, d
        call FillA
        ld a, (RowA)
        ld c, a
        ld a, (RowB)
        sub c
        ld b, a
        ld a, e
        call FillA
        ld a, (RowB)
        ld c, a
        ld a, (RowC)
        sub c
        ld b, a
        ld a, ATTR_ROAD
        call FillA
        ld a, (RowC)
        ld c, a
        ld a, (RowD)
        sub c
        ld b, a
        ld a, e
        call FillA
        ld a, (RowD)
        cpl
        add a, 33
        ld b, a
        ld a, d
        jp FillA

; Old kerb cells that are not part of the new kerb ranges must be cleared on
; every line of the row: [oA, min(oB, a)), [max(oA, b), oB),
; [oC, min(oD, c)), [max(oC, d), oD). Patched into ZeroStale as start/count.
StalePieces:
        ld a, (CurRow)
        sub ROAD_ROW0
        add a, a
        add a, a
        ld l, a
        ld a, (DrawRoadRow.rs1 + 1)
        ld h, a
        ld a, (hl)
        ld (OldA), a
        inc l
        ld a, (hl)
        ld (OldB), a
        inc l
        ld a, (hl)
        ld (OldC), a
        inc l
        ld a, (hl)
        ld (OldD), a
        ; piece 1: [oA, min(oB, a))
        ld a, (OldB)
        ld b, a
        ld a, (RowA)
        cp b
        jr c, .p1
        ld a, b
.p1:    ld b, a
        ld a, (OldA)
        call .piece
        ld (ZeroStale.p1 + 1), hl
        ; piece 2: [max(oA, b), oB)
        ld a, (OldB)
        ld b, a
        ld a, (RowB)
        ld c, a
        ld a, (OldA)
        cp c
        jr nc, .p2
        ld a, c
.p2:    call .piece
        ld (ZeroStale.p2 + 1), hl
        ; piece 3: [oC, min(oD, c))
        ld a, (OldD)
        ld b, a
        ld a, (RowC)
        cp b
        jr c, .p3
        ld a, b
.p3:    ld b, a
        ld a, (OldC)
        call .piece
        ld (ZeroStale.p3 + 1), hl
        ; piece 4: [max(oC, d), oD)
        ld a, (OldD)
        ld b, a
        ld a, (RowD)
        ld c, a
        ld a, (OldC)
        cp c
        jr nc, .p4
        ld a, c
.p4:    call .piece
        ld (ZeroStale.p4 + 1), hl
        ret
; A = start, B = end -> L = start, H = count (0 if end <= start)
.piece: ld l, a
        ld a, b
        sub l
        jr nc, .pc
        xor a
.pc:    ld h, a
        ret

; Clear the stale kerb cells (patched pieces) of line C on the back buffer.
; IY = line address. Preserves DE.
ZeroStale:
        push de
        push iy
        pop hl
        ld e, l
.p1:    ld bc, 0                ; C = start, B = count (patched)
        call .zero
.p2:    ld bc, 0
        call .zero
.p3:    ld bc, 0
        call .zero
.p4:    ld bc, 0
        call .zero
        pop de
        ret
.zero:  inc b
        dec b
        ret z
        ld a, e
        add a, c
        ld l, a
        xor a
.zl:    ld (hl), a
        inc l
        djnz .zl
        ret

; C = road line index -> IY = screen address of column 0 in the back buffer.
; Preserves BC, DE.
LineAddrIY:
        ld a, c
        add a, ROAD_Y0
        ld l, a
        ld h, high ScrLo
        ld a, (hl)
        inc h
        ld h, (hl)
        ld l, a
        ld a, h
.bufOr: or 0
        ld h, a
        push hl
        pop iy
        ret

; --------------------------------------------------------------------------
; Draw road line C (preserved).
; Row constants (patched by DrawRoadRow): forced, merged, ka/ga/gc = a,
; kl = a + STRIP_PAD, kc = c, kr = low StripR + STRIP_PAD + c, gn = d - a,
; lb = b, lc = c - 1, lcall / rcall = LDI chain entries for the kerb widths.
; Frame constants: s1a / s1b (cx state), s2a (centre line state).
DrawRoadLine:
        ; ---- DE = cx
        ld l, c
        set 7, l
        ld h, high CXHi
        ld d, (hl)
        res 7, l
        ld e, (hl)
.forced:
        ld a, 0
        or a
        jr z, .check
        ; row's kerb cells changed: clear stale cells, forget the centre line
        call LineAddrIY
        push bc
        call ZeroStale
        pop bc
        ld l, c
.s2b:   ld h, 0
        ld a, (hl)
        ld (hl), $FF
        inc a
        jr z, .kerbs
        dec a
        rrca
        rrca
        rrca
        and 31
        ld b, a
        ld a, iyl
        add a, b
        ld l, a
        ld a, iyh
        ld h, a
        xor a
        ld (hl), a
        inc l
        ld (hl), a
        jr .kerbs2
.check: ld l, c
.s1a:   ld h, 0
        ld a, (hl)
        cp e
        jr nz, .kerbs
        set 7, l
        ld a, (hl)
        cp d
        jp z, .lane             ; road position unchanged on this buffer
.kerbs: call LineAddrIY
.kerbs2:
        ld l, c
.s1b:   ld h, 0
        ld (hl), e
        set 7, l
        ld (hl), d

        ; ---- first / last road pixel -> D, E
        ld h, high RoadX1
        ld b, (hl)              ; B = X1  (L = i | $80)
        ld a, d
        or a
        jr nz, .slow
        ld a, e
        sub b
        jr c, .slow
        ld d, a
        ld a, e
        dec a
        add a, b
        jr c, .slow
        ld e, a
        jr .masks
.slow:  ex de, hl               ; HL = cx
        ld e, b
        ld d, 0
        push hl
        or a
        sbc hl, de              ; first road pixel
        ld a, h
        or a
        jr z, .s1
        jp m, .s0
        pop hl                  ; >= 256: road entirely right of the screen
        jr .none
.s0:    xor a
        jr .s2
.s1:    ld a, l
.s2:    pop hl
        push af
        add hl, de
        dec hl                  ; last road pixel
        ld a, h
        or a
        jr z, .s3
        jp m, .nonePop          ; < 0: road entirely left of the screen
        ld a, 255
        jr .s4
.s3:    ld a, l
.s4:    ld e, a
        pop af
        ld d, a

.masks: ; road pixel masks for the edge bytes, then D = colB, E = colQ
        ld h, high MaskPage
        ld a, d
        and 7
        add a, low RMask
        ld l, a
        ld a, (hl)
        ld (StripL + STRIP_PAD), a
        ld a, e
        and 7
        add a, low LMaskIncl
        ld l, a
        ld a, (hl)
        ld (StripR + STRIP_PAD), a
        ld a, d
        rrca
        rrca
        rrca
        and 31
        ld d, a
        ld a, e
        rrca
        rrca
        rrca
        and 31
        ld e, a
        jr .copy
.nonePop:
        pop af
.none:  xor a
        ld (StripL + STRIP_PAD), a
        ld (StripR + STRIP_PAD), a
        ld de, $1F00            ; colB = 31, colQ = 0: kerb cells all zero

.copy:  push bc
.merged:
        ld a, 0
        or a
        jr nz, .generic
        ; left kerb source = StripL + PAD - (colB - a), clamped to [0, PAD]
.kl:    ld a, 0
        sub d
        jr nc, .l1
        xor a
.l1:    cp STRIP_PAD + 1
        jr c, .l2
        ld a, STRIP_PAD
.l2:    ld (.lsrc + 1), a
        ; right kerb source = StripR + PAD - (colQ - c), clamped to [StripR, StripR + PAD]
.kr:    ld a, 0
        sub e
        jr c, .r0
        cp low StripR
        jr nc, .r1
.r0:    ld a, low StripR
.r1:    cp low StripR + STRIP_PAD + 1
        jr c, .r2
        ld a, low StripR + STRIP_PAD
.r2:    ld (.rsrc + 1), a

        ld a, iyl
.ka:    add a, 0
        ld e, a
        ld a, iyh
        ld d, a                 ; DE = left kerb cells
.lsrc:  ld hl, StripL
.lcall: call LdiEnd
        ld a, iyl
.kc:    add a, 0
        ld e, a
        ld a, iyh
        ld d, a                 ; DE = right kerb cells
.rsrc:  ld hl, StripR
.rcall: call LdiEnd
        pop bc
        jr .lane

.generic:
        ; narrow road: compose every kerb byte in [a, d) from both edges
        push iy
        pop hl
        ld a, l
.ga:    add a, 0
        ld l, a
.gn:    ld b, 0
.gc:    ld c, 0                 ; column
        inc b
        dec b
        jr z, .gDone
.gl:    ld a, c
        cp d
        jr c, .g0
        ld a, e
        cp c
        jr c, .g0
        ld ixh, $FF
        ld a, c
        cp d
        jr nz, .g1
        ld a, (StripL + STRIP_PAD)
        ld ixh, a
.g1:    ld a, c
        cp e
        jr nz, .g2
        ld a, (StripR + STRIP_PAD)
        and ixh
        ld ixh, a
.g2:    ld a, ixh
        jr .gw
.g0:    xor a
.gw:    ld (hl), a
        inc l
        inc c
        djnz .gl
.gDone: pop bc

.lane:  ; ---- centre line x = cx - LW: light band only, both bytes on road cells
        ld b, $FF
        ld l, c
        set 7, l
        ld h, high Band
        ld a, (hl)
        or a
        jr nz, .laneNew
        ld h, high CXHi
        ld a, (hl)
        or a
        jr nz, .laneNew         ; centre off screen
        res 7, l
        ld e, (hl)              ; cx low
        ld h, high LaneW
        ld a, (hl)
        or a
        jr z, .laneNew
        ld d, a
        ld a, e
        sub d
        jr c, .laneNew
        ld e, a
        rrca
        rrca
        rrca
        and 31
.lb:    cp 0
        jr c, .laneNew
.lc:    cp 0
        jr nc, .laneNew
        ld b, e
.laneNew:
        ld l, c
.s2a:   ld h, 0
        ld a, (hl)
        cp b
        ret z                   ; centre line unchanged on this buffer
        ld (hl), b
        push af
        call LineAddrIY
        pop af
        push iy
        pop hl
        cp $FF
        jr z, .noOld
        ; erase the old centre line bytes
        push hl
        rrca
        rrca
        rrca
        and 31
        add a, l
        ld l, a
        xor a
        ld (hl), a
        inc l
        ld (hl), a
        pop hl
.noOld: ld a, b
        cp $FF
        ret z
        ; draw: mask index = LW*8 + (x & 7)
        rrca
        rrca
        rrca
        and 31
        add a, l
        ld l, a
        push hl
        ld l, c
        ld h, high LaneW
        ld a, (hl)
        add a, a
        add a, a
        add a, a
        ld e, a
        ld a, b
        and 7
        add a, e
        add a, low LaneM1
        ld e, a
        ld d, high LaneM1
        pop hl
        ld a, (de)
        ld (hl), a
        inc l
        ld a, e
        add a, low LaneM2 - low LaneM1
        ld e, a
        ld a, (de)
        ld (hl), a
        ret
