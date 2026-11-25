; ---------------------------------------------------------------------------
; CPC: the keyboard and the joystick
;
; The VSYNC interrupt reads the keyboard's 10 lines (CpcScan) after the
; sound: a read in the main code would be broken by the interrupt's AY
; writes, which change the AY's selected register and the PPI's port A.
; The game's code reads the Spectrum's half-rows (KEY_IN: CpcSpecIn),
; answered from those lines through a table of where each Spectrum key is.
; ---------------------------------------------------------------------------

CpcKeys:        ds 10, $FF      ; the lines as last read (0: pressed)

; From the interrupt: the 10 lines into CpcKeys. A, BC, HL used.
CpcScan:
        ld bc, PPI_A | 14       ; the AY's register 14 (its port A: the keys)
        out (c), c
        ld bc, PPI_C | AY_SELECT
        out (c), c
        ld c, 0
        out (c), c
        ld bc, PPI_CONTROL | PPI_A_IN
        out (c), c
        ld hl, CpcKeys
        ld a, AY_READ           ; line 0, the AY read
.line:  ld b, high PPI_C
        out (c), a
        ld b, high PPI_A
        ini                     ; (HL) <- the line; B back to $F4 - 1: unused
        inc a
        cp AY_READ + 10
        jr c, .line
        ld bc, PPI_CONTROL | PPI_A_OUT
        out (c), c
        ld bc, PPI_C
        out (c), c
        ret

; A = the Spectrum's half-rows to read (as port $FE's high byte: a 0 bit
; each) -> A = their keys (bits 0-4, 0: pressed; bits 5-7 set), as the
; Spectrum's IN would give. BC, DE, HL kept.
CpcSpecIn:
        push bc
        push de
        push hl
        ld c, a                 ; the rows: a 0 bit each
        ld d, $FF               ; the answer (0 bits: pressed)
        ld hl, CpcSpecMap
        ld b, 8
.row:   rr c
        jr nc, .read
        ld a, l                 ; (not read: past its 10 bytes)
        add a, 10
        ld l, a
        jr nc, .next
        inc h
        jr .next
.read:  ld e, 1                 ; the key's bit in the answer
.key:   push bc
        ld c, (hl)              ; its line
        inc hl
        ld a, (hl)              ; its mask
        inc hl
        push hl
        ld hl, CpcKeys
        ld b, 0
        add hl, bc
        and (hl)
        pop hl
        pop bc
        jr nz, .up
        ld a, e                 ; pressed
        cpl
        and d
        ld d, a
.up:    sla e
        bit 5, e
        jr z, .key
.next:  djnz .row
        ld a, d
        or $E0
        pop hl
        pop de
        pop bc
        ret

; The Spectrum's keyboard on the CPC's: per half-row (from $FE's bit 0)
; its five keys (from bit 0), each a line and a bit's mask
CpcSpecMap:
        db 2, $20, 8, $80, 7, $80, 7, $40, 6, $80     ; CAPS (SHIFT) Z X C V
        db 8, $20, 7, $10, 7, $20, 6, $20, 6, $10     ; A S D F G
        db 8, $08, 7, $08, 7, $04, 6, $04, 6, $08     ; Q W E R T
        db 8, $01, 8, $02, 7, $02, 7, $01, 6, $02     ; 1 2 3 4 5
        db 4, $01, 4, $02, 5, $01, 5, $02, 6, $01     ; 0 9 8 7 6
        db 3, $08, 4, $04, 4, $08, 5, $04, 5, $08     ; P O I U Y
        db 2, $04, 4, $10, 4, $20, 5, $20, 5, $10     ; ENTER (RETURN) L K J H
        db 5, $80, 2, $80, 4, $40, 5, $40, 6, $40     ; SPACE SYMBOL (CONTROL) M N B

; The joystick (line 9: up 0, down 1, left 2, right 3, fire 4 and 5) as
; the Kempston's bits (1: pressed). C kept.
GfxJoy:
        ld a, (CpcKeys + 9)
        cpl
        ld b, 0
        rra                     ; up
        jr nc, .nu
        set IN_UP, b
.nu:    rra                     ; down
        jr nc, .nd
        set IN_DOWN, b
.nd:    rra                     ; left
        jr nc, .nl
        set IN_LEFT, b
.nl:    rra                     ; right
        jr nc, .nr
        set IN_RIGHT, b
.nr:    and 3                   ; either fire
        jr z, .nf
        set IN_FIRE, b
.nf:    ld a, b
        ret
