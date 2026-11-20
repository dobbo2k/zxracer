; ---------------------------------------------------------------------------
; AY-3-8912 sound effects, updated from the 50 Hz interrupt.
;   A: engine - square wave, pitch rising with speed, with a small wobble
;      every interrupt so it sounds like a motor rather than a beep
;   B: gravel noise while off the road
;   C: tyre squeal in hard bends at speed
; (Music will take A/B later, with the engine moving to C.)
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
        ld a, (Speed)
        ld e, a
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

SoundTick:
        ld a, (Mute)            ; (the title / goal screens make their own)
        or a
        ret nz
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
        jr .squeal
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
.squeal:
        ; squeal: high tone on C while the tyres smoke (near the grip limit)
        ld e, 0
        ld a, (Squeal)
        or a
        jr z, .sq
        ld a, (FrameCount)
        and 6
        add a, 40               ; wavering high pitch
        ld e, a
        ld a, 4
        call AyWrite
        ld e, 0
        ld a, 5
        call AyWrite
        ld e, 8
.sq:    ld a, 10
        call AyWrite
        ; mixer: tone A, tone C, noise B (0 bits enable)
        ld e, %00101010
        ld a, 7
        jp AyWrite

SFX_BUMP        EQU 6               ; noise period of the effect
SFX_CRASH       EQU 24

; A = effect (noise period): start a 15-frame noise burst
PlaySfx:
        ld (SfxType), a
        ld a, 15
        ld (SfxTimer), a
        ret
