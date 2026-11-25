; C = lamp state (see LightsHold): the three lamps, in both screens. A lamp
; is a circle in the lamp's colour in a black 2 x 2 cell box; state 5 clears
; them back to sky.
LampDraw:
        ld a, c                 ; green: the music starts
        cp 4
        call z, MusicGo
        ld a, (HudOr)
        push af
        IFNDEF NATIVE_GFX       ; (the Einstein, the CPC: screen B only; screen A's
        xor a                   ; memory holds the stage overlay there)
        call .scr
        ENDIF
        ld a, $80
        call .scr
        pop af
        ld (HudOr), a
        IFDEF NATIVE_GFX
        jp GfxLampCells         ; (their cells to be shown: the platform's)
        ELSE
        ret
        ENDIF
.scr:   ld (HudOr), a
        ld b, 0                 ; lamp 0-2
.lamp:  push bc
        ld a, (Palette)         ; gone: sky, no pixels
        ld e, a
        ld d, 0
        ld a, c
        cp 5
        jr z, .col
        dec d                   ; D = $FF: the lamp's pixels
        ld e, $44               ; green
        cp 4
        jr z, .col
        ld e, $42               ; red, if lit yet
        ld a, b
        cp c
        jr c, .col
        ld e, $07               ; unlit (grey)
.col:   ld a, b
        add a, a
        add a, a
        add a, LAMP_COL
        ld c, a
        ld b, LAMP_ROW
        ld ix, LampGlyph
        call .cell
        inc b
        call .cell
        ld a, (HudOr)           ; attributes
        or $58
        ld h, a
        ld a, c
        add a, LAMP_ROW * 32
        ld l, a
        ld (hl), e
        inc l
        ld (hl), e
        ld a, l
        add a, 31
        ld l, a
        ld (hl), e
        inc l
        ld (hl), e
        pop bc
        inc b
        ld a, b
        cp 3
        jr c, .lamp
        ret
; B = row, C = column: 8 lines of the lamp (AND D) from IX
.cell:  call CellAddr
        push bc
        ld b, 8
.ln:    ld a, (ix + 0)
        and d
        ld (hl), a
        inc l
        ld a, (ix + 1)
        and d
        ld (hl), a
        dec l
        inc ix
        inc ix
        inc h
        djnz .ln
        pop bc
        ret
