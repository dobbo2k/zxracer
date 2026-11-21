; ---------------------------------------------------------------------------
; Einstein: the controls (Q / A / O / P / SPACE, as the Spectrum's default)
;
; The keyboard matrix is read through the AY's ports: a row is selected,
; active low, on register 14 (port A, an output) and its keys read, active
; low, from register 15 (port B). The interrupt writes the AY too, so
; interrupts are off between choosing the register and reading it.
; Input bits (as the Kempston's): 0 right, 1 left, 2 down, 3 up, 4 fire.
; ---------------------------------------------------------------------------

ReadInput:
        ld hl, EinKeys
        ld bc, 5 * 256          ; B: keys, C: the input
.key:   ld e, (hl)              ; the row
        inc hl
        di
        ld a, 14
        out (EIN_PSG_SELECT), a
        ld a, e
        out (EIN_PSG_WRITE), a
        ld a, 15
        out (EIN_PSG_SELECT), a
        in a, (EIN_PSG_READ)
        ei
        and (hl)                ; the key's column (0: pressed)
        inc hl
        jr nz, .up
        ld a, c
        or (hl)
        ld c, a
.up:    inc hl
        djnz .key
        ld a, c
        ld (Input), a
        ret

; Per key: the row (active low), the column bit, the input bit (Albert's
; keyboard matrix, as the Wonder Boy port reads it)
EinKeys:
        db ~(1 << 1) & $FF, 1 << 2, 1 << IN_RIGHT   ; P: row 1, column 2
        db ~(1 << 1) & $FF, 1 << 1, 1 << IN_LEFT    ; O: row 1, column 1
        db ~(1 << 6) & $FF, 1 << 6, 1 << IN_DOWN    ; A: row 6, column 6
        db ~(1 << 5) & $FF, 1 << 6, 1 << IN_UP      ; Q: row 5, column 6
        db ~(1 << 0) & $FF, 1 << 6, 1 << IN_FIRE    ; SPACE: row 0, column 6
