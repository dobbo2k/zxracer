; ---------------------------------------------------------------------------
; Einstein: the keyboard, answered as the Spectrum's
;
; The game's own key reads (src/input.asm ReadInput with its redefinable
; KeyMap, the front end, the pause key) ask port $FE: A = the half-rows to
; read (a 0 bit each), the keys back in bits 0-4 (0: pressed). EinSpecIn
; (the KEY_IN macro, src/defs.asm) answers from the Einstein's keyboard:
; its 8 rows read once, then each Spectrum key looked up where the same key
; sits on the Einstein (the shifts have none).
;
; The Einstein's matrix is read through the AY: a row selected (active low)
; on register 14 (port A, an output), its 8 keys read (active low) from
; register 15 (port B). The interrupt writes the AY too, so interrupts are
; off between choosing the register and reading it.
; ---------------------------------------------------------------------------

; A = half-rows (port $FE's high byte) -> A = their keys, as port $FE's
; bits 0-4 (bits 5-7 set). Everything but AF kept.
EinSpecIn:
        push bc
        push de
        push hl
        ld c, a                 ; C: the half-rows wanted (0: wanted)
        ld a, (FrameCount)      ; the keyboard: read once a TV frame
        ld hl, EKeyFrame
        cp (hl)
        call nz, EinKeyScan
        ld e, $FF               ; E: the answer
        ld b, 0                 ; B: the half-row
        ld a, c                 ; C: those wanted, as 1s (done when none are
        cpl                     ; left)
        ld c, a
.h:     srl c
        jr nc, .n
        ld a, b                 ; its keys: SpecKeys + B * 10
        add a, a
        ld l, a
        add a, a
        add a, a
        add a, l
        add a, low SpecKeys
        ld l, a
        ld a, high SpecKeys
        adc a, 0
        ld h, a
        push hl
        ld a, b                 ; its answer this TV frame, worked out once
        add a, low EKeyAns
        ld l, a
        ld a, high EKeyAns
        adc a, 0
        ld h, a
        ld a, (hl)
        or a
        jr nz, .have
        ex (sp), hl             ; (the half-row's keys)
        push hl
        push bc
        ld c, $FF               ; C: its answer
        ld d, 1                 ; D: the key's bit
.key:   ld a, (hl)              ; the key's Einstein row (8: none)
        inc hl
        add a, low EKeyRows
        ld b, a
        ld a, (hl)              ; its column
        inc hl
        push hl
        ld l, b
        ld h, high EKeyRows
        and (hl)
        pop hl
        jr z, .up
        ld a, c
        xor d                   ; pressed: its bit 0
        ld c, a
.up:    sla d
        bit 5, d
        jr z, .key
        ld a, c
        pop bc
        pop hl
        ex (sp), hl
        ld (hl), a
.have:  and e
        ld e, a
        pop hl
.n:     inc b
        ld a, c
        or a
        jr nz, .h
        ld a, e
        pop hl
        pop de
        pop bc
        ret

; A = this TV frame: the Einstein's 8 rows read (EKeyRows, pressed keys
; set); the half-rows' answers to be worked out afresh (EKeyAns: 0)
EinKeyScan:
        ld (hl), a
        ld hl, EKeyAns
        ld b, 8
.z:     ld (hl), 0
        inc hl
        djnz .z
        ld hl, EKeyRows
        ld d, 1
.scan:  ld a, d
        cpl
        ld e, a
        di
        ld a, 14
        out (EIN_PSG_SELECT), a
        ld a, e
        out (EIN_PSG_WRITE), a
        ld a, 15
        out (EIN_PSG_SELECT), a
        in a, (EIN_PSG_READ)
        ei
        cpl
        ld (hl), a
        inc hl
        sla d
        jr nc, .scan
        ld (hl), 0              ; (EKeyRows + 8: no key)
        ret

EKeyAns:        ds 8            ; per half-row, this TV frame's answer (0: not yet)
EKeyRows:       ds 9             ; (the ninth: none, for the shifts)
        ASSERT high EKeyRows == high (EKeyRows + 8)
EKeyFrame:      db $FF          ; (the TV frame they were read in)

; Per Spectrum half-row ($FE, $FD .. $7F) and key (bit 0-4): where the key
; is on the Einstein, its row and its column's bit (row 8: none). The
; Einstein's rows:
;   0 BREAK - F0 F7 ALPHA ENTER SPACE ESC      4  7 6 5 4 3 2 1 F3
;   1 I O P [ _ LF | 0                          5  U Y T R E W Q F2
;   2 K L ; : ] EOT 9 F5                        6  J H G F D S A F1
;   3 , . / 8 EM = ^ F4                         7  M N B V C X Z F6
        MACRO EK row, col
        db row, 1 << col
        ENDM
SpecKeys:
        db 8, 1                         ; CAPS SHIFT
        EK 7, 6                         ; Z
        EK 7, 5                         ; X
        EK 7, 4                         ; C
        EK 7, 3                         ; V
        EK 6, 6                         ; A
        EK 6, 5                         ; S
        EK 6, 4                         ; D
        EK 6, 3                         ; F
        EK 6, 2                         ; G
        EK 5, 6                         ; Q
        EK 5, 5                         ; W
        EK 5, 4                         ; E
        EK 5, 3                         ; R
        EK 5, 2                         ; T
        EK 4, 6                         ; 1
        EK 4, 5                         ; 2
        EK 4, 4                         ; 3
        EK 4, 3                         ; 4
        EK 4, 2                         ; 5
        EK 1, 7                         ; 0
        EK 2, 6                         ; 9
        EK 3, 3                         ; 8
        EK 4, 0                         ; 7
        EK 4, 1                         ; 6
        EK 1, 2                         ; P
        EK 1, 1                         ; O
        EK 1, 0                         ; I
        EK 5, 0                         ; U
        EK 5, 1                         ; Y
        EK 0, 5                         ; ENTER
        EK 2, 1                         ; L
        EK 2, 0                         ; K
        EK 6, 0                         ; J
        EK 6, 1                         ; H
        EK 0, 6                         ; SPACE
        db 8, 1                         ; SYMBOL SHIFT
        EK 7, 0                         ; M
        EK 7, 1                         ; N
        EK 7, 2                         ; B

; ---------------------------------------------------------------------------
; Joystick 1 (the Wonder Boy port's src/platform/einstein/joystick.asm):
; analogue, through the ADC0844 at $38 - channel 0 its X (0 left, 255
; right), channel 1 its Y (0 down, 255 up), 128 at rest - and its fire on
; port $20 bit 0 (low when held). Read only if both axes rested at the start
; (EinJoyDetect): a port with no stick in it may read as one held over.
EIN_ADC         EQU $38
EIN_FIRE        EQU $20
JOY_LOW         EQU $40
JOY_HIGH        EQU $C0

EinJoyDetect:
        xor a
        call EinAdc
        call .centred
        ret nz
        ld a, 1
        call EinAdc
        call .centred
        ret nz
        ld a, 1
        ld (EJoyThere), a
        ret
.centred:
        cp JOY_LOW
        jr c, .off
        cp JOY_HIGH
        jr nc, .off
        xor a
        ret
.off:   or $FF
        ret

; -> A = the stick, as the Kempston's bits (0 right, 1 left, 2 down, 3 up,
; 4 fire). B used.
EinJoy:
        ld a, (EJoyThere)
        or a
        ret z
        push de
        ld e, 0
        xor a                   ; X
        call EinAdc
        cp JOY_LOW
        jr nc, .nl
        set IN_LEFT, e
.nl:    cp JOY_HIGH
        jr c, .nr
        set IN_RIGHT, e
.nr:    ld a, 1                 ; Y
        call EinAdc
        cp JOY_LOW
        jr nc, .nd
        set IN_DOWN, e
.nd:    cp JOY_HIGH
        jr c, .nu
        set IN_UP, e
.nu:    in a, (EIN_FIRE)
        rra
        jr c, .nf
        set IN_FIRE, e
.nf:    ld a, e
        pop de
        ret

; A = a channel -> A = its value: the conversion started, 52 us waited
EinAdc:
        out (EIN_ADC), a
        ld b, 16
.w:     djnz .w
        in a, (EIN_ADC)
        ret

EJoyThere:      db 0
