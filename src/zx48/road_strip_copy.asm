; The unused last 32 bytes of eight consecutive table pages make one
; compatible bitmap strip. The fork workspaces live in the ScrLo/Hi holes
; and Difficulty is in the first half of ZPage on this target.
RaceBitmapShadow EQU X1Page + $E0
RaceAttrScratch  EQU ObjPage + $E0
        ASSERT LWPage == X1Page + $100 && ZPage == X1Page + $200
        ASSERT ZHiPage == X1Page + $300 && DEPage == X1Page + $400
        ASSERT LXPage == X1Page + $500 && CXPage == X1Page + $600
        ASSERT DE2Page == X1Page + $700 && SizeForLine_end <= RaceAttrScratch

ShowRaceStrip:
        ld a, (RaceBitmapBase + 1)
        cp high RaceBitmapShadow
        ret nz
        ; Copy against the scan direction, then publish the finished inks.
        ld hl, RaceBitmapShadow + $700
.bitmap:
        ld de, 0
        ld a, d
        add a, 7
        ld d, a
        call CopyRaceStrip
        ld hl, RaceAttrScratch
.attrs: ld de, 0
        jp PanoLdiEnd - 64

CopyRaceStrip:
        ld a, 8
.line:  push hl
        push de
        call PanoLdiEnd - 64
        pop de
        pop hl
        dec h
        dec d
        dec a
        jr nz, .line
        ret

GetRaceDisplayRow:
        add a, a
        add a, a
        add a, a
        ld l, a
        ld h, high ScrLo
        ld e, (hl)
        inc h
        ld d, (hl)
        ret

; Apply the portal to the staged ground attributes, never to a road
; row that has already been published. Invalidate the row's terrain
; cache so any parts the portal exposes next frame get their inks back.
InkRacePortalRow:
        ld a, (RacePortalRow)
        or a
        ret z
        ld a, (CurRow)
        ld (PtR), a
        sub ROAD_ROW0
        add a, low RowABand
        ld l, a
        ld h, high RowABand
        ld (hl), $FF
        ld a, (PtR)
        ld c, a
        ld hl, ForkCls
        call PortalRow.kind
        ld a, (PtGate)
        or a
        ret z
        ld a, (PtR)
        ld c, a
        ld hl, PtTop
        cp (hl)
        ret nc
        ld hl, ForkCls
        jp Chequer.place
