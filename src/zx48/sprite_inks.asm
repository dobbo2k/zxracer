; Colour plain terrain only. Kerbs and the skyline stay in their own
; inks. Colour the same way every update, even in a busy fork or tunnel.
InkRaceSprite:
        ld a, (ix + 7)
        add a, low (THEME_CACHE + 17)
        ld l, a
        ld h, high THEME_CACHE
        ld a, (hl)
        cp 8
        ret nc
        ld (.ink + 1), a
        rlca
        rlca
        rlca
        ld (.paper + 1), a
        ld hl, (RaceAttrBase)
        ld a, (ix + 1)
        add a, l
        ld l, a
        ld de, (PalGrassL)
        ld a, (PalRoad)
        ld c, a
        ld b, (ix + 2)
.cell:  ld a, l
        and 31
        sub CAR_COL
.car:   cp 0
        jr c, .skip
        ld a, (hl)
        cp e
        jr z, .terrain
        cp d
        jr z, .terrain
        cp c
        jr nz, .skip
.terrain:
        and $38
.paper: cp 0
.ink:   ld a, 0
        jr nz, .attr
        or a
        ld a, 0
        jr nz, .attr
        ld a, 7
.attr:  xor (hl)
        and 7
        jr z, .skip
        xor (hl)
        ld (hl), a
.skip:  inc l
        djnz .cell
        ; Make RowAttrs restore these terrain cells before the next draw.
        ld a, (CurRow)
        sub ROAD_ROW0
        add a, low RowABand
        ld l, a
        ld h, high RowABand
        ld (hl), $FF
        ret

