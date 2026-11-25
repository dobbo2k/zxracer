; ---------------------------------------------------------------------------
; CPC: the panorama, the portal, the palette and the display reset (in bank
; 2: on the CPC all RAM is as fast)
; ---------------------------------------------------------------------------

; ---- the panorama (rows 10-11): the stage's (PANO_CACHE: the Spectrum's,
; 1 bit a pixel, 256 pixels by 16 lines; and a copy 4 pixels on) made a
; Mode 0 one there at a display reset (64 bytes a line), then drawn into a
; screen when its scroll there is not the one wanted, a byte (the
; Spectrum's 4-pixel step) at a time. In a tunnel its rows are the
; ceiling: the shadow's cells.
PANO_INK        EQU ((PEN_PANO_F & 1) * $C0) | (((PEN_PANO_F >> 1) & 1) * $0C) | (((PEN_PANO_F >> 2) & 1) * $30) | (((PEN_PANO_F >> 3) & 1) * $03)
PANO_PAPER      EQU ((PEN_PANO_N & 1) * $C0) | (((PEN_PANO_N >> 1) & 1) * $0C) | (((PEN_PANO_N >> 2) & 1) * $30) | (((PEN_PANO_N >> 3) & 1) * $03)
CPanoA:         db $FF          ; the byte each screen's panorama starts at
CPanoB:         db $FF          ; ($FF: not drawn)
        ASSERT high CPanoA == high CPanoB
CTunWas:        db 0            ; TunInside as last seen

; PANO_CACHE's first copy made a Mode 0 one in its place (from its end down)
CpcPanoConvert:
        ld hl, PANO_CACHE + 32 * PANO_H - 1
        ld de, PANO_CACHE + 64 * PANO_H - 1
        ld bc, 32 * PANO_H
.b:     ld a, (hl)
        push hl
        ld l, a
        ld h, high CHalf2
        ld a, (hl)              ; its second Mode 0 byte's ink pixels
        and PANO_INK ^ PANO_PAPER
        xor PANO_PAPER
        ld (de), a
        dec de
        dec h
        ld a, (hl)              ; its first's
        and PANO_INK ^ PANO_PAPER
        xor PANO_PAPER
        ld (de), a
        dec de
        pop hl
        dec hl
        dec bc
        ld a, b
        or c
        jr nz, .b
        ld hl, PANO_CACHE       ; its first line not all paper
        ld b, 0
.top:   ld c, 64
.tb:    ld a, (hl)
        inc hl
        cp PANO_PAPER
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
        ld (hl), c
        inc a                   ; (none drawn: every line; else from the
        ld a, 0                 ; first not all paper)
        jr z, .k
        ld a, (CPanoTop)
.k:     ld b, a                 ; B = the first line, 0-15
        ld a, PANO_H
        sub b
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
CSkyAttr:       ds (ROAD_ROW0 - 3) * 32, 0     ; rows 3-11's attributes as last seen
CPortalAny:     db 0

CpcPortal:
        ld hl, (TunEnd)         ; a tunnel or the gantry on this stage?
        ld a, h
        or l
        jr nz, .scan
        ld hl, (GateZ)
        ld a, h
        and l
        inc a
        ret z
.scan:  ld hl, $D800 + 3 * 32   ; ---- rows 3-11: changed attributes
        ld de, CSkyAttr
        ld bc, 3 * 256          ; B: row, C: column
.sk:    ld a, (de)
        cp (hl)
        jr z, .skn
        ld a, (hl)
        ld (de), a
        call CpcMarkRC
.skn:   inc hl
        inc de
        inc c
        bit 5, c
        jr z, .sk
        ld c, 0
        inc b
        ld a, b
        cp ROAD_ROW0
        jr c, .sk
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
        jr z, .cn
        ld (hl), e              ; (put back)
        push hl
        push bc
        push de
        call CpcSolid
        pop de
        pop bc
        pop hl
        ld a, b                 ; over the panorama: drawn afresh next time
        cp ROAD_ROW0
        jr nc, .cn
        push hl
        ld hl, CPanoA
        ld a, (CpcHidden)
        add a, l
        ld l, a
        ld (hl), $FF
        pop hl
.cn:    inc hl
        inc c
        bit 5, c
        jr z, .c
        inc b
        ld a, b
        cp 24
        jr c, .r
        ret

; A = an attribute, B = row, C = column: the cell solid in its paper's pen
; in the hidden screen. All spent.
CpcSolid:
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

; The pens from the stage's palette (the Spectrum's attributes, Palette:
; src/vars.asm), until the CPC's own (docs/port_cpc.md phase A); and each
; Spectrum colour's pen (CSpecPB)
CpcPalette:
        ld ix, CPalSrc
        ld e, 0                 ; the pen
.pen:   ld l, (ix + 0)          ; its attribute's address (0: a colour)
        ld h, (ix + 1)
        ld a, h
        or l
        ld a, (ix + 2)          ; 0: its paper, 1: its ink; or the colour
        jr z, .set
        or a
        ld a, (hl)
        jr nz, .ink
        call CpcPaper
        jr .set
.ink:   call CpcInk
.set:   ld bc, GA_PORT
        out (c), e
        ld b, 0
        ld c, e
        ld hl, CPens
        add hl, bc
        ld (hl), a
        ld bc, GA_PORT
        or GA_COLOUR
        out (c), a
        ld bc, 3
        add ix, bc
        inc e
        ld a, e
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
        ld e, 15
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

; Per pen (and the border, 16): the attribute it takes its colour from, and
; 0 for its paper or 1 its ink; or 0 and the hardware colour
CPalSrc:
        dw PalRoad
        db 0                    ; 0 road: the road's paper
        dw 0
        db $14                  ; 1 black
        dw PalKerbL
        db 0                    ; 2 the light kerb
        dw PalKerbD
        db 0                    ; 3 the dark kerb
        dw PalGrassL
        db 0                    ; 4 light grass
        dw PalGrassD
        db 0                    ; 5 dark grass
        dw PalSky
        db 0                    ; 6 sky
        dw PalPano
        db 1                    ; 7 the panorama: its ink
        dw PalPano
        db 0                    ; 8 its paper
        dw TunWall
        db 0                    ; 9 a tunnel's light wall
        dw TunWall + 1
        db 0                    ; 10 its dark wall
        dw PalHud
        db 1                    ; 11 the HUD's ink
        dw PalTime
        db 1                    ; 12 the timer's ink
        dw PalRoad
        db 1                    ; 13 the centre line: the road's ink
        dw 0
        db $0A                  ; 14 bright yellow: a tunnel's lamps and arch
        dw 0
        db $0B                  ; 15 bright white
        dw 0
        db $14                  ; the border: black

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
        call CpcPanoConvert
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
.one:   ld bc, GA_PORT
        out (c), a
        and 2
        rrca
        ld (CpcHidden), a       ; (as if that one were hidden)
        jp CpcCells
