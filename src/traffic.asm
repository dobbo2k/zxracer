; ---------------------------------------------------------------------------
; Traffic: cars, vans and lorries driving along the track in two lanes,
; slower than the player at full speed. Vehicles the player has passed
; respawn ahead in a random lane; now and then one changes lanes. The row of
; the pyramid sets how many there are, the mix and how often they change
; lanes (TrafficRows). Running into one from behind is a bump - the player
; drops below its speed and it is nudged ahead - unless it is much slower:
; then the car spins out (a crash).
; Each vehicle: dw z, db lane x / 4 (signed), db speed, db class (0 car,
; 1 van, 2 lorry), db the lane x / 4 it is heading for.
; ---------------------------------------------------------------------------
N_TRAFFIC       EQU 5           ; at most (the row says how many)
CAR_SIZE        EQU 6
Z_CONTACT       EQU 132         ; a vehicle this close is level with the player's car
HIT_WIDEST      EQU 58          ; the widest class's half-width (bottom-line pixels)
LANE_X          EQU 14          ; lanes at +-56 bottom-line pixels (x / 4)
SPIN_DIFF       EQU 7           ; hitting one this much slower spins the car out
SPIN_NUDGE      EQU 400         ; how far ahead it goes after a spin (a bump: 260)

; Per class: sprite type, half-width for contact, speed = base + random & mask
ClassTab:
        db TYPE_TRAFFIC, 56, 7, 7       ; car: 7-14
        db TYPE_VAN, HIT_WIDEST, 6, 3   ; van: 6-9
        db TYPE_TRUCK, HIT_WIDEST, 5, 3 ; lorry: 5-8

; IX = vehicle -> HL = its ClassTab entry
ClassOf:
        ld a, (ix + 4)
        add a, a
        add a, a
        add a, low ClassTab
        ld l, a
        adc a, high ClassTab
        sub l
        ld h, a
        ret

; Move the vehicles, respawn the ones left behind, check for contact.
UpdateTraffic:
        ld ix, Traffic
        ld a, (NTraffic)
        ld b, a
.car:   push bc
        ; changing lanes: a step towards the lane it is heading for
        ld a, (ix + 5)
        sub (ix + 2)
        jr z, .inLane
        ld a, 1
        jp p, .step
        ld a, -1
.step:  add a, (ix + 2)
        ld (ix + 2), a
        jr .move
.inLane:
        call Random             ; now and then, set off for the other lane
        ld hl, LaneChance
        cp (hl)
        jr nc, .move
        ld a, (ix + 5)
        neg
        ld (ix + 5), a
.move:  ; z += speed * elapsed
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
        jr nz, .respawn         ; well behind the player
        ld a, h
        cp high 8000
        jr nc, .respawn         ; drove off far ahead
        or a
        jr nz, .next
        ld a, l
        cp Z_CONTACT
        jr nc, .next
        ; level with the player's car: touching? (not after a crash)
        ld a, (CrashTimer)
        or a
        jr nz, .respawn
        call LaneOverlap
        jr nc, .respawn         ; passed
        ld a, (Speed)
        sub (ix + 3)
        jr c, .bump
        cp SPIN_DIFF
        jr c, .bump
        ; much faster than it: the car spins out
        ld a, CRASH_FRAMES
        ld (CrashTimer), a
        ld (Spin), a
        call CrewPickTraffic
        ld a, (Speed)           ; the crash, as hard as the car hit
        call CrashStart
        ld de, SPIN_NUDGE
        ld hl, (Pos)
        add hl, de
        ld (ix + 0), l
        ld (ix + 1), h
        jr .next
.bump:  ; slow the player below it, nudge it ahead
        ld a, (ix + 3)
        sub 4
        jr nc, .sp
        xor a
.sp:    ld hl, Speed
        cp (hl)
        jr nc, .slower
        ld (hl), a
.slower:
        ld a, SFX_BUMP
        ld de, 260
.nudge: ld hl, (Pos)
        add hl, de
        ld (ix + 0), l
        ld (ix + 1), h
        call PlaySfx
        jr .next
.respawn:
        call Respawn
.next:  ld bc, CAR_SIZE
        add ix, bc
        pop bc
        dec b
        jp nz, .car
        ret

; Carry set if the vehicle IX overlaps the player's car (preserves IX).
LaneOverlap:
        call ClassOf
        inc hl
        ld c, (hl)
        ld b, 0
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
        ld ix, Traffic
        ld a, (NTraffic)
        ld b, a
.car:   push bc
        push ix
        call ClassOf
        ld a, (hl)
        ld (ObjType), a
        ld l, (ix + 0)
        ld h, (ix + 1)
        ld (ObjZ), hl
        call CarX
        ld (ObjX), a
        ; only vehicles ahead of the player
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
