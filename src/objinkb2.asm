; ---------------------------------------------------------------------------
; Objects in their own inks (src/objink.asm): its pieces in the table pages'
; holes (bank 2), each in a hole of its own: src/holes.asm includes this
; file once for each, with OBJ_PART saying which
; ---------------------------------------------------------------------------
        IF OBJ_PART == 1
; HL = the back buffer's claim list (A spent)
OListHL:
        ld hl, ClaimA
        ld a, (BufHiOr)
        or a
        ret z
        ld hl, ClaimB
        ret

        ENDIF
        IF OBJ_PART == 2
; A = an attribute -> A: with the object's ink (OInk), or black if that is
; its paper's colour (white on black). BC, DE, HL kept.
OInkOn: push bc
        ld c, a
        rrca
        rrca
        rrca
        and 7
        ld b, a
        ld a, (OInk)
        cp b
        jr nz, .put
        or a
        ld a, 7
        jr z, .put
        xor a
.put:   xor c
        and 7
        xor c
        pop bc
        ret

        ENDIF
        IF OBJ_PART == 3

; After EraseSprites: the cells the buffer's last ObjInk claimed, put back,
; last first: their attributes (a kerb cell's PalKerbL or PalKerbD, the
; sky's and the backdrop's SkyRowAttr), and where their pixels were changed
; the backdrop's from the panorama. (A kerb cell's: drawn again by the road;
; elsewhere EraseSprites has put them back.)
ClaimRestore:
        call OListHL
        ld a, (hl)
        or a
        ret z
        ld (hl), 0
        ld b, a
        add a, a
        ld e, a
        ld d, 0
        add hl, de              ; HL: the last one's high byte
.e:     ld d, (hl)
        dec hl
        ld e, (hl)
        dec hl
        push hl
        push bc
        ex de, hl
        ld a, h                 ; its row: (H & 3) * 8 + L / 32
        and 3
        ld c, a
        ld a, l
        and $E0
        or c
        rlca
        rlca
        rlca
        ld c, a
        cp ROAD_ROW0
        jr c, .sky
        ld a, (PalKerbL)
        bit 2, h
        jr z, .put
        ld a, (PalKerbD)
        jr .put
.sky:   call SkyRowAttr         ; (C: the row; BC, DE, HL kept)
.put:   res 2, h
        bit 5, h                ; (its pixels changed: the backdrop's)
        res 5, h
        ld (hl), a
        call nz, OPanoCellP     ; (src/objinkpack.asm)
        pop bc
        pop hl
        djnz .e
        ret

; HL = the object's byte on the cell's first line with any, E = low OS +
; that line, D = how many (OSrcRow: OSrcC, OSrcN; .st its stride): OS, the
; object's 8 bytes (OS cleared first). Z: none of its pixels here. Else OG,
; the ground's (the cell's XOR them), C: any of them.
OCell:  ld b, d
        ld d, high OS
        ld c, 0
.s:     ld a, (hl)
        ld (de), a
        or c
        ld c, a
        inc e
        ld a, l
.st:    add a, 0                ; (patched by OSrcRow: the stride)
        ld l, a
        jr nc, .s1
        inc h
.s1:    djnz .s
        ld a, c
        or a
        ret z
        ld a, (OPixHi)
        ld h, a
        ld a, (OAttrAt)
        ld l, a
        ld de, OS
        ld bc, $0800
.g:     ld a, (de)
        xor (hl)
        set 3, e
        ld (de), a
        res 3, e
        or c
        ld c, a
        inc h
        inc e
        djnz .g
        or 1                    ; (NZ)
        ret
        ENDIF
        IF OBJ_PART == 4
; C = the ground's pixels on the cell's odd lines (OG + 1, 3, 5, 7: enough
; to tell which colour covers more of it) (B, E, HL spent)
OCount: ld hl, OG + 1
        ld c, 0
.cnt:   ld a, (hl)              ; (NibBits: OG's page)
        ld e, l
        ld b, a
        and 15
        or low NibBits
        ld l, a
        ld a, c
        add a, (hl)
        ld c, a
        ld a, b
        rrca
        rrca
        rrca
        rrca
        and 15
        or low NibBits
        ld l, a
        ld a, c
        add a, (hl)
        ld c, a
        ld l, e
        inc l
        inc l
        bit 3, l
        jr nz, .cnt
        ret
        ENDIF
