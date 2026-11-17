; ---------------------------------------------------------------------------
; Player car: steering, speed and track position (M1: simple model)
; ---------------------------------------------------------------------------
STEER           EQU 4           ; pixels (at the bottom line) per 50 Hz frame
PX_MAX          EQU 300
MAX_SPEED       EQU 20          ; depth units per 50 Hz frame
ACCEL           EQU 1
DECEL           EQU 1
BRAKE           EQU 2
OFFROAD_X       EQU 150             ; |PlayerX| beyond the kerb
OFFROAD_SPEED   EQU 8

CRASH_FRAMES    EQU 100

UpdatePlayer:
        call GameUpdate
        call DemoDriver
        call CrashUpdate
        ; frames elapsed since the last update (1..4)
        ld a, (FrameCount)
        ld hl, LastLogic
        ld b, a
        sub (hl)
        ld (hl), b
        jr nz, .nz
        inc a
.nz:    cp 5
        jr c, .el
        ld a, 4
.el:    ld (Elapsed), a

        ; centrifugal force: PlayerX.PXFrac -= curve * speed * elapsed / 128
        ld a, (Speed)
        or a
        jr z, .noCF
        ld b, a
        ld a, (SegCurve)
        ld e, a
        rlca
        sbc a, a
        ld d, a
        ld hl, 0
.cfm:   add hl, de
        djnz .cfm
        push hl                 ; horizon scrolls by curve * speed / 256 per frame
        ld a, (Elapsed)
        ld b, a
        ex de, hl
        ld hl, (HorizonX)
.hz:    add hl, de
        djnz .hz
        ld (HorizonX), hl
        pop hl
        add hl, hl              ; delta per 50 Hz frame in 1/256 pixel
        ex de, hl
        ld a, d
        rlca
        sbc a, a
        ld c, a                 ; sign of the delta
        ld a, (Elapsed)
        ld b, a
.cfe:   ld a, (PXFrac)
        sub e
        ld (PXFrac), a
        ld hl, (PlayerX)
        ld a, l
        sbc a, d
        ld l, a
        ld a, h
        sbc a, c
        ld h, a
        ld (PlayerX), hl
        djnz .cfe
.noCF:
        ; steering
        ld a, (Elapsed)
        ld b, a
        ld a, (Input)
        ld c, a
        ld hl, (PlayerX)
.steer: bit IN_LEFT, c
        jr z, .noL
        ld de, -STEER
        add hl, de
.noL:   bit IN_RIGHT, c
        jr z, .noR
        ld de, STEER
        add hl, de
.noR:   djnz .steer
        ; clamp to +-PX_MAX
        bit 7, h
        jr nz, .neg
        ld de, PX_MAX
        or a
        sbc hl, de
        jr c, .inR
        ld hl, 0
.inR:   add hl, de
        jr .px
.neg:   ld de, -PX_MAX
        or a
        sbc hl, de
        jr nc, .inL
        ld hl, 0
.inL:   add hl, de
.px:    ld (PlayerX), hl

        ; speed
        ld a, (Speed)
        bit IN_DOWN, c
        jr z, .noBrake
        sub BRAKE
        jr nc, .noBrake
        xor a
.noBrake:
        bit IN_UP, c
        jr z, .coast
        add a, ACCEL
        cp MAX_SPEED + 1
        jr c, .spd
        ld a, MAX_SPEED
        jr .spd
.coast: sub DECEL
        jr nc, .spd
        xor a
.spd:   ld (Speed), a
        ; off the road (past the kerb): speed limited, sheds speed quickly
        push af
        ld hl, (PlayerX)
        bit 7, h
        jr z, .absX
        ex de, hl
        ld hl, 0
        or a
        sbc hl, de
.absX:  ld de, OFFROAD_X
        or a
        sbc hl, de
        pop af
        ld b, 0
        jr c, .onRoad
        inc b
        cp OFFROAD_SPEED + 1
        jr c, .onRoad
        sub 2
        ld (Speed), a
.onRoad:
        ld a, b
        ld (OffRoad), a
        ld a, (Speed)

        ; position += speed * elapsed
        ld e, a
        ld d, 0
        ld hl, (Pos)
        ld a, (Elapsed)
        ld b, a
.adv:   add hl, de
        jr nc, .noLap
        ld a, 1
        ld (LapFlag), a
.noLap: djnz .adv
        ld (Pos), hl
        call AddScore
        call UpdateTrack
        call EngineUpdate
        call UpdateTraffic
        jp UpdateObjects

; Demo / attract mode: until a steering key is pressed, drive automatically
; (accelerate, steer back towards the middle of the road).
DEMO_DEADBAND   EQU 6

DemoDriver:
        ld a, (DemoMode)
        or a
        ret z
        call DemoTarget         ; HL = PlayerX the driver aims for
        ld de, (PlayerX)
        or a
        sbc hl, de              ; target - PlayerX
        ld a, (Input)
        set IN_UP, a
        ld c, a
        ld de, DEMO_DEADBAND
        add hl, de
        bit 7, h
        jr nz, .left            ; target < PlayerX - deadband: steer left
        ld de, -2 * DEMO_DEADBAND
        add hl, de
        bit 7, h
        jr nz, .set             ; within the deadband
        set IN_RIGHT, c         ; target > PlayerX + deadband
        jr .set
.left:  set IN_LEFT, c
.set:   ld a, c
        ld (Input), a
        ret

; The demo driver keeps to the middle unless a car ahead (within 1200
; units) is in its path; then it aims for the lane on the other side.
DemoTarget:
        ld ix, Traffic
        ld b, N_TRAFFIC
.car:   ld l, (ix + 0)
        ld h, (ix + 1)
        ld de, (Pos)
        or a
        sbc hl, de
        ld a, h
        cp high 1200
        jr nc, .next            ; behind (wrapped) or far ahead
        push bc
        call LaneOverlap        ; carry: in the player's path
        pop bc
        jr nc, .next
        ld hl, -64              ; car right of centre: go left
        bit 7, (ix + 2)
        ret z
        ld hl, 64
        ret
.next:  ld de, CAR_SIZE
        add ix, de
        djnz .car
        ld hl, 0
        ret

; After a crash: no control, the car is stopped and pulled back towards the
; middle of the road; it spins (DrawCar alternates the steering frames).
CrashUpdate:
        ld a, (CrashTimer)
        or a
        ret z
        ld hl, Elapsed
        sub (hl)
        jr nc, .t
        xor a
.t:     ld (CrashTimer), a
        xor a
        ld (Input), a
        ld (Speed), a
        ld hl, (PlayerX)
        ld de, 6
        bit 7, h
        jr nz, .neg
        or a
        sbc hl, de
        jr nc, .set
        ld hl, 0
        jr .set
.neg:   add hl, de
        jr nc, .set             ; still negative
        ld hl, 0
.set:   ld (PlayerX), hl
        ret
