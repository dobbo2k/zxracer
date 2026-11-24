; ---------------------------------------------------------------------------
; Einstein: one command as sprites (-DEIN_OBJSPR; src/einstein/objspr.asm)
;
; IX = the command. It can be sprites if it is drawn whole (no screen edge
; or crest cuts it: its width and height are a size's of its type, and its
; source one of that size's pre-shifted copies), the size has patterns, it
; is below the HUD (EinObjSprites: and clear of the car's cells), and it
; leaves at most 4 sprites on each scanline it covers
; (counted per band of 8 lines, ESprBand) and 30 in all. Its image is C =
; width / 2 sprites across (the last byte column is the copies' padding)
; and R = height / 16 rows, rounded up, aligned to its bottom line; x is
; the copy's: column * 8 + copy * the copies' step. Then EinObjSprAttrs.
; ---------------------------------------------------------------------------
EinObjSprite:
        ld a, (ix + 0)          ; below the HUD
        cp 24
        ret c
        ld a, (ix + 3)          ; not cut at the screen's left edge
        or a
        ret nz
        ld a, (ix + 7)
        and $7F
        cp 10                   ; (the tunnel sign: not in every theme pack)
        ret nc
        ld (ESprType), a
        add a, a
        ld hl, (StTypeDir)
        add a, l
        ld l, a
        jr nc, .td
        inc h
.td:    ld a, (hl)
        inc hl
        ld h, (hl)
        ld l, a
        push hl
        pop iy                  ; IY = its sizes (8 bytes each: width, height,
        ld b, 9                 ; mask, 0, source, stride)
        ld de, 8
.sz:    ld a, (iy + 0)
        cp (ix + 2)
        jr nz, .szn
        ld a, (iy + 1)
        cp (ix + 6)
        jr z, .szh
.szn:   add iy, de
        djnz .sz
        ret
.szh:   ld a, (ESprType)        ; its patterns: ESprBase + type * 9 + size
        ld c, a
        add a, a
        add a, a
        add a, a
        add a, c
        add a, 9
        sub b
        ld l, a
        ld h, high ESprBase
        ld a, (hl)
        ld (ESprPat), a
        inc a
        ret z                   ; ($FF: none)
        ld a, (iy + 2)          ; the copies' step: the mask's lowest bit
        ld c, a
        neg
        and c
        ld c, a
        ld a, (ix + 1)
        add a, a
        add a, a
        add a, a
        ld (ESprX), a
        ld l, (iy + 4)
        ld h, (iy + 5)
        ld e, (iy + 6)
        ld d, (iy + 7)
        ld b, 8
.cp:    ld a, l
        cp (ix + 4)
        jr nz, .cpn
        ld a, h
        cp (ix + 5)
        jr z, .cpk
.cpn:   add hl, de
        ld a, (ESprX)
        add a, c
        ld (ESprX), a
        djnz .cp
        ret
.cpk:   ld a, (iy + 1)          ; R rows; E = the lines above the image
        ld e, a
        add a, 15
        and $F0
        ld d, a
        sub e
        ld e, a
        ld a, d
        rrca
        rrca
        rrca
        rrca
        ld (ESprR), a
        ld b, a
        ld a, (iy + 0)          ; C across
        srl a
        ld (ESprC), a
        ld c, a
        xor a                   ; R * C, of the sprites left
.mul:   add a, c
        djnz .mul
        ld (ESprN), a
        ld b, a
        ld a, (ESprLeft)
        cp b
        ret c
        ld a, (ix + 0)
        sub e
        ld (ESprTop), a         ; the sprites' top line
        ld a, (ix + 0)          ; its bands of 8 lines: each keeps to 4
        add a, (ix + 6)
        dec a
        rrca
        rrca
        rrca
        and 31
        cp 24
        ret nc
        ld b, a
        ld a, (ESprTop)
        rrca
        rrca
        rrca
        and 31
        ld l, a
        ld a, b
        sub l
        inc a
        ld b, a                 ; B = bands
        ld a, l
        add a, low ESprBand
        ld l, a
        ld h, high ESprBand
        push hl
        push bc
.bc:    ld a, (hl)
        add a, c
        cp 5
        jr nc, .full
        inc l
        djnz .bc
        pop bc
        pop hl
.ba:    ld a, (hl)
        add a, c
        ld (hl), a
        inc l
        djnz .ba
        jp EinObjSprAttrs       ; (src/einstein/objsprhi.asm)
.full:  pop bc
        pop hl
        ret
