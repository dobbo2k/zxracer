; ---------------------------------------------------------------------------
; Einstein: no road row (nor the car) shown half written
; (src/einstein/flip.asm EinUpload)
;
; A frame's upload starts in the vertical blank, but a big one (a curve, the
; slots of many rows) runs on into the picture, and the raster can reach a
; row between its slots and its names: its old names over its new slots,
; tiles from the wrong cells for a TV frame; or the car between its new
; patterns and its colours. Before each road row's writes, and the car's,
; while the upload is timed (the CTC's 16 ms wait, started as the frame was
; seen, at most EIN_SEEN counts after it began), the raster's place is
; worked out from the CTC (EinElapsed): if it could reach the row while the
; writes go, the upload waits till it has gone past. The row then shows its
; old frame in that TV frame, whole, and the new one in the next.
; EinElapsed in bank 2's code, the rest in the ZHiPage table page's hole
; (src/holes.asm): neither the platform code below $4000 nor bank 2 had room.
; ---------------------------------------------------------------------------
        IF HOLD_PART == 1
; HL = counts (256 T) since the frame was seen: the CTC's 16 ms wait, from
; 250 down and reloading at 0, each reload counted
EinElapsed:
        push bc
        in a, (EIN_CTC2)
        ld b, a
        ld a, (EHoldLast)
        cp b
        ld a, b
        ld (EHoldLast), a
        ld hl, (EHoldBase)
        jr nc, .now             ; (no higher than the last read: not reloaded)
        ld bc, 250
        add hl, bc
        ld (EHoldBase), hl
.now:   cpl                     ; + 250 - the count
        add a, 251
        ld c, a
        ld b, 0
        add hl, bc
        pop bc
        ret
EHoldBase:      dw 0
EHoldLast:      db 0
        ELSE
EIN_SEEN        EQU 17          ; (counts of 256 T: the 1 ms poll, the interrupt's entry)

; C = the road row (10-23) about to be written (BC, DE, HL kept)
EinRowHold:
        ld a, (EHoldOn)
        or a
        ret z
        push bc
        push de
        push hl
        ld a, c                 ; its writes, in counts: its names (32 bytes)
        add a, low ERowDrawn    ; 6, its changed slots (16 bytes each) 3 each
        ld l, a
        ld a, high ERowDrawn
        adc a, 0
        ld h, a
        ld a, (hl)
        or a
        jr z, .nn
        ld a, 6
.nn:    ld e, a
        ld a, c
        sub ROAD_ROW0
        jr c, .ns               ; (rows 10-11: no slots)
        add a, low EDirtyRowN
        ld l, a
        ld a, high EDirtyRowN
        adc a, 0
        ld h, a
        ld a, (hl)
        ld d, a
        add a, a
        add a, d
        add a, e
        ld e, a
.ns:    ld a, e
        or a
        jr z, .done             ; (nothing to write)
        ld l, c                 ; its first line: (121 + 8 C) lines after the
        ld h, 0                 ; blank began, about 120 + 8 C counts
        add hl, hl
        add hl, hl
        add hl, hl
        ld bc, 120
        add hl, bc
        ld c, e
        ld b, 8 + 1
        call EinHold
.done:  pop hl
        pop de
        pop bc
        ret

; Before EinCarSync: the car's rows (20-23), its new pose's patterns or its
; cells' colours
EinCarHold:
        ld a, (EHoldOn)
        or a
        ret z
        ld a, (ECarRuns + 1)    ; (a new pose: its patterns, 0 none; then the
        or a                    ; tyres, src/einstein/eintyres.asm)
        ld c, 12 + 6
        jr z, .c
        ld c, 48 + 6
.c:     ld hl, 120 + 8 * 20
        ld b, 8 * 4 + 1

; HL = the first line of the rows about to be written (counts after the
; frame was seen), B = their lines' counts + 1, C = the writes' counts:
; return once they can go before the raster reaches them, or it has gone
; past them (A, BC, DE, HL spent)
EinHold:
        push hl
        push bc
        ld a, c
        add a, EIN_SEEN + 2
        ld c, a
        ld b, 0
        or a
        sbc hl, bc              ; (at least 200 - 72 - 19: no borrow)
        ex de, hl
        call EinElapsed
        or a
        sbc hl, de
        pop bc
        pop de                  ; (their first line)
        ret c                   ; time to write them before it gets there
        ld l, b
        ld h, 0
        add hl, de
        ex de, hl
.w:     call EinElapsed         ; else once it has surely gone past them
        or a
        sbc hl, de
        jr c, .w
        ret
EHoldOn:        db 0            ; (this upload timed: EinUpload)
        ENDIF
