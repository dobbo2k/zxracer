; ---------------------------------------------------------------------------
; Music: two channels of the AY - bass on B, melody on C - played from the
; 50 Hz interrupt after SoundTick, which keeps the engine on A. Each theme
; has its own tune (in its theme pack: it changes with the road), the front
; end has the title tune. Tunes (tools/make_music.py): dw bass, melody; each
; a byte stream: $00 rest, $01-$5E note, $5F tie, $60-$9F length, $FF loop.
; Effects keep priority: while a bump, a crash or gravel has channel B
; (SfxBusy) or a beep has C (BeepTime), the music keeps time there unheard.
; SoundMode (the options screen): 0 music and engine, 1 engine only, 2 music
; only. Not time-critical (bank 5).
; ---------------------------------------------------------------------------
CH_PTR          EQU 0               ; next byte
CH_START        EQU 2               ; where it loops to
CH_LEN          EQU 4               ; current note length (interrupts)
CH_LEFT         EQU 5               ; interrupts left of this note
CH_VOL          EQU 6
CH_PER          EQU 7               ; tone period (word)
CH_TREG         EQU 9               ; tone register (fine; coarse is next)
CH_VREG         EQU 10              ; volume register
CH_V0           EQU 11              ; a note starts at this volume
CH_FLOOR        EQU 12              ; and fades to this
CH_DMASK        EQU 13              ; by one every (mask + 1) interrupts

ChanB:  dw 0, 0                     ; bass
        db 1, 1, 0
        dw 0
        db 2, 9, 12, 8, 1
ChanC:  dw 0, 0                     ; melody
        db 1, 1, 0
        dw 0
        db 4, 10, 13, 9, 3
MusicOn:        db 0
SoundMode:      db 0

; From the interrupt (AF, BC, DE, HL free)
MusicTick:
        ld a, (MusicOn)
        or a
        ret z
        ld a, (Paged)           ; another bank over the tune
        or a
        ret nz
        ld a, (Mute)            ; muted in a game: paused
        or a
        jr z, .on
        ld a, (GameState)
        cp ST_PLAYING
        ret z
.on:    push ix
        ld ix, ChanB
        call MusicStep
        ld ix, ChanC
        call MusicStep
        ld a, (Mute)            ; (the front end has no effects)
        or a
        jr nz, .b
        ld a, (SfxBusy)
        or a
        jr nz, .c
.b:     ld ix, ChanB
        call MusicOut
.c:     ld a, (BeepTime)
        or a
        jr nz, .mix
        ld ix, ChanC
        call MusicOut
.mix:   ; the mixer: the engine's (in the front end: tone A for its jingles),
        ; plus tone C, and tone B (instead of noise B) unless an effect has B
        ld a, (Mute)
        or a
        ld e, %00111110
        jr nz, .tb
        ld a, (MixVal)
        ld e, a
        ld a, (SfxBusy)
        or a
        jr nz, .tc
.tb:    res 1, e                ; tone B on
        set 4, e                ; (and its noise off: tone AND noise is grit)
.tc:    res 2, e
        ld a, 7
        call AyWrite
        pop ix
        ret

; IX = channel: one interrupt of its tune
MusicStep:
        dec (ix + CH_LEFT)
        jr z, .next
        ld a, (ix + CH_LEFT)
        dec a
        jr nz, .decay
        ; the note's last interrupt: a moment's silence before the next
        ; (unless it is tied on, or short)
        ld a, (ix + CH_LEN)
        cp 3
        ret c
        ld l, (ix + CH_PTR)
        ld h, (ix + CH_PTR + 1)
.peek:  ld a, (hl)
        inc hl
        cp $60
        jr c, .seen
        cp $FF
        jr nz, .peek
.seen:  cp $5F
        ret z
        ld (ix + CH_VOL), 0
        ret
.decay: ld a, (FrameCount)
        and (ix + CH_DMASK)
        ret nz
        ld a, (ix + CH_VOL)
        cp (ix + CH_FLOOR)
        ret z
        ret c
        dec (ix + CH_VOL)
        ret
.next:  ld l, (ix + CH_PTR)
        ld h, (ix + CH_PTR + 1)
.ev:    ld a, (hl)
        inc hl
        cp $FF
        jr nz, .nl
        ld l, (ix + CH_START)   ; the end: round again
        ld h, (ix + CH_START + 1)
        jr .ev
.nl:    cp $60
        jr c, .note
        sub $5F                 ; a new length
        ld (ix + CH_LEN), a
        jr .ev
.note:  ld (ix + CH_PTR), l
        ld (ix + CH_PTR + 1), h
        ld c, a
        ld a, (ix + CH_LEN)
        ld (ix + CH_LEFT), a
        ld a, c
        cp $5F
        ret z                   ; tied: the note goes on
        or a
        jr z, .vol              ; a rest: silence
        dec a
        add a, a
        add a, low NoteTab
        ld l, a
        adc a, high NoteTab
        sub l
        ld h, a
        ld a, (hl)
        ld (ix + CH_PER), a
        inc hl
        ld a, (hl)
        ld (ix + CH_PER + 1), a
        ld a, (ix + CH_V0)
.vol:   ld (ix + CH_VOL), a
        ret

; IX = channel: its tone and volume to the AY
MusicOut:
        ld e, (ix + CH_PER)
        ld a, (ix + CH_TREG)
        call AyWrite
        ld e, (ix + CH_PER + 1)
        ld a, (ix + CH_TREG)
        inc a
        call AyWrite
        ld e, (ix + CH_VOL)
        ld a, (ix + CH_VREG)
        jp AyWrite

; HL = tune: play it from the start (unless the sound mode is engine only)
MusicStart:
        ld a, (SoundMode)
        dec a
        ret z
        di
        ld e, (hl)
        inc hl
        ld d, (hl)
        inc hl
        push ix
        ld ix, ChanB
        call .ch
        ld e, (hl)
        inc hl
        ld d, (hl)
        ld ix, ChanC
        call .ch
        pop ix
        ld a, 1
        ld (MusicOn), a
        ei
        ret
.ch:    ld (ix + CH_PTR), e
        ld (ix + CH_PTR + 1), d
        ld (ix + CH_START), e
        ld (ix + CH_START + 1), d
        ld (ix + CH_LEFT), 1
        ld (ix + CH_VOL), 0
        ret

; The current theme's tune
MusicTheme:
        ld hl, (StTune)
        jr MusicStart

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

; AY tone periods, C2 to B6 (tools/make_music.py)
NoteTab:
        INCLUDE "music_notes.asm"
