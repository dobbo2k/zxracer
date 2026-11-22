; ---------------------------------------------------------------------------
; Einstein: the ready-made kerb edges, at a display reset (EinResetDisplay).
; Not time-critical: in bank 2, where the Spectrum has its panorama and kerb
; chains (src/main.asm); the patterns' bytes and colours (EStatByte, EStatCol)
; are with the road (src/einstein/roadgfx.asm).
; ---------------------------------------------------------------------------

; The ready-made kerb edges into VRAM, the middle and bottom thirds (the
; display off, at a display reset: the stage's colours), and their pixels
; and colours for silhouettes (EStatByte, EStatCol)
EinStaticInit:
        call EinColourSets
        ld b, 0                 ; ---- the open road's light and dark kerb
        ld c, 0                 ; C: the pattern (0 .. KERB_N - 1)
.set:   ld a, b                 ; its colour byte: EKC
        add a, a
        add a, a
        add a, a
        sub b
        add a, low (ERowSets + 5)
        ld l, a
        ld a, high (ERowSets + 5)
        adc a, 0
        ld h, a
        ld a, (hl)
        ld (EStatC), a
        ld e, $7F               ; left edges: road from pixel 1 .. 7
.le:    ld a, e
        call .put
        srl e
        jr nz, .le
        ld e, $80               ; right edges: road to pixel 0 .. 6
.re:    ld a, e
        call .put
        sra e
        ld a, e
        inc a
        jr nz, .re
        inc b
        ld a, b
        cp 2
        jr nz, .set
        ret
; A = the pattern's byte (on all 8 lines), EStatC its colour: pattern C of
; both thirds (C then the next); BC, DE kept
.put:   push bc
        push de
        ld (EStatB), a
        ld l, c
        ld h, 0
        ld de, EStatByte
        add hl, de
        ld (hl), a
        ld de, EStatCol - EStatByte
        add hl, de
        ld a, (EStatC)
        ld (hl), a
        IFNDEF EIN_KERB         ; (-DEIN_KERB: the middle third's are slots)
        ld a, c
        add a, KERB_T1          ; the middle third's
        ld bc, VRAM_PAT + $800
        call .one
        pop de
        pop bc
        push bc
        push de
        ENDIF
        ld a, c
        add a, KERB_T2          ; the bottom third's
        ld bc, VRAM_PAT + $1000
        call .one
        pop de
        pop bc
        inc c
        ret
; A = name, BC = its third: its 8 bytes (EStatB) and colours (EStatC)
.one:   ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, bc
        ex de, hl
        push de
        ld a, (EStatB)
        ld l, a
        ld bc, 8
        call VdpFill
        pop de
        ld a, d
        add a, high VRAM_COL
        ld d, a
        ld a, (EStatC)
        ld l, a
        ld bc, 8
        jp VdpFill

EStatC:         db 0
EStatB:         db 0
