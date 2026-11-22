; ---------------------------------------------------------------------------
; -DZX_OBJINK (a prototype): traffic and scenery in their own inks
;
; Assembled into each theme pack (tools/make_stages.py, with ZX_OBJINK=1):
; after the header's palette and tune, Inks (a byte per object type, in the
; type directory's order, 0-10: an ink 0-7, or $FF for none of its own),
; then this routine, at THEME_CACHE + 28: the main loop calls it after
; DrawSprites. Bank 2 has no room for it; the theme cache is paged all
; through play. Globals are written @name (the pack is a MODULE).
;
; For each of the back buffer's draw commands, every cell of its box in rows
; 12-23 that is plain grass or road (its attribute the stage's PalGrassL,
; PalGrassD or PalRoad) and not the car's takes the object type's ink. Its
; paper stays, so only the object's pixels (and a centre-line dash in it)
; change colour; an ink the same as the paper is drawn black (white on
; black). Kerb cells keep their ink: the road's pixels in them would change
; colour too. The row's band in the buffer's state page is then made one no
; row has, so the road writes the row's attributes afresh when the buffer
; is next drawn (src/road.asm DrawRoadRow .rangesSame).
; ---------------------------------------------------------------------------
ObjInk:
        ld hl, (@CmdList)
        ld a, (hl)
        or a
        ret z
        inc hl
.cmd:   push af                 ; (A: the commands left)
        push hl
        push hl
        pop ix
        ld a, (ix + 7)          ; the type's ink
        add a, low Inks
        ld l, a
        ld h, high Inks
        ld a, (hl)
        cp 8
        jp nc, .next            ; (none of its own)
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
.row:   cp @ROAD_ROW0           ; (above the road: as they are)
        jr c, .rowNext
        push af
        cp @CAR_ROW             ; the car's rows: not its cells
        sbc a, a
        cpl
        and @CAR_W
        ld (.carW + 1), a
        pop af
        push af
        ld l, a                 ; HL: the attribute of the box's first cell
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ld a, (@AttrHi)
        add a, h
        ld h, a
        ld a, l
        add a, (ix + 1)
        ld l, a
        ld b, (ix + 2)          ; B: its cells across, D: those coloured
        ld d, 0
.cell:  ld a, l
        and 31
        sub @CAR_COL
.carW:  cp 0
        jr c, .skip
        ld e, (hl)              ; plain grass or road?
        ld a, (@PalGrassL)
        cp e
        jr z, .plain
        ld a, (@PalGrassD)
        cp e
        jr z, .plain
        ld a, (@PalRoad)
        cp e
        jr nz, .skip
.plain: ld a, e                 ; its paper's colour
        rrca
        rrca
        rrca
        and 7
.ink:   cp 0                    ; (the object's ink)
        ld a, (.ink + 1)
        jr nz, .put
        or a                    ; the same as the paper: black, or white on
        ld a, 7                 ; black
        jr z, .put
        xor a
.put:   xor e                   ; the ink into the attribute
        and 7
        xor e
        ld (hl), a
        inc d
.skip:  inc l
        djnz .cell
        pop af                  ; (the row)
        push af
        inc d
        dec d
        jr z, .rowDone
        sub @ROAD_ROW0          ; coloured: its attributes afresh next time
        or $80
        ld l, a
        ld a, (@StatePage)
        add a, 2
        ld h, a
        ld (hl), $FF
.rowDone:
        pop af
.rowNext:
        inc a
.last:  cp 0
        jr c, .row
        jr z, .row
.next:  pop hl
        ld de, @CMD_SIZE
        add hl, de
        pop af
        dec a
        jp nz, .cmd
        ret
