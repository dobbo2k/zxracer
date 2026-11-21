; ---------------------------------------------------------------------------
; Einstein: the sky rows (0-11)
;
; Rows 0-9 mirror the Spectrum's screen B ($C000), where the game's own code
; still draws the HUD, the message line and the sky's artwork. Each of those
; cells has a pattern of its own (rows 0-7 the top third's 256, rows 8-9 the
; middle third's SKY_PAT_T1 on): its 8 bitmap bytes, its attribute's ink and
; paper on all 8 lines. PrintChar and PrintBig mark the cells they write
; (EinMarkCell); RequestFlip sends them.
;
; Rows 10-11 are the panorama: both of its copies (PANO_CACHE: 16 lines of 32
; bytes each, the second 4 pixels on) are patterns, sent at a stage start;
; it scrolls by its 64 names (EinHorizon).
; ---------------------------------------------------------------------------

; HL = a cell's top line in screen B: note it to be sent (all kept)
EinMarkCell:
        push af
        push hl
        ld a, h                 ; the row: its third, then its row in that
        and $18
        ld h, a
        ld a, l
        rlca
        rlca
        rlca
        and 7
        or h
        cp MIRROR_ROWS
        jr nc, .x
        ld h, a
        ld a, l
        and 31
        ld l, a                 ; H = row, L = column
        push de
        call EinMarkHL
        pop de
.x:     pop hl
        pop af
        ret

; B = row, C = column: note the cell to be sent (all kept but AF)
EinMarkRC:
        push hl
        push de
        ld h, b
        ld l, c
        call EinMarkHL
        pop de
        pop hl
        ret

; H = row (0-9), L = column: its bit in EMirrorBits set (a cell noted any
; number of times is sent once; none is ever dropped). A, DE, HL spent.
EinMarkHL:
        ld a, l
        and 7
        add a, low EBitTab
        ld e, a
        ld a, high EBitTab
        adc a, 0
        ld d, a                 ; (DE): its bit
        ld a, h
        add a, a
        add a, a
        ld h, a                 ; row * 4
        ld a, l
        rrca
        rrca
        rrca
        and 3
        add a, h
        add a, low EMirrorBits
        ld l, a
        ld a, high EMirrorBits
        adc a, 0
        ld h, a
        ld a, (de)
        or (hl)
        ld (hl), a
        ld a, 1
        ld (EMirrorN), a
        ret

; The starting lights' cells (src/lampdraw.asm): 2 x 2 cells each, at
; columns LAMP_COL, + 4, + 8 of rows LAMP_ROW and LAMP_ROW + 1
EinLampCells:
        ld b, LAMP_ROW
.r:     ld c, LAMP_COL
.c:     call EinMarkRC
        inc c
        call EinMarkRC
        inc c
        inc c
        inc c
        ld a, c
        cp LAMP_COL + 12
        jr nz, .c
        inc b
        ld a, b
        cp LAMP_ROW + 2
        jr nz, .r
        ret

; Each game frame: FLASH swaps every 16 TV frames (as the Spectrum's); the
; big timer's cells (TimeWarn flashes them) sent again when it does
EinFlash:
        ld a, (FrameCount)
        and 16
        ld hl, EFlashOn
        cp (hl)
        ret z
        ld (hl), a
        ld a, ($D800 + 32 + 14) ; (only while they flash)
        rla
        ret nc
        ld b, 1
.r:     ld c, 14
.c:     call EinMarkRC
        inc c
        ld a, c
        cp 18
        jr nz, .c
        inc b
        ld a, b
        cp 3
        jr nz, .r
        ret

; HL = a big digit's top-left cell (src/extend.asm PrintBig): its four cells
; (all kept: A is the digit)
EinMarkBig:
        push af
        call .four
        pop af
        ret
.four:  call EinMarkCell
        inc l
        call EinMarkCell
        push hl
        ld a, l
        add a, 32
        ld l, a
        call EinMarkCell
        dec l
        call EinMarkCell
        pop hl
        dec l
        ret

; The cells noted (EMirrorBits): into VRAM, all of them. A tunnel's way in
; or out changes the whole sky at once, more than a TV frame of paced
; writes: frames that begin meanwhile are counted, and their sound played.
EinMirror:
        ld a, (EMirrorN)
        or a
        ret z
        xor a
        ld (EMirrorN), a
        ld hl, EMirrorBits
        ld b, 0                 ; B = row, C = column
.r:     ld c, 0
.byte:  ld a, (hl)
        or a
        jr nz, .bits
        ld a, c                 ; (none in these 8)
        add a, 8
        ld c, a
        jr .nb
.bits:  ld e, 1                 ; E: the column's bit
.bit:   ld a, (hl)
        and e
        jr z, .nx
        ld a, e
        cpl
        and (hl)
        ld (hl), a
        push bc
        push de
        push hl
        call EinMirrorCell
        in a, (EIN_VDP_CTRL)    ; a TV frame begun meanwhile (a long list:
        rla                     ; a tunnel's way in or out)? Counted, with
        call c, EinLateFrame    ; its sound
        pop hl
        pop de
        pop bc
.nx:    inc c
        sla e
        jr nz, .bit
.nb:    inc hl
        ld a, c
        cp 32
        jr nz, .byte
        inc b
        ld a, b
        cp MIRROR_ROWS
        jr nz, .r
        ret

; A TV frame begun while the interrupt is still sending (its frame flag
; read): counted, and its sound played, as the interrupt would have
EinLateFrame:
        ld hl, FrameCount
        inc (hl)
        jp SoundTick

; Every cell of rows 0-9 (a new stage, the display off)
EinMirrorAll:
        ld b, 0
.r:     ld c, 0
.c:     push bc
        call EinMirrorCell
        pop bc
        inc c
        ld a, c
        cp 32
        jr nz, .c
        inc b
        ld a, b
        cp MIRROR_ROWS
        jr nz, .r
        ld hl, EMirrorBits      ; (none left to send)
        ld b, MIRROR_ROWS * 4
        xor a
.z:     ld (hl), a
        inc hl
        djnz .z
        ld (EMirrorN), a
        ret

; B = row (0-9), C = column: screen B's cell into its pattern (rows 0-7
; the top third's row * 32 + column, rows 8-9 the middle third's
; SKY_PAT_T1 + (row - 8) * 32 + column)
EinMirrorCell:
        ld a, b
        cp 8
        jr c, .top
        sub 8
        rrca
        rrca
        rrca
        or c
        add a, SKY_PAT_T1
        ld l, a
        ld h, high $0800 / 8    ; (x 8 below: $0800)
        jr EinSendCell
.top:   rrca
        rrca
        rrca
        or c
        ld l, a
        ld h, 0
; B = row, C = column of screen B, HL = the pattern's VRAM address / 8:
; the cell's 8 bitmap bytes there, its attribute's ink over paper on all
; 8 colour lines
EinSendCell:
        add hl, hl
        add hl, hl
        add hl, hl
        push hl
        ld a, b                 ; screen B: $C000 + third * $800 + row in it * 32 + column
        and $18
.scr:   or $C0                  ; (patched: $40, screen A, for the front end)
        ld h, a
        ld a, b
        and 7
        rrca
        rrca
        rrca
        or c
        ld l, a
        ld de, EMPat
        push bc
        ld b, 8
.ln:    ld a, (hl)
        ld (de), a
        inc de
        inc h
        djnz .ln
        pop bc
        ld a, b                 ; its attribute: $D800 + row * 32 + column
        rrca
        rrca
        rrca
        ld l, a
        and $E0
        or c
        ld e, a
        ld a, l
        and 3
.att:   or $D8                  ; (patched: $58)
        ld d, a
        ld a, (de)
        push af
        call AttrInk
        rlca
        rlca
        rlca
        rlca
        ld l, a
        pop af
        push af
        call AttrPaper
        or l
        ld l, a
        pop af                  ; FLASH, in its swapped half: paper over ink
        rla
        ld a, l
        jr nc, .noFl
        ld a, (EFlashOn)
        or a
        ld a, l
        jr z, .noFl
        rrca
        rrca
        rrca
        rrca
.noFl:  ld (EMCol), a
        pop de                  ; the pattern
        push de
        ld hl, EMPat
        ld b, 8
        call EinWrite
        pop hl
        ld de, VRAM_COL
        add hl, de
        ex de, hl
        ld a, (EMCol)
        ld l, a
        ld b, 8
        jp EinFill

; ---------------------------------------------------------------------------
; The player's car: src/car.asm DrawCar draws its 8 x 4 cells into screen B
; (EinCarDirty when it does); they are the bottom third's CAR_PAT on, and
; their names go over the road's in rows 20-23 whenever those are drawn.
CAR_PAT         EQU 256 - 32            ; 224-255
        ASSERT KERB_T2 + KERB_N <= CAR_PAT

; The car's cells into VRAM, if DrawCar drew them: a new frame of it
; (EinCarPrep made it ready) as two blocks, its patterns and colours, else
; only the colours of the cells whose attribute changed (the cockpit's, over
; a new colour underneath)
EinCarSync:
        ld a, (ECarBlock)
        or a
        jr z, .attrs
        xor a
        ld (ECarBlock), a
        ld (EinCarDirty), a
        ld hl, ECarPix          ; (128 bytes a write: the blank's budget counts
        ld de, VRAM_PAT + $1000 + CAR_PAT * 8   ; each)
        ld b, 128
        call EinWrite
        ld de, VRAM_PAT + $1000 + CAR_PAT * 8 + 128
        ld b, 128
        call EinWrite
        ld hl, ECarCol
        ld de, VRAM_COL + $1000 + CAR_PAT * 8
        ld b, 128
        call EinWrite
        ld de, VRAM_COL + $1000 + CAR_PAT * 8 + 128
        ld b, 128
        jp EinWrite
.attrs: ld a, (EinCarDirty)
        or a
        ret z
        xor a
        ld (EinCarDirty), a
        ld hl, $D800 + CAR_ROW * 32 + CAR_COL
        ld de, EinCarAttr
        ld b, CAR_ROW
.ar:    ld c, CAR_COL
.ac:    ld a, (de)
        cp (hl)
        jr z, .an
        ld a, (hl)
        ld (de), a
        push bc
        push de
        push hl
        push af                 ; the colour byte: ink over paper
        call AttrInk
        rlca
        rlca
        rlca
        rlca
        ld l, a
        pop af
        call AttrPaper
        or l
        ld l, a
        ld a, b                 ; VRAM: $3000 + (CAR_PAT + (row - 20) * 8 + column - 12) * 8
        sub CAR_ROW
        add a, a
        add a, a
        add a, a
        add a, c
        add a, CAR_PAT - CAR_COL
        ld e, a
        ld d, high ($3000 / 8)
        ex de, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ex de, hl
        ld b, 8
        call EinFill
        pop hl
        pop de
        pop bc
.an:    inc hl
        inc de
        inc c
        ld a, c
        cp CAR_COL + CAR_W
        jr nz, .ac
        ld a, l
        add a, 32 - CAR_W
        ld l, a
        jr nc, .ah
        inc h
.ah:    inc b
        ld a, b
        cp 24
        jr nz, .ar
        ret


; After DrawCar (the main loop): a new frame of the car (EinCarFull): its 32
; cells' pixels and colours made ready, in pattern order (cell k = (row -
; 20) * 8 + column - 12 at k * 8): ECarPix, ECarCol, sent whole in the next
; vertical blank (EinCarSync); its attributes as sent (EinCarAttr)
EinCarPrep:
        ld a, (EinCarFull)
        or a
        ret z
        xor a
        ld (EinCarFull), a
        ld de, ECarPix
        ld b, CAR_ROW
.r:     ld c, CAR_COL
.c:     ld a, b                 ; screen B's cell (the bottom third)
        and 7
        rrca
        rrca
        rrca
        or c
        ld l, a
        ld h, $D0
        DUP 8
        ld a, (hl)
        ld (de), a
        inc e
        inc h
        EDUP
        push de
        ld a, b                 ; its attribute: $D800 + row * 32 + column
        rrca
        rrca
        rrca
        ld l, a
        and $E0
        or c
        ld e, a
        ld a, l
        and 3
        or $D8
        ld d, a
        ld a, (de)
        pop de
        push de
        push bc
        ld c, a
        ld a, e                 ; (its k: ECarPix's low byte / 8 - 1)
        rrca
        rrca
        rrca
        dec a
        and 31
        ld hl, EinCarAttr
        add a, l
        ld l, a
        jr nc, .ah
        inc h
.ah:    ld (hl), c
        ld a, c                 ; the colour byte: ink over paper
        call AttrInk
        rlca
        rlca
        rlca
        rlca
        ld b, a
        ld a, c
        call AttrPaper
        or b
        pop bc
        pop de
        push de                 ; ECarCol + k * 8: 8 times
        ld hl, ECarCol - ECarPix - 8
        add hl, de
        DUP 8
        ld (hl), a
        inc hl
        EDUP
        pop de
        inc c
        ld a, c
        cp CAR_COL + CAR_W
        jp nz, .c
        inc b
        ld a, b
        cp 24
        jp nz, .r
        ld a, 1
        ld (ECarBlock), a
        ret
ECarBlock:      db 0            ; (ECarPix, ECarCol to be sent)

; ---------------------------------------------------------------------------
; The panorama's patterns: row r (0-1), column c is pattern PANO_PAT +
; r * 32 + c of the middle third (its first copy only: the second's 64
; patterns hold the cells under silhouettes, src/einstein/sprites.asm);
; all of 128-255 in its colours
EinPanoUpload:
        ld de, $0800 + PANO_PAT * 8
        call VdpAddr
        ld hl, PANO_CACHE
        ld b, 2                 ; row
.blk:   push bc
        ld c, 0                 ; column
.col:   push hl
        ld a, l
        add a, c
        ld l, a
        jr nc, .nc
        inc h
.nc:    ld b, 8
.ln:    ld a, (hl)
        out (EIN_VDP_DATA), a   ; (the display is off)
        ld de, 32
        add hl, de
        djnz .ln
        pop hl
        inc c
        ld a, c
        cp 32
        jr nz, .col
        ld de, 32 * 8           ; the next row of cells
        add hl, de
        pop bc
        djnz .blk
        ld a, (PalPano)         ; the colours: ink over paper
        push af
        call AttrInk
        rlca
        rlca
        rlca
        rlca
        ld l, a
        pop af
        call AttrPaper
        or l
        ld l, a
        ld de, VRAM_COL + $0800 + PANO_PAT * 8
        ld bc, 128 * 8
        jp VdpFill

; The panorama's names for its scroll (as src/horizon.asm DrawHorizon, but
; in steps of 8 pixels: one copy; hidden in a tunnel)
EinHorizon:
        ld a, (TunInside)       ; in a tunnel: its ceiling
        or a
        jr nz, EinCeiling
        ld a, (HorizonX + 1)
        and $F8
        ld hl, EPanoLast
        cp (hl)
        ret z
EinHorizonNow:
        and $F8
        ld (EPanoLast), a
        rrca
        rrca
        rrca
        and 31
        ld c, a                 ; C = the column shown at the left
        ld (EPanoCol), a
        ld hl, BaseNames
        ld de, BaseNames + 32
        ld b, 32
.c:     ld a, c
        and 31
        add a, PANO_PAT
        ld (hl), a
        add a, 32
        ld (de), a
        inc hl
        inc de
        inc c
        djnz .c
        ld a, 1
        ld (ERowDrawn + PANO_ROW0), a
        ld (ERowDrawn + PANO_ROW0 + 1), a
        ret
EinCeiling:
        ld hl, EPanoLast        ; (once; $FE: the ceiling's up)
        ld a, $FE
        cp (hl)
        ret z
        ld (hl), a
        ld a, (PalPano)
        call AttrPaper
        ld hl, BaseNames
        ld b, 64
.cl:    ld (hl), a
        inc hl
        djnz .cl
        ld a, 1
        ld (ERowDrawn + PANO_ROW0), a
        ld (ERowDrawn + PANO_ROW0 + 1), a
        ret

EMPat:          ds 8
EMCol:          db 0
EFlashOn:       db 0            ; FLASH cells: ink and paper swapped now
EinCarDirty:    db 1
EinCarFull:     db 1
EinCarAttr:     ds 4 * CAR_W    ; the car's attributes in VRAM
EMirrorN:       db 0            ; any cells noted in EMirrorBits
EPanoLast:      db $FF
