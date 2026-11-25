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
ENGINE_IDLE     EQU (1400 * AYN + AYD / 2) / AYD    ; tone period at standstill (~80 Hz)
ENGINE_STEP     EQU 50              ; period decrease per speed unit (EngineUpdate: shifts;
                                    ; the Einstein's 2 MHz AY: 56, the CPC's 1 MHz: 28)

; A = register, E = value
AyWrite:
        IFDEF CPC               ; (A, E and the flags kept; BC used)
        push af                 ; (a value it holds already: not written, but
        cp 13                   ; the envelope's shape, which restarts it; a
        jr z, .w                ; write through the PPI is about 30 us)
        add a, low CAyShadow
        ld c, a
        ld b, high CAyShadow
        ld a, (bc)
        cp e
        jr z, .same
        ld a, e
        ld (bc), a
        pop af
        push af
        jr .w
.same:  pop af
        ret
.w:
        ld b, $F4               ; the AY's bus is the PPI's port A, its
        out (c), a              ; function port C's bits 6-7: the register
        ld bc, $F6C0            ; selected,
        out (c), c
        ld c, 0
        out (c), c
        cp 7                    ; (the mixer: port A an input, for the
        ld a, e                 ; keyboard, and port B)
        jr nz, .v
        and $3F
.v:     ld b, $F4
        out (c), a              ; its value written
        ld bc, $F680
        out (c), c
        ld c, 0
        out (c), c
        pop af
        ret
        ENDIF
        IFDEF EINSTEIN
        out (EIN_PSG_SELECT), a ; (A kept, as on the Spectrum)
        push af
        cp 7                    ; the mixer: port A out (the keyboard's rows),
        ld a, e                 ; port B in (its columns)
        jr nz, .w
        and $3F
        or $40
.w:     out (EIN_PSG_WRITE), a
        pop af
        ret
        ELSE
        ld bc, AY_SEL
        out (c), a
        ld b, high AY_DATA
        out (c), e
        ret
        ENDIF

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
        IFDEF EINSTEIN          ; (revs x 56 = 32 + 16 + 8: 50 at 2 MHz)
        add hl, hl
        add hl, hl
        add hl, hl
        ld d, h
        ld e, l                 ; 8
        add hl, hl
        ld b, h
        ld c, l                 ; 16
        add hl, hl              ; 32
        ELSE
        IFDEF CPC               ; (revs x 28 = 16 + 8 + 4: 50 at 1 MHz)
        add hl, hl
        add hl, hl
        ld d, h
        ld e, l                 ; 4
        add hl, hl
        ld b, h
        ld c, l                 ; 8
        add hl, hl              ; 16
        ELSE
        add hl, hl
        ld d, h
        ld e, l                 ; 2
        add hl, hl
        add hl, hl
        add hl, hl
        ld b, h
        ld c, l                 ; 16
        add hl, hl              ; 32
        ENDIF
        ENDIF
        add hl, bc
        add hl, de
        ex de, hl
        ld hl, ENGINE_IDLE
        or a
        sbc hl, de
        ld (EnginePeriod), hl
        ret

SFX_BUMP        EQU (6 * AYN + AYD / 2) / AYD  ; noise period of the effect
SFX_CRASH       EQU (24 * AYN + AYD / 2) / AYD
GRAVEL_NOISE    EQU (12 * AYN + AYD / 2) / AYD ; off the road
SQ_TONE         EQU (40 * AYN + AYD / 2) / AYD ; the tyre squeal's tone (and up to 6 more)

; A = effect (noise period): start a 15-frame noise burst
PlaySfx:
        ld (SfxType), a
        ld a, 15
        ld (SfxTimer), a
        ret
