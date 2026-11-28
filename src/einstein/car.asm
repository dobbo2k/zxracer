; ---------------------------------------------------------------------------
; Einstein: the native Spider (src/einstein/sky.asm EinCarSync sends it;
; src/einstein/sprites.asm EinCarNames notes the ground under it)
;
; Its 32 cells are the bottom third's patterns CAR_PAT on (rows 20-23,
; columns CAR_COL on). A pose's lines whose paper is 0 are transparent:
; they take the paper of the ground under the cell (ECarGround). Only the
; cells whose pose or ground changed are coloured again and sent.
; The top and base images are resident. EinCarSync reads their pixels directly.
; ---------------------------------------------------------------------------

; Select the pose and its generated delta from the previous pose. The
; display reset sets CarShownB to $FF, selecting the full-upload row.
EinCarPrep:
        call CarFrame
        ld a, (CarShownB)
        cp c
        ret z
        cp $FF
        jr nz, .old
        ld a, 7
.old:   ld b, a
        add a, a
        add a, a
        add a, a
        sub b
        add a, c                ; previous * 7 + new
        ld e, a
        ld d, 0
        ld hl, EinCarTransitions
        add hl, de
        ld e, (hl)
        ld hl, EinCarChanges
        add hl, de
        ld de, ECarDirty        ; no pending ground edits after WaitFlip
        push bc
        ldi                     ; four row masks, then the pattern run list
        ldi
        ldi
        ldi
        ld (ECarRuns), hl
        pop bc
        ld a, c
        ld (CarShownB), a
        add a, a                ; two source pointers and four ground masks
        add a, a
        add a, a
        ld e, a
        ld d, 0
        ld hl, EinCarFrames
        add hl, de
        ld e, (hl)
        inc hl
        ld d, (hl)
        inc hl
        ld (EinCarSync.top + 1), de
        push hl
        ld hl, 192              ; top inks follow 192 pixel bytes
        add hl, de
        ld (EinCarGroundSync.top + 1), hl
        pop hl
        ld e, (hl)
        inc hl
        ld d, (hl)
        inc hl
        ld (EinCarNames.groundMask + 1), hl
        ld hl, -192             ; both routines index from the first car cell
        add hl, de
        ld (EinCarSync.base + 1), hl
        ld de, 64               ; base inks follow 64 pixel bytes
        add hl, de
        ld (EinCarGroundSync.base + 1), hl
        ret
ECarGround:     ds 32           ; per car cell: the paper under it (TMS)
ECarDirty:      ds 4            ; per car row: its cells to be recoloured
ECarSend:       ds 4            ; (bit k: column CAR_COL + k), then sent
ECarRuns:       dw 0            ; pending resident list, or 0 once uploaded
        ASSERT ECarSend == ECarDirty + 4

; The car's cells whose pose or ground changed (ECarDirty): their colours
; afresh, each transparent line (paper 0, as drawn) over its ground; then to
; be sent (ECarSend)
EinCarGroundSync:
        ld hl, ECarDirty
        ld d, 0                 ; D: the car cell (0-31)
.row:   ld a, (hl)
        or a
        jr z, .none
        ld (hl), 0
        ld c, a
        push hl
        inc hl                  ; (the row's ECarSend)
        inc hl
        inc hl
        inc hl
        or (hl)
        ld (hl), a
        ld b, 8
.cell:  srl c
        call c, .paint
        inc d
        djnz .cell
        pop hl
        jr .next
.none:  ld a, d
        add a, 8
        ld d, a
.next:  inc hl
        bit 5, d
        jr z, .row
        jp EinTyrePrep          ; (the tyres' tread: src/einstein/eintyres.asm)
; D = a car cell: its 8 colour lines (BC, D, HL kept)
.paint: push bc
        push de
        push hl
        ld a, d
        add a, low ECarGround
        ld l, a
        ld a, high ECarGround
        adc a, 0
        ld h, a
        ld c, (hl)              ; C: its ground
        ld a, d
        add a, a
        add a, a
        add a, a
        cp 192
.top:   ld hl, 0                ; selected by EinCarPrep
        jr c, .source
.base:  ld hl, 0
.source:ld e, a
        ld d, 0
        add hl, de
        add a, low ECarCol
        ld e, a
        ld a, high ECarCol
        adc a, 0
        ld d, a
        DUP 8                   ; fixed-size cell; no per-line loop counter
        ld a, (hl)
        and 15
        ld a, (hl)
        jr nz, $ + 3
        or c
        ld (de), a
        inc hl                  ; resident ink planes need not be page-aligned
        inc e
        EDUP
        pop hl
        pop de
        pop bc
        ret
