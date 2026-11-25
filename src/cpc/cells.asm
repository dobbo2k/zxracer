; ---------------------------------------------------------------------------
; CPC: the shadow's cells (docs/port_cpc.md 5.7)
;
; The shared code still draws the HUD, the message line, the starting
; lamps, the pause message, the stage's sky and a tunnel's mouth into the
; Spectrum's screen B at $C000 (bank 7): never shown, a shadow. A cell of
; rows 0-11 it writes is marked (GfxMarkCell and the others, from the
; shared code; CpcSkyScan for the sky's attributes a portal paints), a bit
; for each screen, and each frame the hidden screen's marked cells are
; converted into it (CpcCells): 8 bitmap bytes and an attribute become 8
; lines of 2 Mode 0 bytes, each pair of Spectrum pixels a Mode 0 pixel (ink
; if either is), ink and paper the pens their colours are in (CSpecPB).
; ---------------------------------------------------------------------------

CELL_ROWS       EQU 12              ; rows 0-11: the sky, the HUD, the panorama


; HL = a cell's address in screen B (the shadow): it noted for both
; screens (rows 0-11). Everything kept.
GfxMarkCell:
        push af
        push bc
        ld a, h                 ; the row: its third, then its row in that
        and $18
        ld b, a
        ld a, l
        rlca
        rlca
        rlca
        and 7
        or b
        cp CELL_ROWS
        jr nc, .x
        ld b, a
        ld a, l
        and 31
        ld c, a
        call CpcMarkRC
.x:     pop bc
        pop af
        ret

; B = row (0-11), C = column: the cell noted for both screens. BC kept.
CpcMarkRC:
        push af
        push hl
        push de
        ld a, c                 ; its bit: column & 7
        and 7
        add a, low CBit
        ld l, a
        ld h, high CBit
        ld d, (hl)
        ld a, b                 ; its byte: row x 4 + column / 8
        add a, a
        add a, a
        ld e, a
        ld a, c
        rrca
        rrca
        rrca
        and 3
        add a, e
        add a, low CDirtyA
        ld l, a
        ld h, high CDirtyA
        ld a, d
        or (hl)
        ld (hl), a
        ld a, l
        add a, CDirtyB - CDirtyA
        ld l, a
        ld a, d
        or (hl)
        ld (hl), a
        pop de
        pop hl
        pop af
        ret
CBit:   db $80, $40, $20, $10, $08, $04, $02, $01
        ASSERT high CBit == high (CBit + 7)
        ASSERT high CDirtyA == high (CDirtyB + CELL_ROWS * 4 - 1)

; A big digit's four cells (HL: its top left in the shadow; kept)
GfxMarkBig:
        push af
        call GfxMarkCell
        inc l
        call GfxMarkCell
        push hl
        ld a, l
        add a, 32
        ld l, a
        call GfxMarkCell
        dec l
        call GfxMarkCell
        pop hl
        dec l
        pop af
        ret

; The starting lamps' cells (src/lampdraw.asm: rows LAMP_ROW, LAMP_ROW + 1)
GfxLampCells:
        ld b, LAMP_ROW
.r:     ld c, LAMP_COL
.c:     call CpcMarkRC
        inc c
        ld a, c
        cp LAMP_COL + 12
        jr nz, .c
        inc b
        ld a, b
        cp LAMP_ROW + 2
        jr nz, .r
        ret

; Every cell of rows 0-11 noted for both screens (a display reset)
CpcMarkAll:
        ld hl, CDirtyA
        ld de, CDirtyA + 1
        ld bc, 2 * CELL_ROWS * 4 - 1
        ld (hl), $FF
        ldir
        ret

; Rows B .. C - 1 noted for this screen (the hidden one): its cells there
; covered by something else (an object)
CpcMarkRows:
        call CDirtyHid
.r:     ld a, b
        cp c
        ret nc
        push hl
        ld a, b
        add a, a
        add a, a
        add a, l
        ld l, a
        jr nc, .h
        inc h
.h:     ld (hl), $FF
        inc hl
        ld (hl), $FF
        inc hl
        ld (hl), $FF
        inc hl
        ld (hl), $FF
        pop hl
        inc b
        jr .r

; -> HL = the hidden screen's bits
CDirtyHid:
        ld hl, CDirtyA
        ld a, (CpcHidden)
        or a
        ret z
        ld hl, CDirtyB
        ret

; The hidden screen's noted cells converted into it, their bits cleared
CpcCells:
        call CDirtyHid
        ld b, 0                 ; the row
.row:   ld c, 0                 ; the column
.oct:   ld a, (hl)
        or a
        jr z, .skip
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

; B = row, C = column: the shadow's cell into the hidden screen. All spent.
CpcCell:
        ld a, b                 ; its attribute: $D800 + row x 32 + column
        rrca
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
        ; ink and paper as pens' bytes (FLASH: swapped every 16 TV frames)
        ld e, a
        and 7
        bit 6, e
        jr z, .i
        or 8
.i:     add a, low CSpecPB
        ld l, a
        ld h, high CSpecPB
        ld d, (hl)              ; D = the ink's byte
        ld a, e
        rrca
        rrca
        rrca
        and 7
        bit 6, e
        jr z, .p
        or 8
.p:     add a, low CSpecPB
        ld l, a
        ld a, (hl)              ; A = the paper's
        bit 7, e
        jr z, .nf
        ld l, a
        ld a, (FrameCount)
        and 16
        ld a, l
        jr z, .nf
        ld l, d
        ld d, a
        ld a, l
.nf:    ld ixl, a               ; IXL = paper
        xor d
        ld ixh, a               ; IXH = paper ^ ink
        ; the bitmap: $C000 + (row & $18) x 256 + (row & 7) x 32 + column
        ld a, b
        and $18
        or $C0
        ld d, a
        ld a, b
        rrca
        rrca
        rrca
        and $E0
        or c
        ld e, a
        ; the hidden screen: $4000 + row x 64 + column x 2
        ld a, b
        rrca
        rrca
        ld l, a
        and $3F                 ; (row x 64: row / 4 high, row & 3 x 64 low)
        ld h, a
        ld a, l
        and $C0
        ld l, a
        ld a, c
        add a, a
        add a, l
        ld c, a
        ld a, h
        or $40
        ld b, a                 ; BC = its first byte
        ld h, high CHalf1
        DUP 8
        ld a, (de)              ; 8 Spectrum pixels: 4 Mode 0 pixels
        ld l, a
        ld a, (hl)              ; the first byte's ink pixels
        and ixh
        xor ixl
        ld (bc), a
        inc h
        ld a, (hl)              ; the second's
        dec h
        and ixh
        xor ixl
        inc c
        ld (bc), a
        dec c
        inc d
        ld a, b
        add a, high SCR_LINE
        ld b, a
        EDUP
        ret

; Per Spectrum byte (8 pixels: 4 Mode 0 pixels, each ink if either of its
; two is): the ink pixels of its first Mode 0 byte, then its second's
        ALIGN 256
CHalf1:
bv      DEFL 0
        DUP 256
        db ((((bv >> 7) | (bv >> 6)) & 1) * $AA) | ((((bv >> 5) | (bv >> 4)) & 1) * $55)
bv      DEFL bv + 1
        EDUP
CHalf2:
bv      DEFL 0
        DUP 256
        db ((((bv >> 3) | (bv >> 2)) & 1) * $AA) | ((((bv >> 1) | bv) & 1) * $55)
bv      DEFL bv + 1
        EDUP
; Per screen, per row: its 32 cells' bits (4 bytes), a cell's set if it is
; to be converted into that screen (after CHalf2: at a page's start)
CDirtyA:        ds CELL_ROWS * 4, 0
CDirtyB:        ds CELL_ROWS * 4, 0
; The Spectrum's colours (an attribute's paper or ink, with BRIGHT: 0-15)
; as the Gate Array's
SpecHw: db $14, $04, $1C, $18, $16, $06, $1E, $00     ; black blue red magenta green cyan yellow white
        db $14, $15, $0C, $0D, $12, $13, $0A, $0B     ; and bright
        ASSERT high SpecHw == high (SpecHw + 15)
; Each Spectrum colour: the byte of the pen it is shown in (a pen whose
; colour it is: CpcPalette)
CSpecPB:        ds 16, 0
        ASSERT high CSpecPB == high (CSpecPB + 15)
