; (In a gap of bank 2.)
; DE = tone period: a short beep on channel C (SoundTick ends it)
StartBeep:
        di
        push de
        ld a, 4
        call AyWrite
        pop de
        ld e, d
        ld a, 5
        call AyWrite
        ld e, 13
        ld a, 10
        call AyWrite
        ld a, 12
        ld (BeepTime), a
        ei
        ret
