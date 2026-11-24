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

        IFNDEF EINSTEIN         ; (the Spectrum's drawing: not in the Einstein build)
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
        ld (DrawRoadRow.rs3 + 1), a
        ld a, (BufHiOr)
        ld (DrawRoadRow.bufOr + 1), a
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

        ENDIF
; The road's shape for the next frame (no screen access: it runs while the
; last frame waits for its flip). Pass 1 only when the shape changed: the
; player moved sideways, or curves, hills or the fork are in view (this
; frame or the last).
RoadPrepare:
        call UpdateTunnel
        call BuildCurveList
        call ForkFrame
        ld a, (RoadStraight)
        ld hl, LastStraight
        ld b, (hl)
        ld (hl), a
        and b
        jr z, .shapeChanged
        ld a, (ForkLim)         ; past the split the road changes every frame
        ld hl, P1ForkLim
        or (hl)
        jr nz, .shapeChanged
        ld hl, (PlayerX)
        ld de, (Pass1PX)
        or a
        sbc hl, de
        jr z, .shapeSame
.shapeChanged:
        ld hl, (PlayerX)
        ld (Pass1PX), hl
        IFDEF EINSTEIN
        ld a, 1                 ; (every row's shape to be drawn again)
        ld (EinShape), a
        ENDIF
        call RoadPass1
.shapeSame:
        jp RoadBands

; --------------------------------------------------------------------------
; Road edges and centre line per line, from the bottom line up.
; The road centre is a single accumulator: total (HL.C, 16.8) starts at
; 128 - PlayerX on the bottom line and each line up adds dx (DE.B, 16.8),
; which starts at PlayerX / 96 (the player's lateral offset in perspective)
; and gains the segment curvature every line (screen-space curves).
; Alternate registers: L' = line index, H' = table page.
RoadPass1:
        ; fork lines (in pairs) and their per-row flags
        ld a, (ForkLim)
        and $FE
        ld (P1ForkLim), a
        ld (.fl + 1), a
        ld hl, RowFork
        ld b, 24 - ROAD_ROW0
        xor a
.rf:    ld (hl), a
        inc l
        djnz .rf
        ld hl, $00FF            ; no second span until ForkLine finds one
        ld (FkD2), hl
        ld a, (P1ForkLim)       ; store the second spans only with a fork in view
        or a
        ld a, 3
        jr z, .nff
        xor a
.nff:   ld (.ff + 1), a
        ld (HillStore.hf + 1), a
        ; hills in view: lines are stored through the hill mapping
        ld a, (HillOr)
        or a
        jr nz, .hills
        ld a, (P1Hill)
        or a
        call nz, HillReset      ; back to one screen line per depth line
        xor a
        ld (P1Hill), a
        ld hl, .flat
        jr .hset
.hills: ld a, (P1Hill)
        or a                    ; Z: flat mapping last frame, rebuild unconditionally
        ld a, 1
        ld (P1Hill), a
        call HillMap
        ld hl, HillStore
.hset:  ld (.store + 1), hl
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
        ; curvature at the bottom line, the first boundary and the first zone
        push hl
        xor a
        ld (CurK), a
        ld hl, ZoneLines
        ld (ZonePtr), hl
        ld a, (hl)
        ld (NextNZ), a
        ld a, (CurveList)
        call SetCurve
        ld hl, CurveList + 2
        ld (CurvePtr), hl
        ld a, (hl)
        ld (NextNB), a
        call NextEvent
        ; P = 2 dx + 3 k: what a pair of lines adds to the centre (each line
        ; up adds dx, and dx gains k each line); a pair then adds P, and P
        ; gains 4 k
        sla b
        rl e
        rl d
        ld hl, CurK3
        ld a, b
        add a, (hl)
        ld b, a
        inc hl
        ld a, e
        adc a, (hl)
        ld e, a
        inc hl
        ld a, d
        adc a, (hl)
        ld d, a
        pop hl
        exx
        ld l, ROAD_LINES - 1
        exx
        ; Lines are computed in pairs: each odd line exactly, and the even
        ; line above it takes the same edges (the renderer copies it).
.cx:    exx
        ld a, l
        exx
.nx:    cp $FF                  ; a curve boundary or zone line (NextEvent)
        jp z, .event
.go:    ; ---- odd line: edges and centre line from cx = total
        IFDEF EIN_NOLANE        ; (the Einstein, no centre line: cx in BC')
        push hl
        exx
        pop bc                  ; BC' = cx
        ld h, high CXPage       ; road centre on this line, for the scenery
        set 7, l
        ld (hl), b
        res 7, l
        ld (hl), c
        ld a, l
.fl:    cp 0                    ; past the split? (P1ForkLim, patched)
        jp c, .fork
        ld h, high X1Page
        ld a, b
        or a
        jr nz, .slow            ; cx outside 0..255
        ld a, c
        sub (hl)                ; cx - X1
        jr c, .slow
        ld d, a                 ; D' = first road pixel
        ld a, c
        dec a
        add a, (hl)             ; cx + X1 - 1
        jr c, .slow
        ld e, a                 ; E' = last road pixel
        ELSE
        ld a, l
        ld ixl, a
        ld a, h
        ld ixh, a
        exx
        ld h, high CXPage       ; road centre on this line, for the scenery
        set 7, l
        ld (hl), a
        res 7, l
        ld a, ixl
        ld (hl), a
        ld a, l
.fl:    cp 0                    ; past the split? (P1ForkLim, patched)
        jp c, ForkLine
        ld a, ixh
        or a
        ld h, high X1Page
        ld c, (hl)              ; C' = X1
        jr nz, .slow            ; cx outside 0..255
        ld a, ixl
        ld b, a                 ; B' = cx
        sub c                   ; cx - X1
        jr c, .slow
        ld d, a                 ; D' = first road pixel
        ld a, b
        dec a
        add a, c                ; cx + X1 - 1
        jr c, .slow
        ld e, a                 ; E' = last road pixel
        ld a, b
        ld h, high LWPage
        sub (hl)                ; centre line x = cx - LW (LW = 255: none)
        jr nc, .lane
        ld a, $FF
.lane:  ld c, a                 ; C' = centre line x
        ENDIF
.store: jp .flat                ; (HillStore when hills are in view)
.flat:  ; this line and the one above it
        ld h, high DEPage
        ld (hl), d
        dec l
        ld (hl), d
        set 7, l
        ld (hl), e
        inc l
        ld (hl), e
        res 7, l
        IFDEF EIN_NOLANE
        dec l
        ELSE
        ld h, high LXPage
        ld (hl), c
        dec l
        ld (hl), c
        ENDIF
.ff:    jr .ffs                 ; (patched: 0 with a fork in view)
        call ForkPair
.ffs:   inc l
.stored:
        exx
.acc:   ; ---- two lines up: total += P, P += 4 k (patched by ApplyCurve)
        ld a, c
        add a, b
        ld c, a
        adc hl, de
        ld a, b
.p4f:   add a, 0
        ld b, a
        ld a, e
.p4l:   adc a, 0
        ld e, a
        ld a, d
.p4h:   adc a, 0
        ld d, a
        exx
        dec l
        dec l
        exx
        jp p, .cx
        ret

        IFDEF EIN_NOLANE
.fork:  push bc                 ; (ForkLine takes cx in IX)
        pop ix
        jp ForkLine
.slow:  ; BC' = cx (16-bit), HL' = X1Page + line
        ld a, (hl)
        push hl
        ld h, b
        ld l, c
        ld c, a
        ld b, 0
        call Span               ; (src/fork.asm) D', E' on the screen, or $FF, 0
        pop hl
        jp .store
        ELSE
.slow:  ; IX = cx (16-bit), C' = X1, L' = line
        ld h, high LWPage
        ld b, (hl)              ; B' = LW (255: none)
        push hl
        push ix
        pop hl                  ; HL' = cx
        ld a, h
        or a
        ld a, $FF
        jr nz, .sl1
        ld a, l
        sub b
        jr nc, .sl1
        ld a, $FF
.sl1:   push af                 ; centre line x
        ld b, 0                 ; BC' = X1
        push hl
        or a
        sbc hl, bc              ; first road pixel
        bit 7, h
        jr nz, .f0
        ld a, h
        or a
        jr nz, .noRoad2         ; >= 256: road entirely right of the screen
        ld a, l
        jr .f1
.f0:    xor a
.f1:    ld d, a
        pop hl
        add hl, bc
        dec hl                  ; last road pixel
        bit 7, h
        jr nz, .noRoad1         ; < 0: road entirely left of the screen
        ld a, h
        or a
        ld a, l
        jr z, .f2
        ld a, 255
.f2:    ld e, a
        jr .sdone
.noRoad2:
        pop hl
.noRoad1:
        ld de, $FF00
.sdone: pop af
        ld c, a
        pop hl
        jp .store
        ENDIF

.event: ; the curvature changes on this line: P += 3 (k' - k)
        push hl
        ld hl, (CurK3)
        ld (OldK3), hl
        ld a, (CurK3 + 2)
        ld (OldK3 + 2), a
        exx
        ld a, l
        exx
        ld hl, NextNB
        cp (hl)
        call z, NextCurve
        exx
        ld a, l
        exx
        ld hl, NextNZ
        cp (hl)
        call z, NextZone
        call NextEvent
        ld hl, CurK3
        ld a, b
        add a, (hl)
        ld b, a
        inc hl
        ld a, e
        adc a, (hl)
        ld e, a
        inc hl
        ld a, d
        adc a, (hl)
        ld d, a
        ld hl, OldK3
        ld a, b
        sub (hl)
        ld b, a
        inc hl
        ld a, e
        sbc a, (hl)
        ld e, a
        inc hl
        ld a, d
        sbc a, (hl)
        ld d, a
        pop hl
        jp .go

; Light/dark band per line: bit STRIPE_BIT of (z + position), z of the
; depth line the screen line shows; bit 7: that depth line is in a tunnel
RoadBands:
        ld a, (Pos)
        ld c, a
        ld b, ROAD_LINES / 2
        ld hl, SrcLine
        ld d, high ZLo
        ld a, (TunJN)
        or a
        jr nz, .tunnel
        ld a, (P1Hill)
        or a
        jr nz, .hills
        ld hl, ZLo
        ld de, Band
.flat:  ld a, (hl)
        add a, c
        and STRIPE_BIT
        ld (de), a
        inc l
        inc l
        inc e
        inc e
        djnz .flat
        ret

        ; Band and SrcLine have the same offset on their respective pages.
        ASSERT low Band == low SrcLine
.hills: ld e, (hl)
        ld a, (de)
        add a, c
        and STRIPE_BIT
        ld h, high Band
        ld (hl), a
        ld h, high SrcLine
        inc l
        inc l
        djnz .hills
        ret

        ; SrcLine is the identity map on flat ground, including in tunnels.
.tunnel:
        ld (.length + 1), a
        ld a, (TunJ0)
        ld (.first + 1), a
.pair:  ld e, (hl)
        ld a, e
.first: sub 0
.length: cp 0
        ld a, (de)
        jr c, .inside
        add a, c
        and STRIPE_BIT
        jr .store
.inside: add a, c
        and STRIPE_BIT
        or $80
.store: ld h, high Band
        ld (hl), a
        ld h, high SrcLine
        inc l
        inc l
        djnz .pair
        ret

        IFNDEF EINSTEIN         ; (the Spectrum's drawing: not in the Einstein build)
; --------------------------------------------------------------------------
DrawRoadRow:
        ; both fork branches on screen in this row?
        ld a, (CurRow)
        add a, low RowFork - ROAD_ROW0
        ld l, a
        ld h, high RowFork
        ld a, (hl)
        or a
        jp nz, DrawForkRow
        ; ---- edges of the row's top (0) and bottom (1) lines
        ld a, (CurI)
        ld l, a
        ld h, high DEPage
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
        ld (RowRW0), a
        ld a, d
        or $80
        ld l, a
        ld a, (hl)
        ld (RowRW1), a
        pop hl
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

        ; ---- drawn by DrawForkRow last time on this buffer? clear its kerb
        ;      cells and redraw everything
        ld a, (CurRow)
        sub ROAD_ROW0 - $40
        ld l, a
.rs3:   ld h, 0
        ld a, (hl)
        or a
        jr z, .notFork
        ld (hl), 0
        call ClearKerbCells
        ld a, 1
        ld (RowStaleCar), a     ; (anywhere, perhaps under the car)
        jr .rowStore
.notFork:
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
        call StalePieces        ; old kerb cells no longer in the ranges
        call StaleHitsCar
        call ZeroStaleRow       ; clear them on all 8 lines of the row
.rowStore:
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
        ld a, (CurRow)
        cp CAR_ROW
        jr c, .lines
        call z, SaveCockpit
        ld a, 1
        ld (CarAttrDirty), a

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
        call DualEntry
        ld (DrawRoadLine.lcall + 1), hl
        ld a, (RowC)
        ld (DrawRoadLine.kc + 1), a
        add a, low StripR + STRIP_PAD
        ld (DrawRoadLine.kr + 1), a
        ld a, (RowD)
        ld hl, RowC
        sub (hl)                ; right kerb width
        call DualEntry
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
        ; ---- rows under the player's car: no centre line (hidden anyway), and
        ;      tell the car when the road may have written into its block
        ld a, (CurRow)
        cp CAR_ROW
        jr c, .notCar
        ld a, $FF
        ld (DrawRoadLine.lb + 1), a
        ld a, (RowForced)       ; stale kerb cells cleared under the car?
        or a
        jr z, .k1
        ld a, (RowStaleCar)
        or a
        jr nz, .carDirty
.k1:    ld a, (RowA)            ; left kerb cells [a, b) overlap columns 12-19?
        cp CAR_COL + CAR_W
        jr nc, .k2
        ld a, (RowB)
        cp CAR_COL + 1
        jr nc, .carDirty
.k2:    ld a, (RowC)            ; right kerb cells [c, d)?
        cp CAR_COL + CAR_W
        jr nc, .notCar
        ld a, (RowD)
        cp CAR_COL + 1
        jr c, .notCar
.carDirty:
        ld a, 1
        ld (CarDirty), a
.notCar:
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
        ; ---- lines in pairs: every write goes to both lines of a pair
        ld a, (CurI)
        ld c, a
        ld b, 4
.line:  push bc
        call DrawRoadLine
        pop bc
        inc ixh
        inc ixh
        inc c
        inc c
        djnz .line
        ld a, c
        ld (CurI), a
        ret



; A = width in bytes (clamped to STRIP_PAD) -> HL = entry into the
; dual-write chain (7 bytes per byte copied, see main.asm)
DualEntry:
        cp STRIP_PAD + 1
        jr c, .ok
        ld a, STRIP_PAD
.ok:    ld l, a
        add a, a
        add a, a
        add a, a
        sub l                   ; 7 * width
        neg
        add a, low DualEnd
        ld l, a
        ld h, high DualEnd
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
        push hl
        ld a, (RowBand)
        ld bc, (PalGrassL)      ; C = light grass, B = dark grass
        ld de, (PalKerbL)       ; E = light kerb, D = dark kerb
        add a, a                ; carry: in a tunnel; zero: a light band
        jr nc, .open
        ld bc, (TunWall)        ; (src/tunnel.asm)
        ld de, (TunKerbs)
.open:  jr z, .gl
        ld c, b
        ld e, d
.gl:    ld d, c                 ; D = grass, E = kerb
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
        ld a, (PalRoad)
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
        call FillA
        pop hl                  ; (the row's first cell)
        ld a, (RowBand)         ; a tunnel's light band: lamps on the walls,
        cp $80                  ; the cells beside the kerbs (only from inside)
        ret nz
        ld a, (TunInside)
        or a
        ret z
        ld a, (RowA)
        or a
        jr z, .lr
        dec a
        add a, l
        ld e, a
        ld d, h
        ld a, TUN_LAMP
        ld (de), a
.lr:    ld a, (RowD)
        cp 32
        ret nc
        add a, l
        ld l, a
        ld (hl), TUN_LAMP
        ret

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
        ld b, (hl)              ; old a
        inc l
        ld c, (hl)              ; old b
        inc l
        ld d, (hl)              ; old c
        inc l
        ld e, (hl)              ; old d
        ; piece 1: [old a, min(old b, a))
        ld a, (RowA)
        cp c
        jr c, .e1
        ld a, c
.e1:    sub b
        jr nc, .n1
        xor a
.n1:    ld h, a
        ld l, b
        ld (ZeroStaleRow.p1 + 1), hl
        ; piece 2: [max(old a, b), old b)
        ld a, (RowB)
        cp b
        jr nc, .s2
        ld a, b
.s2:    ld l, a
        ld a, c
        sub l
        jr nc, .n2
        xor a
.n2:    ld h, a
        ld (ZeroStaleRow.p2 + 1), hl
        ; piece 3: [old c, min(old d, c))
        ld a, (RowC)
        cp e
        jr c, .e3
        ld a, e
.e3:    sub d
        jr nc, .n3
        xor a
.n3:    ld h, a
        ld l, d
        ld (ZeroStaleRow.p3 + 1), hl
        ; piece 4: [max(old c, d), old d)
        ld a, (RowD)
        cp d
        jr nc, .s4
        ld a, d
.s4:    ld l, a
        ld a, e
        sub l
        jr nc, .n4
        xor a
.n4:    ld h, a
        ld (ZeroStaleRow.p4 + 1), hl
        ret

; RowStaleCar = 1 if a stale piece (car rows only) overlaps the car's columns
StaleHitsCar:
        xor a
        ld (RowStaleCar), a
        ld a, (CurRow)
        cp CAR_ROW
        ret c
        ld hl, ZeroStaleRow.p1 + 1
        call .chk
        ld hl, ZeroStaleRow.p2 + 1
        call .chk
        ld hl, ZeroStaleRow.p3 + 1
        call .chk
        ld hl, ZeroStaleRow.p4 + 1
.chk:   ld a, (hl)              ; start
        inc hl
        ld b, (hl)              ; count
        inc b
        dec b
        ret z
        cp CAR_COL + CAR_W
        ret nc                  ; right of the car
        add a, b
        cp CAR_COL + 1
        ret c                   ; left of it
        ld a, 1
        ld (RowStaleCar), a
        ret

; Clear the stale kerb cells (pieces patched by StalePieces) on all 8 lines
; of the current row, a column strip at a time.
ZeroStaleRow:
        ld a, (CurRow)
        ld b, a
        and 7
        rrca
        rrca
        rrca
        ld e, a                 ; row's low address byte
        ld a, b
        and $18
        or $40
        ld hl, BufHiOr
        or (hl)
        ld d, a                 ; row's first line high byte
.p1:    ld bc, 0                ; C = start, B = count (patched)
        call .zero
.p2:    ld bc, 0
        call .zero
.p3:    ld bc, 0
        call .zero
.p4:    ld bc, 0
.zero:  inc b
        dec b
        ret z
        ld a, e
        add a, c
        ld l, a
        xor a
.col:   ld h, d                 ; a column of 8 lines, unrolled
        DUP 7
        ld (hl), a
        inc h
        EDUP
        ld (hl), a
        inc l
        djnz .col
        ret

; --------------------------------------------------------------------------
; Draw road line C (preserved) at bitmap address IX (preserved).
; Row constants (patched by DrawRoadRow): forced, merged, ka/ga/gc = a,
; kl = a + STRIP_PAD, kc = c, kr = low StripR + STRIP_PAD + c, gn = d - a,
; lb = b, lc = c - 1, lcall / rcall = dual-write chain entries for the kerb
; widths (each byte goes to both lines of the pair).
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
        ; the row's kerb cells changed (stale cells already cleared by the
        ; row): clear the old centre line on both lines of the pair
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
        inc h
        ld (hl), a
        dec l
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
.lcall: call DualEnd            ; both lines of the pair
        ld a, ixl
.kc:    add a, 0
        ld e, a
        ld a, ixh
        ld d, a                 ; DE = right kerb cells
.rsrc:  ld hl, StripR
.rcall: call DualEnd
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
        inc h
        ld (hl), a
        dec h
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
        and STRIPE_BIT          ; (not the tunnel bit)
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
        ; erase the old centre line bytes (both lines of the pair)
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
        inc h
        ld (hl), a
        dec l
        ld (hl), a
.noOld: ld a, b
        cp $FF
        ret z
        ; draw: mask index = LW*8 + (x & 7)
        ld l, c
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
        inc h
        ld (hl), a
        inc l
        ld a, e
        add a, low LaneM2 - low LaneM1
        ld e, a
        ld a, (de)
        ld (hl), a
        dec h
        ld (hl), a
        ret
        ENDIF
