; ---------------------------------------------------------------------------
; CPC: the game's packs from the disc (docs/port_cpc.md 5.11)
;
; Everything the Spectrum keeps in its pack banks (the stage packs, the
; between-stages overlay, the front end, the pictures) is on the disc in
; SPEED.DAT, each packed (tools/zpack.py) from a sector of its own
; (tools/make_cpc.py). CpcLoad reads one into bank 4 and unpacks it from
; there to where it goes, a byte of the packed stream at a time with bank 4
; paged in at $4000; whatever it writes is seen as in play (the hidden
; screen at $4000, bank 7 at $C000). The interrupt runs on meanwhile but
; for a sector's read: nothing it touches is at $4000 or $C000 (Paged keeps
; the tune, in the theme cache, out of it).
; ---------------------------------------------------------------------------

        INCLUDE "fdc.asm"

; HL = a pack's first logical sector, BC = its packed bytes, DE = where it
; goes. The motor stays on (CpcMotorOff when the loading is done).
CpcLoad:
        ld (CLoadDst), de
        ld a, 1
        ld (Paged), a
        push hl
        push bc
        call FdcStart
        pop hl
        ld bc, 511
        add hl, bc
        ld a, h
        srl a                   ; (BC + 511) / 512 sectors
        ld (CLoadN), a
        pop hl
        call FdcPlace           ; D, E: its first sector's place
        ld bc, GA_PORT | RAM_BANK4
        out (c), c
        ld hl, $4000
.sec:   call FdcReadSector
        jr nc, .sec             ; (till it reads)
        call FdcNext
        ld a, (CLoadN)
        dec a
        ld (CLoadN), a
        jr nz, .sec
        ld hl, $4000
        ld de, (CLoadDst)
        call CpcUnpack
        xor a
        ld (Paged), a
        jp CpcSelect

CLoadDst:       dw 0
CLoadN:         db 0

; The loading done
CpcMotorOff     EQU FdcStop

; A sector that will not read: the border red till one does
FdcFailed:
        ld a, GA_COLOUR | $0C   ; (bright red)
        jr FdcBorder
FdcRecovered:
        ld a, GA_COLOUR | HW_BLACK
FdcBorder:
        ld bc, GA_PORT | $10
        out (c), c
        out (c), a
        ret

; HL = packed data in bank 4 (at $4000 with it paged in), DE = where it
; goes: unpacked (tools/zpack.py's format, as src/loader.asm Unpack). The
; packed bytes are read through CUnGet; what has been unpacked is copied
; from where it went (matches), the hidden screen's configuration in.
CpcUnpack:
        ld a, (CpcHidden)       ; (the configuration CUnGet puts back)
        add a, a
        or RAM_A
        ld (CUnGet.dst + 1), a
        ld a, $80
.lit:   call CUnGamma           ; a literal run
        ex af, af'              ; (the bits kept)
.lc:    call CUnGet
        ld (de), a
        inc de
        dec bc
        ld a, b
        or c
        jr nz, .lc
        ex af, af'
        call CUnBit
        jr c, .new
        call CUnGamma           ; a repeat match: the last offset again
.copy:  push hl
        push bc
        ld bc, (CUnOff)
        ld h, d
        ld l, e
        or a
        sbc hl, bc
        pop bc
        ldir
        pop hl
        call CUnBit
        jr nc, .lit
.new:   call CUnGamma           ; a match: the offset's high part + 1 (256: the end)
        inc b
        dec b
        ret nz
        dec c
        ld b, c
        ex af, af'
        call CUnGet
        ld c, a
        ex af, af'
        inc bc
        ld (CUnOff), bc
        call CUnGamma
        inc bc                  ; its length
        jr .copy
; -> BC: an interlaced Elias-gamma number
CUnGamma:
        ld bc, 1
.g:     call CUnBit
        ret c
        call CUnBit
        rl c
        rl b
        jr .g
; -> carry: the next bit
CUnBit: add a, a
        ret nz
        call CUnGet             ; (the carry kept)
        rla
        ret
; -> A = the next packed byte, from bank 4; HL past it. Flags, BC kept.
CUnGet: push bc
        ld bc, GA_PORT | RAM_BANK4
        out (c), c
        ld a, (hl)
        inc hl
.dst:   ld c, RAM_A             ; (patched: the hidden screen's)
        out (c), c
        pop bc
        ret
CUnOff:         dw 0
