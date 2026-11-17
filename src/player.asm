; ---------------------------------------------------------------------------
; Player car: steering, speed and track position (M1: simple model)
; ---------------------------------------------------------------------------
STEER           EQU 4           ; pixels (at the bottom line) per 50 Hz frame
PX_MAX          EQU 200
MAX_SPEED       EQU 20          ; depth units per 50 Hz frame
ACCEL           EQU 1
DECEL           EQU 1

UpdatePlayer:
        call DemoDriver
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

        ; position += speed * elapsed
        ld e, a
        ld d, 0
        ld hl, (Pos)
        ld a, (Elapsed)
        ld b, a
.adv:   add hl, de
        djnz .adv
        ld (Pos), hl
        jp UpdateTrack

; Demo / attract mode: until a steering key is pressed, drive automatically
; (accelerate, steer back towards the middle of the road).
DEMO_DEADBAND   EQU 6

DEMO_IDLE       EQU 100             ; game frames without input before attract mode

DemoDriver:
        ld a, (Input)
        or a
        ld hl, IdleCount
        jr z, .idle
        ld (hl), 0
        jr .mode
.idle:  ld a, (hl)
        cp DEMO_IDLE
        jr nc, .resume
        inc (hl)
        jr .mode
.resume:
        ld a, 1
        ld (DemoMode), a
.mode:  ld a, (DemoMode)
        or a
        ret z
        ld a, (Input)
        and (1 << IN_LEFT) | (1 << IN_RIGHT)
        jr z, .auto
        xor a
        ld (DemoMode), a
        ret
.auto:  ld a, (Input)
        set IN_UP, a
        ld c, a
        ld hl, (PlayerX)
        ld de, DEMO_DEADBAND
        add hl, de
        bit 7, h
        jr nz, .right           ; PlayerX < -deadband: steer right
        ld de, -2 * DEMO_DEADBAND
        add hl, de
        bit 7, h
        jr nz, .set             ; within the deadband
        set IN_LEFT, c
        jr .set
.right: set IN_RIGHT, c
.set:   ld a, c
        ld (Input), a
        ret
