; ---------------------------------------------------------------------------
; Einstein: the native Spider (src/einstein/sky.asm EinCarSync sends it;
; src/einstein/sprites.asm EinCarNames notes the ground under it)
;
; Its 32 cells are the bottom third's patterns CAR_PAT on (rows 20-23,
; columns CAR_COL on). A pose's lines whose paper is 0 are transparent:
; they take the paper of the ground under the cell (ECarGround). Only the
; cells whose pose or ground changed are coloured again and sent.
; (Resident data and code: in bank 5's part, src/main.asm)
; ---------------------------------------------------------------------------

; The pose for this frame: a new one's patterns and colours, as drawn
EinCarPrep:
        call CarFrame
        ld a, (CarShownB)
        cp c
        ret z
        ld a, c
        ld (CarShownB), a
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
        push hl
        ex de, hl
        ld de, ECarPix
        ld bc, 192
        ldir
        ld de, ECarSourceInks
        ld c, 192
        ldir
        pop hl
        ld e, (hl)
        inc hl
        ld d, (hl)
        ex de, hl
        ld de, ECarPix + 192
        ld c, 64
        ldir
        ld de, ECarSourceInks + 192
        ld c, 64
        ldir
        ld a, 1
        ld (ECarBlock), a
        ld a, $FF               ; every cell recoloured
        ld hl, ECarDirty
        ld (hl), a
        inc hl
        ld (hl), a
        inc hl
        ld (hl), a
        inc hl
        ld (hl), a
        ret
ECarGround:     ds 32           ; per car cell: the paper under it (TMS)
ECarDirty:      ds 4            ; per car row: its cells to be recoloured
ECarSend:       ds 4            ; (bit k: column CAR_COL + k), then sent
ECarBlock:      db 0            ; a new pose's patterns to be sent
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
        ret
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
        ld l, a
        ld h, high ECarSourceInks
        add a, low ECarCol
        ld e, a
        ld a, high ECarCol
        adc a, 0
        ld d, a
        ld b, 8
.line:  ld a, (hl)
        and 15
        ld a, (hl)
        jr nz, .opaque
        or c
.opaque:ld (de), a
        inc l
        inc e
        djnz .line
        pop hl
        pop de
        pop bc
        ret
