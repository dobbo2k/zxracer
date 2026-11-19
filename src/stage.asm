; ---------------------------------------------------------------------------
; Stages: loading a stage's packs into the caches, the checkpoint at the end
; of a stage and the fork that picks the next one.
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
STAGE_BONUS     EQU $40             ; BCD seconds added at a checkpoint
NAME_FRAMES     EQU 120             ; how long the new stage's name shows

; A = stage index: load its theme and track, reset the track state and
; the display.
LoadStage:
        ld (Stage), a
        ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl              ; 16 bytes per stage
        ld de, StageTable
        add hl, de
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
        ld (LdBank), a
        ld (LdSrc), de
        ld (LdLen), bc
        ld hl, THEME_CACHE
        ld (LdDst), hl
.chunk: ld hl, (LdLen)
        ld a, h
        or l
        jr z, .themeDone
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
.themeDone:
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
        ; ---- headers
        ld hl, (THEME_CACHE)
        ld (StTypeDir), hl
        ld hl, (THEME_CACHE + 2)
        ld (StPano), hl
        ld hl, (THEME_CACHE + 4)
        ld (StName), hl
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
        ld hl, 0
        ld (PlayerDx), hl
        ld hl, 0
        ld (SegStart), hl
        call InitTraffic
        jp ResetDisplay

; A = bank, HL = source (in $C000-$FFFF), DE = destination, BC = length:
; copy with the bank paged at $C000, then page bank 7 back. HL advances.
CopyFromBank:
        push bc
        ld b, a
        ld a, (Port7FFD)
        and $F8
        or b
        push bc
        ld bc, PORT_7FFD
        out (c), a
        pop bc
        pop bc
        ldir
        ld a, (Port7FFD)
        and $F8
        or 7
        ld (Port7FFD), a
        push bc
        ld bc, PORT_7FFD
        out (c), a
        pop bc
        ret

; Start both buffers afresh in the new palette: bitmaps, attributes, HUD
; labels, and every per-buffer record of what is on screen.
ResetDisplay:
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
        ld bc, 11
        ld (hl), $FF
        ldir                    ; HudCacheA + HudCacheB
        ld hl, 0
        ld (MsgLastA), hl
        ld (MsgLastB), hl
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
.state: ld d, h
        ld e, l
        inc de
        ld (hl), 0
        ld bc, 255
        ldir                    ; St1: D, E
        inc hl
        inc de
        ld (hl), $FF
        ld bc, 255
        ldir                    ; St2: centre line
        inc hl
        inc de
        ld (hl), 0
        ld bc, 127
        ldir                    ; St3: row ranges
        inc hl
        inc de
        ld (hl), $FF
        ld bc, 127
        ldir                    ; St3: row bands
        ret

; The car reached the end of the stage: take the branch it is on (left or
; right), or the goal on the last row.
Checkpoint:
        xor a
        ld (StageDone), a
        ld a, (Stage)
        ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl              ; 16 bytes per stage
        ld de, StageTable + 10
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
        jr nz, Restart          ; attract mode: round again
        ld a, ST_OVER
        ld (GameState), a
        ld a, OVER_FRAMES
        ld (StateTimer), a
        ld hl, MsgGoal
        ld (Message), hl
        ld a, 1
        ld (GoalPending), a
        ret

; Back to the first stage (new game, or attract mode).
Restart:
        ld hl, START_POS
        ld (Pos), hl
        ld hl, 0
        ld (PlayerX), hl
        ld (LatVX), hl
        xor a
        ld (StageDone), a
        ld a, FIRST_STAGE
        jp LoadStage

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
