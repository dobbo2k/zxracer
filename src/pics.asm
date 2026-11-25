; The pictures' unpacker (front end; it pages the pictures' banks over the
; overlay, so it is resident, bank 5).
; A = bank, HL = compressed picture in it: unpack into screen A, show it
ShowPic:
        IFDEF NATIVE_GFX        ; (the Einstein: A = its records, HL = the first,
        jp GfxPicture           ; in STAGES.DAT)
        ENDIF
        or P7FFD_ROM48 | P7FFD_SHADOW
        ld bc, PORT_7FFD
        ld (Paged), a           ; (A <> 0: the title tune is out of reach)
        out (c), a
        ld de, $4000
        call UnLZ
        xor a
        ld (Paged), a
        ld a, P7FFD_ROM48 | 7   ; screen A on show, bank 7 back
        ld (Port7FFD), a
        ld bc, PORT_7FFD
        out (c), a
        ret

; HL = source, DE = destination (see tools/make_screens.py)
UnLZ:   ld a, (hl)
        inc hl
        cp $FF
        ret z
        cp $80
        jr nc, .match
        inc a
        ld c, a
        ld b, 0
        ldir                    ; literals
        jr UnLZ
.match: sub $80 - 3
        ld c, a
        ld b, 0
        ld a, (hl)
        inc hl
        push hl
        ld h, (hl)
        ld l, a                 ; offset
        push de
        ex de, hl
        or a
        sbc hl, de              ; destination - offset
        pop de
        ldir                    ; (overlapping copies repeat, like LDIR should)
        pop hl
        inc hl
        jr UnLZ
