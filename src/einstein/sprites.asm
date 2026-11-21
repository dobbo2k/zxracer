; ---------------------------------------------------------------------------
; Einstein: traffic and scenery
;
; The Spectrum's own code projects them and XORs pre-scaled silhouettes
; into screen B (src/scenery.asm EraseSprites, DrawSprites; CmdListB holds
; the draw commands: y, column, bytes a line, skip, source, height). The
; Spectrum's road is never drawn there, so below the sky screen B holds
; just the silhouettes. Each cell a command covers is put together here:
;
;   rows 0-9    the sky: mirrored as ever (src/einstein/sky.asm)
;   rows 10-11  the panorama: the panorama's pattern XOR the silhouette, in
;               a pattern of the cell's own (the middle third's 192-255)
;   rows 12-23  the road: the road's cell (a solid colour or a slot) XOR the
;               silhouette, in a slot of the row's own. A silhouette takes
;               the cell's ink, as on the Spectrum: black on grass and kerbs,
;               white on the road.
;
; A row is put together again (NameBuf from BaseNames, then its silhouette
; cells, then the car's names) if its road or panorama changed, or a
; silhouette covers or covered it (EMaskU).
; ---------------------------------------------------------------------------
PANO_SPR        EQU 192             ; the panorama rows' cells under a silhouette
MASK_ROW        EQU 4               ; bytes of a mask row: a bit a column

; After DrawSprites: EMaskN, the cells the new commands cover, and EMaskU,
; those and the cells the old ones did (last frame's EMaskN: the commands
; EraseSprites took away); the sky's cells in EMaskU to be mirrored
EinSprCells:
        ld hl, EMaskN           ; U = last frame's N
        ld de, EMaskU
        ld bc, 24 * MASK_ROW
        ldir
        ld hl, EMaskN
        ld de, EMaskN + 1
        ld bc, 24 * MASK_ROW - 1
        ld (hl), 0
        ldir
        ld hl, CmdListB
        ld ix, EMaskN
        call .cmds
        ld hl, EMaskN           ; U |= N
        ld de, EMaskU
        ld b, 24 * MASK_ROW
.u:     ld a, (de)
        or (hl)
        ld (de), a
        inc hl
        inc de
        djnz .u
        ld b, 0                 ; the sky's rows: mirrored
        ld hl, EMaskU
.mr:    ld c, 0
.mb:    ld a, (hl)
        inc hl
        or a
        jr nz, .bits
        ld a, c
        add a, 8
        ld c, a
        jr .mnext
.bits:  ld e, 8
.bit:   rrca
        call c, EinMarkRCa
        inc c
        dec e
        jr nz, .bit
.mnext: ld a, c
        cp 32
        jr nz, .mb
        inc b
        ld a, b
        cp MIRROR_ROWS
        jr nz, .mr
        ret
; HL = a command list (a count, then commands), IX = a mask: set the cells
.cmds:  ld a, (hl)
        or a
        ret z
        ld b, a
        inc hl
.cmd:   push bc
        ld a, (hl)              ; y top
        ld d, a
        inc hl
        ld c, (hl)              ; column
        inc hl
        ld e, (hl)              ; bytes a line
        inc hl
        inc hl
        inc hl
        inc hl
        ld a, (hl)              ; height
        inc hl
        inc hl
        push hl
        add a, d
        dec a                   ; the last line
        rrca
        rrca
        rrca
        and 31
        ld h, a                 ; H = the last row
        ld a, d
        rrca
        rrca
        rrca
        and 31
        ld b, a                 ; B = the row
.row:   ld a, b
        cp 24
        jr nc, .done
        push bc
        ld d, e                 ; D = columns to go
.col:   ld a, c
        cp 32
        jr nc, .rowDone
        push hl
        call EinMaskSet
        pop hl
        inc c
        dec d
        jr nz, .col
.rowDone:
        pop bc
        ld a, b
        inc b
        cp h
        jr nz, .row
.done:  pop hl
        pop bc
        djnz .cmd
        ret

; B = row, C = column, IX = a mask: set its bit (BC, DE, IX kept)
EinMaskSet:
        push de
        ld a, b
        add a, a
        add a, a
        ld e, a
        ld a, c
        rrca
        rrca
        rrca
        and 3
        add a, e
        ld e, a
        ld d, 0
        push ix
        pop hl
        add hl, de
        ld a, c
        and 7
        ld e, a
        ld a, 1
        inc e
.sh:    dec e
        jr z, .set
        rlca
        jr .sh
.set:   or (hl)
        ld (hl), a
        pop de
        ret

; (EinMarkRC, keeping A: for the bit loop above)
EinMarkRCa:
        push af
        call EinMarkRC
        pop af
        ret

; HL = a mask row (4 bytes) -> A: any bit set (Z: none). HL kept
EinMaskAny:
        push hl
        ld a, (hl)
        inc hl
        or (hl)
        inc hl
        or (hl)
        inc hl
        or (hl)
        pop hl
        ret

; B = row -> HL = its row in a mask (IX's)
EinMaskRow:
        ld a, b
        add a, a
        add a, a
        ld e, a
        ld d, 0
        push ix
        pop hl
        add hl, de
        ret

; ---------------------------------------------------------------------------
; The panorama's rows (10-11): put together if their names changed or a
; silhouette covers or covered them
EinPanoCompose:
        xor a
        ld (EPanoN), a
        ld b, PANO_ROW0
.r:     push bc
        call EinComposeStart
        jr z, .next
        ld a, (TunInside)       ; (in a tunnel these rows are its ceiling)
        or a
        jr nz, .portal
        ld ix, EMaskN           ; the cells under a silhouette
        call EinMaskRow
        ld c, 0
.cb:    ld a, (hl)
        inc hl
        or a
        jr nz, .cb8
        ld a, c                 ; (none in these 8)
        add a, 8
        ld c, a
        jr .cbn
.cb8:   ld e, 8
.cbit:  rrca
        jr nc, .cn
        push af
        push de
        push hl
        call EinPanoCell
        pop hl
        pop de
        pop af
.cn:    inc c
        dec e
        jr nz, .cbit
.cbn:   ld a, c
        cp 32
        jr nz, .cb
.portal:
        ld hl, (EComposePtr)    ; then the portal's cells
        call EinPortalCells
.next:  pop bc
        inc b
        ld a, b
        cp ROAD_ROW0
        jr nz, .r
        ret

; B = row: if it changed or a silhouette covers or covered it, its names
; from BaseNames into NameBuf (EComposePtr: its NameBuf row), and its names
; to be sent. Z: nothing to do. (B kept)
EinComposeStart:
        ld ix, EMaskU
        call EinMaskRow
        call EinMaskAny
        ld c, a
        ld a, b
        add a, low ERowDrawn
        ld l, a
        ld a, high ERowDrawn
        adc a, 0
        ld h, a
        ld a, (hl)
        or c
        ret z
        ld (hl), 1
        ld a, b                 ; NameBuf + row * 32, BaseNames + (row - 10) * 32
        rrca
        rrca
        rrca
        ld l, a
        and $E0
        ld e, a
        ld a, l
        and 3
        ld d, a
        ld hl, NameBuf
        add hl, de
        ld (EComposePtr), hl
        push hl
        ld hl, BaseNames - PANO_ROW0 * 32
        add hl, de
        pop de
        push bc
        ld bc, 32
        ldir
        pop bc
        or 1                    ; NZ
        ret

; B = row, C = column -> ESprM: screen B's 8 bytes of the cell (the
; silhouette's pixels); Z if there are none (BC kept)
EinSprMask:
        ld a, b
        and $18
        or $C0
        ld h, a
        ld a, b
        and 7
        rrca
        rrca
        rrca
        or c
        ld l, a
        ld de, ESprM
        push bc
        ld bc, 8 * 256
.ln:    ld a, (hl)
        ld (de), a
        or c
        ld c, a
        inc de
        inc h
        djnz .ln
        ld a, c
        pop bc
        or a
        ret

; B = row (10-11), C = column under a silhouette: its own pattern, the
; panorama's (copy 0, its column EPanoCol + C) XOR the silhouette
EinPanoCell:
        call EinSprMask
        ret z
        ld a, b                 ; EPanoSpr + ((row - 10) * 32 + column) * 8
        sub PANO_ROW0
        rrca
        rrca
        rrca
        or c
        ld (EPanoIdx), a
        ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        ld de, EPanoSpr
        add hl, de
        ex de, hl
        ld a, (EPanoCol)        ; the panorama's bytes: PANO_CACHE + ((row - 10) * 8 + line) * 32 + its column
        add a, c
        and 31
        ld l, a
        ld a, b
        sub PANO_ROW0
        ld h, a                 ; (x 256: 8 lines of 32)
        push bc
        ld bc, PANO_CACHE
        add hl, bc
        ld bc, ESprM
        ld a, 8
.ln:    push af
        ld a, (bc)
        xor (hl)
        ld (de), a
        inc bc
        inc de
        push de
        ld de, 32
        add hl, de
        pop de
        pop af
        dec a
        jr nz, .ln
        pop bc
        ld a, (EPanoN)          ; to be sent
        ld l, a
        inc a
        ld (EPanoN), a
        ld h, 0
        ld de, EPanoList
        add hl, de
        ld a, (EPanoIdx)
        ld (hl), a
        ld hl, (EComposePtr)    ; its name
        ld a, l
        add a, c
        ld l, a
        jr nc, .nm
        inc h
.nm:    ld a, (EPanoIdx)
        add a, PANO_SPR
        ld (hl), a
        ret

; In the vertical blank (RequestFlip): the panorama rows' silhouette cells
EinPanoSend:
        ld a, (EPanoN)
        or a
        ret z
        ld b, a
        ld hl, EPanoList
.c:     push bc
        ld a, (hl)
        inc hl
        push hl
        ld l, a                 ; VRAM: $0800 + (PANO_SPR + idx) * 8, from EPanoSpr + idx * 8
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        push hl
        ld de, $0800 + PANO_SPR * 8
        add hl, de
        ex de, hl
        pop hl
        ld bc, EPanoSpr
        add hl, bc
        ld b, 8
        call EinWrite
        pop hl
        pop bc
        djnz .c
        ret

; ---------------------------------------------------------------------------
; A road row (ERow) after EinDraw: put together if it changed or a
; silhouette covers or covered it; the car's names over rows 20-23
EinRoadCompose:
        ld a, (ERow)
        add a, ROAD_ROW0
        ld b, a
        call EinComposeStart
        ret z
        push bc
        call EinRowSlots        ; the row's slots: the road's, then these
        pop bc
        ld a, (ERow)
        ld e, a
        ld d, 0
        ld hl, ERowLo
        add hl, de
        ld a, (hl)
        ld (ESlotN), a
        ld hl, ERowHi
        add hl, de
        ld a, (hl)
        ld (ESlotTop), a
        ld ix, EMaskN
        call EinMaskRow
        ld c, 0
.cb:    ld a, (hl)
        inc hl
        or a
        jr nz, .cb8
        ld a, c                 ; (none in these 8)
        add a, 8
        ld c, a
        jr .cbn
.cb8:   ld e, 8
.cbit:  rrca
        jr nc, .cn
        push af
        push de
        push hl
        push bc
        call EinSprCell
        pop bc
        pop hl
        pop de
        pop af
.cn:    inc c
        dec e
        jr nz, .cbit
.cbn:   ld a, c
        cp 32
        jr nz, .cb
        ld hl, (EComposePtr)    ; the portal's cells
        call EinPortalCells
        ld a, b                 ; the car's names
        cp CAR_ROW
        ret c
        sub CAR_ROW
        add a, a
        add a, a
        add a, a
        add a, CAR_PAT
        ld hl, (EComposePtr)
        ld de, CAR_COL
        add hl, de
        ld c, CAR_W
.car:   ld (hl), a
        inc hl
        inc a
        dec c
        jr nz, .car
        ret

; B = row (12-23), C = column under a silhouette: a slot of the row's, the
; road's cell XOR the silhouette, in the cell's colours
EinSprCell:
        ld a, b                 ; (not the car's cells: its names go over)
        cp CAR_ROW
        jr c, .ok
        ld a, c
        cp CAR_COL
        jr c, .ok
        cp CAR_COL + CAR_W
        ret c
.ok:    call EinSprMask
        ret z
        ld hl, (EComposePtr)
        ld a, l
        add a, c
        ld l, a
        jr nc, .h
        inc h
.h:     ld (ESprName), hl
        ld a, (hl)              ; the road's name there
        cp SLOT_FIRST
        jr nc, .slot
        ld e, a                 ; a solid colour: the silhouette in its ink
        ld a, (ERoadPaperT)
        cp e
        ld a, (ERoadInkT)
        jr z, .ink
        ld a, 1                 ; (black: grass, kerbs)
.ink:   rlca
        rlca
        rlca
        rlca
        or e
        push af
        ld hl, ESprM
        ld de, EPat
        ld bc, 8
        ldir
        pop af
        jr .commit
.slot:  sub SLOT_FIRST          ; a slot: its index, its pattern and colour
        ld l, a
        ld a, b
        cp 16
        ld a, l
        jr c, .t1
        add a, 4 * SLOTS_T1
.t1:    ld l, a
        ld h, 0
        ld d, h
        ld e, l
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, de
        ld de, SlotShadow
        add hl, de
        ld de, ESprM
        push bc
        ld bc, EPat
        ld a, 8
.x:     push af
        ld a, (de)
        xor (hl)
        ld (bc), a
        inc hl
        inc de
        inc bc
        pop af
        dec a
        jr nz, .x
        pop bc
        ld a, (hl)              ; its colour
.commit:
        call EinCommitSlot
        cp $FF
        ret z
        ld hl, (ESprName)
        ld (hl), a
        ret

; ---------------------------------------------------------------------------
EComposePtr:    dw 0
ESprName:       dw 0
ESprM:          ds 8
ERoadPaperT:    db 0            ; the road's paper and ink (TMS)
ERoadInkT:      db 0
EPanoCol:       db 0            ; the panorama's column at the left edge
EPanoIdx:       db 0
EPanoN:         db 0
EPanoList:      ds 64
EPanoSpr:       ds 64 * 8
ERowLo:         ds 12           ; per road row: its road's slots end, its
ERowHi:         ds 12           ; centre line's begin
EMaskN:         ds 24 * MASK_ROW
EMaskU:         ds 24 * MASK_ROW
        ALIGN 32                ; (a row never crosses a page: EinFillRun)
BaseNames:      ds (24 - PANO_ROW0) * 32    ; rows 10-23 as the road and panorama draw them
