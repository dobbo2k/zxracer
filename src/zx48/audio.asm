RacePitch:
        ld c, 0
        ld a, (GameState)
        or a
        ret z
        ld a, (SoundMode)
        or a
        jr nz, .engine
        ld a, (EffectPitch)
        or a
        jr z, .engine
        ld c, a
        ld a, (EffectUntil)
        ld hl, FrameCount
        sub (hl)
        jr z, .clear
        cp 13
        jr nc, .clear
        ret
.clear: xor a
        ld (EffectPitch), a
        ld c, a
.engine:
        ld a, (Lights)
        cp LIGHTS_GO
        ret nc
        ld a, (Speed)
        srl a
        cpl
        add a, 151
        ld c, a
        ret

StartBeep:
        ld a, e
        cp BEEP_RED & 255
        ld a, 55
        jr z, .set
        ld a, 28
.set:   ld c, a
        ld a, 10
        jr SetEffect
WarnBeep:
        ld c, 32
        ld a, 6
        jr SetEffect
CrashStart:
        ld c, $FF
        ld a, 12
        jr SetEffect
PlaySfx:
        ld c, 117
        ld a, 3
SetEffect:
        push hl
        ld hl, FrameCount
        add a, (hl)
        ld (EffectUntil), a
        ld a, c
        ld (EffectPitch), a
        pop hl
        ret
Silence:
        xor a
        ld (EffectPitch), a
        out ($FE), a
        ret

EffectUntil: db 0
EffectPitch: db 0
