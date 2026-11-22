; ---------------------------------------------------------------------------
; Einstein, -DEIN_KERB (a prototype): the rest of src/einstein/kerbrow.asm,
; below $4000 (bank 2 is full): a kerb cell's name or slot, the far rows'
; shared cells, the right run, and a slot's colours a line at a time.
; ---------------------------------------------------------------------------
        INCLUDE "kerbmac.asm"   ; (KLOAD, KPUT, KLEFT, KRIGHT)

; The right run [ERC, ERD): road to E (kerb right of it), or no road in the
; cell: kerb to R
EinKerbRight:
        ld a, (ERD)
        ld hl, ERC
        sub (hl)
        ret z
        ld (.n + 1), a
        ld a, (hl)
        add a, a
        add a, a
        add a, a
        ld c, a                 ; C: the cell's first pixel
.cell:  ld h, high EKGe
        ld b, 0
        ld de, $FF00
        KRIGHT 0
        KRIGHT 1
        IFNDEF EIN_KERB4
        KRIGHT 2
        KRIGHT 3
        ENDIF
        call EinKerbCell
        ld a, c
        add a, 8
        ld c, a
.n:     ld a, 0
        dec a
        ld (.n + 1), a
        jp nz, .cell
        ret

; C = the cell's first pixel, EPat its 8 lines (each pair's byte on two), B
; the pairs over road (pair 0 in bit 3), D the AND of the pairs' bytes, E
; their OR -> its name: solid if it can be (all kerb, all road, all grass),
; else a slot of the kerb's colours over grass and over road, by line. BC
; kept.
EinKerbCell:
        ld a, d
        inc a
        ld a, (ECK)
        jr z, .name             ; all kerb
        ld a, e
        or a
        jr nz, .slot
        ld a, b                 ; no kerb: all road, all grass, or both
        cp KALL
        ld a, (ECR)
        jr z, .name
        ld a, b
        or a
        ld a, (EKGN)
        jr z, .name
.slot:  ld a, b
        or a
        ld a, (EKCG)
        jr z, .commit           ; all over grass
        ld a, b
        cp KALL
        ld a, (EKCR)
        jr z, .commit           ; all over road
        ld a, b                 ; both: the lines over road, the second pair
        add a, low EKLines
        ld l, a
        ld h, high EKLines
        ld a, (hl)
        ld (EComM), a
        ld a, (EKCR)
        ld (EComC2), a
        ld a, (EKCG)
.commit:
        push bc
        call EinCommitSlot
        pop bc
        cp $FF
        jr nz, .name
        xor a                   ; (the row's slots all used: back to one pair)
        ld (EComM), a
        ld (EComC2), a
        ret
.name:  ld e, a
        ld a, c                 ; (its cell)
        rrca
        rrca
        rrca
        and 31
        ld hl, (ERowPtr)
        add a, l
        ld l, a
        jr nc, .nm
        inc h
.nm:    ld (hl), e
        ret

; The runs sharing cells (a narrow road): every cell of [ERA, ERD), per
; pair road from D to E, kerb [L, D) and (E, R]
EinKerbMerged:
        push iy
        ld a, (ERD)
        ld hl, ERA
        sub (hl)
        ld (.n + 1), a
        ld a, (hl)
        add a, a
        add a, a
        add a, a
        ld c, a                 ; C: the cell's first pixel
.cell:  ld h, high EKGe
        ld b, 0
        ld de, $FF00
        ld ix, EKP              ; (IX: the pair; IY: its two lines)
        ld iy, EPat
.pair:  ld a, (ix + 4)          ; road: from D, not past E
        sub c
        ld l, a
        ld a, (hl)
        ld (.road + 1), a
        ld a, (ix + 8)
        sub c
        inc a
        ld l, a
        ld a, (hl)
        cpl
.road:  and 0
        jr z, .noRoad
        cpl                     ; the rest kerb (and grass, if any, as kerb)
        scf
        jr .put
.noRoad:
        ld a, (ix + 8)          ; no road: left of it, kerb from L; right of
        cp c                    ; it, kerb to R
        jr c, .right
        ld a, (ix + 0)
        sub c
        ld l, a
        ld a, (hl)
        or a
        jr .put
.right: ld a, (ix + 12)
        sub c
        inc a
        ld l, a
        ld a, (hl)
        cpl
        or a
.put:
        DUP 8 / KPAIRS
        ld (iy + 0), a
        inc iy
        EDUP
        rl b
        ld l, a
        and d
        ld d, a
        ld a, l
        or e
        ld e, a
        inc ix
        ld a, ixl
        cp low (EKP + KPAIRS)
        jr nz, .pair
        call EinKerbCell
        ld a, c
        add a, 8
        ld c, a
.n:     ld a, 0
        dec a
        ld (.n + 1), a
        jr nz, .cell
        pop iy
        ret

; From EinSendSlot, the VRAM address set: HL = a slot's colour byte, then the
; mask of the lines over its second and that one: 8 colour bytes, a line
; each. 34 or 35 T a byte: paced enough for the picture's time too.
EinSendCols:
        ld e, (hl)
        inc hl
        ld b, (hl)
        inc hl
        ld c, (hl)
        DUP 8
        ld a, e
        rr b
        jr nc, $ + 3
        ld a, c
        out (EIN_VDP_DATA), a
        EDUP
        ret

        ALIGN 16
EKLines:                        ; the groups over road (group 0 the highest
        IFDEF EIN_KERB4         ; bit) -> lines
        db $00, $F0, $0F, $FF
        ELSE
        db $00, $C0, $30, $F0, $0C, $CC, $3C, $FC
        db $03, $C3, $33, $F3, $0F, $CF, $3F, $FF
        ENDIF
