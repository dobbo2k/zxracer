; Behind a crest the mouth can retreat above the skyline. Clear the
; sky rows it used to cover below its new bottom as well as PortalClean's
; rows above its top.
ClearRacePortalTail:
        ld a, (PtRow)
        cp ROAD_ROW0
        jr c, .clip
        ld a, ROAD_ROW0
.clip:  ld c, a
        ld hl, RacePortalSkyEnd
        ld b, (hl)
        ld (hl), a
.row:   ld a, c
        cp b
        ret nc
        push bc
        call RowAttrHL
        call SkyRowAttr
        ld b, 32
        call FillA
        pop bc
        inc c
        jr .row

RacePortalFirst:  db CAR_ROW      ; sentinel for no portal, PtRow is exclusive
RacePortalSkyEnd: db 3
RacePortalRow:    db 0
