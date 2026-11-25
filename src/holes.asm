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
; Arpeggios (semitones of the 2nd and 3rd notes): 1 major, 2 minor,
; 3 seventh, 4 minor seventh, 5 major seventh, 6 sus4, 7 power (5th, octave),
; 8 octave
ArpTab:         db 4, 7,  3, 7,  4, 10,  3, 10,  4, 11,  5, 7,  7, 12,  12, 12
        IFDEF ZX_OBJINK
OBJ_PART        DEFL 4
        INCLUDE "objinkb2.asm"  ; (objects' inks: OCount)
        ENDIF
        ASSERT $ <= ScrLo + 256
        ORG ScrHi + $C4
        ASSERT ScrHi_end <= ScrHi + $C4
; Envelopes: start volume, the volume it fades to, fade every (mask+1)
; 0 pluck, 1 sustained lead, 2 soft, 3 bass, 4 heavy bass, 5 echo
EnvTab:         db 13, 9, 3,  13, 11, 15,  11, 8, 3,  12, 8, 1,  13, 10, 3,  9, 4, 3
        ASSERT $ <= ScrHi + 256
        ORG X1Page + $60
        ASSERT RoadX1_end <= X1Page + $60
; (src/tunnel.asm DrawPortal's working variables: moved here for room)
PtN:            ds 5
PtY:            db 0
PtRow:          db 0
PtTop:          db 0
PtR:            db 0
PtFar:          db 0                ; $FF: too far for the arch
PtGate:         db 0                ; drawing a gantry, not a tunnel
        ASSERT $ <= X1Page + $80
        ORG X1Page + $E0
        ASSERT RoadRW_end <= X1Page + $E0
; (src/music.asm's flags: moved here for room)
MusicOn:        db 0
SoundMode:      db 0
SfxBusy:        db 0                ; a hit has channel B (and the noise)
MixBits:        db 0                ; the mixer setting being built
DrumPtr:        dw 0                ; the drum sounding: its next step (0: none)
SqHold:         db 0                ; interrupts until the next chirp may start
SqTimer:        db 0                ; interrupts left of a chirp
        ASSERT $ <= X1Page + 256
        ORG LWPage + $60
        ASSERT LaneWp_end <= LWPage + $60
; (src/tunnel.asm's colours and where the stage overlay is: moved here for room)
TunWall:        db $48, $08         ; walls: bright blue, blue (light / dark bands)
TUN_LAMP        EQU $76             ; lamps on the walls (src/road.asm RowAttrs): bright yellow
TunKerbs:       db $78, $00         ; kerbs: bright white, black
TunSky:         db C_, C_           ; the ceiling (white ink: the message line; the backdrop is cleared)
        INCLUDE "stageov_pack.asm"
        ASSERT $ <= LWPage + $80
        ORG LWPage + $E0
        ASSERT Band_end <= LWPage + $E0
; (src/extend.asm JingleTick's: moved here for room)
JingleHold:     db 0
; A new stage begins: a short high beep (C) on its first frame (extended
; play: the flourish instead, src/gap4.asm)
JingleGo:
        dw 106
        db 8
        dw 0
        ASSERT $ <= LWPage + 256
        ORG ZPage + $60
        ASSERT ZLo_end <= ZPage + $60
        IFDEF ZX_OBJINK         ; (src/objink.asm: a cell's object and ground
OS:             ds 8            ; pixels, and the bits in a nibble)
OG:             ds 8
NibBits:        db 0, 1, 1, 2, 1, 2, 2, 3, 1, 2, 2, 3, 2, 3, 3, 4
        ASSERT (OS & 15) == 0 && OG == OS + 8 && NibBits == OS + 16
        ENDIF
        ASSERT $ <= ZPage + $80
        ORG ZPage + $E0
        ASSERT LaneW_end <= ZPage + $E0
; (src/stage.asm StageOv's: moved here for room)
OvEntry:        dw 0
OvArg:          db 0
OvBlank:        db 0
; Difficulty (the options screen): 0 easy, 1 normal, 2 hard. The overlay
; reads it for the starting time, the checkpoint bonus, the par times and
; the weaving (src/stageov.asm DiffTable).
Difficulty:     db 1
        ASSERT $ <= ZPage + 256
        ORG DEPage + $60
        ASSERT RoadD_end <= DEPage + $60
; (TunWidth's end, below: moved here for room) E widened by C
TunWidthE:
        ld a, e
        add a, c
        jr nc, .e
        sbc a, a
.e:     ld e, a
        ret
        ASSERT $ <= DEPage + $80
        ORG DEPage + $E0
        ASSERT RoadE_end <= DEPage + $E0
        IFDEF ZX_OBJINK         ; (src/objink.asm) per buffer: a count, then
ClaimA:         db 0            ; the cells to put back
                ds 2 * CLAIMS
        ENDIF
        ASSERT $ <= DEPage + 256
        ORG LXPage + $60
        ASSERT LaneX_end <= LXPage + $60
        IFDEF ZX_OBJINK
ClaimB:         db 0
                ds 2 * CLAIMS
        ENDIF
        ASSERT $ <= LXPage + $80
        ORG LXPage + $E0
        ASSERT ForkT1_end <= LXPage + $E0
        IFDEF ZX_OBJINK         ; (src/objink.asm's working)
OInk:           db 0            ; the object's ink
ORow:           db 0            ; the row
OSky:           db 0            ; its own attribute (the sky's, the backdrop's)
OFork:          db 0            ; a fork's row (no kerb cells)
OList:          dw 0            ; the back buffer's claim list
OAttrAt:        dw 0            ; the cell: its attribute's address,
OAttr:          db 0            ; its attribute
OSrcOk:         db 0            ; OSrcRow's done for the row:
OSrc:           dw 0
OSrcC:          db 0
OSrcN:          db 0            ; (just after OSrcC: src/objink.asm)
OPixHi:         db 0
        ASSERT OSrcN == OSrcC + 1
        ENDIF
        ASSERT $ <= LXPage + 256
        ORG ObjPage + $60
        ASSERT ObjScale_end <= ObjPage + $60
        IFDEF ZX_OBJINK
OBJ_PART        DEFL 1
        INCLUDE "objinkb2.asm"  ; (objects' inks: OListHL)
        ENDIF
        ASSERT $ <= ObjPage + $80
        ORG ObjPage + $E0
        ASSERT SizeForLine_end <= ObjPage + $E0
        IFDEF ZX_OBJINK
OBJ_PART        DEFL 2
        INCLUDE "objinkb2.asm"  ; (objects' inks: OInkOn)
        ENDIF
        ASSERT $ <= ObjPage + 256
        ORG ZHiPage + $60
        ASSERT ZHi_end <= ZHiPage + $60
; (src/extend.asm PrintBig's table: moved here for room)
; a nibble's 4 pixels, each doubled
DblNib:         db $00, $03, $0C, $0F, $30, $33, $3C, $3F, $C0, $C3, $CC, $CF, $F0, $F3, $FC, $FF
        ASSERT high DblNib == high (DblNib + 15)
        IFDEF ZX_OBJINK
OBJ_PART        DEFL 3
        INCLUDE "objinkb2.asm"  ; (objects' inks: putting their cells back)
        ENDIF
        ASSERT $ <= ZHiPage + 256
        ORG MaskPage + $20
        ASSERT LMaskIncl_end <= MaskPage + $20
        ASSERT $ <= MaskPage + $40
        ORG MaskPage + $C0
        ASSERT LaneM2_end <= MaskPage + $C0
LampGlyph:
        db $07,$E0,$18,$18,$33,$CC,$67,$E6,$4F,$F2,$DF,$FB,$9F,$F9,$BF,$FD
        db $BF,$FD,$9F,$F9,$DF,$FB,$4F,$F2,$67,$E6,$33,$CC,$18,$18,$07,$E0
; the route of the last game (the stage played on each row; $FF: not reached)
Route:          ds 5, $FF
; the music's snare drum (src/music.asm)
DrumSnare:      db 14, (6 * AYN + AYD / 2) / AYD
                dw (250 * AYN + AYD / 2) / AYD
                db 13, (7 * AYN + AYD / 2) / AYD
                dw 0
                db 11, (8 * AYN + AYD / 2) / AYD
                dw 0
                db 9, (9 * AYN + AYD / 2) / AYD
                dw 0
                db 6, (10 * AYN + AYD / 2) / AYD
                dw 0
                db 3, (10 * AYN + AYD / 2) / AYD
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
                dw (300 * AYN + AYD / 2) / AYD
                db 14, 0
                dw (600 * AYN + AYD / 2) / AYD
                db 12, 0
                dw (1000 * AYN + AYD / 2) / AYD
                db 10, 0
                dw (1500 * AYN + AYD / 2) / AYD
                db 7, 0
                dw (2100 * AYN + AYD / 2) / AYD
                db 4, 0
                dw (2800 * AYN + AYD / 2) / AYD
                db 0
DrumHat:        db 10, (1 * AYN + AYD / 2) / AYD
                dw 0
                db 6, (1 * AYN + AYD / 2) / AYD
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
        ld e, GRAVEL_NOISE      ; noise period
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
.mx:    jp TunEcho              ; (src/tunnel.asm: C free - a tunnel's echo?)
.mw:    ld a, 7
        jp AyWrite
; (a checkpoint message: moved here from bank 5 for room)
; The checkpoint's messages (filled in by OvCheckpoint)
MsgTime:        db " STAGE TIME 0'00", $22, "00 ", 0
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
; (the last ten seconds: moved here from bank 5 for room)
; The last 10 seconds (GameUpdate, each second): the big timer's cells
; FLASH in both screens (the next display reset clears it).
TimeWarn:
        ld a, (PalTime)
        or $80
        IFNDEF NATIVE_GFX       ; (the Einstein, the CPC: screen B only)
        ld hl, $5800 + 32 + 14
        call .cells
        ENDIF
        ld hl, $D800 + 32 + 14
.cells: ld c, 2
.row:   ld b, 4
.c:     ld (hl), a
        inc l
        djnz .c
        ld de, 32 - 4
        add hl, de
        dec c
        jr nz, .row
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
        add a, (6 * AYN + AYD / 2) / AYD
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
; (a checkpoint message: moved here from bank 5 for room)
MsgBonus:       ds MSG_LEN + 1
        ASSERT $ <= StateA3 + 256
        ORG StateB3 + $8C
        ASSERT RowBBand_end <= StateB3 + $8C
CrashTickA:                     ; A: squeal while spinning, else the thud
        ld a, (Spin)
        or a
        jr z, .thud
        ld a, (FrameCount)      ; the squeal: a wavering high tone
        and 6
        add a, SQ_TONE
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
        IFDEF EINSTEIN
        call EinCoarse          ; (the AY at 2 MHz: src/einstein/boot.asm)
        ELSE
        IFDEF CPC
        call CpcCoarse          ; (the AY at 1 MHz: src/cpc/boot.asm)
        ELSE
        ld e, 0
        ENDIF
        ENDIF
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

; A new stage with music (MusicWait set, src/stage.asm StageOvE): each
; interrupt, from JingleTick, only the jingle - no engine, no tune - until
; it has played out, then MusicWait counts a short gap and the tune starts
MusicWaitTick:
        pop hl                  ; (out of SoundTick: nothing else this interrupt)
        call JingleRun
        ld a, (JingleHold)      ; the jingle still to come or playing?
        ld hl, (JinglePtr)
        or h
        or l
        ld hl, BeepTime
        or (hl)
        jp z, MusicGap
        ld a, (hl)              ; a note: its time, and its end (the music would)
        or a
        ret z
        dec (hl)
        ret nz
        ld e, (hl)
        ld a, 10                ; (volume C off)
        jp AyWrite
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
MusicGap:                       ; (MusicWaitTick: the gap, then the tune)
        ld hl, MusicWait
        dec (hl)
        ret nz
        jp MusicTheme
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
        add a, (24 * AYN + AYD / 2) / AYD
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
; (tunnels: moved here from bank 5 for room)
; Tunnels (src/tunnel.asm): each game frame, which road lines are in this
; stage's tunnel and whether the car is in it
UpdateTunnel:
        ld hl, (TunEnd)
        ld a, h
        or l
        jr z, .none
        ld de, (Pos)
        sbc hl, de              ; (no carry after the OR) -> to its end
        jr c, .none             ; behind us
        jr z, .none
        push hl
        ld hl, (TunStart)
        or a
        sbc hl, de              ; to its start
        ld a, ROAD_LINES        ; in it: down to the bottom line
        ld c, 1
        jr c, .in
        jr z, .in
        dec c
        ld a, h
        cp high 4096
        jr nc, .far             ; beyond the furthest road line
        ex de, hl
        call ObjLine            ; the last line at or beyond its start ...
        inc a                   ; ... the next is nearer: out of it
.in:    ld b, a                 ; B: the first line out of it (nearer), C: in it
        pop de                  ; to its end
        xor a
        ld h, a
        ld a, d
        cp high EXIT_SEE
        ld a, h
        jr nc, .j0              ; (its end too far to see: in it up to the furthest line)
        push bc
        call ObjLine
        pop bc
        inc a                   ; the first line nearer than its end
.j0:    ld (TunJ0), a
        ld e, a
        ld a, b
        sub e
        jr nc, .jn
        xor a
.jn:    ld (TunJN), a
        ld a, c
        jp Ceiling
.far:   pop hl
.none:  xor a
        ld (TunJN), a
        jp Ceiling
; The open hi-hat (src/music.asm DrumTab): moved here for room
DrumOpen:       db 11, (1 * AYN + AYD / 2) / AYD
                dw 0
                db 9, (1 * AYN + AYD / 2) / AYD
                dw 0
                db 7, (1 * AYN + AYD / 2) / AYD
                dw 0
                db 5, (1 * AYN + AYD / 2) / AYD
                dw 0
                db 3, (1 * AYN + AYD / 2) / AYD
                dw 0
                db 0
        ASSERT $ <= FILL_END - 64
        ORG Gap2Free            ; (after the starting lights, before the XOR chain)
; (src/tunnel.asm DrawPortal's: moved here for room) A tunnel's mouth: B, D,
; E = the road's width and edges on the line where it meets it, HL = DEPage
; + $80 + the line. B becomes the road's width at the mouth's own depth line
; (the nearest in it: from outside the way out is never in sight, so the
; tunnel's lines start at 0) and D, E are widened by as much as that is
; more than at the line shown there. Beyond a crest the nearest line in the
; tunnel that shows can be much further in than the mouth, and the opening
; shrank and grew as the hill hid and showed lines; and close by, with the
; road's edge off the screen, its width on the screen made the opening too
; low (the arch dropped, its rows left above it). (An edge off the screen
; stays there.) C changed.
TunWidth:
        ld h, high SrcLine      ; (L = $80 + the line)
        ld l, (hl)
        ld h, high X1Page
        ld c, (hl)              ; the road's half-width at the line shown
        ld a, (TunJN)
        dec a
        ld l, a
        ld a, (hl)              ; ... and at the mouth
        add a, a
        jr nc, .w
        sbc a, a                ; (255 at most)
.w:     ld b, a
        ld a, (hl)
        sub c
        ld c, a                 ; how much wider there
        ld a, d
        sub c
        jr nc, .d
        xor a
.d:     ld d, a
        jp TunWidthE
        ASSERT low SrcLine == $80
        ASSERT $ <= XOR_END - 5 * 8
