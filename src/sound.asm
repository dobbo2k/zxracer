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
ENGINE_STEP     EQU 50              ; period decrease per speed unit (EngineUpdate: shifts)

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
.revs:  ld l, a                 ; revs x 50 (ENGINE_STEP) = 32 + 16 + 2
        ld h, 0
        add hl, hl
        ld d, h
        ld e, l                 ; 2
        add hl, hl
        add hl, hl
        add hl, hl
        ld b, h
        ld c, l                 ; 16
        add hl, hl              ; 32
        add hl, bc
        add hl, de
        ex de, hl
        ld hl, ENGINE_IDLE
        or a
        sbc hl, de
        ld (EnginePeriod), hl
        ret

SFX_BUMP        EQU 6               ; noise period of the effect
SFX_CRASH       EQU 24

; A = effect (noise period): start a 15-frame noise burst
PlaySfx:
        ld (SfxType), a
        ld a, 15
        ld (SfxTimer), a
        ret
