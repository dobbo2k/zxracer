; ---------------------------------------------------------------------------
; Einstein: the sky rows (0-11)
;
; Rows 0-2 carry the instruments. In rows 3-9 the moving ink in screen B
; is composited over cached native pattern and colour planes. Tunnel and
; lamp attributes select the ordinary solid/bitmap path. The two panorama
; rows scroll by name, in eight-pixel steps, with separate overlapping cells.
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
        ld a, (EFrontOn)
        or a
        jr nz, .legacy
        ld a, b
        or a
        jr nz, .notHeader
        ld a, c
        sub 14
        cp 4
        ld a, $71
        jr nc, .noFl
        ld a, $F4
        jr .noFl
.notHeader:
        cp 3
        jr c, .legacy
        ld a, (TunInside)
        or a
        jr nz, .legacy
        push bc
        ld c, b
        call SkyRowAttr
        ld l, a
        pop bc
        ld a, (de)
        cp l
        jr nz, .legacy
        ld a, b
        cp MSG_ROW
        jp nz, EinSkyCell
        ld a, c
        sub MSG_COL
        cp MSG_LEN
        jp nc, EinSkyCell
        ld hl, (Message)
        ld de, MsgNone
        or a
        sbc hl, de
        jp z, EinSkyCell
        ld a, $F4              ; white message on blue when one is active
        jr .noFl
.legacy:
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

; B,C = screen cell. EMPat contains only moving ink (object or message).
; Copy the original pair back exactly on each uncovered scanline.
EinSkyCell:
        ld a, b
        sub 3
        ld h, a
        ld a, c
        add a, a
        add a, a
        add a, a
        ld l, a
        ld de, ESkyPixels
        add hl, de
        ld de, ESkyInks - ESkyPixels
        push hl
        add hl, de
        push hl
        pop ix
        pop hl
        ld de, EMPat
        ld iy, ENativeInk
        ld b, 8
.pixels:
        ld a, (de)
        or a
        jr z, .base
        ld c, a
        ld a, (ix)
        and 15
        cp 1
        jr nz, .dark
        or $F0
        jr .ink
.dark:  or $10
.ink:   ld (iy), a
        ld a, c
        jr .p
.base:  ld a, (ix)
        ld (iy), a
        ld a, (hl)
.p:     inc ix
        inc iy
        ld (de), a
        inc hl
        inc de
        djnz .pixels
        pop de
        push de
        ld hl, EMPat
        ld b, 8
        call EinWrite
        pop de
        set 5, d
        ld hl, ENativeInk
        ld b, 8
        jp EinWrite
ENativeInk: ds 8

; ---------------------------------------------------------------------------
; The native Spider owns the bottom third's last 32 patterns (rows 20-23).
CAR_PAT         EQU 256 - 32            ; 224-255
        ASSERT KERB_T2 + KERB_N <= CAR_PAT

; In the vertical blank: a new pose's patterns, and each car row's cells
; recoloured (ECarSend), its first changed cell to its last
EinCarSync:
        ld a, (ECarBlock)
        or a
        jr z, .colours
        xor a
        ld (ECarBlock), a
        ld hl, ECarPix
        ld de, VRAM_PAT + $1000 + CAR_PAT * 8
        push de
        ld b, 128
        call EinWrite
        pop de
        set 7, e
        ld b, 128
        call EinWrite
.colours:
        ld hl, ECarSend
        ld c, 0                 ; C: the row's first cell (0, 8, 16, 24)
.row:   ld a, (hl)
        or a
        jr z, .next
        ld (hl), 0
        push hl
        ld d, a
        ld e, c                 ; E: past its last changed cell
.hi:    inc e
        srl a
        jr nz, .hi
        ld a, d
        ld b, c                 ; B: its first
.lo:    rrca
        jr c, .send
        inc b
        jr .lo
.send:  ld a, e
        sub b
        add a, a
        add a, a
        add a, a
        ld d, a                 ; (bytes: 8 a cell)
        ld a, b
        add a, a
        add a, a
        add a, a
        ld b, d
        push bc
        ld e, a                 ; ECarCol + first * 8 -> its colours' VRAM
        add a, low ECarCol
        ld l, a
        ld a, high ECarCol
        adc a, 0
        ld h, a
        ld d, high (VRAM_COL + $1000 + CAR_PAT * 8)
        ASSERT low (VRAM_COL + $1000 + CAR_PAT * 8) == 0
        call EinWrite
        pop bc
        pop hl
.next:  inc hl
        ld a, c
        add a, 8
        ld c, a
        cp 32
        jr nz, .row
        ret

; ---------------------------------------------------------------------------
; The panorama's patterns: row r (0-1), column c is pattern PANO_PAT +
; r * 32 + c of the middle third (its first copy only: the second's 64
; patterns hold the cells under silhouettes, src/einstein/sprites.asm);
; matching scanline inks for the 64 scrolling patterns
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
        ld hl, PANO_CACHE + 512
        ld de, VRAM_COL + $0800 + PANO_PAT * 8
        ld b, 0
        call VdpWrite
        ld de, VRAM_COL + $0800 + PANO_PAT * 8 + 256
        ld b, 0
        jp VdpWrite

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
EMirrorN:       db 0            ; any cells noted in EMirrorBits
EPanoLast:      db $FF
