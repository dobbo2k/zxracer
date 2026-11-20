; ---------------------------------------------------------------------------
; Player car: steering, sideways momentum and grip, speed, track position
; ---------------------------------------------------------------------------
STEER_ACC       EQU 64          ; sideways acceleration (1/256 px per frame per frame):
                                ; 4 pixels a frame once it has built up
GRIP            EQU 200         ; |curvature * speed| the tyres hold
PX_MAX          EQU 300         ; from the middle of the road (or the branch)
MAX_SPEED       EQU 20          ; depth units per 50 Hz frame
ACCEL           EQU 1
DECEL           EQU 1
BRAKE           EQU 2
OFFROAD_X       EQU 150             ; |PlayerX| beyond the kerb
OFFROAD_SPEED   EQU 8

CRASH_FRAMES    EQU 160         ; (time for her to tell him off, and his reply)

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
        call ForkPlayer         ; past the split: carried along the branch

        ; ---- sideways handling. Per 50 Hz frame the car's sideways speed
        ; LatVX (1/256 pixel per frame) gets the bend's outward push
        ; (curve * speed / 4) and the steering, and the tyres take 1/16 of
        ; it away: so the car settles at 4 * curve * speed outwards and
        ; 4 pixels a frame when steering, but builds up to it over a third
        ; of a second and carries its drift on after a bend. Past the grip
        ; limit (|curve * speed| > GRIP) it slides: an extra push of a
        ; quarter of the excess, half the steering, half the grip.
        ld a, (Speed)
        ld b, a
        ld a, (SegCurve)
        ld e, a
        rlca
        sbc a, a
        ld d, a
        ld hl, 0
        inc b
        dec b
        jr z, .noCF
.cfm:   add hl, de
        djnz .cfm               ; HL = curve * speed
        push hl                 ; horizon scrolls by curve * speed / 256 per frame
        ld a, (Elapsed)
        ld b, a
        ex de, hl
        ld hl, (HorizonX)
.hz:    add hl, de
        djnz .hz
        ld (HorizonX), hl
        pop hl
.noCF:  ld (LatF), hl
        ; push = -(curve * speed) / 4
        ld d, h
        ld e, l
        sra d
        rr e
        sra d
        rr e
        ld hl, 0
        or a
        sbc hl, de
        ld (LatAcc), hl
        ; grip
        ld hl, (LatF)
        call AbsHL
        ld de, GRIP
        or a
        sbc hl, de              ; HL = excess
        ld a, 0
        jr c, .grip
        srl h
        rr l
        srl h
        rr l                    ; a quarter of it
        ex de, hl
        ld hl, (LatF)           ; slide: push -= sign(F) * excess
        bit 7, h
        ld hl, (LatAcc)
        jr nz, .sl
        or a
        sbc hl, de
        jr .sl1
.sl:    add hl, de
.sl1:   ld (LatAcc), hl
        ld a, 1
.grip:  ld (Sliding), a
        ; steering
        ld a, (Input)
        ld c, a
        ld de, 0
        bit IN_LEFT, c
        jr z, .noL
        ld de, -STEER_ACC
.noL:   bit IN_RIGHT, c
        jr z, .noR
        ld hl, STEER_ACC
        add hl, de
        ex de, hl
.noR:   ld a, (Sliding)
        or a
        jr z, .full
        sra d                   ; sliding: half the steering
        rr e
.full:  ld hl, (LatAcc)
        add hl, de
        ld (LatAcc), hl
        ; per 50 Hz frame: speed += push + steering, grip, position
        ld a, (Elapsed)
        ld b, a
.lat:   push bc
        ld hl, (LatVX)
        ld de, (LatAcc)
        add hl, de
        ld d, h
        ld e, l
        sra d
        rr e
        sra d
        rr e
        sra d
        rr e
        sra d
        rr e
        ld a, (Sliding)
        or a
        jr z, .firm             ; sliding: 1/32 instead of 1/16
        sra d
        rr e
.firm:  or a
        sbc hl, de
        ; no push or steering and almost still: stop (no endless creep)
        ld a, (LatAcc)
        ld c, a
        ld a, (LatAcc + 1)
        or c
        jr nz, .vx
        push hl
        ld de, 15
        add hl, de
        ld de, -31
        add hl, de              ; carry unless -15 <= LatVX <= 15
        pop hl
        jr c, .vx
        ld hl, 0
.vx:    ld (LatVX), hl
        ld a, h                 ; PlayerX.PXFrac += LatVX
        rlca
        sbc a, a
        ld d, a
        ld e, h
        ld a, (PXFrac)
        add a, l
        ld (PXFrac), a
        ld hl, (PlayerX)
        adc hl, de
        ld (PlayerX), hl
        pop bc
        djnz .lat
        ld a, (Input)
        ld c, a
        ; clamp to +-(PX_MAX + PlayerDx), stopping the sideways motion
        ld hl, (PlayerDx)
        ld de, PX_MAX
        add hl, de
        ex de, hl
        ld hl, (PlayerX)
        bit 7, h
        jr nz, .neg
        or a
        sbc hl, de
        jr c, .inR
        ld hl, 0
        ld (LatVX), hl
.inR:   add hl, de
        jr .px
.neg:   add hl, de
        jr c, .inL
        ld hl, 0
        ld (LatVX), hl
.inL:   or a
        sbc hl, de
.px:    ld (PlayerX), hl

        ; speed
        ld a, (Speed)
        bit IN_DOWN, c
        jr z, .noBrake
        sub BRAKE
        jr nc, .noBrake
        xor a
.noBrake:
        ld b, a
        ld a, (Sliding)         ; sliding: the tyres scrub speed off
        or a
        ld a, b
        jr z, .grips
        ld hl, SlideTick
        inc (hl)
        bit 0, (hl)
        jr z, .spd
        jr .coast
.grips: bit IN_UP, c
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
        ld hl, (PlayerX)        ; distance from the middle of the branch
        call AbsHL
        ld de, (PlayerDx)
        or a
        sbc hl, de
        call AbsHL
        ld de, OFFROAD_X
        or a
        sbc hl, de
        ld b, 0
        ld a, (Speed)
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
        djnz .adv
        ld (Pos), hl
        ; end of the stage? (the checkpoint is handled by GameUpdate)
        ld de, (StageLen)
        or a
        sbc hl, de
        jr c, .inStage
        ld a, 1
        ld (StageDone), a
.inStage:
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
        push hl
        ld hl, (LatVX)          ; where the car will be in 16 frames
        ld b, 4
.pr:    sra h
        rr l
        djnz .pr
        ld de, (PlayerX)
        add hl, de
        ex de, hl
        pop hl
        or a
        sbc hl, de              ; target - that
        ld a, (Input)
        ld c, a
        ld a, (Sliding)         ; lift off while sliding
        or a
        jr nz, .gas
        set IN_UP, c
.gas:
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
; units) is in its path; then it aims for the lane away from the nearest one.
DemoTarget:
        ; near the fork: take one of the branches (varying by stage)
        ld a, (HasFork)
        or a
        jr z, .traffic
        ld hl, (ForkZ)
        ld de, (Pos)
        or a
        sbc hl, de
        jr c, .branch
        ld de, 1500
        sbc hl, de
        jr nc, .traffic
.branch:
        ld hl, (PlayerDx)
        ld de, 40
        add hl, de
        ld a, (Stage)
        rra
        ret c
        jp NegHL
.traffic:
        ld hl, 1200
        ld (DemoNear), hl
        ld hl, 0
        ld (DemoAim), hl
        ld ix, Traffic
        ld b, N_TRAFFIC
.car:   ld l, (ix + 0)
        ld h, (ix + 1)
        ld de, (Pos)
        or a
        sbc hl, de              ; z_rel
        bit 7, h
        jr nz, .next            ; behind
        ld de, (DemoNear)
        push hl
        or a
        sbc hl, de
        pop hl
        jr nc, .next            ; not nearer than the best so far
        push hl
        push bc
        ld bc, HIT_HALFWIDTH + 32   ; give way well before contact
        call LaneOverlapBC      ; carry: in the player's path
        pop bc
        pop hl
        jr nc, .next
        ld (DemoNear), hl
        ld hl, -64              ; car right of centre: go left
        bit 7, (ix + 2)
        jr z, .aim
        ld hl, 64
.aim:   ld (DemoAim), hl
.next:  ld de, CAR_SIZE
        add ix, de
        djnz .car
        ld hl, (DemoAim)
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
        call CrewSay
        xor a
        ld (Input), a
        ld (Speed), a
        ld (Sliding), a
        ld h, a
        ld l, a
        ld (LatVX), hl
        ; (towards the middle of the branch it is on)
        ld hl, (PlayerX)
        ld a, h
        push af
        call AbsHL
        ld de, (PlayerDx)
        or a
        sbc hl, de              ; offset from the middle
        ld de, 6
        bit 7, h
        jr nz, .neg
        or a
        sbc hl, de
        jr nc, .rel
        ld hl, 0
        jr .rel
.neg:   add hl, de
        jr nc, .rel             ; still negative
        ld hl, 0
.rel:   ld de, (PlayerDx)
        add hl, de
        pop af
        bit 7, a
        call nz, NegHL
        ld (PlayerX), hl
        ret
