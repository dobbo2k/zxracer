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
