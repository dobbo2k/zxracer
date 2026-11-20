; ---------------------------------------------------------------------------
; Stages: loading a stage's packs into the caches (an overlay,
; src/stageov.asm), the checkpoint at the end of a stage and the fork that
; picks the next one.
;
; Theme pack -> THEME_CACHE (bank 7, $DB00-$FFFF): header
;   +0 type directory, +2 panorama, +4 name, +6 palette (9 attribute bytes)
; Track pack -> TRACK_CACHE (bank 5): header +0 segments, +2 objects,
;   +4 stage length.
; Packs live in banks 0/1/3/4/6, which share the $C000 slot with bank 7, so a
; theme is copied through TRACK_CACHE in chunks (the track is loaded after).
; ---------------------------------------------------------------------------
TRACK_CACHE_SIZE EQU $8000 - TRACK_CACHE
        IFNDEF FIRST_STAGE
FIRST_STAGE     EQU 0               ; (testing: start on another stage)
        ENDIF
        IFNDEF START_POS
START_POS       EQU 0               ; (testing: start further along it)
        ENDIF
STAGE_BONUS     EQU $48             ; BCD seconds added at a checkpoint
NAME_FRAMES     EQU 120             ; how long the new stage's name shows

; ---------------------------------------------------------------------------
; Loading stages: the stage-loading code is an overlay (src/stageov.asm) run
; from screen A; these are the ways in.
; ---------------------------------------------------------------------------
; Back to the first stage (new game, or attract mode).
Restart:
        ld a, FIRST_STAGE
; A = stage: from its start, standing still (and the screen blank meanwhile)
RestartAt:
        ld hl, OvRestartAt
        jr StageOv

; A = stage: its packs again after the front end, and the display reset
ReloadStage:
        ld hl, OvReloadStage
        jr StageOv

; The front-end overlay into bank 7 (over the theme cache)
LoadFrontEnd:
        ld hl, OvLoadFrontEnd
        jr StageOv

; A = stage, from the checkpoint: the last game frame stays on show
LoadStage:
        ld hl, OvLoadStage
        ld e, 0
        jr StageOvE

; HL = an entry in the overlay, A = what it takes in A. With screen B on
; show (blanked first, as there is no telling what it holds), copy the
; overlay into screen A, call the entry, then show what was on show before.
StageOv:
        ld e, 1
StageOvE:
        ld (OvArg), a
        ld (OvEntry), hl
        ld a, e
        ld (OvBlank), a
        ld a, (MusicOn)         ; no music while loading
        ld (OvMusic), a
        call MusicStop
        call WaitFlip           ; (no flip may happen meanwhile)
        ld a, (OvBlank)
        or a
        jr z, .shown
        ld hl, $D800            ; screen B's attributes: black
        ld de, $D801
        ld bc, 767
        ld (hl), 0
        ldir
.shown: ld a, (Port7FFD)
        push af
        or P7FFD_SHADOW
        ld (Port7FFD), a
        ld bc, PORT_7FFD
        out (c), a
        ld hl, StageOvPack
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
        ld de, STAGEOV_AT
        call CopyFromBank
        ld a, (OvArg)
        ld hl, (OvEntry)
        call .go
        pop af
        ld (Port7FFD), a
        ld bc, PORT_7FFD
        out (c), a
        ld a, (OvBlank)         ; a checkpoint: the new theme's tune
        or a
        ret nz
        ld a, (OvMusic)
        or a
        ret z
        jp MusicTheme
.go:    jp (hl)
OvEntry:        dw 0
OvArg:          db 0
OvBlank:        db 0
OvMusic:        db 0
STAGEOV_AT      EQU $4000

; A = bank, HL = source (in $C000-$FFFF), DE = destination, BC = length:
; copy with the bank paged at $C000, then page bank 7 back. HL advances.
CopyFromBank:
        push bc
        ld b, a
        ld a, 1
        ld (Paged), a           ; (the music's tune is out of reach meanwhile)
        ld a, (Port7FFD)
        and $F8
        or b
        push bc
        ld bc, PORT_7FFD
        out (c), a
        pop bc
        pop bc
        ldir
        xor a
        ld (Paged), a
        ld a, (Port7FFD)
        and $F8
        or 7
        ld (Port7FFD), a
        push bc
        ld bc, PORT_7FFD
        out (c), a
        pop bc
        ret

ST3_USED        EQU $68             ; St3: row ranges, the fork rows' state ($40)
                                    ; and the cockpit's attributes ($60)
; Start both buffers afresh in the new palette: bitmaps, attributes, HUD
; labels, and every per-buffer record of what is on screen.
ResetDisplay:
        call WaitFlip
        call InitScreens
        xor a
        call InitHud
        ld a, $80
        call InitHud
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
        ld a, $FF
        ld (CarShownA), a
        ld (CarShownB), a
        ld (PanoLastA), a
        ld (PanoLastB), a
        ld a, 1
        ld (CarDirty), a
        ld (CarAttrDirty), a
        xor a
        ld (CmdListA), a
        ld (CmdListB), a
        ld (LastStraight), a
        ld hl, $8000
        ld (Pass1PX), hl
        ret
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

; The car reached the end of the stage: take the branch it is on (left or
; right), or the goal on the last row.
Checkpoint:
        xor a
        ld (StageDone), a
        ld a, (Stage)
        ld l, a
        ld h, 0
        add hl, hl              ; 2 bytes per stage
        ld de, StageNext
        add hl, de              ; -> left, right
        ld a, (PlayerX + 1)
        bit 7, a
        jr nz, .left
        inc hl
.left:  ld a, (hl)
        cp $FF
        jr z, .goal
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
        ld a, (GameState)
        cp ST_PLAYING
        ret nz
        ld hl, MsgNone          ; (clears the fork message)
        ld (Message), hl
        ld a, (Time)            ; extra time
        add a, STAGE_BONUS
        daa
        jr nc, .t
        ld a, $99
.t:     ld (Time), a
        call StageMessage
        ld a, NAME_FRAMES
        ld (StateTimer), a
        ret
.goal:  ld a, (GameState)
        cp ST_PLAYING
        jp nz, Restart          ; attract mode: round again
        ld a, ST_OVER
        ld (GameState), a
        ld a, OVER_FRAMES
        ld (StateTimer), a
        ld hl, MsgGoal
        ld (Message), hl
        ld a, 1
        ld (GoalPending), a
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

        INCLUDE "stageov_pack.asm"  ; where the overlay is; the next stages
