; ---------------------------------------------------------------------------
; Sound, from the 50 Hz interrupt (SoundTick): the music, or without it the
; engine.
;
; With music (a game after the green light, the title screens): drums on A,
; bass on B, melody on C, and no engine. A tyre squeal (sliding, spinning,
; tyre smoke) takes A over from the drums; a bump or crash takes B
; from the bass; the starting lights' last beep takes C. The music keeps time
; meanwhile (a squeal near the grip limit is a chirp now and then, so the
; drums go on); gravel off the road takes B like a hit. Without music (the attract demo, waiting at the lights, or the
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
CH_TGT          EQU 15              ; the note's own period (word)
CH_ARPX         EQU 17              ; arpeggio: semitones of its 2nd and 3rd
CH_ARPY         EQU 18              ; notes (both 0: off)
CH_ARPPH        EQU 19              ; which of the three is sounding
CH_VIB          EQU 20              ; vibrato: depth = period >> this (0: off)
CH_AGE          EQU 21              ; interrupts since the note began
CH_SLPEND       EQU 22              ; a slide into the next note: 2^this interrupts
CH_SLLEFT       EQU 23              ; interrupts left of a slide
CH_STEP         EQU 24              ; its step per interrupt (word)
CH_BASE         EQU 26              ; the note (1-60)
CH_SIZE         EQU 27
VIB_DELAY       EQU 10              ; vibrato starts this far into a note

ChanA:  dw 0, 0                     ; drums
        db 1, 1, 0
        dw 0
        db 0, 8, 0, 0, 0, 0
        ds CH_SIZE - 15
ChanB:  dw 0, 0                     ; bass
        db 1, 1, 0
        dw 0
        db 2, 9, 12, 8, 1, 0
        ds CH_SIZE - 15
ChanC:  dw 0, 0                     ; melody
        db 1, 1, 0
        dw 0
        db 4, 10, 13, 9, 3, 0
        ds CH_SIZE - 15
SQ_CHIRP        EQU 24
SQ_SLIDE        EQU 12
SQ_NOISE        EQU 4               ; the squeal's grit: a high noise
SQ_CYCLE        EQU 128

; (SoundTick, the interrupt's way in: src/musicb2.asm)

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
        jr .busy
.nohit: ld a, (Mute)            ; off the road and moving: gravel on B
        or a
        jr nz, .busy0
        ld a, (OffRoad)
        or a
        jr z, .busy0
        ld a, (Speed)
        or a
        jr z, .busy0
        ld e, 10
        ld a, 9
        call AyWrite
        ld e, 12
        ld a, 6
        call AyWrite
        ld a, 1
        jr .busy
.busy0: xor a
.busy:  ld (SfxBusy), a
        ld ix, ChanA
        call MusicStep
        ld ix, ChanB
        call MusicStep
        call Pitch
        ld ix, ChanC
        call MusicStep
        call Pitch
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
        ld e, 10
        ld a, 8
        call AyWrite
        ld a, (SfxBusy)         ; grit: noise mixed in (a hit's or gravel's
        or a                    ; noise, if one has the generator)
        jr nz, .grit
        ld e, SQ_NOISE
        ld a, 6
        call AyWrite
.grit:  ld hl, 0                ; (the drum it cut off is gone)
        ld (DrumPtr), hl
        ld hl, MixBits
        res 0, (hl)             ; tone A
        res 3, (hl)             ; and noise A
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
        cp 6
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
DrumTab:        dw DrumKick, DrumSnare, DrumHat, DrumTom, DrumOpen
DrumTom:        db 14, 0
                dw 500
                db 13, 0
                dw 600
                db 11, 0
                dw 720
                db 9, 0
                dw 860
                db 6, 0
                dw 1000
                db 3, 0
                dw 1150
                db 0
DrumOpen:       db 11, 1
                dw 0
                db 10, 1
                dw 0
                db 8, 1
                dw 0
                db 6, 1
                dw 0
                db 4, 1
                dw 0
                db 2, 1
                dw 0
                db 0


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
        cp $A0
        jr nc, .cmd
        sub $5F                 ; a new length
        ld (ix + CH_LEN), a
        jr .ev
.cmd:   ld c, a                 ; $A0+n arpeggio, $B0+n envelope,
        and $0F                 ; $C0+s slide, $D0+s vibrato
        ld b, a
        ld a, c
        cp $B0
        jr nc, .env
        ld a, b                 ; arpeggio n: ArpTab entry n-1 (0: off)
        or a
        jr z, .arp0
        add a, a
        add a, low (ArpTab - 2)
        ld e, a
        adc a, high (ArpTab - 2)
        sub e
        ld d, a
        ld a, (de)
        inc de
        ld (ix + CH_ARPX), a
        ld a, (de)
.arpy:  ld (ix + CH_ARPY), a
        ld (ix + CH_ARPPH), 0
        jr .ev
.arp0:  ld (ix + CH_ARPX), a
        jr .arpy
.env:   cp $C0
        jr nc, .sl
        ld a, b                 ; envelope n: EnvTab entry (3 bytes)
        add a, a
        add a, b
        add a, low EnvTab
        ld e, a
        adc a, high EnvTab
        sub e
        ld d, a
        ld a, (de)
        ld (ix + CH_V0), a
        inc de
        ld a, (de)
        ld (ix + CH_FLOOR), a
        inc de
        ld a, (de)
        ld (ix + CH_DMASK), a
        jr .ev
.sl:    cp $D0
        jr nc, .vib
        ld (ix + CH_SLPEND), b
        jp .ev
.vib:   ld (ix + CH_VIB), b
        jp .ev
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
        ld (ix + CH_BASE), a
        call NotePeriod         ; -> DE
        ld (ix + CH_TGT), e
        ld (ix + CH_TGT + 1), d
        ld (ix + CH_AGE), 0
        ld (ix + CH_SLLEFT), 0
        ld a, (ix + CH_SLPEND)  ; sliding in: from the last pitch
        or a
        jr z, .noSl
        ld b, a
        ld (ix + CH_SLPEND), 0
        ld l, (ix + CH_PER)
        ld h, (ix + CH_PER + 1)
        ex de, hl
        push af                 ; (A: the slide's 2^A)
        or a
        sbc hl, de              ; target - now
        ld c, h                 ; (its sign: shift the size, so the steps
        bit 7, h                ; never overshoot)
        call nz, NegHL
.shr:   srl h
        rr l
        djnz .shr
        bit 7, c
        call nz, NegHL
        ld (ix + CH_STEP), l
        ld (ix + CH_STEP + 1), h
        pop af
        ld b, a
        ld a, 1
.pow:   add a, a
        djnz .pow
        ld (ix + CH_SLLEFT), a
.noSl:  ld a, (ix + CH_V0)
.vol:   ld (ix + CH_VOL), a
        ret

; IX = channel: its pitch this interrupt - the arpeggio's note, a slide's
; way, or the note with vibrato once it has sounded a while
Pitch:  ld a, (ix + CH_NOTE)
        or a
        ret z                   ; a rest
        ld a, (ix + CH_ARPX)
        or (ix + CH_ARPY)
        jr z, .slide
        ld a, (ix + CH_ARPPH)   ; arpeggio: base, +X, +Y in turn
        ld b, (ix + CH_BASE)
        or a
        jr z, .ap
        ld c, (ix + CH_ARPX)
        dec a
        jr z, .ax
        ld c, (ix + CH_ARPY)
.ax:    ld a, b
        add a, c
        ld b, a
.ap:    ld a, (ix + CH_ARPPH)
        inc a
        cp 3
        jr c, .ph
        xor a
.ph:    ld (ix + CH_ARPPH), a
        ld a, b
        call NotePeriod
        jr .set
.slide: ld a, (ix + CH_SLLEFT)
        or a
        jr z, .vib
        dec (ix + CH_SLLEFT)
        jr z, .tgt
        ld l, (ix + CH_PER)
        ld h, (ix + CH_PER + 1)
        ld e, (ix + CH_STEP)
        ld d, (ix + CH_STEP + 1)
        add hl, de
        ex de, hl
        jr .set
.vib:   ld a, (ix + CH_AGE)
        inc a
        jr z, .old
        ld (ix + CH_AGE), a
.old:   ld b, (ix + CH_VIB)
        inc b
        dec b
        jr z, .tgt
        cp VIB_DELAY
        jr c, .tgt
        rrca                    ; phase: (age / 2) & 7
        and 7
        ld c, a
        ld l, (ix + CH_TGT)
        ld h, (ix + CH_TGT + 1)
.dep:   srl h                   ; depth = period >> VIB
        rr l
        djnz .dep
        ex de, hl
        ld l, (ix + CH_TGT)
        ld h, (ix + CH_TGT + 1)
        ld a, c                 ; 0 1 2 1 0 -1 -2 -1 depths
        and 3
        jr z, .vset
        cp 2
        jr nz, .one
        add hl, de
.one:   bit 2, c
        jr nz, .neg
        add hl, de
        jr .vset
.neg:   or a
        sbc hl, de
        cp 2
        jr nz, .vset
        sbc hl, de
.vset:  ex de, hl
        jr .set
.tgt:   ld e, (ix + CH_TGT)
        ld d, (ix + CH_TGT + 1)
.set:   ld (ix + CH_PER), e
        ld (ix + CH_PER + 1), d
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
        ld a, (ix + CH_VOL)
        ld e, a
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
        ld (ix + CH_ARPX), 0    ; no effects until the tune says
        ld (ix + CH_ARPY), 0
        ld (ix + CH_VIB), 0
        ld (ix + CH_SLPEND), 0
        ld (ix + CH_SLLEFT), 0
        ret

; (NoteTab, the tone periods, ArpTab, EnvTab and some of the drums are in
; src/holes.asm; NotePeriod, MusicTheme, MusicGo, MusicStop and AyPut in
; src/musicb2.asm, bank 2)
