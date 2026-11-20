; ---------------------------------------------------------------------------
; Sound, from the 50 Hz interrupt (SoundTick): the music, or without it the
; engine.
;
; With music (a game after the green light, the title screens): drums on A,
; bass on B, melody on C, and no engine. A tyre squeal (sliding, spinning,
; tyre smoke) takes A over from the drums; a bump or crash takes B
; from the bass; the starting lights' last beep takes C. The music keeps time
; meanwhile (a squeal near the grip limit is a chirp now and then, so the
; drums go on). Without music (the attract demo, waiting at the lights, or the
; sound set to the engine): the engine note on A, gravel and hits on B.
;
; Tunes (tools/make_music.py): dw bass, melody, drums; each a byte stream:
; $00 rest, $01-$5E note (drums: 1 kick, 2 snare, 3 hi-hat), $5F tie,
; $60-$9F length, $FF loop. Each theme has its own tune (in its theme pack:
; it changes with the road), the front end has the title tune.
; SoundMode (the options screen): 0 music and effects, 1 the engine.
; Not time-critical (bank 5).
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
CH_NOTE         EQU 14              ; the last event (drums: which drum)

ChanA:  dw 0, 0                     ; drums
        db 1, 1, 0
        dw 0
        db 0, 8, 0, 0, 0, 0
ChanB:  dw 0, 0                     ; bass
        db 1, 1, 0
        dw 0
        db 2, 9, 12, 8, 1, 0
ChanC:  dw 0, 0                     ; melody
        db 1, 1, 0
        dw 0
        db 4, 10, 13, 9, 3, 0
MusicOn:        db 0
SoundMode:      db 0
SfxBusy:        db 0                ; a hit has channel B (and the noise)
MixBits:        db 0                ; the mixer setting being built
DrumPtr:        dw 0                ; the drum sounding: its next step (0: none)
SqHold:         db 0                ; interrupts until the next chirp may start
SqTimer:        db 0                ; interrupts left of a chirp
SQ_CHIRP        EQU 24
SQ_SLIDE        EQU 12
SQ_CYCLE        EQU 128

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
        jr MusicPlay
.game:  ld a, (MusicOn)
        or a
        jr nz, MusicPlay
        jp EngineSounds

; One interrupt of music (and the squeal and hits)
MusicPlay:
        ld a, (Paged)           ; another bank over the tune
        or a
        ret nz
        push ix
        ld a, (SfxTimer)        ; a hit: a noise burst on B
        or a
        jr z, .nohit
        dec a
        ld (SfxTimer), a
        ld e, a                 ; (fading with the timer)
        ld a, 9
        call AyWrite
        ld a, (SfxType)
        ld e, a
        ld a, 6
        call AyWrite
        ld a, 1
.nohit: ld (SfxBusy), a
        ld ix, ChanA
        call MusicStep
        ld ix, ChanB
        call MusicStep
        ld ix, ChanC
        call MusicStep
        ld a, %00111111         ; everything off, then on as used
        ld (MixBits), a
        ; A: the squeal, or the drums. A full squeal while the car slides
        ; past its grip or spins; near the limit (tyre smoke) a chirp, at
        ; most one every SQ_CYCLE interrupts.
        ld a, (Mute)            ; (the front end: no car)
        or a
        jr nz, .drums
        ld a, (Sliding)
        ld hl, Spin
        or (hl)
        jr z, .smoke
        ld a, SQ_SLIDE          ; (held on a little: sliding flickers at the
        ld (SqTimer), a         ; grip limit)
.smoke: ld hl, SqHold           ; a chirp at most every SQ_CYCLE
        ld a, (hl)
        or a
        jr z, .h0
        dec (hl)
        jr .tim
.h0:    ld a, (Squeal)
        or a
        jr z, .tim
        ld (hl), SQ_CYCLE
        ld a, SQ_CHIRP
        ld (SqTimer), a
.tim:   ld hl, SqTimer          ; (a chirp always plays out)
        ld a, (hl)
        or a
        jr z, .drums
        dec (hl)
.sq:    ld a, (FrameCount)      ; a wavering high tone
        and 6
        add a, 40
        ld e, a
        xor a
        call AyWrite
        ld e, 0
        ld a, 1
        call AyWrite
        ld e, 9
        ld a, 8
        call AyWrite
        ld hl, 0                ; (the drum it cut off is gone)
        ld (DrumPtr), hl
        ld hl, MixBits
        res 0, (hl)
        jr .b
.drums: call DrumOut
.b:     ; B: the bass, or a hit
        ld a, (SfxBusy)
        or a
        ld hl, MixBits
        jr nz, .bhit
        res 1, (hl)
        ld ix, ChanB
        call MusicOut
        jr .c
.bhit:  res 4, (hl)
.c:     ; C: the melody, or the green light's beep
        ld a, (BeepTime)
        or a
        jr z, .mel
        dec a
        ld (BeepTime), a
        jr .mix
.mel:   ld ix, ChanC
        call MusicOut
.mix:   ld hl, MixBits
        res 2, (hl)
        ld e, (hl)
        ld a, 7
        call AyWrite
        pop ix
        ret

; Channel A's drum: start one when its track says, play a step of it
DrumOut:
        ld a, (ChanA + CH_LEFT) ; a new event this interrupt?
        ld hl, ChanA + CH_LEN
        cp (hl)
        jr nz, .run
        ld a, (ChanA + CH_NOTE)
        or a
        jr z, .run
        cp 4
        jr nc, .run             ; (a tie)
        dec a
        add a, a
        add a, low DrumTab
        ld l, a
        adc a, high DrumTab
        sub l
        ld h, a
        ld a, (hl)
        inc hl
        ld h, (hl)
        ld l, a
        ld (DrumPtr), hl
.run:   ld hl, (DrumPtr)
        ld a, h
        or l
        jr z, .quiet
        ld a, (hl)              ; volume (0: the end)
        or a
        jr z, .end
        ld e, a
        ld a, 8
        call AyWrite
        inc hl
        ld a, (hl)              ; noise period (0: none)
        inc hl
        or a
        jr z, .tone
        ld e, a
        ld a, (SfxBusy)         ; (a hit has the noise generator)
        or a
        jr nz, .tone
        push hl
        ld a, 6
        call AyWrite
        ld hl, MixBits
        res 3, (hl)
        pop hl
.tone:  ld e, (hl)              ; tone period (0: none)
        inc hl
        ld d, (hl)
        inc hl
        ld (DrumPtr), hl
        ld a, d
        or e
        ret z
        push de
        xor a
        call AyWrite
        pop de
        ld e, d
        ld a, 1
        call AyWrite
        ld hl, MixBits
        res 0, (hl)
        ret
.end:   ld hl, 0
        ld (DrumPtr), hl
.quiet: ld e, 0
        ld a, 8
        jp AyWrite

; Drums: per interrupt db volume (0: the end), noise period (0: none),
; dw tone period (0: none)
DrumTab:        dw DrumKick, DrumSnare, DrumHat
DrumKick:       db 15, 0
                dw 300
                db 14, 0
                dw 600
                db 12, 0
                dw 1000
                db 10, 0
                dw 1500
                db 7, 0
                dw 2100
                db 4, 0
                dw 2800
                db 0
DrumSnare:      db 14, 6
                dw 250
                db 13, 7
                dw 0
                db 11, 8
                dw 0
                db 9, 9
                dw 0
                db 6, 10
                dw 0
                db 3, 10
                dw 0
                db 0
DrumHat:        db 10, 1
                dw 0
                db 6, 1
                dw 0
                db 0

; No music: the engine on A, gravel and hits on B, the lights' beeps on C
EngineSounds:
        ; engine period with a small wobble every interrupt
        ld hl, (EnginePeriod)
        ld a, (FrameCount)
        and 3
        add a, l
        ld l, a
        jr nc, .nw
        inc h
.nw:    push hl
        ld e, l
        xor a                   ; tone A fine
        call AyWrite
        pop hl
        ld e, h
        ld a, 1                 ; tone A coarse
        call AyWrite
        ; engine volume: 11 when the game is running, quieter in attract
        ld e, 11
        ld a, (GameState)
        cp ST_PLAYING
        jr z, .vol
        ld e, 7
.vol:   ld a, 8
        call AyWrite
        ; effects: a burst of noise on B (bump, crash) overrides the gravel
        ld a, (SfxTimer)
        or a
        jr z, .noSfx
        dec a
        ld (SfxTimer), a
        ld e, a                 ; volume fades with the timer
        ld a, 9
        call AyWrite
        ld a, (SfxType)
        ld e, a                 ; noise period: low = rumble
        ld a, 6
        call AyWrite
        jr .mix
.noSfx:
        ; gravel: noise on B while off the road and moving
        ld e, 0
        ld a, (OffRoad)
        or a
        jr z, .gr
        ld a, (Speed)
        or a
        jr z, .gr
        ld e, 10
.gr:    ld a, 9
        call AyWrite
        ld e, 12                ; noise period
        ld a, 6
        call AyWrite
.mix:
        ; mixer: tone A, noise B (0 bits enable), and tone C for a beep
        ld a, (BeepTime)
        or a
        jr z, .mx
        dec a
        ld (BeepTime), a
        jr nz, .bp
        ld e, a                 ; its end: volume C off
        ld a, 10
        call AyWrite
.bp:    ld e, %00101010
        jr .mw
.mx:    ld e, %00101110
.mw:    ld a, 7
        jp AyWrite

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
        ld (ix + CH_NOTE), a
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

; HL = tune: play it from the start (unless the sound is set to the engine)
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
        inc hl
        ld ix, ChanC
        call .ch
        ld e, (hl)
        inc hl
        ld d, (hl)
        ld ix, ChanA
        call .ch
        ld hl, 0
        ld (DrumPtr), hl
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

; AY tone periods, C2 to B6 (tools/make_music.py)
NoteTab:
        INCLUDE "music_notes.asm"
