; ---------------------------------------------------------------------------
; Traffic and scenery in their own inks, in front of the road and the
; backdrop (-DZX_OBJINK, the default). ObjInk and OClaim are resident in
; bank 5; ClaimRestore, the rest and their data in the table pages' holes
; (src/objinkb2.asm, src/holes.asm); OSrcRow and OPanoCell in every theme
; pack (src/objinkpack.asm).
;
; DrawSprites XORs each object's silhouette into the back buffer, where it
; takes the ink of whatever cell it is in: a kerb cell's black, the
; backdrop's mountains' or the clouds'; and where it crosses the ground's
; own pixels (a kerb cell's road, the mountains) they show through it.
; After it, each cell of a draw command's box (the first command's first:
; traffic, then the nearest scenery) that is still the ground's own takes
; the object's ink:
;
;   - plain grass or road (rows 12-23: the stage's PalGrassL, PalGrassD or
;     PalRoad), not the car's: its paper kept; the row's band in the
;     buffer's state page is made $FF, so the road writes the row's
;     attributes afresh when the buffer is next drawn;
;   - a kerb cell (PalKerbL, PalKerbD; not in a fork's row: DrawForkRow
;     finds its kerb cells by their attributes), the backdrop's (rows
;     10-11) or the sky's (rows 6-9, below the message line), outside a
;     tunnel: noted in the buffer's claim list, and put back by
;     ClaimRestore when that buffer is next drawn (after EraseSprites).
;
; Where the ground has no pixels of its own in the cell (its pixels are the
; object's XOR alone) the ink is all it takes, its paper kept. Where it has
; (a kerb's road, the mountains) the cell's pixels become the object's
; alone, in its ink, over whichever of the ground's two colours covers more
; of the cell: a car at the road's edge stays on the road's black, a palm
; by the kerb on the kerb's colour. Such a kerb cell's lines are drawn
; again when the buffer is next drawn (their edges in the state page made
; ones pass 1 never makes); the backdrop's pixels are copied back from the
; panorama. The sky's clouds are left as they were (there is no copy of
; them to put back).
;
; An ink the same as the paper it goes on is drawn black (white on black):
; the snowman on white snow, a bush on green grass.
;
; Each object type's ink is in the theme pack (Inks, at THEME_CACHE + 17:
; tools/make_stages.py; $FF for none of its own). Until 25 November 2026
; this routine was in every theme pack too and coloured only plain grass
; and road: objects over the kerbs and the backdrop lost their colour, and
; the road's pixels showed through them.
; ---------------------------------------------------------------------------
OBJ_INKS        EQU THEME_CACHE + 17    ; a type's ink (0-7), $FF: none
OSrcRowP        EQU THEME_CACHE + 28    ; (src/objinkpack.asm: in the theme pack)
OPanoCellP      EQU THEME_CACHE + 31
OBJ_ROW0        EQU 6                   ; the first sky row with objects coloured
CLAIMS          EQU 15                  ; the cells a buffer's claim list holds

ObjInk:
        call OListHL            ; this buffer's claim list: empty (ClaimRestore
        ld (hl), 0              ; has put back the last one's)
        ld (OList), hl
        ld hl, (CmdList)
        ld a, (hl)
        or a
        ret z
        inc hl
.cmd:   push af                 ; (A: the commands left)
        push hl
        push hl
        pop ix
        ld a, (ix + 7)          ; the type's ink
        add a, low OBJ_INKS
        ld l, a
        ld h, high OBJ_INKS
        ld a, (hl)
        cp 8
        jp nc, .next            ; (none of its own)
        ld (OInk), a
        ld (.ink + 1), a
        ld a, (ix + 0)          ; its rows: y / 8 .. (y + h - 1) / 8
        ld b, a
        add a, (ix + 6)
        dec a
        rrca
        rrca
        rrca
        and 31
        ld (.last + 1), a
        ld a, b
        rrca
        rrca
        rrca
        and 31
.row:   cp OBJ_ROW0             ; (above the sky's rows: as they are)
        jp c, .rowNext
        ld (ORow), a
        ld c, a
        xor a
        ld (OSrcOk), a          ; (the object's lines there: found when needed)
        ld a, c
        cp ROAD_ROW0
        jr nc, .road
        ld a, (TunInside)       ; the sky's and the backdrop's rows: their own
        or a                    ; attribute (not in a tunnel: its ceiling)
        jp nz, .rowDone
        call SkyRowAttr
        ld (.sky + 1), a
        ld a, .uc - .disp - 2
        jr .disp0
.road:  add a, low RowFork - ROAD_ROW0  ; (a fork's row: no kerb cells)
        ld l, a
        ld h, high RowFork
        ld a, (hl)
        ld (OFork), a
        ld a, .rc - .disp - 2
.disp0: ld (.disp + 1), a
        ld a, c                 ; the car's rows: not its cells
        cp CAR_ROW
        sbc a, a
        cpl
        and CAR_W
        ld (.carW + 1), a
        ld l, c                 ; HL: the attribute of the box's first cell
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ld a, (AttrHi)
        add a, h
        ld h, a
        ld a, l
        add a, (ix + 1)
        ld l, a
        ld b, (ix + 2)          ; B: its cells across, D: plain ones coloured
        ld d, 0
.cell:  ld a, l
        and 31
        sub CAR_COL
.carW:  cp 0
        jr c, .skip
        ld e, (hl)
.disp:  jr .rc                  ; (patched: .rc in the road's rows, .uc above)
.uc:    ld a, e                 ; the sky's or the backdrop's own?
.sky:   cp 0
        jr nz, .skip
        jr .claim
.rc:    ld a, (PalGrassL)       ; plain grass or road?
        cp e
        jr z, .plain
        ld a, (PalGrassD)
        cp e
        jr z, .plain
        ld a, (PalRoad)
        cp e
        jr z, .plain
        ld a, (PalKerbL)        ; a kerb cell?
        cp e
        jr z, .kerb
        ld a, (PalKerbD)
        cp e
        jr nz, .skip
.kerb:  ld a, (OFork)
        or a
        jr nz, .skip
.claim: call OClaim
        jr .skip
.plain: ld a, e                 ; its ink, the paper kept (black if the same,
        rrca                    ; white on black)
        rrca
        rrca
        and 7
.ink:   cp 0                    ; (patched: the object's ink)
        ld a, (.ink + 1)
        jr nz, .put
        or a
        ld a, 7
        jr z, .put
        xor a
.put:   xor e
        and 7
        xor e
        ld (hl), a
        inc d
.skip:  inc l
        djnz .cell
        ld a, d                 ; plain cells coloured: the row's attributes
        or a                    ; afresh next time
        jr z, .rowDone
        ld a, (ORow)
        sub ROAD_ROW0
        or $80
        ld l, a
        ld a, (StatePage)
        add a, 2
        ld h, a
        ld (hl), $FF
.rowDone:
        ld a, (ORow)
.rowNext:
        inc a
.last:  cp 0
        jp c, .row
        jp z, .row
.next:  pop hl
        ld de, CMD_SIZE
        add hl, de
        pop af
        dec a
        jp nz, .cmd
        ret

; HL = the attribute of a kerb, backdrop or sky cell under the command at
; IX (row ORow), E = it: the object in front of the ground there, the cell
; noted to be put back. BC, DE, HL kept.
OClaim: push hl
        ld hl, (OList)
        ld a, (hl)
        cp CLAIMS
        pop hl
        ret nc                  ; (the list full: the cell as it is)
        push bc
        push de
        push hl
        ld (OAttrAt), hl
        ld a, e
        ld (OAttr), a
        ld a, (OSrcOk)          ; (once a row: the object's lines there)
        or a
        call z, OSrcRowP
        ld hl, 0                ; ---- its 8 bytes in the cell (0 where none)
        ld (OS), hl
        ld (OS + 2), hl
        ld (OS + 4), hl
        ld (OS + 6), hl
        ld a, (OAttrAt)         ; its byte: the cell's column less the command's
        and 31
        sub (ix + 1)
        ld hl, (OSrc)
        add a, l
        ld l, a
        jr nc, .h
        inc h
.h:     ld de, (OSrcC)          ; (E: low OS + the first line, D: how many)
        call OCell              ; (bank 2: its pixels and the ground's)
        jp z, .out              ; (none of its pixels here: as it is)
        ld a, c
        or a
        ld a, (OAttr)
        jr z, .plain            ; none of the ground's: the object's ink, the
                                ; paper kept
        ld a, (ORow)            ; (the sky's clouds: no copy of them to put
        cp PANO_ROW0            ; back)
        jp c, .out
        call OCount             ; the object alone, over the ground's ink if
                                ; it covers more than half the cell, else its
                                ; paper (C: its pixels)
        ld a, (OAttr)
        ld b, a
        and 7
        rlca
        rlca
        rlca
        ld e, a
        ld a, c
        cp 17                   ; (of 32)
        ld a, b
        jr c, .paper
        and $C7
        or e
.paper: call OInkOn
        ld hl, (OAttrAt)
        ld (hl), a
        ld a, (OPixHi)          ; the object's pixels alone
        ld h, a
        ld de, OS
        ld b, 8
.w:     ld a, (de)
        ld (hl), a
        inc e
        inc h
        djnz .w
        ld c, $20               ; (the backdrop's: its pixels to copy back)
        ld a, (ORow)            ; a kerb cell: its lines drawn again next time
        sub ROAD_ROW0
        jr c, .note
        ld c, 0
        add a, a
        add a, a
        add a, a
        ld l, a
        ld a, (StatePage)
        ld h, a
        ld b, 4
.inv:   ld (hl), $FE            ; (D > E: pass 1 makes only $FF, 0 - no road)
        set 7, l
        ld (hl), 0
        res 7, l
        inc l
        inc l
        djnz .inv
        jr .note
.plain: call OInkOn
        ld hl, (OAttrAt)
        cp (hl)
        jr z, .out              ; (the same: nothing to put back)
        ld (hl), a
        ld c, 0                 ; (its pixels as they were)
.note:  ld hl, (OList)          ; ---- noted: its address; in its high byte,
        ld a, (hl)              ; bit 5 (C) its pixels to copy back, bit 2
        inc (hl)                ; the dark kerb's colour
        add a, a
        inc a
        ld e, a
        ld d, 0
        add hl, de
        ld de, (OAttrAt)
        ld a, d
        or c
        ld d, a
        ld a, (PalKerbD)
        ld b, a
        ld a, (OAttr)
        cp b
        jr nz, .k
        set 2, d
.k:     ld (hl), e
        inc hl
        ld (hl), d
.out:   pop hl
        pop de
        pop bc
        ret
