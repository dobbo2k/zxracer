; Small pieces of the music player (src/music.asm) in bank 2.

; A = note (1-60, more wraps down an octave) -> DE = its period
NotePeriod:
        cp 61
        jr c, .ok
        sub 12
.ok:    dec a
        add a, a
        add a, low NoteTab
        ld e, a
        adc a, high NoteTab
        sub e
        ld d, a
        ex de, hl
        ld e, (hl)
        inc hl
        ld d, (hl)
        ret

; The current theme's tune
MusicTheme:
        ld hl, (StTune)
        jp MusicStart

; At the green light: the theme's tune, in a game
MusicGo:
        ld a, (GameState)
        cp ST_PLAYING
        ret nz
        jr MusicTheme

; Stop the music, silence its channels
MusicStop:
        xor a
        ld (MusicOn), a
        di
        ld e, a
        ld a, 8
        call AyWrite
        ld e, 0
        ld a, 9
        call AyWrite
        ld e, 0
        ld a, 10
        call AyWrite
        ei
        ret

; A = register, E = value, from outside the interrupt (which writes the AY
; too: a register selected and then written must not be split)
AyPut:  di
        call AyWrite
        ei
        ret

; From the interrupt: the sound. A crash has the AY to itself while it lasts
; (the music keeps time unheard); else the music, or without it the engine.
SoundTick:
        ld a, (Mute)
        or a
        jr z, .game
        ld a, (GameState)       ; muted in a game: paused, silent
        cp ST_PLAYING
        ret z
        ld a, (MusicOn)         ; the front end: its tune, if on
        or a
        ret z
        jp MusicPlay
.game:  call JingleTick
        ld a, (CrashOn)
        or a
        jr z, .noCrash
        ld a, (MusicOn)
        or a
        call nz, MusicKeep
        jp CrashTick
.noCrash:
        ld a, (MusicOn)
        or a
        jp nz, MusicPlay
        jp EngineSounds

; A = the speed at impact (0-20): the crash sound, bigger the faster - it
; holds longer (speed / 2 interrupts) and fades slower (one step every
; speed / 4 + 1), a thud above speed 6, debris above 12
CrashStart:
        ld (CrashI), a
        ld b, a
        srl a
        ld (CrashHold), a
        ld a, b
        srl a
        srl a
        inc a
        ld (CrashRate), a
        ld (CrashCnt), a
        ld a, 15
        ld (CrashVol), a
        xor a
        ld (CrashAge), a
        inc a
        ld (CrashOn), a
        ret
