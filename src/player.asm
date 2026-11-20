; ---------------------------------------------------------------------------
; Player car: steering, sideways momentum and grip, speed, track position
; ---------------------------------------------------------------------------
STEER_ACC       EQU 64          ; sideways acceleration (1/256 px per frame per frame):
                                ; 4 pixels a frame once it has built up
GRIP            EQU 200         ; |curvature * speed| the tyres hold
PX_MAX          EQU 300         ; from the middle of the road (or the branch)
MAX_SPEED       EQU 20          ; depth units per 50 Hz frame (HIGH gear: 280 km/h)
LOW_MAX         EQU 13          ; LOW gear's top speed (182 km/h)
DEMO_UP         EQU 13          ; the demo driver changes up at this speed...
DEMO_DOWN       EQU 8           ; ... and down below this one
COAST_D         EQU 16          ; speed lost per 50 Hz frame (1/256ths): off the throttle
BRAKE_D         EQU 64          ; braking
SLIDE_D         EQU 24          ; sliding past the grip limit (the throttle does nothing)
LIMIT_D         EQU 32          ; LOW gear above its top speed: engine braking
OFFROAD_X       EQU 150             ; |PlayerX| beyond the kerb
OFFROAD_SPEED   EQU 8

CRASH_FRAMES    EQU 160         ; (time for her to tell him off, and his reply)
SPIN_D          EQU 48          ; a spin-out's slowing (1/256ths per frame)

UpdatePlayer:
        call GameUpdate
        call DemoDriver
        call CrashUpdate
        call LightsHold
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
        ; gear: fire (SPACE) changes between LOW and HIGH
        ld a, (Input)
        and 1 << IN_FIRE
        ld hl, FireWas
        ld b, (hl)
        ld (hl), a
        jr z, .noShift          ; not pressed
        ld a, b
        or a
        jr nz, .noShift         ; still held from before
        ld a, (Gear)
        xor 1
        ld (Gear), a
.noShift:

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

        ; speed, per 50 Hz frame
        ld a, (Elapsed)
        ld b, a
.spd:   push bc
        call SpeedStep
        pop bc
        djnz .spd
        ld a, (Input)
        ld c, a
        ld a, (Speed)
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

; One 50 Hz frame of speed (Speed.SpeedFrac, 8.8). The throttle's pull
; depends on the gear and the speed, as on an arcade racer's shifter: LOW
; pulls hard but tops out at LOW_MAX (above it, after changing down at
; speed, the engine brakes the car to it); HIGH reaches MAX_SPEED but pulls
; weakly from low speeds. From a standstill LOW reaches 182 km/h in about
; 4 s, HIGH then 280 km/h in about 5 more; starting in HIGH takes 10 s to
; 182. Braking beats the throttle; sliding scrubs speed off.
SpeedStep:
        ld a, (Input)
        ld c, a
        ld hl, (SpeedFrac)      ; L = fraction, H = Speed
        ld de, -BRAKE_D
        bit IN_DOWN, c
        jr nz, .add
        ld de, -SLIDE_D
        ld a, (Sliding)
        or a
        jr nz, .add
        ld de, -COAST_D
        bit IN_UP, c
        jr z, .add
        ; throttle
        ld a, (Gear)
        or a
        ld a, h
        ld de, HighPull
        ld b, MAX_SPEED
        jr nz, .pull
        ld de, -LIMIT_D
        cp LOW_MAX + 1
        jr nc, .add             ; LOW above its top speed: engine braking
        ld de, LowPull
        ld b, LOW_MAX
.pull:  cp b
        jr nc, .top             ; at the gear's top speed
        push hl
        ld l, a
        ld h, 0
        add hl, de
        ld e, (hl)              ; the pull at this speed
        ld d, 0
        pop hl
        add hl, de
        ld a, h
        cp b
        jr c, .set
.top:   ld h, b                 ; (not past the gear's top)
        ld l, 0
        jr .set
.add:   add hl, de
        jr c, .set              ; (adding a negative: carry while >= 0)
        ld hl, 0
.set:   ; hills: a climb slows the moving car, a descent speeds it up
        ld a, h
        or l
        jr z, .st
        ld a, (CurveList + 1)   ; the hill at the car (+: climbing)
        neg
        add a, a                ; HILL_K = 2 (1/256ths per frame per unit)
        ld e, a
        rlca
        sbc a, a
        ld d, a
        add hl, de
        bit 7, h
        jr z, .st
        ld hl, 0
.st:    ld (SpeedFrac), hl
        ret
LowPull:                        ; LOW: 1/256ths of a speed unit per frame
        db 22, 22, 22, 22, 22, 22           ; 0-5
        db 18, 18, 18, 18                   ; 6-9
        db 12, 12, 12                       ; 10-12
HighPull:                       ; HIGH
        db 5, 5, 5, 5, 5, 5                 ; 0-5: it bogs down
        db 8, 8, 8, 8                       ; 6-9
        db 10, 10, 10, 10, 10, 10           ; 10-15
        db 7, 7                             ; 16-17
        db 5, 5                             ; 18-19

; Demo / attract mode: until a steering key is pressed, drive automatically
; (accelerate, steer back towards the middle of the road).
DEMO_DEADBAND   EQU 6
DEMO_LOOK       EQU 1200            ; how far ahead it looks for traffic
DEMO_SIDE       EQU 130             ; where it drives (lanes at +-56, the edge at 150)
DEMO_LIFT       EQU 700             ; it lifts off this close behind one in its path

DemoDriver:
        ld a, (DemoMode)
        or a
        ret z
        ld a, (Speed)           ; its own gear changes
        ld hl, Gear
        cp DEMO_UP
        jr c, .low
        ld (hl), 1
        jr .geared
.low:   cp DEMO_DOWN
        jr nc, .geared
        ld (hl), 0
.geared:
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
        push hl
        ld hl, (DemoNear)       ; or close behind a vehicle in its path
        ld de, DEMO_LIFT
        sbc hl, de              ; (carry clear)
        pop hl
        jr c, .gas
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

; The demo driver keeps to the middle until a vehicle is near (within
; DEMO_LOOK); then it drives on the outer edge of the road, on the side
; away from the lane that one is heading for, and keeps to that side (at a
; fork, to the outer edge of the branch it takes).
DemoTarget:
        ld hl, DEMO_LOOK
        ld (DemoNear), hl
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
.branch:                        ; the outer edge of the branch (its traffic
        ld de, (PlayerDx)       ; keeps to +-56 from the middle of it)
        ld hl, DEMO_SIDE
        add hl, de
        ld a, (Stage)
        rra
        ld de, DEMO_SIDE
        jr c, .br
        call NegHL
        ld de, -DEMO_SIDE
.br:    ld (DemoAim), de        ; (and that side afterwards)
        ret
.traffic:
        ld hl, DEMO_LOOK
        ld (DemoAny), hl
        ld ix, Traffic
        ld a, (NTraffic)
        ld b, a
.car:   ld l, (ix + 0)
        ld h, (ix + 1)
        ld de, (Pos)
        or a
        sbc hl, de              ; z_rel
        bit 7, h
        jr nz, .next            ; behind
        ld de, (DemoAny)
        push hl
        sbc hl, de              ; (carry clear)
        pop hl
        jr nc, .path
        ld (DemoAny), hl        ; the nearest ahead, in any lane
        ld a, (ix + 5)
        ld (DemoHead), a
.path:  ld de, (DemoNear)
        push hl
        sbc hl, de
        pop hl
        jr nc, .next
        push hl
        push bc
        ld bc, HIT_WIDEST
        call LaneOverlapBC      ; carry: in the player's path
        pop bc
        pop hl
        jr nc, .next
        ld (DemoNear), hl       ; the nearest in its path
.next:  ld de, CAR_SIZE
        add ix, de
        djnz .car
        ; the middle until a vehicle is near; then the outer edge of the
        ; road, away from where that one is heading, and that side from then
        ; on (the lanes are at +-56: no vehicle reaches a car out there)
        ld hl, (DemoAim)
        ld a, h
        or l
        ret nz                  ; keep to the side it chose
        ld hl, (DemoAny)
        ld de, DEMO_LOOK
        sbc hl, de              ; (carry clear)
        ld hl, 0
        ret z
        ld hl, -DEMO_SIDE
        ld a, (DemoHead)
        rlca
        jr nc, .aim
        ld hl, DEMO_SIDE
.aim:   ld (DemoAim), hl
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
        ld (Sliding), a
        ld a, (Spin)            ; a spin-out: the car slides on, slowing hard
        or a
        jr z, .stop
        ld a, (Elapsed)
        ld b, a
        ld hl, (SpeedFrac)
        ld de, -SPIN_D
.sd:    add hl, de
        jr nc, .stop            ; at a standstill
        djnz .sd
        ld (SpeedFrac), hl
        jr .lat
.stop:  xor a
        ld (Spin), a
        ld (Speed), a
.lat:   xor a
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
