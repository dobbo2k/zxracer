; Compose the scenery-heavy strip just below the skyline off screen.
; The rest of the road uses the faster incremental writer.
BUFFERED_ROAD_ROWS EQU 3
        ASSERT ROAD_ROW0 + BUFFERED_ROAD_ROWS <= CAR_ROW
BeginRaceStrip:
        ld a, (CurRow)
        call GetRaceDisplayRow
        ld (RaceBitmapBase), de
        ; The display's attribute row has the same low byte. Its high
        ; byte comes from the third of the screen the bitmap is in.
        ld a, d
        and $18
        rrca
        rrca
        rrca
        or high RACE_ATTRS
        ld d, a
        ld (RaceAttrBase), de
        ld a, (CurRow)
        sub ROAD_ROW0
        cp BUFFERED_ROAD_ROWS
        ret nc
        add a, a
        ld c, a
        ld b, 0
        jr z, .masks
        ; Projected forks and long frames leave less time for extra copies.
        ; Always give the road's top row first use of the buffer.
        ld a, (RowFork)
        or a
        jr nz, .direct
        ld a, (FrameCount)
        ld hl, LastFlip
        sub (hl)
        cp 2
        ret nc
.masks:
        ld hl, (RaceMask)
        add hl, bc
        ld a, (hl)
        inc hl
        or (hl)
        ld hl, (RaceOldMask)
        add hl, bc
        or (hl)
        inc hl
        or (hl)
        ret z
        ld de, (RaceBitmapBase)
        ld (ShowRaceStrip.bitmap + 1), de
        ld de, (RaceAttrBase)
        ld (ShowRaceStrip.attrs + 1), de
        ld hl, RaceAttrScratch
        ld (RaceAttrBase), hl
        ld hl, RaceBitmapShadow
        ld (RaceBitmapBase), hl
        ld c, 8
        ld b, 32
        xor a
.line:  call FillA
        ld l, low RaceBitmapShadow
        inc h
        dec c
        jr nz, .line
        scf
        ret
.direct:
        or a
        ret

