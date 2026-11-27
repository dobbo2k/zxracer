; ---------------------------------------------------------------------------
; CPC: start-up and the interrupt
;
; The disc's loader (src/cpc/loader.asm) puts the game in place with the
; firmware gone and jumps to CpcBoot. From then on the machine is the
; game's: interrupts in mode 2 through the Spectrum's own vector table
; ($BE00, every entry $BDBD: JP Isr), six a frame from the Gate Array.
; ---------------------------------------------------------------------------

; The CRTC: 64 bytes a line (R1 = 32 words), 24 rows of 8 lines (R6, R9)
; in a 312-line frame (R4 = 38: 39 rows), VSYNC at row 30 (R7: line 240)
CpcCrtc:        db 63, 32, 42, $8E, 38, 0, 24, 30, 0, 7, 0, 0, CRTC_A, 0

CpcBoot:
        di
        ld sp, STACK_TOP
        ld bc, GA_PORT | GA_MODE0       ; mode 0, both ROMs off
        out (c), c
        ld c, RAM_A                     ; screen A hidden at $4000
        out (c), c
        call CpcBlack                   ; every pen and the border black
        ld hl, CpcCrtc
        ld de, 0                        ; (E: the register)
.crtc:  ld b, high CRTC_SELECT
        out (c), e
        ld b, high CRTC_WRITE
        ld a, (hl)
        out (c), a
        inc hl
        inc e
        ld a, e
        cp 14
        jr c, .crtc
        ld bc, PPI_CONTROL | PPI_A_OUT
        out (c), c
        xor a                           ; the AY silent: every register 0, the
.ay:    ld e, 0                         ; mixer's tones and noise off
        cp 7
        jr nz, .v
        ld e, $3F
.v:     call AyWrite
        inc a
        cp 14
        jr c, .ay
        call SelectBackBuffer           ; (the shared drawing code: screen B)
        ld a, $80
        ld (HudOr), a
        jp start

; Every pen and the border black (blanking: the Spectrum's black attributes)
CpcBlack:
        ld bc, GA_PORT
        ld e, 16
.pen:   out (c), e
        ld a, GA_COLOUR | HW_BLACK
        out (c), a
        dec e
        jp p, .pen
        ret

; (InitInterrupts, after IM 2): the Gate Array's interrupts in step
CpcIntInit:
        ld bc, GA_PORT | GA_MODE0 | $10 ; its line counter reset
        out (c), c
        xor a
        ld (CIndex), a
        ret

; The interrupt, six a frame: the Gate Array's, 2 lines after VSYNC begins
; (line 242) and every 52 lines on. The one at VSYNC (PPI port B's bit 0
; set) is the Spectrum's 50 Hz interrupt: the TV frame counted, a frame
; that is ready shown if it is due, the sound, the keyboard. Taken late,
; VSYNC over, it is still known: the sixth since the last.
CIndex:         db 0            ; interrupts since the last at VSYNC
CGrid:          db 0            ; the TV frame the last shown was due at
        IFNDEF FLIP_DEBT
FLIP_DEBT        EQU 3           ; after a late frame, up to 3 TV frames made
        ENDIF                   ; up, one a frame shown (-DFLIP_DEBT=0: none)
FLIP_GAP        EQU MIN_FRAMES - 1  ; (but never less than 2 apart: 3 - 1)

CpcIsr:
        push af
        push bc
        ld b, high PPI_B
        in a, (c)
        rra
        jr c, .vsync
        ld a, (CIndex)
        inc a
        ld (CIndex), a
        cp 6
        jr nc, .vsync           ; (VSYNC missed: interrupts off a while)
        pop bc
        pop af
        ei
        reti
.vsync: xor a
        ld (CIndex), a
        push hl
        push de
        ld hl, FrameCount
        inc (hl)
        ld a, (FlipPending)
        or a
        jr z, .snd
        ld a, (hl)              ; at least FLIP_GAP since the last shown
        ld hl, LastFlip
        sub (hl)
        cp FLIP_GAP
        jr c, .snd
        ld a, (FrameCount)      ; and at or past the grid's next tick
        ld hl, CGrid
        sub (hl)
        cp MIN_FRAMES
        jr c, .snd
        ld a, (hl)              ; the grid on a step, owing at most FLIP_DEBT
        add a, MIN_FRAMES       ; TV frames
        ld (hl), a
        ld a, (FrameCount)
        sub (hl)
        cp FLIP_DEBT + 1
        jr c, .owed
        ld a, (FrameCount)
        sub FLIP_DEBT
        ld (hl), a
.owed:  ld a, (FrameCount)
        ld (LastFlip), a
        call CpcShow            ; the screen just drawn shown (src/cpc/flip.asm)
        xor a
        ld (FlipPending), a
.snd:   call CpcTyreTick        ; (the rear tyres' tread: src/cpc/tyres.asm)
        call SoundTick
        call CpcScan            ; the keyboard's 10 lines (src/cpc/keys.asm)
        pop de
        pop hl
        pop bc
        pop af
        ei
        reti

; The next TV frame (FRAME_WAIT; in the front end its share of cells
; first: src/cpc/front.asm). Everything kept.
CpcHalt:
        push af
        push hl
        ld a, (CFrontOn)
        or a
        jr z, .w0
        push bc
        push de
        push ix
        call CFrontSync
        pop ix
        pop de
        pop bc
.w0:    ld hl, FrameCount
        ld a, (hl)
.w:     halt
        cp (hl)
        jr z, .w
        pop hl
        pop af
        ret

; D = a coarse tone period (the Spectrum's D * 256 at 1.77 MHz) -> DE = the
; same pitch on the CPC's 1 MHz AY: D * 144 (AF kept; HL spent)
CpcCoarse:
        push af
        ld l, d
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl              ; 16 D
        ld d, h
        ld e, l
        add hl, hl
        add hl, hl
        add hl, hl              ; 128 D
        add hl, de
        ex de, hl               ; 144 D
        pop af
        ret
