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

; A new game: from the first stage, the clock and score afresh
StartGame:
        ld hl, OvStartGame
        jr StageOv

; HL = an entry in the overlay, A = what it takes in A. With screen B on
; show (blanked first, as there is no telling what it holds), copy the
; overlay into screen A, call the entry, then show what was on show before.
MUSIC_GAP       EQU 12              ; a new stage: interrupts from its beep to its tune
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
        ld a, (OvBlank)         ; a checkpoint: the sound on again, the new theme's tune
        or a
        ret nz
        ld (Mute), a
        ld a, (OvMusic)         ; with music: the tune after the beep and a gap
        or a
        ret z
        ld a, MUSIC_GAP
        ld (MusicWait), a
        ret
.go:    jp (hl)
OvMusic:        db 0                ; (OvEntry, OvArg, OvBlank: src/holes.asm)
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

; The end of a display reset (OvResetDisplay, in the overlay): screen B,
; cleared and labelled, over screen A - and over the overlay with it.
CopyScreenBA:
        ld hl, $C000
        ld de, $4000
        ld bc, 6912
        ldir
        ret

; The car reached the end of the stage: the goal on the last row, else the
; next stage (OvCheckpoint) with the last game frame on show meanwhile.
Checkpoint:
        xor a
        ld (StageDone), a
        ld a, (StageRow)
        cp NUM_ROWS
        jr nc, .goal
        ld a, 1                 ; the interrupt's sound off till the new stage
        ld (Mute), a            ; (StageOvE turns it on again, after the load)
        ld hl, OvCheckpoint
        ld e, 0
        jp StageOvE
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

