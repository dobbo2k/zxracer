; Normal kerb spans use the unrolled copier. Switch to the clipped
; copier only for spans that run through the car.
ClipCarKerbs:
        ld a, (RowA)
        cp CAR_COL + CAR_W
        jr nc, .right
        ld a, (RowB)
        cp CAR_COL + 1
        jr c, .right
        ld hl, .leftCopy
        ld (DrawRoadLine.lcall + 1), hl
.right: ld a, (RowC)
        cp CAR_COL + CAR_W
        ret nc
        ld a, (RowD)
        cp CAR_COL + 1
        ret c
        ld hl, .rightCopy
        ld (DrawRoadLine.rcall + 1), hl
        ret
.leftCopy:
        ld a, (RowA)
        ld b, a
        ld a, (RowB)
        jr .width
.rightCopy:
        ld a, (RowC)
        ld b, a
        ld a, (RowD)
.width: sub b
        ret z
        cp STRIP_PAD + 1
        jr c, .count
        ld a, STRIP_PAD
.count: ld b, a
.copy:  ld a, e
        and 31
        sub CAR_COL
        cp CAR_W
        jr c, .skip
        ld a, (hl)
        ld (de), a
        inc d
        ld (de), a
        dec d
.skip:  inc e
        inc l
        djnz .copy
        ret
