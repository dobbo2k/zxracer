; One bit per sprite and road row, in command-list order. Build this from
; the projected list so strips without sprites take the ordinary road path.
IndexRaceSprites:
        ld hl, (RaceMask)
        ld d, h
        ld e, l
        inc de
        ld bc, (24 - ROAD_ROW0) * 2 - 1
        ld (hl), 0
        ldir
        ld hl, (CmdList)
        ld a, (hl)
        or a
        ret z
        inc hl
        push hl
        pop ix
        ld bc, 1
.sprite:
        push af
        ld a, (ix + 0)
        add a, (ix + 6)
        dec a
        cp ROAD_Y0
        jr c, .next
        and $F8
        ld d, a
        ld a, (ix + 0)
        and $F8
        cp ROAD_Y0
        jr nc, .top
        ld a, ROAD_Y0
.top:   ld e, a
        sub ROAD_Y0
        rrca
        rrca
        ld hl, (RaceMask)
        add a, l
        ld l, a
        jr nc, .row
        inc h
.row:   ld a, (hl)
        or c
        ld (hl), a
        inc hl
        ld a, (hl)
        or b
        ld (hl), a
        inc hl
        ld a, e
        cp d
        jr z, .next
        add a, 8
        ld e, a
        jr .row
.next:  ld de, CMD_SIZE
        add ix, de
        sla c
        rl b
        pop af
        dec a
        jr nz, .sprite
        ret

RaceMask:       dw RaceMasksA
RaceOldMask:    dw RaceMasksB
