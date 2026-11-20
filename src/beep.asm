; (In a gap of bank 2, after pause.asm.)
; DE = tone period: a short beep on channel C (SoundTick ends it)
StartBeep:
        ld a, 12
        di
        call BeepOn
        ei
        ret
; DE = tone period, A = length (interrupts); interrupts off
BeepOn:
        ld (BeepTime), a
        push de
        ld a, 4
        call AyWrite
        pop de
        ld e, d
        ld a, 5
        call AyWrite
        ld e, 13
        ld a, 10
        jp AyWrite
