; ---------------------------------------------------------------------------
; AY-3-8912: register writes, the engine note's pitch and the effects (the
; interrupt's SoundTick and the music are in src/music.asm). Without music:
;   A: engine - square wave, pitch rising with the revs (speed and gear:
;      it drops when you change up), with a small wobble
;      every interrupt so it sounds like a motor rather than a beep
;   B: gravel noise while off the road, bumps and crashes
; ---------------------------------------------------------------------------
AY_SEL          EQU $FFFD
AY_DATA         EQU $BFFD
ENGINE_IDLE     EQU 1400            ; tone period at standstill (~80 Hz)
ENGINE_STEP     EQU 50              ; period decrease per speed unit

; A = register, E = value
AyWrite:
        ld bc, AY_SEL
        out (c), a
        ld b, high AY_DATA
        out (c), e
        ret

; Called from the IM2 handler. Preserves everything but AF, BC, DE, HL.
; Engine tone period for the current speed, once per game frame (not in
; the interrupt): IDLE - speed * STEP.
EngineUpdate:
        ld a, (Speed)           ; revs: speed in HIGH, 1.5 x speed in LOW
        ld b, a
        ld a, (Gear)
        or a
        ld a, b
        jr nz, .revs
        srl b
        add a, b
.revs:  ld e, a
        ld d, 0
        ld hl, 0
        ld b, ENGINE_STEP
.m:     add hl, de
        djnz .m
        ex de, hl
        ld hl, ENGINE_IDLE
        or a
        sbc hl, de
        ld (EnginePeriod), hl
        ret

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

SFX_BUMP        EQU 6               ; noise period of the effect
SFX_CRASH       EQU 24

; A = effect (noise period): start a 15-frame noise burst
PlaySfx:
        ld (SfxType), a
        ld a, 15
        ld (SfxTimer), a
        ret
