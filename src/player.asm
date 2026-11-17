; ---------------------------------------------------------------------------
; Player car: steering, speed and track position (M1: simple model)
; ---------------------------------------------------------------------------
STEER           EQU 4           ; pixels (at the bottom line) per 50 Hz frame
PX_MAX          EQU 200
MAX_SPEED       EQU 20          ; depth units per 50 Hz frame
ACCEL           EQU 1
DECEL           EQU 1

UpdatePlayer:
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

        ; steering
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
        ret
