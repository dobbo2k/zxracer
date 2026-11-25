; ---------------------------------------------------------------------------
; Objects in their own inks (src/objink.asm): its pieces in every theme pack,
; at THEME_CACHE + 28 after the pack's Inks (tools/make_stages.py; the pack
; is a MODULE: the game's names are written name)
; ---------------------------------------------------------------------------
ObjPack:
        jp OSrcRow              ; (THEME_CACHE + 28: OSrcRowP)
        jp OPanoCell            ; (+ 31: OPanoCellP)

; The command at IX in row ORow: OSrc, the address of its line at the row's
; top (or its first); OSrcC, low OS + the row's first line with any (0-7);
; OSrcN, how many; OPixHi, the row's line 0; OCell's stride (its bytes a
; line)
OSrcRow:
        ld a, (@ORow)
        ld b, a
        and $18
        or $40
        ld c, a
        ld a, (@BufHiOr)
        or c
        ld (@OPixHi), a
        ld a, b                 ; the object's line at the row's top (< 0: it
        add a, a                ; starts lower)
        add a, a
        add a, a
        sub (ix + 0)
        ld c, 0
        jr nc, .t
        neg
        ld c, a
        xor a
.t:     ld b, a                 ; B: that line, C: the row's first
        ld a, (ix + 6)          ; its lines from there, at most the row's
        sub b
        ld e, a
        ld a, 8
        sub c
        cp e
        jr c, .n
        ld a, e
.n:     ld (@OSrcN), a
        ld a, c
        add a, low @OS
        ld (@OSrcC), a
        ld a, (ix + 2)          ; data + B lines of (bytes + skipped)
        add a, (ix + 3)
        ld (@OCell.st + 1), a
        ld e, b
        ld d, 0
        ld hl, 0
        ld b, 4
.m:     rrca
        jr nc, .m1
        add hl, de
.m1:    sla e
        rl d
        djnz .m
        ld e, (ix + 4)
        ld d, (ix + 5)
        add hl, de
        ld (@OSrc), hl
        ld a, 1
        ld (@OSrcOk), a
        ret

; HL = the attribute of a cell in rows 10-11: its pixels from the panorama,
; at the scroll the buffer shows (PanoLast; $FF: none drawn, or cleared in a
; tunnel - then none)
OPanoCell:
        ld a, (@BufHiOr)
        or $48                  ; (rows 8-15's lines 0)
        ld b, a
        ld a, l
        and 31
        ld c, a
        ld de, (@PanoLast)
        ld a, (de)
        cp $FF
        jr z, .clear
        ld d, a                 ; the panorama's byte there: (column + scroll
        rrca                    ; / 8) & 31, of the copy 4 pixels on (512
        rrca                    ; on) if the scroll says so; row 11: its lines
        rrca                    ; 8-15 (256 on)
        add a, c
        and 31
        ld e, a
        ld a, d
        and 4
        rrca
        ld d, a
        ld a, l
        and $20
        rlca
        rlca
        rlca
        add a, d
        ld d, a
        ld h, b
        push hl
        ld hl, (@StPano)
        add hl, de
        ex de, hl
        pop hl
        ld b, 8
.c:     ld a, (de)
        ld (hl), a
        inc h
        ld a, e
        add a, 32
        ld e, a
        jr nc, .c1
        inc d
.c1:    djnz .c
        ret
.clear: ld h, b
        ld b, 8
.z:     ld (hl), 0
        inc h
        djnz .z
        ret
