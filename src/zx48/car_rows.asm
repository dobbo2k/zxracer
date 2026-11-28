; Choose one pose for the frame. Repair any part of the car that the road
; touched before moving on to the next strip.
BeginRaceCar:
        call CarFrame
        ld a, (CarShownA)
        cp c
        ld a, c
        ld (CarShownA), a
        ld a, (CarDirty)
        jr z, .same
        ld a, 1
.same:  ld (RaceNewPose), a
        xor a
        ld (CarDirty), a
        ld a, c
        add a, a
        add a, a
        ld l, a
        ld h, 0
        ld de, CarGfxFrames
        add hl, de
        ld e, (hl)
        inc hl
        ld d, (hl)
        inc hl
        ld (CarTopSrc), de
        ld e, (hl)
        inc hl
        ld d, (hl)
        ld (CarBotSrc), de
        ret

DrawRaceCarRow:
        ld a, (CurRow)
        sub CAR_ROW
        ret c
        ld c, a
        ld a, (RaceNewPose)
        ld hl, CarDirty
        or (hl)
        ret z
        ld (hl), 0
        ld a, c
        ld hl, (CarBotSrc)
        cp 3
        jr z, .source
        rrca
        rrca
        ld e, a
        ld d, 0
        ld hl, (CarTopSrc)
        add hl, de
.source:
        ld de, (RaceBitmapBase)
        ld a, e
        add a, CAR_COL
        ld e, a
        ld b, 8
.line:  push bc
        call PanoLdiEnd - CAR_W * 2
        ld a, e
        sub CAR_W
        ld e, a
        inc d
        pop bc
        djnz .line
        ret

RaceNewPose:    db 0

FinishRaceCar:
        ld a, (RaceNewPose)
        ld hl, CarAttrDirty
        or (hl)
        ret z
        ld hl, (CarTopSrc)
        ld bc, CAR_TOP_PX
        add hl, bc
