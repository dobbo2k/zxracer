; HL = packed data (tools/zpack.py format), DE = destination. A holds the
; bits not yet used, above a marker bit.
Unpack: ld a, $80
.lit:   call Gamma              ; a literal run
        ldir
        call GetBit
        jr c, .new
        call Gamma              ; a repeat match: the last offset again
.copy:  push hl
        push bc
        ld bc, (LastOff)
        ld h, d
        ld l, e
        or a
        sbc hl, bc
        pop bc
        ldir
        pop hl
        call GetBit
        jr nc, .lit
.new:   call Gamma              ; a match: offset's high part + 1 (256: the end)
        inc b
        dec b
        ret nz
        dec c
        ld b, c
        ld c, (hl)
        inc hl
        inc bc
        ld (LastOff), bc
        call Gamma
        inc bc                  ; length
        jr .copy
; -> BC: an interlaced Elias-gamma number
Gamma:  ld bc, 1
.g:     call GetBit
        ret c
        call GetBit
        rl c
        rl b
        jr .g
; -> carry: the next bit
GetBit: add a, a
        ret nz
        ld a, (hl)
        inc hl
        rla
        ret
LastOff:        dw 0

