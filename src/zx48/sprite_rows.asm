; On the fixed display, keep the previous sprites on screen until their
; background is ready to redraw. Visit the skyline, then the road strips
; from top to bottom. Each strip loses its old sprites only for the time
; it takes to update that strip.
RaceSky:
        xor a
        ld (RaceInk), a
        exx
        ld de, $FFFF
        exx
        ld c, ROAD_Y0
        ld hl, (RaceOldList)
        call SpriteStrip
        ld a, (TunInside)
        or a
        jr z, .day
        ld a, (PanoLastA)
        inc a
        jr nz, .sprites
        ld (PanoLastA), a
        ld hl, $4840
        call PanoramaClear
        jr .sprites
.day:   call DrawHorizonIfTime
.sprites:
        exx
        ld de, $FFFF
        exx
        xor a
        ld c, ROAD_Y0
        ld hl, (CmdList)
        jp SpriteStrip

EraseRaceRow:
        xor a
        ld (RaceInk), a
        ld hl, (RaceOldList)
        ld de, (RaceOldMask)
        jr RaceSpriteRow
PaintRaceRow:
        ld a, 1
        ld (RaceInk), a
        ld hl, (CmdList)
        ld de, (RaceMask)
RaceSpriteRow:
        ld a, (CurRow)
        sub ROAD_ROW0
        add a, a
        add a, e
        ld e, a
        jr nc, .index
        inc d
.index: ex de, hl
        ld c, (hl)
        inc hl
        ld b, (hl)
        ld a, b
        or c
        ret z
        push bc
        exx
        pop de
        exx
        ex de, hl
        ld a, (RaceInk)
        or a
        call nz, PrepareRaceInkRow
        ld a, (CurRow)
        add a, a
        add a, a
        add a, a
        add a, 8
        ld c, a
        sub 8
        ; A = first line, C = first line outside this strip.
SpriteStrip:
        ld (.first + 1), a
        ld a, c
        ld (.limit + 1), a
        ld a, (hl)
        or a
        ret z
        ld b, a
        inc hl
        push hl
        pop ix
.next:  exx
        srl d
        rr e
        exx
        jr nc, .skip
        ld a, (ix + 0)
.limit: cp 0
        jr nc, .skip
        ld c, a
        add a, (ix + 6)
        ld e, a
.first: ld a, 0
        cp e
        jr nc, .skip
        cp c
        jr nc, .top
        ld a, c
.top:   push bc                 ; count and original top
        ld c, a
        ld a, (.limit + 1)
        cp e
        jr c, .bottom
        ld a, e
.bottom:
        sub c
        ld b, a
        ld a, c
        sub (ix + 0)
        ld e, (ix + 4)
        ld d, (ix + 5)
        jr z, .draw
        push bc
        push de
        ld d, a
        ld e, (ix + 2)
        ld a, (ix + 3)
        add a, e
        ld e, a
        ld a, d
        call MulS8U8
        pop de
        add hl, de
        ex de, hl
        pop bc
.draw:  call XorRaceSlice
        ld a, (RaceInk)
        or a
        call nz, InkRaceSprite
        pop bc
        exx
        ld a, d
        or e
        exx
        ret z
.skip:  ld de, CMD_SIZE
        add ix, de
        djnz .next
        ret

; B = lines, C = first y, DE = its source byte. Each road slice is inside
; one character row. The sky can span multiple rows. The opaque car block
; owns its pixels, so neither erase nor redraw can punch holes in it.
XorRaceSlice:
        ld l, (ix + 2)
        ld h, (ix + 1)
        ld a, (ix + 3)
        add a, l
        ld (.stride + 1), a
        ld a, c
        cp CAR_ROW * 8
        jr c, .setup
        ld a, h
        cp CAR_COL
        jr c, .left
        cp CAR_COL + CAR_W
        jr nc, .setup
        ; Starts behind the car. Skip to the right of the block.
        sub CAR_COL + CAR_W
        add a, l
        ret nc
        ret z
        ld a, CAR_COL + CAR_W
        sub h
        ld h, CAR_COL + CAR_W
        push hl
        ld l, a
        ld h, 0
        add hl, de
        ex de, hl
        pop hl
        ld a, (ix + 1)
        sub h
        add a, l
        ld l, a
        jr .setup
.left:  ld a, CAR_COL
        sub h
        cp l
        jr nc, .setup
        ld l, a
.setup: ld a, h
        ld (.column + 1), a
.stride:
        ld a, 0
        sub l
        ld (.step + 1), a
        ld (.roadStep + 1), a
        ld a, l
        add a, a
        add a, a
        add a, l
        neg
        ld (.xor + 1), a
        ld iy, .afterSky
        ld a, c
        cp ROAD_Y0
        jr c, .begin
        ld iy, .roadStep
        ld a, (.roadStep + 1)
        or a
        jr nz, .begin
        ld iy, .roadNext        ; the common case: no clip or row boundary
.begin:
        call .address
.line:
.leftByte:
        ld l, 0
.xor:   jp XorEnd - 256
.afterSky:
.step:  ld a, 0
        add a, e
        ld e, a
        jr nc, .noCarry
        inc d
.noCarry:
        dec b
        ret z
        inc c
        inc h
        ld a, h
        and 7
        call z, .address
        jr .line
.roadStep:
        ld a, 0
        add a, e
        ld e, a
        jr nc, .roadNext
        inc d
.roadNext:
        inc h
        djnz .line
        ret
.address:
        ld a, c
        cp ROAD_Y0
        jr c, .skyAddress
        and 7
        ld hl, (RaceBitmapBase)
        add a, h
        ld h, a
        ld a, l
        jr .column
.skyAddress:
        ld l, c
        ld h, high ScrLo
        ld a, (hl)
        inc h
        ld h, (hl)
.column:
        add a, 0
        ld (.leftByte + 1), a
        ret

SwapRaceSprites:
        ld hl, (RaceOldList)
        ld de, (CmdList)
        ld (RaceOldList), de
        ld (CmdList), hl
        ld hl, (RaceOldMask)
        ld de, (RaceMask)
        ld (RaceOldMask), de
        ld (RaceMask), hl
        ret

RaceOldList:    dw CmdListB
RaceInk:        db 0

PrepareRaceInkRow:
        ld a, (CurRow)
        cp CAR_ROW
        sbc a, a
        cpl
        and CAR_W
        ld (InkRaceSprite.car + 1), a
        ret

; A removed kerb cell inside the new road should already look like empty
; road while its old bitmap is cleared. Keep any surviving kerbs intact.
CoverStaleRaceKerb:
        ld a, l
        and 31
        ld h, a
        ld a, (RowB)
        cp h
        jr z, .inside
        ret nc
.inside:
        ld a, (RowC)
        cp h
        ret c
        ret z
CoverRaceRoadCell:
        ld a, (RaceAttrBase + 1)
        ld h, a
.paper:
        ld (hl), 0
        ret

PrepareRaceRoadCover:
        ld a, (PalRoad)
        and $78
        ld b, a
        rrca
        rrca
        rrca
        and 7
        or b
        ld (CoverRaceRoadCell.paper + 1), a
        ret

; C/D are the previous inner kerb bounds. Delay the new paper only
; when a kerb is taking over a column that used to be road.
FlagRaceKerbAdvance:
        ld a, (RowB)
        cp c
        jr c, .right
        jr nz, .stage
.right: ld a, (RowC)
        cp d
        ret nc
.stage: ld a, 1
        ld (RacePendingAttrs), a
        ret

