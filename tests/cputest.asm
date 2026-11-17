; ---------------------------------------------------------------------------
; CPU self-test for the zxsim emulator. Each CHECK records the actual A and F
; next to hand-computed expected values; tests/run_cputest.py compares them
; (undocumented flag bits 3 and 5 are masked out).
; ---------------------------------------------------------------------------
        DEVICE ZXSPECTRUM128
RESULTS EQU $A000

        MACRO CHECK ea, ef
        push af
        push hl
        push af
        pop hl
        ld (iy+0), h
        ld (iy+1), l
        ld (iy+2), ea
        ld (iy+3), ef
        ld hl, 4
        ex de, hl
        add iy, de
        ex de, hl
        pop hl
        pop af
        ENDM

        ORG $8000
start:  di
        ld sp, $9000
        ld iy, RESULTS
        ; 1-5: 8-bit arithmetic
        ld a, $7F : add a, 1      : CHECK $80, $94
        ld a, $FF : add a, 1      : CHECK $00, $51
        ld a, $10 : sub $20       : CHECK $F0, $83
        ld a, $80 : sub 1         : CHECK $7F, $16
        ld a, 5   : cp 5          : CHECK $05, $42
        ; 6-10: inc/dec/logic/rotate
        ld a, $0F : scf : inc a   : CHECK $10, $11
        ld a, 1 : or a : dec a    : CHECK $00, $42
        ld a, $F0 : and $3C       : CHECK $30, $14
        xor a                     : CHECK $00, $44
        ld a, $81 : or a : rlca   : CHECK $03, $85
        ; 11-13: 16-bit
        ld hl, $7FFF : ld de, 1 : or a : sbc hl, de : ld a, h : CHECK $7F, $02
        ld a, l                   : CHECK $FE, $02
        xor a : ld hl, $0FFF : ld de, 1 : add hl, de : ld a, h : CHECK $10, $54
        ld hl, $FFFF : ld bc, 0 : scf : adc hl, bc : ld a, h : CHECK $00, $51
        ; 15-17: CB prefix
        ld a, 1 : or a : rr a     : CHECK $00, $45
        ld a, $80 : or a : bit 7, a : CHECK $80, $90
        ld b, 0 : set 3, b : res 0, b : ld a, b : or a : CHECK $08, $00
        ; 18: djnz
        ld b, 5 : xor a
.dj:    inc a : djnz .dj          : CHECK $05, $00
        ; 19: ldir
        xor a : ld hl, src : ld de, dst : ld bc, 4 : ldir : ld a, (dst+3) : CHECK $04, $40
        ; 20: push/pop
        ld bc, $1234 : push bc : pop af : CHECK $12, $14
        ; 21-23: index registers
        ld ix, data : ld a, (ix+2) : add a, (ix+1) : CHECK $32, $10
        ld (ix+3), $55 : ld a, (ix+3) : CHECK $55, $10
        push ix : ld ix, $AB00 : ld a, ixh : pop ix : CHECK $AB, $10
        ; 24: call/ret
        call sub42                : CHECK $42, $10
        ; 25-28
        ld a, 1 : neg             : CHECK $FF, $93
        ld a, $15 : add a, $27 : daa : CHECK $42, $14
        ld a, 3 : srl a           : CHECK $01, $01
        ld hl, mem : ld a, $12 : rld : CHECK $13, $01
        ld a, (hl)                : CHECK $42, $01
        ; 30-31: exchanges
        ld hl, 1 : ld de, 2 : ex de, hl : ld a, l : or a : CHECK $02, $00
        ld b, 7 : exx : ld b, 9 : exx : ld a, b : or a : CHECK $07, $00
        ; 32: sbc a
        ld a, $10 : scf : sbc a, $0F : CHECK $00, $52
        ; 33: cpir
        or a : ld hl, data2 : ld bc, 4 : ld a, 3 : cpir : ld a, c : CHECK $01, $46
        ; 34: IM2 interrupts
        ld a, $90 : ld i, a
        ld hl, $9000 : ld (hl), $95 : ld de, $9001 : ld bc, 256 : ldir
        im 2
        xor a : ld (ticks), a
        ei : halt : halt : halt : di
        ld a, (ticks) : or a      : CHECK $03, $04
        ; 35: 128K paging - write bank 3, read back after switching banks
        ld bc, $7FFD : ld a, $13 : out (c), a : ld a, $77 : ld ($C000), a
        ld a, $14 : out (c), a : ld a, $11 : ld ($C000), a
        ld a, $13 : out (c), a : ld a, ($C000) : or a : CHECK $77, $04

        ; 36-40: memory loads/stores via BC, DE, (nn)
        ld hl, $1234 : ld (word), hl : ld hl, 0 : ld a, (word+1) : or a : CHECK $12, $04
        ld hl, (word) : ld a, l : or a : CHECK $34, $00
        ld bc, word : ld a, $5A : ld (bc), a : ld de, word : ld a, (de) : or a : CHECK $5A, $04
        push iy : ld ix, $4321 : ld (word), ix : ld iy, (word) : ld a, iyl : pop iy : or a : CHECK $21, $04
        ld a, $99 : ld ($9F00), a : xor a : ld a, ($9F00) : CHECK $99, $44

        ; end marker
        ld (iy+0), $EE : ld (iy+1), $EE
done:   jr done

sub42:  ld a, $42 : ret
isr:    push af : ld a, (ticks) : inc a : ld (ticks), a : pop af : ei : reti
ticks:  db 0
src:    db 1, 2, 3, 4
dst:    ds 4
data:   db 10, 20, 30, 0
data2:  db 1, 2, 3, 4
mem:    db $34
word:   dw 0

        ORG $9595
        jp isr

        SAVESNA "build/cputest.sna", start
