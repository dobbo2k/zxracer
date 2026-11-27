; ---------------------------------------------------------------------------
; CPC: the panorama, the portal, the palette and the display reset (in bank
; 2: on the CPC all RAM is as fast)
; ---------------------------------------------------------------------------

; The stage overlay installs a ready-to-scroll Mode 0 panorama in PANO_CACHE.
CPanoA:         db $FF          ; the byte each screen's panorama starts at
CPanoB:         db $FF          ; ($FF: not drawn)
        ASSERT high CPanoA == high CPanoB
CTunWas:        db 0            ; TunInside as last seen

CpcPanoReset:
        ld a, (PenByte + PEN_SKY)
        ld e, a
        ld hl, PANO_CACHE       ; first line containing landscape pixels
        ld b, 0
.top:   ld c, 64
.tb:    ld a, (hl)
        inc hl
        cp e
        jr nz, .found
        dec c
        jr nz, .tb
        inc b
        ld a, b
        cp PANO_H
        jr c, .top
.found: ld a, b
        ld (CPanoTop), a
        ld a, $FF
        ld (CPanoA), a
        ld (CPanoB), a
        ret
CPanoTop:       db 0            ; the panorama's first line not all paper

CpcHorizon:
        ld a, (TunInside)       ; in a tunnel: its rows are the ceiling (the
        ld hl, CTunWas          ; shadow's cells: noted as it starts)
        cp (hl)
        jr z, .same
        ld (hl), a
        ld b, PANO_ROW0
        ld c, 0
        or a
        jr z, .out
.mark:  call CpcMarkRC          ; (rows 10-11, both screens)
        inc c
        bit 5, c
        jr z, .mark
        ld c, 0
        inc b
        ld a, b
        cp ROAD_ROW0
        jr c, .mark
        ret
.out:   ld a, $FF               ; out again: the panorama drawn afresh
        ld (CPanoA), a
        ld (CPanoB), a
.same:  ld a, (TunInside)
        or a
        ret nz
        ld a, (HorizonX + 1)    ; the scroll: a byte each 4 pixels
        rrca
        rrca
        and $3F
        ld c, a
        ld hl, CPanoA
        ld a, (CpcHidden)
        or a
        jr z, .a
        inc hl
.a:     ld a, (hl)
        cp c
        ret z
        IF FIXED_ELAPSED == 0   ; (one byte behind and the frame already late:
        cp $FF                  ; not now, as the Spectrum's DrawHorizonIfTime;
        jr z, .draw             ; none drawn: always)
        sub c
        inc a                   ; (the benchmark's runs always draw it)
        and $3F
        cp 3
        jr nc, .draw
        ld a, (FrameCount)
        push hl
        ld hl, LastFlip
        sub (hl)
        pop hl
        cp MIN_FRAMES
        ret nc
.draw:  ld a, (hl)
        ENDIF
        ld (hl), c
        inc a                   ; (none drawn: every line; else from the
        ld a, 0                 ; first not all paper)
        jr z, .k
        ld a, (CPanoTop)
.k:     ld b, a                 ; B = the first line, 0-15
        ld a, PANO_H
        sub b
        ret z                   ; an entirely empty panorama on a scroll
        ld (.n + 1), a
        ld a, b                 ; its address: line 80 + B
        and 7
        add a, a
        add a, a
        add a, a
        add a, high (SCR + PANO_ROW0 * SCR_ROW)
        ld d, a
        ld a, b
        and 8
        add a, a
        add a, a
        add a, a
        add a, low (SCR + PANO_ROW0 * SCR_ROW)
        ld e, a
        ld l, b                 ; its source: PANO_CACHE + 64 B
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        push bc
        ld bc, PANO_CACHE
        add hl, bc
        pop bc
        push hl
        pop ix
.n:     ld b, 0
.ln:    push bc
        push de
        ld a, ixl               ; [0, 64 - c) from [c, 64)
        add a, c
        ld l, a
        ld a, ixh
        adc a, 0
        ld h, a
        ld a, 64
        sub c
        push bc
        call LdiN               ; (BC spent)
        pop bc
        push ix                 ; [64 - c, 64) from [0, c)
        pop hl
        ld a, c
        push bc
        call LdiN
        pop bc
        pop de
        ld a, d                 ; the next line: $800 on, or a row on
        add a, high SCR_LINE
        ld d, a
        cp high (SCR + 8 * SCR_LINE)
        jr c, .nr
        sub high (8 * SCR_LINE)
        ld d, a
        ld a, e
        add a, 64
        ld e, a
.nr:    push de
        ld de, 64
        add ix, de
        pop de
        pop bc
        djnz .ln
        ret

; ---- a tunnel's mouth, its way out and the gantry: DrawPortal (shared)
; paints them into the shadow's attributes. Rows 3-11: a changed attribute
; notes its cell (converted then, as the HUD's); rows 10-23: a cell whose
; attribute is not its row's own (PalPano, the road rows' PalGrassL, as
; the display reset left them) is the portal's: drawn solid in its paper's
; pen over the road (or the panorama, which is then drawn afresh), and its
; attribute put back for the next frame's painting.
        ALIGN 32
CSkyAttr:       ds (ROAD_ROW0 - 3) * 32, 0     ; rows 3-11's attributes as last seen
CPortalAny:     db 0
CPortalWas:     db 0            ; GateWas as CpcPortal last saw it
CRowAny:        db 0            ; CRowFull has a row set
CSkyMin:        db 3            ; the sky rows painted since CpcPortal looked
CSkyMax:        db ROAD_ROW0 - 1    ; (RowAttrHL, PaintRaceSky: CSkyPainted)

; (src/tunnelb2.asm RowAttrHL) A = a row the shared code paints: noted.
; Everything kept.
CSkyPainted:
        push hl
        ld hl, CSkyMin
        cp (hl)
        jr nc, .mx
        ld (hl), a
.mx:    inc hl
        cp (hl)
        jr c, .x
        ld (hl), a
.x:     pop hl
        ret

; (Before the road) the road's rows the portal's cells cover from edge to
; edge (no cell with its row's own attribute: DrawPortal just painted
; them), CRowFull: the road leaves them out (src/cpc/road.asm CpcRoad)
CpcPortalRows:
        ld a, (CRowAny)         ; (none, unless found)
        or a
        jr z, .none
        xor a
        ld (CRowAny), a
        ld hl, CRowFull
        ld b, ROAD_ROWS
.clr:   ld (hl), a
        inc hl
        djnz .clr
.none:  ld a, (GateWas)         ; (as CpcPortal: nothing painted, nothing to do)
        ld hl, CPortalWas
        or (hl)
        ret z
        ld a, (PtRow)           ; the rows the portal paints: above PtRow
        sub ROAD_ROW0
        ret c
        ret z
        cp ROAD_ROWS + 1
        jr c, .n
        ld a, ROAD_ROWS
.n:     ld b, a
        ld de, CRowFull
        ld hl, $D800 + ROAD_ROW0 * 32
.row:   push bc
        push hl
        ld a, (PalGrassL)       ; any cell its own?
        ld bc, 32
        cpir
        jr z, .next
        ld a, 1
        ld (de), a
        ld (CRowAny), a
.next:  pop hl
        ld bc, 32
        add hl, bc
        pop bc
        inc de
        djnz .row
        ret

CpcPortal:
        ld a, (GateWas)         ; nothing painted (DrawPortal: a portal, or
        ld hl, CPortalWas       ; the sky put back after one) this frame nor
        ld c, (hl)              ; the last: nothing to see to
        ld (hl), a
        or c
        ret z
.scan:  ld a, (CSkyMin)          ; ---- rows 3-11 the shared code painted
        ld b, a                 ; (CSkyPainted): changed attributes
        ld a, (CSkyMax)
        inc a
        ld (.skEnd + 1), a
        ld a, $FF
        ld (CSkyMin), a
        xor a
        ld (CSkyMax), a
        ld a, b
        cp 3
        jr nc, .s3
        ld b, 3
.s3:    ld a, (.skEnd + 1)
        cp ROAD_ROW0 + 1
        jr c, .s4
        ld a, ROAD_ROW0
        ld (.skEnd + 1), a
.s4:    ld a, b
        ld hl, .skEnd + 1
        cp (hl)
        jr nc, .skDone
        rrca                    ; HL = row B's attributes, DE = CSkyAttr's
        rrca
        rrca
        ld l, a
        and 3
        or high $D800
        ld h, a
        ld a, l
        and $E0
        ld l, a
        push hl
        ld a, b
        sub 3
        ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ld de, CSkyAttr
        add hl, de
        ex de, hl
        pop hl
        ld c, 0                 ; B: row, C: column
.sk:    REPT 4
        ld a, (de)
        cp (hl)
        call nz, .new
        inc e
        inc l
        inc c
        ENDR
        bit 5, c
        jr z, .sk
        ld a, l                 ; (a row: 32 bytes, 32-aligned)
        or a
        jr nz, .sh
        inc h
.sh:    ld a, e
        or a
        jr nz, .sd
        inc d
.sd:    ld c, 0
        inc b
        ld a, b
.skEnd: cp ROAD_ROW0            ; (patched: past the last row painted)
        jr c, .sk
.skDone:
        ld a, (PtRow)           ; ---- rows 10 on: those the portal paints
        cp ROAD_ROW0            ; (above PtRow: src/tunnel.asm DrawPortal)
        jr nc, .pr
        ld a, ROAD_ROW0
.pr:    ld (.last + 1), a
        ; ---- rows 10-23: the portal's cells
        ld hl, $D800 + PANO_ROW0 * 32
        ld b, PANO_ROW0
.r:     ld a, b                 ; the row's own attribute
        cp ROAD_ROW0
        ld a, (PalPano)
        jr c, .own
        ld a, (PalGrassL)
.own:   ld e, a
        ld c, 0
.c:     ld a, (hl)
        cp e
        jr nz, .run
.cn:    inc hl
        inc c
.cc:    bit 5, c
        jr z, .c
        inc b
        ld a, b
.last:  cp 24                   ; (patched: the rows the portal paints)
        jr c, .r
        ret
.new:   ld a, (hl)              ; (a changed attribute: kept, its cell noted)
        ld (de), a
        jp CpcMarkRC
.run:   ld d, a                 ; a run of the portal's cells, one attribute:
        ld a, c                 ; each put back, then drawn at once
        ld (.first + 1), a
.rn:    ld (hl), e
        inc hl
        inc c
        bit 5, c
        jr nz, .re
        ld a, (hl)
        cp d
        jr z, .rn
.re:    push hl
        push bc
        push de
        ld a, c
.first: ld c, 0                 ; (patched: its first column)
        sub c
        ld ixl, a               ; IXL = its cells
        ld a, d
        call CpcSolidRun
        pop de
        pop bc
        pop hl
        ld a, b                 ; over the panorama: drawn afresh next time
        cp ROAD_ROW0
        jr nc, .cc
        push hl
        ld hl, CPanoA
        ld a, (CpcHidden)
        add a, l
        ld l, a
        ld (hl), $FF
        pop hl
        jr .cc

; A = an attribute, B = row, C = column, IXL = cells (1-32): they solid in
; its paper's pen in the hidden screen. All spent.
CpcSolidRun:
        call CpcSolidAt         ; E = the pen's byte, HL = the first byte
        ld a, ixl
        cp 3                    ; (3 cells or more: pushed, a word in 4 us)
        jr c, .stores
        ld c, a                 ; the chain's entry: a push a word (a cell's
        ld a, low CPushEnd      ; two bytes in a line)
        sub c
        ld (.go + 1), a
        ld a, high CPushEnd
        sbc a, 0
        ld (.go + 2), a
        ld a, c                 ; HL = the first line's end
        add a, a
        add a, l
        ld l, a
        jr nc, .e
        inc h
.e:     ld d, e
        ld (CPushSp), sp
        ld iy, .back
        ld b, 8
.pl:    di                      ; (the stack in the screen meanwhile)
        ld sp, hl
.go:    jp CPushEnd             ; (patched)
.back:  ld sp, (CPushSp)
        ei
        ld a, h
        add a, high SCR_LINE
        ld h, a
        djnz .pl
        ret
.stores:
        ld a, ixl
        add a, a
        add a, a                ; (4 bytes of code a cell)
        ld c, a
        ld a, low CStoreEnd
        sub c
        ld (.sgo + 1), a
        ld a, high CStoreEnd
        sbc a, 0
        ld (.sgo + 2), a
        ld b, 8
.l:     push hl
.sgo:   call CStoreEnd          ; (patched: 2 bytes a cell in a line)
        pop hl
        ld a, h
        add a, high SCR_LINE
        ld h, a
        djnz .l
        ret
CStores:
        DUP 64
        ld (hl), e
        inc l
        EDUP
CStoreEnd:
        ret
CPushes:
        DUP 32
        push de
        EDUP
CPushEnd:
        jp (iy)
CPushSp:        dw 0

; The hidden screen's noted cells converted into it, their bits cleared
; (src/cpc/cells.asm: the cells and their bits)
CpcCells:
        call CDirtyHid
        ld b, 0                 ; the row
.row:   ld c, 0                 ; the column
.oct:   ld a, (hl)
        or a
        jr z, .skip
        inc a                   ; (all 8: one colour, all the same? drawn at
        jr nz, .one             ; once, CGroupSolid)
        push hl
        push bc
        call CGroupSolid
        pop bc
        pop hl
        jr nz, .one
        ld d, a                 ; (A = the groups of 8 drawn)
.clr:   ld (hl), 0
        dec d
        jr z, .skip
        inc hl
        ld a, c
        add a, 8
        ld c, a
        jr .clr
.one:   ld a, (hl)
        ld (hl), 0
        push hl
        ld e, a                 ; its 8 cells' bits, from the left
.bit:   sla e
        jr nc, .nb
        push bc
        push de
        call CpcCell
        pop de
        pop bc
.nb:    inc c
        ld a, c
        and 7
        jr nz, .bit
        pop hl
        jr .n8
.skip:  ld a, c
        add a, 8
        ld c, a
.n8:    inc hl
        ld a, c
        cp 32
        jr c, .oct
        inc b
        ld a, (TunInside)       ; (the panorama's rows: in a tunnel only, its
        or a                    ; ceiling; else the panorama, drawn as it is)
        ld a, PANO_ROW0
        jr z, .lim
        ld a, CELL_ROWS
.lim:   cp b
        jr z, .done
        jr nc, .row
.done:  ret

; B = row, C = column (a multiple of 8), HL = their bits (all set): its 8
; cells one attribute, ink as paper? Then they drawn in it at once
; (CpcSolidRun), and the next 8 too while all noted and the same: Z, A =
; the groups of 8; else NZ
CGroupSolid:
        ld (CGBits), hl
        ld a, b                 ; HL = the first's attribute: $D800 + row x 32
        rrca                    ; + column
        rrca
        rrca
        ld l, a
        and 3
        or high $D800
        ld h, a
        ld a, l
        and $E0
        or c
        ld l, a
        ld a, (hl)
        ld e, a                 ; ink as paper?
        rrca
        rrca
        rrca
        xor e
        and 7
        ret nz
        ld d, 7                 ; the other 7 the same?
.same:  inc l
        ld a, (hl)
        cp e
        ret nz
        dec d
        jr nz, .same
        ld a, 1
        ld (CGN), a
.more:  ld a, l                 ; the next 8: in the row, all noted, the same?
        inc a
        and 31
        jr z, .draw
        push hl
        ld hl, (CGBits)
        inc hl
        ld a, (hl)
        ld (CGBits), hl
        pop hl
        inc a
        jr nz, .draw
        push hl
        ld d, 8
.s8:    inc l
        ld a, (hl)
        cp e
        jr nz, .no
        dec d
        jr nz, .s8
        pop af                  ; (HL on: its last)
        ld a, (CGN)
        inc a
        ld (CGN), a
        jr .more
.no:    pop hl
.draw:  ld a, (CGN)
        add a, a
        add a, a
        add a, a
        ld ixl, a
        ld a, e
        call CpcSolidRun
        ld a, (CGN)
        cp a                    ; (Z)
        ret
CGBits:         dw 0
CGN:            db 0

; (src/cpc/cells.asm CpcCell) IXL = paper's byte, IXH = paper ^ ink, DE =
; the cell's bitmap, BC = its first byte: one colour (ink as paper, or no
; ink pixels)? Then drawn in the paper's pen, Z; else NZ (BC, DE kept)
CCellSolid:
        ld a, ixh
        or a
        jr z, .solid
        ld h, d
        ld l, e
        ld a, (hl)
        REPT 7
        inc h
        or (hl)
        ENDR
        ret nz
.solid: ld h, b
        ld l, c
        ld a, ixl
        ld e, a
        DUP 7
        ld (hl), e
        inc l
        ld (hl), e
        dec l
        ld a, h
        add a, high SCR_LINE
        ld h, a
        EDUP
        ld (hl), e
        inc l
        ld (hl), e
        xor a                   ; (Z)
        ret

; A = an attribute, B = row, C = column: the cell solid in its paper's pen
; in the hidden screen. All spent.
CpcSolid:
        call CpcSolidAt
        ld b, 8
.l:     ld (hl), e
        inc l
        ld (hl), e
        dec l
        ld a, h
        add a, high SCR_LINE
        ld h, a
        djnz .l
        ret
; A = an attribute, B = row, C = column -> E = its paper's pen's byte, HL =
; the cell's first byte in the hidden screen
CpcSolidAt:
        rrca
        rrca
        rrca
        and 15                  ; (paper and BRIGHT: bits 3-6)
        bit 3, a
        jr z, .nb
        and 7
        or 8
.nb:    add a, low CSpecPB
        ld l, a
        ld h, high CSpecPB
        ld e, (hl)              ; its byte
        ld a, b                 ; $4000 + row x 64 + column x 2
        rrca
        rrca
        ld l, a
        and $3F
        or high SCR
        ld h, a
        ld a, l
        and $C0
        ld l, a
        ld a, c
        add a, a
        add a, l
        ld l, a
        ret

; ---- colours (SpecHw, CSpecPB: src/cpc/cells.asm)
CPens:          ds 17, 0        ; each pen's colour (and the border's)
; The pens searched for a Spectrum colour, in order
CPenOrder:      db 1, 6, 7, 8, 11, 12, 13, 14, 15, 9, 10, 2, 3, 4, 5, 0

; A = an attribute -> A = its paper's hardware colour (with BRIGHT). HL used.
CpcPaper:
        ld l, a
        and $40
        rrca
        rrca
        rrca
        ld h, a
        ld a, l
        rrca
        rrca
        rrca
        and 7
        or h
        jr CpcHw
; A = an attribute -> A = its ink's hardware colour (with BRIGHT). HL used.
CpcInk: ld l, a
        and $40
        rrca
        rrca
        rrca
        ld h, a
        ld a, l
        and 7
        or h
CpcHw:  add a, low SpecHw
        ld l, a
        ld h, high SpecHw
        ld a, (hl)
        ret

; The pens: the stage's (its art pack: 16 pens and the border as the Gate
; Array's colours, after the panorama and the clouds: tools/make_cpc.py
; stage_art); and each Spectrum colour's pen (CSpecPB)
CpcPalette:
        ld hl, CpcStageInks
        call CpcPens
        ; Outdoor cells use bright cyan (day) or magenta (sunset) as a
        ; sky token. Map it to the same native sky ink as the panorama.
        ld a, (THEME_CACHE + 6)
        rrca
        rrca
        rrca
        and 7
        add a, low CSpecPB + 8
        ld l, a
        ld h, high CSpecPB
        ld a, (PenByte + PEN_SKY)
        ld (hl), a
        ret
; HL = 17 hardware colours: the pens and the border those; each Spectrum
; colour's pen found (CSpecPB)
CpcPens:
        ld de, CPens
        ld bc, GA_PORT
        xor a
.pen:   out (c), a              ; (the pen)
        push af
        ld a, (hl)
        ld (de), a
        or GA_COLOUR
        out (c), a
        pop af
        inc hl
        inc de
        inc a
        cp 17
        jr c, .pen
        ; ---- each Spectrum colour's pen: the first in CPenOrder with its
        ; colour (or bright white's, 15)
        ld c, 0                 ; the colour
.col:   ld a, c
        add a, low SpecHw
        ld l, a
        ld h, high SpecHw
        ld d, (hl)              ; its hardware colour
        ld hl, CPenOrder
        ld b, 16
.find:  ld e, (hl)
        push hl
        ld hl, CPens
        ld a, l
        add a, e
        ld l, a
        jr nc, .f1
        inc h
.f1:    ld a, (hl)
        pop hl
        cp d
        jr z, .got
        inc hl
        djnz .find
        ld e, 2                 ; bright white fallback
.got:   ld a, e                 ; its byte
        add a, low PenByte
        ld l, a
        ld h, high PenByte
        ld a, (hl)
        ld hl, CSpecPB
        ld b, 0
        add hl, bc
        ld (hl), a
        inc c
        ld a, c
        cp 16
        jr c, .col
        ret

; Both screens cleared (A: the byte)
CpcClearBoth:
        ld e, a
        ld a, RAM_A
        call CpcClear
        ld a, RAM_B
        call CpcClear
        jp CpcSelect
; A = a RAM configuration: the screen it puts at $4000 cleared to E
CpcClear:
        push af                 ; (CRamNow: not known while it is ours:
        ld a, $FF               ; src/cpc/tyres.asm)
        ld (CRamNow), a
        pop af
        ld bc, GA_PORT
        out (c), a
        ld (.sp + 1), sp
        ld b, e
        ld c, e
        di
        ld sp, $8000
        ld a, 32                ; 32 x 256 words
.l:     ld d, 0
.w:     push bc
        dec d
        jr nz, .w
        dec a
        jr nz, .l
.sp:    ld sp, 0
        ei
        ret

; (The end of OvResetDisplay, the shadow made afresh) the stage's pens; both
; screens cleared, the panorama made Mode 0, every cell of rows 0-9 (and
; the panorama's, in a tunnel) converted into both
CpcResetDisplay:
        call CpcFrontOff
        call CpcPalette
        ld a, (PenByte + PEN_SKY)
        call CpcClearBoth
        call CpcPanoReset
        ld a, (TunInside)
        ld (CTunWas), a
        ld hl, CSkyAttr         ; (the sky's attributes as they are now)
        ld de, $D800 + 3 * 32
        ex de, hl
        ld bc, (ROAD_ROW0 - 3) * 32
        ldir
        call CpcMarkAll         ; both screens' cells
        ld a, (CpcHidden)
        push af
        ld a, RAM_A
        call .one
        ld a, RAM_B
        call .one
        pop af
        ld (CpcHidden), a
        jp CpcSelect
.one:
        push af                 ; (CRamNow: not known while it is ours:
        ld a, $FF               ; src/cpc/tyres.asm)
        ld (CRamNow), a
        pop af
        ld bc, GA_PORT
        out (c), a
        and 2
        rrca
        ld (CpcHidden), a       ; (as if that one were hidden)
        jp CpcCells
