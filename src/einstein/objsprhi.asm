; ---------------------------------------------------------------------------
; Einstein: the object sprites' code in the theme cache's top, above the
; largest theme pack (-DEIN_OBJSPR; src/einstein/objspr.asm). No disc read
; writes past its length there, and the front end's code ends far below.
; ---------------------------------------------------------------------------

; (EinObjSprite, with ESprTop, ESprX, ESprPat, ESprR, ESprC and ESprN set,
; the budget taken): the sprites' attributes; the command's y top then $FF.
EinObjSprAttrs:
        ld a, (ESprLeft)
        ld hl, ESprN
        sub (hl)
        ld (ESprLeft), a
        call EinObjSprInk       ; C = the colour (src/einstein/objspr.asm)
        ld hl, (ESprPtr)
        ld a, (ESprTop)
        dec a
        ld d, a                 ; D = Y (the line above)
        ld a, (ESprPat)
        add a, a
        add a, a
        ld e, a                 ; E = the pattern (16 x 16: 4 a step)
        ld a, (ESprR)
        ld b, a
.row:   push bc
        ld a, (ESprC)
        ld b, a
        ld a, (ESprX)
.col:   ld (hl), d              ; Y, X, pattern, colour
        inc hl
        ld (hl), a
        inc hl
        ld (hl), e
        inc hl
        ld (hl), c
        inc hl
        add a, 16
        inc e
        inc e
        inc e
        inc e
        djnz .col
        ld a, d
        add a, 16
        ld d, a
        pop bc
        djnz .row
        ld (ESprPtr), hl
        ld (ix + 0), $FF        ; (not into screen B)
        ret

; (OvSprPatterns) IX = a size: its patterns into VRAM, the address set:
; row by row, each pattern's left byte column's 16 lines, then its right's.
; The rows are aligned to the image's bottom line: lines above it clear.
OvSprImage:
        push bc
        ld e, (ix + 0)
        ld d, 0                 ; DE = a line on
        ld l, (ix + 4)
        ld h, (ix + 5)          ; HL = the row's first line in the image
        ld a, (ix + 1)
        ld c, a
        add a, 15
        and $F0
        sub c
        neg
        ld c, a                 ; C = the row's first line (from -pad)
.row:   xor a                   ; byte column
.col:   push af
        push hl
        add a, l
        ld l, a
        jr nc, .c1
        inc h
.c1:    ld a, c
        ld b, 16
.ln:    or a
        push af
        ld a, 0                 ; (above the image: clear)
        jp m, .z
        ld a, (hl)
        add hl, de
.z:     out (EIN_VDP_DATA), a
        pop af
        inc a
        djnz .ln
        pop hl
        pop af
        inc a
        ld b, a
        ld a, (ix + 0)
        and $FE
        cp b
        ld a, b
        jr nz, .col
        ld a, c                 ; the next row: on by this one's lines
        ld b, 16
.adv:   or a
        jp m, .an
        add hl, de
.an:    inc a
        djnz .adv
        ld c, a
        cp (ix + 1)
        jr c, .row
        pop bc
        ret

; (OvSprPatterns) IX = a size: E = the patterns it takes, R * C (D = C)
OvSprCount:
        ld a, (ix + 1)
        add a, 15
        rrca
        rrca
        rrca
        rrca
        and 15
        ld e, a
        ld a, (ix + 0)
        srl a
        ld d, a
        xor a
.m:     add a, d
        dec e
        jr nz, .m
        ld e, a
        ret
