; 48K round preparation. Everything needed is already in the archive.
TRACK_CACHE_SIZE EQU $8000 - TRACK_CACHE
PANO_H          EQU 16
SFX_BUMP        EQU 0
ENGINE_IDLE     EQU 0
THEME_CACHE     EQU $A1E0           ; palette and inks in the gap before the tables
SCRATCH         EQU $4000
VARIANTS        EQU $4600
        ASSERT SCRATCH + SPRITE_SCRATCH_48 <= VARIANTS
        ASSERT VARIANTS + 8 * 8 <= $5800

        IFNDEF FIRST_STAGE
FIRST_STAGE     EQU 0
        ENDIF
        IFNDEF START_POS
START_POS       EQU 0
        ENDIF

Restart:
        ld a, FIRST_STAGE
RestartAt:
        jp OvRestartAt
ReloadStage:
        jp OvReloadStage
StartGame:
        jp OvStartGame

ResetRaceClock:
        ld a, (FrameCount)
        ld (LastLogic), a
        ld (LastFlip), a
        ret

; A = round index. The first six pointers and the route fields are read
; from the immutable stage table. The bitmap is free scratch until reset.
LoadPacks:
        ld (Stage), a
        call BlankAttrs
        ld a, (Stage)
        call StageEntry
        push hl
        pop ix
        ld a, (ix + 12)
        ld (StageRow), a
        ld e, a
        ld d, 0
        ld hl, Route - 1
        add hl, de
        ld a, (Stage)
        ld (hl), a
        ld l, (ix + 6)
        ld h, (ix + 7)
        ld (StName), hl
        ld l, (ix + 8)
        ld h, (ix + 9)
        ld (RoundClouds), hl
        ld l, (ix + 2)
        ld h, (ix + 3)
        push ix
        call ExpandTrack
        pop ix
        ld l, (ix + 4)
        ld h, (ix + 5)
        ld de, SCRATCH
        call Unpack
        call ExpandPanorama
        ; Only a different region needs fresh roadside bitmaps and inks.
        ld a, (Stage)
        call StageEntry
        ld a, (hl)
        inc hl
        ld h, (hl)
        ld l, a
        ld de, (LoadedTheme)
        or a
        sbc hl, de
        ret z
        add hl, de
        ld (LoadedTheme), hl
        ld e, (hl)
        inc hl
        ld d, (hl)
        inc hl
        push de
        ld de, THEME_CACHE + 17
        ld bc, 11
        ldir
        ld (StTypeDir), hl
        pop hl
        ld de, ThemeSprites
        jp ExpandScenery

        INCLUDE "track_decode.asm"

; Convert the packed columns to a scanline source for the renderer.
ExpandPanorama:
        ld hl, SCRATCH
        ld de, THEME_CACHE + 6
        ld bc, 9
        ldir
        ld de, PANO_CACHE
        ld (StPano), de
        ld c, 32
.column:
        push de
        ld b, 16
.pixel: ld a, (hl)
        inc hl
        ld (de), a
        ld a, e
        add a, 32
        ld e, a
        jr nc, .down
        inc d
.down:  djnz .pixel
        pop de
        inc de
        dec c
        jr nz, .column
        ret

RoundClouds:    dw 0
LoadedTheme:    dw 0
        INCLUDE "../stageov.asm"
