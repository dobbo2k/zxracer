; ---------------------------------------------------------------------------
; Einstein, -DEIN_KERB (a prototype): the road's rows (12-23) with both of
; the kerb's edges exact, in 2-line steps, where the ready-made way puts the
; kerb's outer edge on a cell's edge and its inner edge upright in the row
; (8-line steps). Every row of the open road comes here; one it can't draw
; (a pair without road, a run over 119 pixels wide) goes the exact way
; (EinRowBase). The middle third's ready-made kerb edges' patterns are slots
; instead (11 a row, not 5), and no row is drawn the ready-made way.
;
; Per line pair p (lines 0, 2, 4, 6 of the row: the Spectrum computes one
; line in two), from its D (first road pixel), E (last) and the kerb's
; width RW (of the depth line shown): grass, kerb [L, D), road, kerb
; (E, R], grass, with L = D - RW and R = E + RW. A cell of the left run
; [ERA, ERB) or the right run [ERC, ERD) gets, per pair, a byte of kerb
; pixels over one ground colour: road if the pair has road in the cell,
; else grass. Where a pair has grass, kerb and road all in one cell
; (Graphics II: two colours a line), its grass is drawn as kerb. Where the
; runs share a cell (the far rows: a narrow road), every cell of [ERA, ERD)
; is made with both kerbs at once (EinKerbMerged).
;
; A slot holds two colour bytes, kerb over grass and kerb over road, and a
; mask of the lines that take the second (SLOT_SIZE 11: EinCommitAt,
; EinSendSlot), as Graphics II has a colour pair a line.
;
; Tuned: the pairs loaded unrolled, their extremes kept in registers; each
; cell's pairs unrolled, straight into EPat, through EKGe; the cell's name
; or slot in src/einstein/kerbcell.asm (below $4000: bank 2 is full).
; ---------------------------------------------------------------------------

; (v - x0) & 255 -> the pixels of a cell (x0 its first) from pixel v on: 0-7
; a mask, 8-127 none (v right of the cell), 128-255 all (v left of it). The
; runs are at most 119 pixels wide, so v - x0 and v - x0 + 1 (past v) stay
; in -119 .. 127.
        ALIGN 256
EKGe:   db $FF, $7F, $3F, $1F, $0F, $07, $03, $01
        ds 120, 0
        ds 128, $FF

; (The macros KLOAD, KPUT, KLEFT and KRIGHT: src/einstein/kerbmac.asm.)

; From EinRowFast: an open road row, ERBand set. NZ, no carry: drawn (EinRow
; notes its slots). Carry: not this way (EinRowBase).
EinKerbRow:
        ld a, (EI)              ; ---- pairs without road (D > E): all, the
        ld l, a                 ; row is grass; some, the exact way
        ld h, high DEPage
        ld bc, KPAIRS * 256     ; (B: the pairs, C: those without road)
.nr:    ld a, (hl)
        set 7, l
        cp (hl)
        res 7, l
        jr c, .nr1
        jr z, .nr1
        inc c
.nr1:
        DUP KSTEP
        inc l
        EDUP
        djnz .nr
        ld a, c
        or a
        jr z, .pairs
        cp KPAIRS
        jp nz, .generic
        xor a                   ; no road: all grass, no slot of the road's
        ld (ERA), a
        ld (ERB), a
        ld (ERC), a
        ld (ERD), a
        call EinRowNames
        call EinRowSlots
        call EinSlotRange
        or 1
        ret
.pairs: push iy                 ; ---- the pairs, and the runs' extremes
        ld a, (EI)
        ld c, a
        ld b, $FF
        ld ix, $FF00
        ld iy, 0
        KLOAD 0
        KLOAD 1
        IFNDEF EIN_KERB4
        KLOAD 2
        KLOAD 3
        ENDIF
        ld a, ixl               ; (each run at most 119 pixels wide)
        sub b
        cp 120
        jp nc, .wide
        ld a, iyl
        sub ixh
        cp 120
        jp nc, .wide
        ld a, b                 ; ERA: the least L's cell
        call .cell
        ld (ERA), a
        ld a, ixl               ; ERB: past the most D's
        call .cell
        inc a
        ld (ERB), a
        ld a, iyl               ; ERD: past the most R's
        call .cell
        inc a
        ld (ERD), a
        ld a, ixh               ; ERC: the least E's
        call .cell
        ld (ERC), a
        ld hl, ERB
        cp (hl)
        ld a, 0
        jr nc, .apart
        ld a, iyl               ; (the runs share a cell: [ERA, ERD) at once,
        sub b                   ; at most 119 pixels too; named kerb)
        cp 120
        jp nc, .wide
        ld a, (ERA)
        ld (ERB), a
        ld (ERC), a
        ld a, 1
.apart: ld (EKMerged), a
        pop iy
        call EinRowNames        ; ---- the names, slots, colours
        call EinRowSlots
        call EinSlotRange
        ld a, (ECK)             ; kerb over grass, kerb over road
        add a, a
        add a, a
        add a, a
        add a, a
        ld c, a
        ld a, (ECG)
        or c
        ld (EKCG), a
        ld a, (ECR)
        or c
        ld (EKCR), a
        ld a, (ECG)
        call EinGroundName
        ld (EKGN), a
        ld a, (EKMerged)
        or a
        jr z, .left
        call EinKerbMerged      ; (src/einstein/kerbcell.asm)
        jp .done
.left:  ld a, (ERB)             ; ---- the left run
        ld hl, ERA
        sub (hl)
        ld (.ln + 1), a
        ld a, (hl)
        add a, a
        add a, a
        add a, a
        ld c, a                 ; C: the cell's first pixel
.lc:    ld h, high EKGe
        ld b, 0
        ld de, $FF00
        KLEFT 0
        KLEFT 1
        IFNDEF EIN_KERB4
        KLEFT 2
        KLEFT 3
        ENDIF
        call EinKerbCell
        ld a, c
        add a, 8
        ld c, a
.ln:    ld a, 0                 ; (the cells left)
        dec a
        ld (.ln + 1), a
        jp nz, .lc
        call EinKerbRight       ; ---- the right run (src/einstein/kerbcell.asm)
.done:
        IFDEF EIN_DASH
        call EinDashRow
        ENDIF
        or 1                    ; (drawn: NZ, no carry)
        ret
.wide:  pop iy
.generic:
        scf
        ret

; A = a pixel -> A = its cell
.cell:  rrca
        rrca
        rrca
        and 31
        ret

EKP:    ds 4                    ; the pairs' L,
        ds 4                    ; D,
        ds 4                    ; E,
        ds 4                    ; R (pixels)
        ASSERT high EKP == high (EKP + 15)
EKCG:   db 0                    ; colour bytes: kerb over grass, over road
EKCR:   db 0
EKGN:   db 0                    ; the grass's name
EKMerged:       db 0            ; the runs share a cell
EComM:  db 0                    ; (EinCommitAt: the lines over the second
EComC2: db 0                    ; colour byte, and it; 0 but for the kerb)
