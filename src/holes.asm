; ---------------------------------------------------------------------------
; Data in the unused ends of the lookup-table pages (bank 2, src/main.asm
; includes tables.asm). Most tables fill 96 or 192 bytes of their 256-byte
; page; nothing reads or writes past them - checked with zxsim -u over whole
; games (PLAN.md) - except one byte after ScrLo and ScrHi, kept clear, and
; the parts of the state pages OvResetDisplay clears. Besides data, two
; routines that are not time-critical live in the state pages' holes. The
; ASSERTs keep a table from growing into what follows it.
; ---------------------------------------------------------------------------
        ORG ScrLo + $C4         ; (ScrLo + $C0..$C3 kept clear)
        ASSERT ScrLo_end <= ScrLo + $C4
CrewSay0a: db "< WATCH THE ROAD!   ", 0
CrewSay0b: db "   SORRY, SORRY... >", 0
; Arpeggios (semitones of the 2nd and 3rd notes): 1 major, 2 minor,
; 3 seventh, 4 minor seventh, 5 major seventh, 6 sus4, 7 power (5th, octave),
; 8 octave
ArpTab:         db 4, 7,  3, 7,  4, 10,  3, 10,  4, 11,  5, 7,  7, 12,  12, 12
        ASSERT $ <= ScrLo + 256
        ORG ScrHi + $C4
        ASSERT ScrHi_end <= ScrHi + $C4
CrewSay1a: db "< ARE YOU BLIND?!   ", 0
CrewSay1b: db "  THE SUN WAS LOW! >", 0
; Envelopes: start volume, the volume it fades to, fade every (mask+1)
; 0 pluck, 1 sustained lead, 2 soft, 3 bass, 4 heavy bass
EnvTab:         db 13, 9, 3,  13, 11, 15,  11, 8, 3,  12, 8, 1,  13, 10, 3
        ASSERT $ <= ScrHi + 256
        ORG X1Page + $60
        ASSERT RoadX1_end <= X1Page + $60
CrewSay2a: db "< MY HAIR! MY HAIR! ", 0
        ASSERT $ <= X1Page + $80
        ORG X1Page + $E0
        ASSERT RoadRW_end <= X1Page + $E0
CrewSay2b: db "   IT LOOKS GREAT! >", 0
        ASSERT $ <= X1Page + 256
        ORG LWPage + $60
        ASSERT LaneWp_end <= LWPage + $60
CrewSay3a: db "< LET ME DRIVE!     ", 0
        ASSERT $ <= LWPage + $80
        ORG LWPage + $E0
        ASSERT Band_end <= LWPage + $E0
CrewSay3b: db "   NOT A CHANCE... >", 0
        ASSERT $ <= LWPage + 256
        ORG ZPage + $60
        ASSERT ZLo_end <= ZPage + $60
CrewSay4a: db "< NICE ONE, GENIUS! ", 0
        ASSERT $ <= ZPage + $80
        ORG ZPage + $E0
        ASSERT LaneW_end <= ZPage + $E0
CrewSay4b: db "    IT JUMPED OUT! >", 0
        ASSERT $ <= ZPage + 256
        ORG DEPage + $60
        ASSERT RoadD_end <= DEPage + $60
CrewSay5a: db "< I SAID SLOW DOWN! ", 0
        ASSERT $ <= DEPage + $80
        ORG DEPage + $E0
        ASSERT RoadE_end <= DEPage + $E0
CrewSay5b: db "   I WAS GOING TO! >", 0
        ASSERT $ <= DEPage + 256
        ORG LXPage + $60
        ASSERT LaneX_end <= LXPage + $60
CrewSay6a: db "< LOSE THE SHADES!  ", 0
        ASSERT $ <= LXPage + $80
        ORG LXPage + $E0
        ASSERT ForkT1_end <= LXPage + $E0
CrewSay6b: db " THEY LOOK COOL... >", 0
        ASSERT $ <= LXPage + 256
        ORG ObjPage + $60
        ASSERT ObjScale_end <= ObjPage + $60
CrewSay7a: db "< OPEN YOUR EYES!   ", 0
        ASSERT $ <= ObjPage + $80
        ORG ObjPage + $E0
        ASSERT SizeForLine_end <= ObjPage + $E0
CrewSay7b: db "    THEY ARE OPEN! >", 0
        ASSERT $ <= ObjPage + 256
        ORG ZHiPage + $60
        ASSERT ZHi_end <= ZHiPage + $60
CrewTraffic:
        dw CrewSayT0a, CrewSayT0b
        dw CrewSayT1a, CrewSayT1b
        dw CrewSayT2a, CrewSayT2b
        dw CrewSay4a, CrewSay4b
CrewSayT0a: db "< YOU HIT A LORRY!  ", 0
CrewSayT0b: db "   IT BRAKED HARD! >", 0
CrewSayT1a: db "< YOU TAILGATED HIM!", 0
CrewSayT1b: db " HE WAS IN MY WAY! >", 0
CrewSayT2a: db "< LOOK AT THAT DENT!", 0
CrewSayT2b: db "   THAT WAS THERE! >", 0
        ASSERT $ <= ZHiPage + 256
        ORG MaskPage + $20
        ASSERT LMaskIncl_end <= MaskPage + $20
CrewLines:      ; her line, his reply
        dw CrewSay0a, CrewSay0b
        dw CrewSay1a, CrewSay1b
        dw CrewSay2a, CrewSay2b
        dw CrewSay3a, CrewSay3b
        dw CrewSay4a, CrewSay4b
        dw CrewSay5a, CrewSay5b
        dw CrewSay6a, CrewSay6b
        dw CrewSay7a, CrewSay7b
        ASSERT $ <= MaskPage + $40
        ORG MaskPage + $C0
        ASSERT LaneM2_end <= MaskPage + $C0
LampGlyph:
        db $00, $00, $03, $C0, $0F, $F0, $1F, $F8, $3F, $FC, $3F, $FC, $7F, $FE, $7F, $FE
        db $7F, $FE, $7F, $FE, $3F, $FC, $3F, $FC, $1F, $F8, $0F, $F0, $03, $C0, $00, $00
; the route of the last game (the stage played on each row; $FF: not reached)
Route:          ds 5, $FF
; the music's snare drum (src/music.asm)
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
        ASSERT $ <= MaskPage + 256
        ORG StripPage + $39
        ASSERT StripR_end <= StripPage + $39
; The high-score table (score: 4 BCD bytes, low byte first; initials)
HI_ENTRIES      EQU 5
HI_SIZE         EQU 7
HiTable:
        db $00, $00, $06, $00, "ACE"
        db $00, $00, $05, $00, "SUN"
        db $00, $00, $04, $00, "RUN"
        db $00, $00, $03, $00, "BOB"
        db $00, $00, $02, $00, "DOT"
; AY tone periods of the music's notes, C2 to B6 (tools/make_music.py)
NoteTab:
        INCLUDE "music_notes.asm"
; the music's kick drum and hi-hat (src/music.asm)
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
DrumHat:        db 10, 1
                dw 0
                db 6, 1
                dw 0
                db 0
        ASSERT $ <= StripPage + 256

; The state pages (src/stageov.asm OvResetDisplay clears only their tables)
        ORG StateA2 + $60
        ASSERT StALane_end <= StateA2 + $60
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
        ASSERT $ <= StateA2 + 256
        ORG StateB2 + $60
        ASSERT StBLane_end <= StateB2 + $60
; The demo driver, near no fork: the traffic decides (see DemoTarget)
DemoTraffic:
        ld hl, DEMO_LOOK
        ld (DemoAny), hl
        ld ix, Traffic
        ld a, (NTraffic)
        ld b, a
.car:   ld l, (ix + 0)
        ld h, (ix + 1)
        ld de, (Pos)
        or a
        sbc hl, de              ; z_rel
        bit 7, h
        jr nz, .next            ; behind
        ld de, (DemoAny)
        push hl
        sbc hl, de              ; (carry clear)
        pop hl
        jr nc, .path
        ld (DemoAny), hl        ; the nearest ahead, in any lane
        ld a, (ix + 5)
        ld (DemoHead), a
.path:  ld de, (DemoNear)
        push hl
        sbc hl, de
        pop hl
        jr nc, .next
        push hl
        push bc
        ld bc, HIT_WIDEST
        call LaneOverlapBC      ; carry: in the player's path
        pop bc
        pop hl
        jr nc, .next
        ld (DemoNear), hl       ; the nearest in its path
.next:  ld de, CAR_SIZE
        add ix, de
        djnz .car
        ; the middle until a vehicle is near; then the outer edge of the
        ; road, away from where that one is heading, and that side from then
        ; on (the lanes are at +-56: no vehicle reaches a car out there)
        ld hl, (DemoAim)
        ld a, h
        or l
        ret nz                  ; keep to the side it chose
        ld hl, (DemoAny)
        ld de, DEMO_LOOK
        sbc hl, de              ; (carry clear)
        ld hl, 0
        ret z
        ld hl, -DEMO_SIDE
        ld a, (DemoHead)
        rlca
        jr nc, .aim
        ld hl, DEMO_SIDE
.aim:   ld (DemoAim), hl
        ret
        ASSERT $ <= StateB2 + 256
        ORG StateA3 + $8C
        ASSERT RowABand_end <= StateA3 + $8C
; A crash (CrashStart): the AY is its own until it fades. B: a noise burst,
; a crack deepening to a rumble, held then fading; A: a falling, gritty
; thud (or, spinning, the tyre squeal); C: clattering debris. From the
; interrupt (AF, BC, DE, HL free).
CrashTick:
        ld a, %00101111         ; mixer: noise B on, the rest as we go
        ld (CrMix), a
        ld hl, CrashAge
        inc (hl)
        ld a, (CrashHold)
        or a
        jr z, .fade
        dec a
        ld (CrashHold), a
        jr .vol
.fade:  ld hl, CrashCnt
        dec (hl)
        jr nz, .vol
        ld a, (CrashRate)
        ld (hl), a
        ld hl, CrashVol
        dec (hl)
        jr z, .end
.vol:   ld a, (CrashVol)
        ld e, a
        ld a, 9
        call AyWrite
        ld a, (CrashAge)        ; noise: a crack, deepening
        srl a
        add a, 6
        cp 31
        jr c, .np
        ld a, 31
.np:    ld e, a
        ld a, 6
        call AyWrite
        jp CrashTickA
.end:   xor a
        ld (CrashOn), a
        ld e, a
        ld a, 8
        call AyWrite
        ld e, 0
        ld a, 9
        call AyWrite
        ld e, 0
        ld a, 10
        jp AyWrite
        ASSERT $ <= StateA3 + 256
        ORG StateB3 + $8C
        ASSERT RowBBand_end <= StateB3 + $8C
CrashTickA:                     ; A: squeal while spinning, else the thud
        ld a, (Spin)
        or a
        jr z, .thud
        ld a, (FrameCount)      ; the squeal: a wavering high tone
        and 6
        add a, 40
        ld e, a
        ld d, 0
        ld a, 10
        jr .tone
.thud:  ld a, (CrashI)          ; the thud: falling (coarse period 2..9),
        cp 6                    ; fading over 16 interrupts
        jr c, .aoff
        ld a, (CrashAge)
        cp 16
        jr nc, .aoff
        ld e, a
        srl a
        add a, 2
        ld d, a
        ld a, 15
        sub e
        ld e, 0
.tone:  ld (CrVolA), a
        ld hl, CrMix
        res 0, (hl)             ; tone A
        res 3, (hl)             ; and noise A: grit
        xor a
        call AyWrite
        ld e, d
        ld a, 1
        call AyWrite
        ld a, (CrVolA)
        ld e, a
        jr .avol
.aoff:  ld e, 0
.avol:  ld a, 8
        call AyWrite
        jp CrashTickC
        ASSERT $ <= StateB3 + 256
        ORG StateA1 + $E0
        ASSERT StAE_end <= StateA1 + $E0
CrashMix:
        ld a, (CrMix)
        ld e, a
        ld a, 7
        jp AyWrite
CrMix:          db 0
CrVolA:         db 0
CrashOn:        db 0
CrashI:         db 0            ; the speed at impact
CrashAge:       db 0
CrashHold:      db 0
CrashRate:      db 0
CrashCnt:       db 0
CrashVol:       db 0
        ASSERT $ <= StateA1 + 256
        ORG StateB1 + $60
        ASSERT StBD_end <= StateB1 + $60
; The music keeps time through a crash: its channels step on, unheard
MusicKeep:
        ld a, (Paged)
        or a
        ret nz
        push ix
        ld ix, ChanA
        call MusicStep
        ld ix, ChanB
        call MusicStep
        ld ix, ChanC
        call MusicStep
        pop ix
        ret
        ASSERT $ <= StateB1 + $80
        ORG StateB1 + $E0
        ASSERT StBE_end <= StateB1 + $E0
; Stage records: each stage's best time (50 Hz frames, 0: none yet), kept
; until the Spectrum is switched off (the route screen sets them)
StageBest:      ds 15 * 2
        ASSERT $ <= StateB1 + 256
        ORG Gap3Free            ; (after the starting lights, src/main.asm)
CrashTickC:                     ; C: debris, a clatter of high notes
        ld e, 0
        ld a, (CrashI)
        cp 12
        jr c, .c
        ld a, (CrashAge)
        cp 40
        jr nc, .c
        rra
        jr c, .c                ; (every other interrupt)
        ld e, a
        add a, a
        add a, e
        and 31
        add a, 24
        ld e, a                 ; a high, jumping pitch
        ld a, 4
        call AyWrite
        ld e, 0
        ld a, 5
        call AyWrite
        ld hl, CrMix
        res 2, (hl)
        ld e, 11
.c:     ld a, 10
        call AyWrite
        jp CrashMix
        ASSERT $ <= FILL_END - 64
