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
        xor a                   ; (the Spectrum's rows made afresh)
        ld (CRowOk), a
        ret

; A = the Spectrum's half-rows to read (as port $FE's high byte: a 0 bit
; each) -> A = their keys (bits 0-4, 0: pressed; bits 5-7 set), as the
; Spectrum's IN would give. Each half-row is made from the CPC's lines once
; a scan (CRowVal, CRowOk: CpcScan clears it), by its own unrolled code
; (src/cpc/keyrows.asm). One row (the game's reads): straight to its value.
; BC, DE, HL kept.
CpcSpecIn:
        push bc
        push hl
        ld c, a
        cpl
        ld b, a                 ; B = the rows as 1 bits
        dec a                   ; one row only? (B & (B - 1) = 0, B not 0)
        and b
        jr nz, .all
        or b
        jr z, .all
        ld hl, CRowVal - 1      ; its value's byte
.find:  inc l
        rr c
        jr c, .find
        ld a, (CRowOk)
        and b
        jr z, .make
        ld a, (hl)
        pop hl
        pop bc
        ret
.make:  call CRowMake
        pop hl
        pop bc
        ret
.all:   ld a, c                 ; (none or several rows: each)
        pop hl
        pop bc
        push bc
        push de
        push hl
        ld c, a                 ; the rows: a 0 bit each
        ld d, $FF               ; the answer (0 bits: pressed)
        ld hl, CRowVal - 1
        ld b, 1                 ; this row's bit
.row:   inc l
        rr c
        jr c, .next
        ld a, (CRowOk)
        and b
        ld a, (hl)
        call z, CRowMake
        and d
        ld d, a
.next:  sla b
        jr nc, .row
        ld a, d
        or $E0
        pop hl
        pop de
        pop bc
        ret

; HL = the row's byte in CRowVal, B = its bit: the row made and kept -> A
; (BC, DE, HL kept)
CRowMake:
        push bc
        push de
        push hl
        ld a, l
        sub low CRowVal
        add a, a
        add a, low CRowMakers
        ld l, a
        ld h, high CRowMakers
        ld a, (hl)
        inc l
        ld h, (hl)
        ld l, a
        call .jp                ; A = the row's keys
        pop hl
        ld (hl), a
        pop de
        pop bc
        push af
        ld a, (CRowOk)
        or b
        ld (CRowOk), a
        pop af
        ret
.jp:    jp (hl)

CRowOk:         db 0            ; the rows made since the last scan (a bit each)

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
