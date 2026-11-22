; ---------------------------------------------------------------------------
; Einstein: TMS9129 access
;
; With the display on and the beam in the picture, VRAM accesses must be at
; least 32 T-states apart (8 us at 4 MHz), or the chip loses them (Albert
; counts each one; the harness fails a run that has any). Every write here
; keeps that gap, so it is safe at any time.
; ---------------------------------------------------------------------------

; A = value, E = register
VdpReg:
        out (EIN_VDP_CTRL), a
        ld a, e
        or $80
        out (EIN_VDP_CTRL), a
        ret

; DE = VRAM address to write from
VdpAddr:
        ld a, e
        out (EIN_VDP_CTRL), a
        ld a, d
        and $3F
        or $40
        out (EIN_VDP_CTRL), a
        ret

; HL = source, DE = VRAM address, B = count (1-256, 0: 256): 32 T a byte.
; HL advances.
VdpWrite:
        call VdpAddr
        ld c, EIN_VDP_DATA
.lp:    outi
        nop
        jr nz, .lp
        ret

; DE = VRAM address, BC = count, L = value: 42 T a byte
VdpFill:
        call VdpAddr
.lp:    ld a, l
        out (EIN_VDP_DATA), a
        dec bc
        ld a, b
        or c
        jr nz, .lp
        ret

; Graphics II, 16K, 16x16 sprites, the display off; registers 0-7
VdpInit:
        ld hl, VdpRegs
        ld e, 0
.r:     ld a, (hl)
        call VdpReg
        inc hl
        inc e
        ld a, e
        cp 8
        jr nz, .r
        in a, (EIN_VDP_CTRL)    ; (any frame flag latched meanwhile: gone)
        ret
VdpRegs:
        db $02                  ; R0: M3, Graphics II
        db $82                  ; R1: 16K, display off, no interrupt, 16x16 sprites
        db VRAM_NAMES / $400    ; R2: names
        db $FF                  ; R3: colours at $2000, the full Graphics II mask
        db $03                  ; R4: patterns at $0000, the full mask
        db VRAM_SPRATTR / $80   ; R5: sprite attributes
        db VRAM_SPRPAT / $800   ; R6: sprite patterns
        db $01                  ; R7: black backdrop

VdpOn:  ld a, $C2               ; R1: the display on
        ld e, 1
        jp VdpReg

VdpOff: ld a, $82
        ld e, 1
        jp VdpReg

; ---------------------------------------------------------------------------
; Spectrum colours -> TMS9129 colours (bright in bit 3)
SpecTms:
        db 1, 4, 6, 13, 12, 7, 10, 14           ; black blue red magenta green cyan yellow white
        db 1, 5, 8, 13, 3, 7, 11, 15            ; bright

; A = attribute -> A = the TMS colour of its paper (HL kept)
AttrPaper:
        rrca
        rrca
        rrca
        and $0F
        jr SpecColour
; A = attribute -> A = the TMS colour of its ink (HL kept)
AttrInk:
        ld e, a
        and 7
        bit 6, e
        jr z, SpecColour
        or 8
SpecColour:
        push hl
        ld hl, SpecTms
        add a, l
        ld l, a
        jr nc, .h
        inc h
.h:     ld a, (hl)
        pop hl
        ret
