; ---------------------------------------------------------------------------
; Traffic: a few cars driving along the track in lanes, slower than the
; player at full speed. Cars the player has passed respawn ahead in a
; random lane. Running into one from behind is a bump: the player drops to
; below its speed and the car is nudged ahead.
; Each car: dw z, db lane x / 4 (signed), db speed.
; ---------------------------------------------------------------------------
N_TRAFFIC       EQU 3
CAR_SIZE        EQU 4
Z_CONTACT       EQU 132         ; a car this close is level with the player's car
HIT_HALFWIDTH   EQU 56          ; |lane - PlayerX| below this: the cars touch
; (LaneOverlap preserves IX)
LANE_X          EQU 14          ; lanes at +-56 bottom-line pixels (x / 4)

InitTraffic:
        ld hl, TrafficInit
        ld de, Traffic
        ld bc, N_TRAFFIC * CAR_SIZE
        ldir
        ret

TrafficInit:
        dw 1500
        db LANE_X, 10
        dw 2700
        db -LANE_X, 13
        dw 3900
        db LANE_X, 9

; Move the cars, respawn the ones left behind, check for contact.
UpdateTraffic:
        ld ix, Traffic
        ld b, N_TRAFFIC
.car:   push bc
        ; z += speed * elapsed
        ld e, (ix + 3)
        ld d, 0
        ld l, (ix + 0)
        ld h, (ix + 1)
        ld a, (Elapsed)
        ld b, a
.mv:    add hl, de
        djnz .mv
        ld (ix + 0), l
        ld (ix + 1), h
        ; z_rel = z - Pos
        ld de, (Pos)
        or a
        sbc hl, de
        bit 7, h
        jr nz, .behind          ; well behind the player
        ld a, h
        cp high 8000
        jr nc, .respawn         ; drove off far ahead
        or a
        jr nz, .next
        ld a, l
        cp Z_CONTACT
        jr nc, .next
        ; level with the player's car: touching?
        call LaneOverlap
        jr nc, .behind
        ; bump: slow the player below this car, nudge the car ahead
        ld a, (ix + 3)
        sub 4
        jr nc, .sp
        xor a
.sp:    ld hl, Speed
        cp (hl)
        jr nc, .slower
        ld (hl), a
.slower:
        ld hl, (Pos)
        ld de, 260
        add hl, de
        ld (ix + 0), l
        ld (ix + 1), h
        ld a, SFX_BUMP
        call PlaySfx
        jr .next
.behind:
.respawn:
        ; somewhere ahead, beyond the scenery horizon: Pos + 3200..4223
        call Random
        and 3
        add a, high 3200
        ld d, a
        call Random
        ld e, a
        ld hl, (Pos)
        add hl, de
        ld (ix + 0), l
        ld (ix + 1), h
        call Random
        ld c, LANE_X
        rra
        jr c, .lane
        ld c, -LANE_X
.lane:  ld (ix + 2), c
        and 7
        add a, 7                ; speed 7..14
        ld (ix + 3), a
.next:  ld bc, CAR_SIZE
        add ix, bc
        pop bc
        dec b
        jp nz, .car
        ret

; Carry set if the object at lane (ix+2) overlaps the player's car.
LaneOverlap:
        ld bc, HIT_HALFWIDTH
; BC = half-width to test against
LaneOverlapBC:
        call CarX
        ld l, a
        rlca
        sbc a, a
        ld h, a
        add hl, hl
        add hl, hl              ; lane x in bottom-line pixels
        ld de, (PlayerX)
        or a
        sbc hl, de
        bit 7, h
        jr z, .pos
        ex de, hl
        ld hl, 0
        or a
        sbc hl, de
.pos:   or a
        sbc hl, bc
        ret

DrawTraffic:
        ld a, TYPE_TRAFFIC
        ld (ObjType), a
        ld ix, Traffic
        ld b, N_TRAFFIC
.car:   push bc
        push ix
        ld l, (ix + 0)
        ld h, (ix + 1)
        ld (ObjZ), hl
        call CarX
        ld (ObjX), a
        ; only cars ahead of the player
        ld de, (Pos)
        or a
        sbc hl, de
        bit 7, h
        jr nz, .skip
        ld de, Z_NEARV
        sbc hl, de
        jr c, .skip
        call DrawObject
.skip:  pop ix
        ld bc, CAR_SIZE
        add ix, bc
        pop bc
        djnz .car
        ret

; 8-bit pseudo-random number in A (xorshift on a 16-bit state)
Random:
        push hl
        ld hl, (RandSeed)
        ld a, h
        rra
        ld a, l
        rra
        xor h
        ld h, a
        ld a, l
        rra
        ld a, h
        rra
        xor l
        ld l, a
        xor h
        ld h, a
        ld (RandSeed), hl
        pop hl
        ret
