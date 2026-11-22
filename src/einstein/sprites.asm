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
;   rows 12-23  the road: the silhouette in the object's own ink (a third of
;               its height each: EObjectInks) over the road cell's colour, in
;               a slot of the row's own. A cell of two colours (a kerb edge,
;               a slot drawn the exact way) gives the one most of its pixels
;               show (EinCellGround), so objects keep their colours across
;               kerbs, where the Spectrum's take the cell's ink.
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
; Only the rows that have any (ENRows, EURows) are copied and cleared.
EinSprCells:
        ld hl, EURows           ; U's rows that N has none in now: cleared
        ld de, ENRows
        ld c, 0                 ; (C: the first of these 8 rows)
.u0:    ld a, (de)
        cpl
        and (hl)
        call nz, .uclr
        inc hl
        inc de
        ld a, c
        add a, 8
        ld c, a
        cp 24
        jr nz, .u0
        ld hl, ENRows           ; N's rows: into U, and cleared
        ld c, 0
.n0:    ld a, (hl)
        or a
        call nz, .ncpy
        inc hl
        ld a, c
        add a, 8
        ld c, a
        cp 24
        jr nz, .n0
        ld hl, ENRows           ; (U's rows now N's; N's none)
        ld de, EURows
        ldi
        ldi
        ldi
        xor a
        ld (ENRows), a
        ld (ENRows + 1), a
        ld (ENRows + 2), a
        ld hl, CmdListB         ; (each cell into U too)
        call .cmds
        ld a, (EURows)          ; the sky's rows (0-9): mirrored
        ld e, a
        ld a, (EURows + 1)
        and 3
        ld d, a                 ; (D E: their rows' bits)
        ld b, 0
        ld hl, EMaskU
.mr:    ld c, 0
        srl d
        rr e
        jr c, .mb0
        inc hl                  ; (none in the row)
        inc hl
        inc hl
        inc hl
        jr .mrn
.mb0:   push de
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
        pop de
.mrn:   ld a, d
        or e
        ret z                   ; (no more rows with any)
        inc b
        jr .mr
; A = 8 rows' bits from row C: those rows of U cleared (BC, DE, HL kept)
.uclr:  push bc
        push hl
.ub:    srl a
        jr nc, .un
        push af
        ld a, c
        add a, a
        add a, a
        ld l, a
        ld h, high EMaskU
        ASSERT low EMaskU == 0
        xor a
        ld (hl), a
        inc l
        ld (hl), a
        inc l
        ld (hl), a
        inc l
        ld (hl), a
        pop af
.un:    inc c
        or a
        jr nz, .ub
        pop hl
        pop bc
        ret
; A = 8 rows' bits from row C: those rows of N into U, and cleared
.ncpy:  push bc
        push de
        push hl
.nb:    srl a
        jr nc, .nn
        push af
        ld a, c
        add a, a
        add a, a
        ld e, a
        ld d, high EMaskU
        add a, low EMaskN
        ld l, a
        ld h, high EMaskN
        ASSERT high EMaskN == high (EMaskN + 24 * MASK_ROW - 1)
        DUP 4
        ld a, (hl)
        ld (de), a
        ld (hl), 0
        inc l
        inc e
        EDUP
        pop af
.nn:    inc c
        or a
        jr nz, .nb
        pop hl
        pop de
        pop bc
        ret
; HL = a command list (a count, then commands): set the cells in N and U
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
        ld a, (hl)              ; divide the projected height into three paint bands
        push af
        srl a
        ld b, a
        srl a
        add a, d
        ld (.middle + 1), a
        add a, b
        ld (.base + 1), a
        inc hl
        ld a, (hl)              ; three inks per object type
        ld b, a
        add a, a
        add a, b
        ld (.type + 1), a
        pop af
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
        jp nc, .done
        push bc
        push de
        push hl
        ld a, 32                ; E columns from C, up to column 31
        sub c
        jp z, .rowDone
        jp c, .rowDone
        cp e
        jr c, .n
        ld a, e
.n:     ld e, a                 ; (E: the row's cells, at least 1)
        push hl                 ; (the row's bit in ENRows and EURows)
        ld a, b
        and 7
        add a, low EBitTab
        ld l, a
        ld h, high EBitTab
        ASSERT high EBitTab == high (EBitTab + 7)
        ld d, (hl)              ; D: its bit
        ld a, b
        rrca
        rrca
        rrca
        and 3
        add a, low ENRows
        ld l, a
        ld a, high ENRows
        adc a, 0
        ld h, a
        ld a, d
        or (hl)
        ld (hl), a
        inc hl
        inc hl
        inc hl
        ld a, d
        or (hl)
        ld (hl), a
        pop hl
        ld a, b                 ; IX: the row's byte of column C in N (U
        add a, a                ; 96 on), D: its bit
        add a, a
        ld d, a
        ld a, c
        rrca
        rrca
        rrca
        and 3
        add a, d
        add a, low EMaskN
        ld ixl, a
        ld a, high EMaskN
        adc a, 0
        ld ixh, a
        ld a, c
        and 7
        add a, low EBitTab
        ld l, a
        ld a, high EBitTab
        adc a, 0
        ld h, a
        ld d, (hl)
        push de
        ld l, 0                 ; L: this mask byte's cells
.mc:    ld a, l
        or d
        ld l, a
        rlc d
        call c, .flush
        dec e
        jr nz, .mc
        call .flush
        pop de
        ld a, b                 ; ---- the cells' ink (rows 10-23: rows above
        cp PANO_ROW0            ; are the sky's own, src/einstein/sky.asm)
        jr c, .rowDone
        add a, a                ; the object's type's, by the third of its
        add a, a                ; height the row's middle line is in
        add a, a
        add a, 4
.middle: cp 0
        ld a, 0
        jr c, .shade
        ld a, b
        add a, a
        add a, a
        add a, a
        add a, 4
.base:  cp 0
        ld a, 1
        jr c, .shade
        inc a
.shade:
.type:  add a, 0
        ld hl, EObjectInks
        ASSERT low EObjectInks == 0
        add a, l
        ld l, a
        ld d, (hl)
        call EinMaterialCell    ; (BC, DE kept)
        ld a, d
.pt:    ld (hl), a
        inc l
        dec e
        jr nz, .pt
.rowDone:
        pop hl
        pop de
        pop bc
        ld a, b
        inc b
        cp h
        jp nz, .row
.done:  pop hl
        pop bc
        dec b
        jp nz, .cmd
        ret
; (L: a mask byte's cells into N and U at IX; IX on, L clear)
.flush: ld a, (ix + 0)
        or l
        ld (ix + 0), a
        ld a, (ix + 24 * MASK_ROW)
        or l
        ld (ix + 24 * MASK_ROW), a
        inc ix
        ld l, 0
        ret

; Last frame's silhouettes out of screen B (src/scenery.asm EraseSprites):
; their lines above the panorama only. Below, screen B holds nothing else,
; and EinSprMask clears each cell as it reads it.
EinErase:
        ld a, PANO_ROW0 * 8
        ld (RunCommand.clipY + 1), a
        call EraseSprites
        ld a, 192
        ld (RunCommand.clipY + 1), a
        ret

; B = row, C = column, IX = a mask: set its bit (BC, DE, IX kept)
EinMaskSet:
        push de
        call EinMaskBit
        or (hl)
        ld (hl), a
        pop de
        ret

; B = row, C = column, IX = a mask -> HL = its byte, A = its bit
EinMaskBit:
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
        add a, low EBitTab
        ld e, a
        ld a, high EBitTab
        adc a, 0
        ld d, a
        ld a, (de)
        ret
EBitTab:        db 1, 2, 4, 8, 16, 32, 64, 128

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
        ret z                   ; none: its names straight from BaseNames
        ld a, b
        add a, low ERowDrawn
        ld l, a
        ld a, high ERowDrawn
        adc a, 0
        ld h, a
        ld (hl), 2              ; (sent from NameBuf)
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

; B = row (10-23), C = column -> EPat: screen B's 8 bytes of the cell (the
; silhouette's pixels), the cell cleared (EinErase leaves these rows to
; this); Z if there are none (BC kept)
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
        ld de, EPat
        push bc
        ld c, 0
        DUP 7
        ld a, (hl)
        ld (de), a
        ld (hl), 0
        or c
        ld c, a
        inc e
        inc h
        EDUP
        ld a, (hl)
        ld (de), a
        ld (hl), 0
        or c
        pop bc
        or a
        ret

; B = row (4-23), C = column -> HL: the projected object's ink for the cell
; (EObjectUpper: rows 4-11, EObjectLower: rows 12-23, each page-aligned).
; BC, DE kept.
EinMaterialCell:
        ld a, b
        sub 12
        jr nc, .low
        add a, 8                ; (rows 4-11: 0-7, x 32)
        rrca
        rrca
        rrca
        or c
        ld l, a
        ld h, high EObjectUpper
        ret
.low:   rrca                    ; (rows 12-23: 0-11, x 32)
        rrca
        rrca
        ld l, a
        and 3
        add a, high EObjectLower
        ld h, a
        ld a, l
        and $E0
        or c
        ld l, a
        ret

; B = row (10-11), C = column. A bare line keeps its panorama pixels and
; colours. A covered line uses the silhouette over the panorama's paper.
EinPanoCell:
        ld a, (TunInside)       ; (in a tunnel these rows are its ceiling: the
        or a                    ; cell only cleared)
        jp nz, EinSprMask
        call EinSprMask
        ret z
        call EinMaterialCell
        ld a, (hl)
        exx                     ; B' = material ink, C' = ink repeated in both nibbles
        ld c, a
        rlca
        rlca
        rlca
        rlca
        ld b, a
        or c
        ld c, a
        exx
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
        ld a, (EPanoCol)        ; the underlying tile can wrap within its own row
        add a, c
        and 31
        ld l, a
        ld a, b
        sub PANO_ROW0
        rrca
        rrca
        rrca
        or l
        ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        push bc                 ; restore row and column for the caller
        ld bc, PANO_CACHE
        add hl, bc
        push hl
        push de
        exx                     ; HL'/DE' follow the two colour planes
        pop hl
        ld de, EPanoInkBuf - EPanoSpr
        add hl, de
        ex de, hl
        pop hl
        inc h
        inc h                   ; source inks start 512 bytes after pixels
        exx                     ; HL/DE follow the two pixel planes
        ld bc, EPat
.ln:    ld a, (bc)
        or a
        jr z, .bare
        ld (de), a
        exx
        ld a, (hl)
        and 15
        or b
        cp c
        jr nz, .ink
        xor $F0
        or $10
        jr .ink
.bare:
        ld a, (hl)
        ld (de), a
        exx
        ld a, (hl)
.ink:   ld (de), a
        inc l                   ; all source and destination cells are 8-aligned
        inc e
        exx
        inc l
        inc e
        inc c
        ld a, c
        and 7
        jr nz, .ln
        ASSERT ((PANO_CACHE | EPanoSpr | EPanoInkBuf | EPat) & 7) == 0
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

; The compositor lists each nonempty tile once, in increasing display order.
; Join adjacent entries for one pattern write and one colour write per run.
EinPanoSend:
        ld a, (EPanoN)
        or a
        ret z
        ld b, a
        ld hl, EPanoList
.run:   ld c, (hl)              ; first tile of this run
        ld a, c
        ld e, 0
.more:  inc e
        inc hl
        dec b                   ; B = entries still to consume
        jr z, .send
        inc a
        cp (hl)
        jr nz, .send
        bit 3, e                ; cap the timed write at 8 tiles (64 bytes)
        jr z, .more
.send:  push bc
        push hl
        ld a, e
        add a, a
        add a, a
        add a, a
        ld l, c
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
        ld b, a
        push bc
        push de
        push hl
        call EinWrite
        pop hl
        ld de, EPanoInkBuf - EPanoSpr
        add hl, de
        pop de
        pop bc
        set 5, d
        call EinWrite
        pop hl
        pop bc
        ld a, b
        or a
        jr nz, .run
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
        ld hl, ERowHi           ; (bit 7: taken from the top down)
        add hl, de
        ld a, (hl)
        and $7F
        ld (ESlotTop), a
        xor (hl)
        rlca
        ld (EDown), a
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
        jp EinPortalCells

; B = a car row (20-23), HL = its names: the car's (CAR_COL on). The paper
; under each of its cells noted (ECarGround); a cell whose paper changed is
; to be recoloured (ECarDirty)
EinCarNames:
        ld a, b
        sub CAR_ROW
        push af                 ; (the car row)
        add a, a
        add a, a
        add a, a
        ld e, a
        ld d, 0
        ld ix, ECarGround
        add ix, de
        add a, CAR_PAT
        ld c, a                 ; C: the car's name
        ld de, CAR_COL
        add hl, de
        ld de, $0100            ; D: the cell's bit, E: the cells changed
        ASSERT CAR_W == 8
.car:   ld a, (hl)              ; the paper under it: a solid cell's colour,
        cp SLOT_FIRST           ; the verge's, or the road's (a kerb edge, a
        jr c, .surface          ; slot)
        cp GROUND_PAT
        jr z, .g0
        cp GROUND_PAT + 1
        ld a, (ECR)
        jr nz, .surface
        ld a, (EGroundPapers + 1)
        jr .surface
.g0:    ld a, (EGroundPapers)
.surface:
        cp (ix)
        jr z, .same
        ld (ix), a
        ld a, e
        or d
        ld e, a
.same:  inc ix
        ld (hl), c
        inc hl
        inc c
        sla d
        jr nc, .car
        pop af
        ld c, a                 ; pose edits already in ECarDirty; only a cell
        ld b, 0                 ; with transparent lines needs a ground edit
.groundMask:
        ld hl, EinCarFrames + 4 ; default at first reset, then the current pose
        add hl, bc
        ld a, (hl)
        and e
        ret z
        ld e, a
        ld a, c
        add a, low ECarDirty
        ld l, a
        ld a, high ECarDirty
        adc a, 0
        ld h, a
        ld a, (hl)
        or e
        ld (hl), a
        ret

; B = row (12-23), C = column under a silhouette: a slot of the row's, the
; road's cell XOR the silhouette, in the cell's colours
EinSprCell:
        call EinSprMask         ; (read, and cleared)
        ret z
        ld a, b                 ; (not the car's cells: its names go over)
        cp CAR_ROW
        jr c, .ok
        ld a, c
        cp CAR_COL
        jr c, .ok
        cp CAR_COL + CAR_W
        ret c
.ok:    ld hl, (EComposePtr)
        ld a, l
        add a, c
        ld l, a
        jr nc, .h
        inc h
.h:     ld (ESprName), hl
        ld a, (hl)              ; the road's name there
        call EinGroundPaper
        cp SLOT_FIRST
        call nc, EinCellGround  ; (two colours: the main one, objcolour.asm)
        push af                 ; one ink band from the projected object
        call EinMaterialCell
        ld e, (hl)
        pop af
        cp e
        jr nz, .contrast
        ld e, 1
        cp e
        jr nz, .contrast
        ld e, 15
.contrast:
        ld d, a
        ld a, e
        rlca
        rlca
        rlca
        rlca
        ld e, d
        or e                    ; (its pixels: the silhouette's, in EPat)
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
ERoadPaperT:    db 0            ; the road's paper and ink (TMS)
ERoadInkT:      db 0
EPanoCol:       db 0            ; the panorama's column at the left edge
EPanoIdx:       db 0
EPanoN:         db 0
ENRows:         ds 3            ; the rows (a bit each) with any in EMaskN,
EURows:         ds 3            ; and in EMaskU (EinSprCells)
        ASSERT EURows == ENRows + 3
ERowLo:         ds 12           ; per road row: its silhouettes' free slots
ERowHi:         ds 12           ; (ESlotN, ESlotTop; ERowHi bit 7: EDown)
