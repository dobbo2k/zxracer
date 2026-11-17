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
; Pass 1 (only when the road shape changes): per road line i (0 = horizon ..
;   95 = bottom) the first and last road pixel D, E (clamped to the screen;
;   D > E means no road on screen) and the centre-line x.
; Bands (every frame): light/dark band per line.
; Pass 2, per character row: kerb cell ranges from the row's top and bottom
;   lines, attributes (only rewritten when they change), then per line the
;   kerb bytes (only if D/E changed or the row's ranges changed) and the
;   centre line (only if it changed). The 8 pixel lines of a row are 256
;   bytes apart, so the line address is just INC IXH.
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
        ld (StalePieces.rs + 1), a
        ld a, (BufHiOr)
        ld (DrawRoadRow.bufOr + 1), a

        ; pass 1 only when the road shape changed: the player moved sideways
        ; or a curve is in view (this frame or the last)
        call BuildCurveList
        ld a, (RoadStraight)
        ld hl, LastStraight
        ld b, (hl)
        ld (hl), a
        and b
        jr z, .shapeChanged
        ld hl, (PlayerX)
        ld de, (Pass1PX)
        or a
        sbc hl, de
        jr z, .shapeSame
.shapeChanged:
        ld hl, (PlayerX)
        ld (Pass1PX), hl
        call RoadPass1
.shapeSame:
        call RoadBands

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
; Road edges and centre line per line, from the bottom line up.
; The road centre is a single accumulator: total (HL.C, 16.8) starts at
; 128 - PlayerX on the bottom line and each line up adds dx (DE.B, 16.8),
; which starts at PlayerX / 96 (the player's lateral offset in perspective)
; and gains the segment curvature every line (screen-space curves).
; Alternate registers: L' = line index, H' = table page.
RoadPass1:
        ; dx = PlayerX / 96 ~= PlayerX * 2.664 / 256
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
        ld b, l                 ; dx fraction
        ld a, h
        ld e, a
        rlca
        sbc a, a
        ld d, a                 ; DE = dx integer part (sign-extended)
        ; total = 128 - PlayerX
        push de
        ld de, (PlayerX)
        ld hl, 128
        or a
        sbc hl, de
        pop de
        ld c, 0
        ; curvature at the bottom line and the first boundary
        push hl
        ld a, (CurveList)
        call SetCurve
        ld hl, CurveList + 1
        ld (CurvePtr), hl
        ld a, (hl)
        ld (.nb + 1), a
        pop hl
        exx
        ld l, ROAD_LINES - 1
        exx
.cx:    exx
        ld a, l
        exx
.nb:    cp $FF
        call z, NextCurve
        ; IX = cx = total
        ld a, l
        ld ixl, a
        ld a, h
        ld ixh, a
        ; advance to the next line up: dx += curvature, total += dx
        ld a, b
.cl:    add a, 0
        ld b, a
        ld a, e
.ch:    adc a, 0
        ld e, a
        ld a, d
.ch2:   adc a, 0
        ld d, a
        ld a, c
        add a, b
        ld c, a
        adc hl, de
        ld a, ixh
        or a
        exx
        jr nz, .slow            ; cx outside 0..255
        ; ---- fast path: 8-bit maths
        ld a, ixl
        ld b, a                 ; B' = cx
        ld h, high X1Page
        sub (hl)                ; cx - X1
        jr c, .slow
        ld h, high DEPage
        ld (hl), a              ; D
        ld a, b
        dec a
        ld h, high X1Page
        add a, (hl)             ; cx + X1 - 1
        jr c, .slow
        set 7, l
        ld h, high DEPage
        ld (hl), a              ; E
        res 7, l
        ld a, b
        ld h, high LWPage
        sub (hl)                ; centre line x = cx - LW (LW = 255: none)
        jr nc, .lane
        ld a, $FF
.lane:  ld h, high LXPage
        ld (hl), a
.next:  dec l
        exx
        jp p, .cx
        ret

.slow:  ; IX = cx (16-bit), L' = i
        push ix
        pop de                  ; DE' = cx
        ld h, high X1Page
        ld c, (hl)
        ld b, 0                 ; BC' = X1
        push hl
        ld h, d
        ld l, e
        or a
        sbc hl, bc              ; first road pixel
        bit 7, h
        jr nz, .f0
        ld a, h
        or a
        jr nz, .noRoad          ; >= 256: road entirely right of the screen
        ld a, l
        jr .f1
.f0:    xor a
.f1:    ex af, af'              ; A' = D
        ld h, d
        ld l, e
        add hl, bc
        dec hl                  ; last road pixel
        bit 7, h
        jr nz, .noRoad          ; < 0: road entirely left of the screen
        ld a, h
        or a
        ld a, l
        jr z, .f2
        ld a, 255
.f2:    ld c, a                 ; E
        ex af, af'
        ld b, a                 ; D
        pop hl
        ld h, high DEPage
        ld (hl), b
        set 7, l
        ld (hl), c
        res 7, l
        jr .slane
.noRoad:
        pop hl
        ld h, high DEPage
        ld (hl), $FF
        set 7, l
        ld (hl), 0
        res 7, l
.slane: ld a, ixh
        or a
        ld a, $FF
        jr nz, .slw
        ld a, ixl
        ld h, high LWPage
        sub (hl)
        jr nc, .slw
        ld a, $FF
.slw:   ld h, high LXPage
        ld (hl), a
        jr .next

; Light/dark band per line: bit STRIPE_BIT of (z + position)
RoadBands:
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
DrawRoadRow:
        ; ---- edges of the row's top (0) and bottom (1) lines
        ld a, (CurI)
        ld l, a
        ld h, high DEPage
        ld b, (hl)              ; D0
        set 7, l
        ld c, (hl)              ; E0
        ld h, high X1Page
        ld a, (hl)
        ld (RowRW0), a
        ld a, l
        add a, 7
        ld l, a
        ld a, (hl)
        ld (RowRW1), a
        ld h, high DEPage
        ld e, (hl)              ; E1
        res 7, l
        ld d, (hl)              ; D1
        ; a line without road (D > E) borrows the other line's edges
        ld a, c
        cp b
        jr nc, .t0
        ld b, d
        ld c, e
        ld a, (RowRW1)
        ld (RowRW0), a
.t0:    ld a, e
        cp d
        jr nc, .t1
        ld d, b
        ld e, c
        ld a, (RowRW0)
        ld (RowRW1), a
.t1:    ld a, c
        cp b
        jr nc, .haveRoad
        xor a                   ; no road on this row: all grass
        ld (RowA), a
        ld (RowB), a
        ld (RowC), a
        ld (RowD), a
        ld (RowMerged), a
        jr .ranges
.haveRoad:
        ; a = min(D - RW) >> 3   (clamped at 0)
        ld a, (RowRW0)
        ld h, a
        ld a, b
        sub h
        jr nc, .a0
        xor a
.a0:    ld l, a
        ld a, (RowRW1)
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
        ld (RowA), a
        ; b = max(D) >> 3 + 1
        ld a, b
        cp d
        jr nc, .b0
        ld a, d
.b0:    rrca
        rrca
        rrca
        and 31
        ld l, a                 ; max column of the first road pixel
        inc a
        ld (RowB), a
        ; c = min(E) >> 3, at least b
        ld a, c
        cp e
        jr c, .c0
        ld a, e
.c0:    rrca
        rrca
        rrca
        and 31
        cp l                    ; narrow road: an edge cell holds both edges
        ld h, 1
        jr c, .c1
        jr z, .c1
        ld h, 0
.c1:    ld l, a
        ld a, h
        ld (RowMerged), a
        ld a, (RowB)
        cp l
        jr nc, .c2
        ld a, l
.c2:    ld (RowC), a
        ; d = max(E + RW) >> 3 + 1   (clamped at 255)
        ld a, (RowRW0)
        add a, c
        jr nc, .d0
        ld a, 255
.d0:    ld l, a
        ld a, (RowRW1)
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
        ld a, (RowC)
        cp l
        jr nc, .d3
        ld a, l
.d3:    ld (RowD), a

.ranges:
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
        ; ---- bitmap address of the row's first pixel line -> IX
        ld a, (CurRow)
        ld b, a
        and 7
        rrca
        rrca
        rrca
        ld ixl, a               ; (row & 7) << 5
        ld a, b
        and $18
        or $40
.bufOr: or 0
        ld ixh, a
        ld a, (CurI)
        ld c, a
        ld b, 8
.line:  push bc
        call DrawRoadLine
        pop bc
        inc ixh
        inc c
        djnz .line
        ld a, c
        ld (CurI), a
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
.rs:    ld h, 0
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

; Clear the stale kerb cells (patched pieces) on the line at IX. Preserves DE.
ZeroStale:
        push de
        ld a, ixh
        ld h, a
        ld a, ixl
        ld e, a
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

; --------------------------------------------------------------------------
; Draw road line C (preserved) at bitmap address IX (preserved).
; Row constants (patched by DrawRoadRow): forced, merged, ka/ga/gc = a,
; kl = a + STRIP_PAD, kc = c, kr = low StripR + STRIP_PAD + c, gn = d - a,
; lb = b, lc = c - 1, lcall / rcall = LDI chain entries for the kerb widths.
; Frame constants: s1a / s1b (D/E state), s2a / s2b (centre line state).
DrawRoadLine:
        ld l, c
        ld h, high DEPage
        ld d, (hl)
        set 7, l
        ld e, (hl)              ; D, E = first / last road pixel
.forced:
        ld a, 0
        or a
        jr nz, .clearRow
.s1a:   ld h, 0
        ld a, (hl)
        cp e
        jr nz, .kerbs
        res 7, l
        ld a, (hl)
        cp d
        jp z, .lane             ; edges unchanged on this buffer
        jr .kerbs

.clearRow:
        ; the row's kerb cells changed: clear stale cells and the centre line
        push bc
        call ZeroStale
        pop bc
        ld l, c
.s2b:   ld h, 0
        ld a, (hl)
        ld (hl), $FF            ; centre line forgotten
        cp $FF
        jr z, .kerbs
        rrca
        rrca
        rrca
        and 31
        add a, ixl
        ld l, a
        ld a, ixh
        ld h, a
        xor a
        ld (hl), a
        inc l
        ld (hl), a

.kerbs: ld l, c
.s1b:   ld h, 0
        ld (hl), d
        set 7, l
        ld (hl), e
        ld a, e
        cp d
        jr c, .none
        ; road pixel masks for the edge bytes, then D = colB, E = colQ
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

        ld a, ixl
.ka:    add a, 0
        ld e, a
        ld a, ixh
        ld d, a                 ; DE = left kerb cells
.lsrc:  ld hl, StripL
.lcall: call LdiEnd
        ld a, ixl
.kc:    add a, 0
        ld e, a
        ld a, ixh
        ld d, a                 ; DE = right kerb cells
.rsrc:  ld hl, StripR
.rcall: call LdiEnd
        pop bc
        jr .lane

.generic:
        ; narrow road: compose every kerb byte in [a, d) from both edges
        ld a, ixh
        ld h, a
        ld a, ixl
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
        ld a, c
        cp d
        ld a, $FF
        jr nz, .g1
        ld a, (StripL + STRIP_PAD)
.g1:    ex af, af'
        ld a, c
        cp e
        jr nz, .g2
        ld a, (StripR + STRIP_PAD)
        ld (.gm + 1), a
        ex af, af'
.gm:    and $FF
        jr .gw
.g2:    ex af, af'
        jr .gw
.g0:    xor a
.gw:    ld (hl), a
        inc l
        inc c
        djnz .gl
.gDone: pop bc

.lane:  ; ---- centre line: light band only, both bytes on road cells
        ld b, $FF
        ld l, c
        set 7, l
        ld h, high Band
        ld a, (hl)
        or a
        jr nz, .laneNew
        res 7, l
        ld h, high LaneX
        ld a, (hl)
        cp $FF
        jr z, .laneNew
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
        cp $FF
        jr z, .noOld
        ; erase the old centre line bytes
        rrca
        rrca
        rrca
        and 31
        add a, ixl
        ld l, a
        ld a, ixh
        ld h, a
        xor a
        ld (hl), a
        inc l
        ld (hl), a
.noOld: ld a, b
        cp $FF
        ret z
        ; draw: mask index = LW*8 + (x & 7)
        ld l, c
        set 7, l
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
        ld a, b
        rrca
        rrca
        rrca
        and 31
        add a, ixl
        ld l, a
        ld a, ixh
        ld h, a
        ld a, (de)
        ld (hl), a
        inc l
        ld a, e
        add a, low LaneM2 - low LaneM1
        ld e, a
        ld a, (de)
        ld (hl), a
        ret
