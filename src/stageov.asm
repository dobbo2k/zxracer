; ---------------------------------------------------------------------------
; The between-stages overlay: loading a stage (its packs into the caches,
; the track state, the traffic) and the stage table. It only runs at a stage
; change, at power-on and between games - each time the screen is about to
; be cleared (ResetDisplay) or replaced by the front end - so it runs from
; screen A: StageOv (src/stage.asm) shows screen B, copies this in from its
; pack bank and calls one of the Ov... entries. Assembled to run at $4000.
; ---------------------------------------------------------------------------

EXTRA_BONUS     EQU $10             ; BCD seconds more at a checkpoint for a stage under its par time
NAME_FRAMES     EQU 120             ; how long the new stage's name shows

; A = stage: the packs again after the front end (the demo carries on)
OvReloadStage:
        call LoadPacks
        jp OvResetDisplay

; The front-end overlay into bank 7 (over the theme cache)
OvLoadFrontEnd:
        ld hl, FrontEndPack
        ld a, (hl)
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)
        inc hl
        ld c, (hl)
        inc hl
        ld b, (hl)
        ld hl, THEME_CACHE
        jp CopyToCache

; A new game: the clock, the score and the starting lights afresh, from the
; first stage
OvStartGame:
        ld a, ST_PLAYING
        ld (GameState), a
        xor a
        IF AUTOPLAY
        inc a                   ; video build: the autopilot keeps driving
        ENDIF
        ld (DemoMode), a
        xor a
        ld (SecTick), a
        ld hl, Score
        ld (hl), a
        inc hl
        ld (hl), a
        inc hl
        ld (hl), a
        inc hl
        ld (hl), a
        call DiffEntry          ; the starting time
        ld a, (hl)
        ld (Time), a
        ld a, LIGHTS_TIME
        ld (Lights), a
        ld a, $FF
        ld (LampState), a
        ld a, FIRST_STAGE
        call RestartState
        call LoadStage
        jp NameShow             ; the first stage's name

; A = stage: from its start, standing still
OvRestartAt:
        call RestartState
        call LoadStage
        jp OvResetDisplay

; The end of a stage that is not the last: its time recorded, onto the
; branch the car is on (left or right), extra time - more under the stage's
; par time (extended play) - and the messages: the time, the bonus, the new
; stage's name.
OvCheckpoint:
        ld a, (StageRow)        ; this stage's time, for the results
        add a, a
        ld e, a
        ld d, 0
        ld hl, StageTimes - 2
        add hl, de
        ld de, (StageClock)
        ld (hl), e
        inc hl
        ld (hl), d
        ld a, (Stage)
        call StageEntry
        push hl
        ld de, 13
        add hl, de
        ld e, (hl)              ; par time
        inc hl
        ld d, (hl)
        ld a, (Difficulty)      ; easy: + 1/8, hard: - 1/16
        cp 1
        jr z, .par
        ld h, d
        ld l, e
        srl h
        rr l
        srl h
        rr l
        srl h
        rr l
        or a                    ; (A = 0: easy)
        jr nz, .hard
        add hl, de
        jr .pd
.hard:  srl h
        rr l
        ex de, hl
        or a
        sbc hl, de
.pd:    ex de, hl
.par:   ld hl, (StageClock)
        or a
        sbc hl, de
        sbc a, a                ; $FF: under par
        ld (OvFast), a
        pop hl
        ld de, 10
        add hl, de              ; -> left, right
        ld a, (PlayerX + 1)
        bit 7, a
        jr nz, .left
        inc hl
.left:  ld a, (hl)
        push af
        ld hl, (PlayerX)        ; onto the middle of the new road
        ld de, (PlayerDx)
        bit 7, h
        jr nz, .rl
        or a
        sbc hl, de
        jr .rb
.rl:    add hl, de
.rb:    ld (PlayerX), hl
        ld hl, (Pos)            ; carry the overshoot into the new stage
        ld de, (StageLen)
        or a
        sbc hl, de
        ld (Pos), hl
        pop af
        call LoadStage
        ld hl, (StageClock)     ; (the time, for the message)
        push hl
        ld hl, 0
        ld (StageClock), hl
        pop hl
        ld a, (GameState)
        cp ST_PLAYING
        jp nz, OvResetDisplay   ; (attract mode)
        ld de, MsgTime + 12
        call FmtTime
        ; the bonus: its message and the extra time
        call DiffEntry
        inc hl
        ld c, (hl)              ; this level's bonus
        ld a, 1                 ; a beep as the new stage shows (or the flourish)
        ld (JingleHold), a
        ld hl, JingleGo
        ld (JinglePtr), hl
        ld hl, TxtTimeBonus
        ld a, (OvFast)
        or a
        jr z, .b
        ld hl, JingleExt        ; with a flourish
        ld (JinglePtr), hl
        ld a, c
        add a, EXTRA_BONUS
        daa
        ld c, a
        ld hl, TxtExtended
.b:     ld de, MsgBonus
        ld a, c
        ld bc, MSG_LEN + 1
        ldir
        ld hl, MsgBonus + BONUS_AT
        ld c, a
        rrca
        rrca
        rrca
        rrca
        and $0F
        add a, "0"
        ld (hl), a
        inc hl
        ld a, c
        and $0F
        add a, "0"
        ld (hl), a
        ld a, (Time)
        add a, c
        daa
        jr nc, .t
        ld a, $99
.t:     ld (Time), a
        call StageMessage
        ld hl, MsgTime          ; the bonus, then the time, then the name
        ld (MsgThen), hl
        ld hl, MsgBuf
        ld (MsgThen + 2), hl
        ld hl, MsgBonus
        ld (Message), hl
        ld a, MSG_FRAMES
        ld (StateTimer), a
        jp OvResetDisplay
OvFast:         db 0
BONUS_AT        EQU 17
TxtTimeBonus:   db "   TIME BONUS   +00 ", 0
TxtExtended:    db " EXTENDED PLAY! +00 ", 0

; The stage's name for a while (a new game)
NameShow:
        call StageMessage
        ld a, NAME_FRAMES
        ld (StateTimer), a
        jp OvResetDisplay

; A = stage (kept): a new run from the stage's start, standing still
RestartState:
        push af
        ld hl, Route            ; a new run: no route yet
        ld b, 5
.rt:    ld (hl), $FF
        inc hl
        djnz .rt
        ld hl, MsgThen          ; no messages queued, no stage times
        ld b, RUN_VARS
.rv:    ld (hl), 0
        inc hl
        djnz .rv
        ld hl, 0                ; no jingle
        ld (JinglePtr), hl
        ld hl, START_POS
        ld (Pos), hl
        ld hl, 0
        ld (PlayerX), hl
        ld (LatVX), hl
        xor a
        ld (StageDone), a
        ld (Gear), a            ; LOW
        ld (SpeedFrac), hl      ; (and Speed)
        ld (LatAcc), hl
        ld (Sliding), a
        ld (CrashTimer), a
        ld (Spin), a
        ld (CrashOn), a         ; (no crash sound left over)
        ld a, 1 << IN_FIRE      ; (a fire press that started the game is no gear change)
        ld (FireWas), a
        pop af
        ret

; Message line: the new stage's name, centred.
StageMessage:
        ld hl, MsgBuf
        ld de, MsgBuf + 1
        ld bc, MSG_LEN - 1
        ld (hl), " "
        ldir
        ld hl, (StName)
        ld b, 0
.len:   ld a, (hl)
        or a
        jr z, .gotLen
        inc hl
        inc b
        jr .len
.gotLen:
        ld a, MSG_LEN
        sub b
        srl a
        ld e, a
        ld d, 0
        ld hl, MsgBuf
        add hl, de
        ex de, hl
        ld hl, (StName)
        ld c, b
        ld b, 0
        ldir
        ld hl, MsgBuf
        ld (Message), hl
        ret

; Per difficulty: the starting time, the time added at a checkpoint (BCD)
DiffTable:
        db $80, $55             ; easy
        db START_TIME, $48      ; normal
        db $60, $44             ; hard
; HL -> this difficulty's DiffTable entry
DiffEntry:
        ld a, (Difficulty)
        add a, a
        ld l, a
        ld h, 0
        ld de, DiffTable
        add hl, de
        ret

; A = stage -> HL = its entry in the stage table
StageEntry:
        ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl              ; 16 bytes per stage
        ld de, StageTable
        add hl, de
        ret

; A = stage index: load its theme and track, reset the track state and
; the traffic.
LoadStage:
        call LoadPacks
        jp StageHeaders

; A = stage index: copy its theme and track packs into the caches (and
; nothing else: the demo carries on after the front end with this).
LoadPacks:
        push af
        call WaitFlip           ; (no flip may happen while banks are paged)
        pop af
        ld (Stage), a
        call StageEntry
        ; ---- theme pack -> THEME_CACHE, via TRACK_CACHE
        ld a, (hl)
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)
        inc hl
        ld c, (hl)
        inc hl
        ld b, (hl)
        inc hl
        push hl
        ld hl, THEME_CACHE
        call CopyToCache
        pop hl                  ; stage table pointer
        ; ---- track pack -> TRACK_CACHE
        ld a, (hl)
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)
        inc hl
        ld c, (hl)
        inc hl
        ld b, (hl)
        inc hl
        push hl
        ex de, hl
        ld de, TRACK_CACHE
        call CopyFromBank
        pop hl
        inc hl
        inc hl
        ld a, (hl)
        ld (StageRow), a
        ld e, a                 ; the route: this row's stage
        ld d, 0
        ld hl, Route - 1
        add hl, de
        ld a, (Stage)
        ld (hl), a
        ; StageEntry is shared by the route logic. Art has its own five-byte
        ; directory entry, so the existing track and fork offsets stay fixed.
        ld l, a
        ld h, 0
        ld d, h
        ld e, l
        add hl, hl
        add hl, hl
        add hl, de
        ld de, RoundArtTable
        add hl, de
        ld a, (hl)
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)
        inc hl
        ld c, (hl)
        inc hl
        ld b, (hl)
        ex de, hl
        IFDEF EINSTEIN
        ; InitHud marks cells in the name-buffer area. Keep the compressed
        ; streams in screen-A scratch until all of the HUD writes are done.
        ld (EinArtLength + 1), bc
        ld de, BaseNames
        call EinRead
        ld hl, BaseNames
        ld de, THEME_CACHE + 6
        ld bc, 9
        ldir
        ret
        ELSE
        ld de, ART_INPUT
        call CopyFromBank
        ld hl, ART_INPUT
        ld de, THEME_CACHE + 6  ; tunnel exits also read the stage's own colours
        ld bc, 9
        ldir
        ld de, ART_BITMAP
        call UnLZ
        ld hl, ART_BITMAP
        ld de, PANO_CACHE
        ld bc, 512
        ldir
        ; DE = second panorama. Keep the first nibble for the seam of each row.
        ld hl, ART_BITMAP
        ld c, 16
.row:   ld a, (hl)
        rrca
        rrca
        rrca
        rrca
        and 15
        ld (.wrap + 1), a
        ld b, 31
.byte:  ld a, (hl)
        inc hl
        ; Form (current << 4) | (next >> 4).
        rlca
        rlca
        rlca
        rlca
        and $F0
        push bc
        ld b, a
        ld a, (hl)
        rrca
        rrca
        rrca
        rrca
        and 15
        or b
        pop bc
        ld (de), a
        inc de
        djnz .byte
        ld a, (hl)
        inc hl
        rlca
        rlca
        rlca
        rlca
        and $F0
.wrap:  or 0
        ld (de), a
        inc de
        dec c
        jr nz, .row
        ret

        ENDIF

; Scratch in the hidden display, beyond the overlay and below screen-A data.
ART_INPUT       EQU $4A00
ART_BITMAP      EQU $5200
        ASSERT ART_BITMAP + 512 + 640 <= $5B00

StageHeaders:
        ld hl, (THEME_CACHE)
        ld (StTypeDir), hl
        ld hl, (THEME_CACHE + 2)
        ld (StPano), hl
        ld hl, (THEME_CACHE + 4)
        ld (StName), hl
        ld hl, (THEME_CACHE + 15)
        ld (StTune), hl
        ld hl, THEME_CACHE + 6
        ld de, Palette
        ld bc, 9
        ldir
        ld hl, (TRACK_CACHE)
        ld (StTrack), hl
        ld (SegPtr), hl
        ld hl, (TRACK_CACHE + 2)
        ld (StObjects), hl
        ld (ObjFirst), hl
        ld hl, (TRACK_CACHE + 6)
        ld (TunStart), hl
        ld hl, (TRACK_CACHE + 8)
        ld (TunEnd), hl
        xor a
        ld (TunInside), a
        ld (TunJN), a
        ld hl, (TRACK_CACHE + 4)
        ld (StageLen), hl
        ld de, -SPLIT_LEN
        add hl, de
        ld (ForkZ), hl
        ld a, (StageRow)        ; every row but the last ends in a fork
        cp NUM_ROWS
        sbc a, a
        and 1
        ld (HasFork), a
        ld hl, $FFFF            ; the gantry: only over the goal
        or a
        jr nz, .gate
        ld hl, (StageLen)
        ld de, -150
        add hl, de
.gate:  ld (GateZ), hl
        xor a
        ld (GateWas), a
        ld hl, 0
        ld (PlayerDx), hl
        ld (SegStart), hl
        jp InitTraffic

ST3_USED        EQU $68             ; St3: row ranges, the fork rows' state ($40)
                                    ; and the cockpit's attributes ($60)
; Start both buffers afresh in the new palette: screen B cleared and
; labelled, every per-buffer record of what is on screen reset, then screen
; B copied over screen A (CopyScreenBA, resident) - over this overlay too,
; so that is the last thing done.
OvResetDisplay:
        call WaitFlip
        IFNDEF EINSTEIN
        ; ---- a Kempston joystick? One reads 0 in bits 5-7 at all times. With
        ; none, port $1F floats: on a 128K or +2 the screen bytes the ULA is
        ; reading, $FF in the border. A pixel byte with bits 5-7 clear passed
        ; ReadInput's check, and a stray fire bit changed gear. So read for a
        ; whole frame: ReadInput's IN stays only if every read was clear.
        ld bc, 1500             ; (51 T a read: a frame and a little more)
.kemp:  in a, ($1F)
        and $E0
        jr nz, .noKemp
        dec bc
        ld a, b
        or c
        jr nz, .kemp
        ld hl, $1FDB            ; in a, ($1F)
        jr .kempSet
.noKemp:
        ld hl, $FF3E            ; ld a, $FF: no Kempston
.kempSet:
        ld (ReadInput.kemp), hl
        ENDIF
        ; screen B: bitmap clear; sky rows get the sky attribute, road rows grass
        ld hl, $C000
        ld de, $C001
        ld (hl), 0
        ld bc, 6143
        ldir
        ld h, d
        ld l, e
        inc de
        ld a, (PalHud)
        ld (hl), a
        ld bc, 32 * 3 - 1
        ldir
        ld h, d
        ld l, e
        inc de
        ld a, (PalSky)
        ld (hl), a
        ld bc, 32 * (PANO_ROW0 - 3) - 1
        ldir
        ld h, d
        ld l, e
        inc de
        ld a, (PalPano)
        ld (hl), a
        ld bc, 32 * (ROAD_ROW0 - PANO_ROW0) - 1
        ldir
        ld h, d
        ld l, e
        inc de
        ld a, (PalGrassL)
        ld (hl), a
        ld bc, 32 * (24 - ROAD_ROW0) - 1
        ldir
        call InitHud
        ; Fixed sky artwork sits below the message and between the portraits.
        ; Copy just once, before CopyScreenBA duplicates the complete display.
        IFNDEF EINSTEIN
        ld hl, ART_BITMAP + 512
        ld b, 48
.cloud: push bc
        push hl
        ld l, b
        ld h, high ScrLo
        ld a, (hl)
        add a, 6
        ld e, a
        inc h
        ld a, (hl)
        or $80
        ld d, a
        pop hl
        ld bc, 20
        ldir
        pop bc
        inc b
        ld a, b
        cp 80
        jr nz, .cloud
        ENDIF
        ld hl, $D800 + 3 * 32
        call PaintRaceSky
        ; road state pages (per buffer: St1 D/E = 0, St2 lane = $FF,
        ; St3 row ranges = 0 / row band = $FF)
        ld hl, StateA1
        call .state
        ld hl, StateB1
        call .state
        ; caches
        ld hl, HudCacheA
        ld de, HudCacheA + 1
        ld bc, 13
        ld (hl), $FF
        ldir                    ; HudCacheA + HudCacheB
        ld hl, 0
        ld (MsgLastA), hl
        ld (MsgLastB), hl
        xor a
        ld (CrewShownA), a
        ld (CrewShownB), a
        ld (CmdListA), a
        ld (CmdListB), a
        ld (LastStraight), a
        dec a
        ld (CarShownA), a
        ld (CarShownB), a
        ld (PanoLastA), a
        ld (PanoLastB), a
        ld a, 1
        ld (CarDirty), a
        ld (CarAttrDirty), a
        ld hl, $8000
        ld (Pass1PX), hl
        IFDEF EINSTEIN
        jp EinResetDisplay      ; screen B into the VDP (src/einstein/flip.asm)
        ELSE
        jp CopyScreenBA
        ENDIF
.state: ld bc, StAD_end - StAD   ; (just the tables: the rest of each page
        xor a                   ; holds other data - src/holes.asm)
        call .fill              ; St1: D
        ld l, $80
        ld bc, StAE_end - StAE
        call .fill              ; St1: E
        inc h
        ld l, 0
        ld bc, StALane_end - StALane
        ld a, $FF
        call .fill              ; St2: centre line
        inc h
        ld l, 0
        ld bc, ST3_USED
        xor a
        call .fill              ; St3: row ranges, fork rows, cockpit
        ld l, $80
        ld bc, RowABand_end - RowABand
        ld a, $FF
; HL = start, BC = length, A = value (HL is kept)
.fill:  push hl
        ld (hl), a
        ld d, h
        ld e, l
        inc de
        dec bc
        ldir
        pop hl
        ret

; Screen B's HUD labels and the timer's red cells
InitHud:
        ld a, $80
        ld (HudOr), a
        ld hl, DashHeader
        ld de, $C000
        ld a, 8
.strip: ld bc, 32
        ldir
        ld e, 0
        inc d
        dec a
        jr nz, .strip
        ld a, (PalHud)
        cp $4F                  ; Riviera blue fascia, cyan lettering
        jr nz, .label
        ld a, $4D
.label: ld hl, $D800
        ld b, 32
.top:   ld (hl), a
        inc hl
        djnz .top
        ld hl, $D800 + 14
        ld a, (PalTime)
        and 7
        rlca
        rlca
        rlca
        or $40                  ; black TIME lettering on its accent paper
        ld b, 4
.badge: ld (hl), a
        inc hl
        djnz .badge
        ld hl, $D800 + 32 + 14  ; red attribute cells for the big timer (rows 1-2, columns 14-17)
        ld a, (PalTime)
        ld c, a
        ld b, 2
.ta:    ld (hl), c
        inc l
        ld (hl), c
        inc l
        ld (hl), c
        inc l
        ld (hl), c
        ld a, l
        add a, 32 - 3
        ld l, a
        djnz .ta
        ld bc, $011D
        ld de, TxtKmh
        call PrintAt
        ld bc, $0201            ; STAGE n
        ld de, TxtStage
        call PrintAt
        ld a, (StageRow)
        jp PrintDigit
TxtKmh:         db "KM", 0
TxtStage:       db "STAGE ", 0

; A = bank, DE = source, BC = length, HL = destination in bank 7 (the
; theme cache): copy through TRACK_CACHE in chunks (which it overwrites).
CopyToCache:
        IFDEF EINSTEIN
        ex de, hl               ; (no banks: DE's records of STAGES.DAT, BC of them)
        jp EinRead
        ENDIF
        ld (LdBank), a
        ld (LdSrc), de
        ld (LdLen), bc
        ld (LdDst), hl
.chunk: ld hl, (LdLen)
        ld a, h
        or l
        ret z
        ld bc, TRACK_CACHE_SIZE
        or a
        sbc hl, bc
        jr nc, .full            ; a full chunk, HL = what remains after it
        add hl, bc
        ld b, h
        ld c, l                 ; the last, shorter chunk
        ld hl, 0
.full:  ld (LdLen), hl
        push bc
        ld a, (LdBank)
        ld hl, (LdSrc)
        ld de, TRACK_CACHE
        call CopyFromBank
        ld (LdSrc), hl
        pop bc
        ld hl, TRACK_CACHE
        ld de, (LdDst)
        ldir                    ; bounce -> theme cache (bank 7 is paged again)
        ld (LdDst), de
        jr .chunk

; The traffic at a stage start (its moves: src/traffic.asm, bank 2)
InitTraffic:
        ld hl, TrafficInit
        ld de, Traffic
        ld bc, N_TRAFFIC * CAR_SIZE
        ldir
        ld a, (StageRow)        ; this row's mix
        dec a
        ld l, a
        add a, a
        add a, a
        add a, l
        ld l, a
        ld h, 0
        ld de, TrafficRows
        add hl, de
        ld de, NTraffic
        ld bc, 5
        ldir
        ld hl, WeaveChance      ; easy: half the weaving, hard: half as much again
        ld a, (Difficulty)
        cp 1
        ret z
        ld a, (hl)
        jr c, .easy
        ld c, a
        srl a
        add a, c
        ld (hl), a
        ret
.easy:  srl a
        ld (hl), a
        ret

TrafficInit:
        IFDEF SPIN_TEST
        dw 1300                 ; (testing: a slow lorry in the middle of the road)
        db 0, 3, 2, 0
        ELSE
        dw 1500
        db LANE_X, 10, 0, LANE_X
        ENDIF
        dw 2700
        db -LANE_X, 13, 0, -LANE_X
        dw 3900
        db LANE_X, 7, 2, LANE_X
        dw 5100
        db -LANE_X, 8, 1, -LANE_X
        dw 6300
        db LANE_X, 12, 0, LANE_X

; Per row: how many vehicles, then a random 0-7 at or above the first
; number is a van, at or above the second a lorry; the chances (/256 per
; game frame) of a lane change and of a vehicle in reach weaving into the
; player's path
TrafficRows:
        db 3, 6, 7, 2, 0
        db 3, 5, 7, 3, 3
        db 4, 5, 6, 4, 5
        db 4, 4, 6, 6, 7
        db 5, 4, 6, 8, 10

        INCLUDE "stages.asm"    ; the stage table
        ASSERT $ <= ART_INPUT
        ASSERT NUM_ROWS == 5    ; (StageTimes, src/vars.asm)
        ASSERT NUM_STAGES == 15 ; (StageBest, src/holes.asm)
