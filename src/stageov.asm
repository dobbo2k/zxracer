; ---------------------------------------------------------------------------
; The between-stages overlay: loading a stage (its packs into the caches,
; the track state, the traffic) and the stage table. It only runs at a stage
; change, at power-on and between games - each time the screen is about to
; be cleared (ResetDisplay) or replaced by the front end - so it runs from
; screen A: StageOv (src/stage.asm) shows screen B, copies this in from its
; pack bank and calls one of the Ov... entries. Assembled to run at $4000.
; ---------------------------------------------------------------------------

; A = stage: the packs again after the front end (the demo carries on)
OvReloadStage:
        call LoadPacks
        jp ResetDisplay

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

; A = stage: from its start, standing still
OvRestartAt:
        push af
        ld hl, Route            ; a new run: no route yet
        ld b, 5
.rt:    ld (hl), $FF
        inc hl
        djnz .rt
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
        ld a, 1 << IN_FIRE      ; (a fire press that started the game is no gear change)
        ld (FireWas), a
        pop af
        jp OvLoadStage

; A = stage index: load its theme and track, reset the track state and
; the display.
OvLoadStage:
        call LoadPacks
        jr StageHeaders

; A = stage index: copy its theme and track packs into the caches (and
; nothing else: the demo carries on after the front end with this).
LoadPacks:
        push af
        call WaitFlip           ; (no flip may happen while banks are paged)
        pop af
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
        ret

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

; A = bank, DE = source, BC = length, HL = destination in bank 7 (the
; theme cache): copy through TRACK_CACHE in chunks (which it overwrites).
CopyToCache:
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
        add a, a
        add a, a
        ld l, a
        ld h, 0
        ld de, TrafficRows
        add hl, de
        ld de, NTraffic
        ld bc, 4
        ldir
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
; number is a van, at or above the second a lorry; the chance (/256 per
; game frame) of a lane change
TrafficRows:
        db 3, 6, 7, 2
        db 3, 5, 7, 3
        db 4, 5, 6, 4
        db 4, 4, 6, 6
        db 5, 4, 6, 8

        INCLUDE "stages.asm"    ; the stage table
