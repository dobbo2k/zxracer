; ---------------------------------------------------------------------------
; Einstein: start-up and the 50 Hz tick
;
; XtalDOS loads SPEEDRUN.COM at $0100 and jumps there. From then on the
; machine is the game's: interrupts in mode 2 through the Spectrum's own
; vector table ($BE00, every entry $BDBD: JP Isr), now driven by the CTC.
; ---------------------------------------------------------------------------

EinBoot:
        di
        ld sp, STACK_TOP
        call VdpInit            ; Graphics II, the display off
        ld a, 7                 ; the AY: tone and noise off, port A out (the
        ld e, $3F               ; keyboard's rows), port B in
        call AyWrite
        call EinJoyDetect       ; (a joystick at rest: there)
        call SelectBackBuffer   ; the Spectrum drawing code's pointers: screen B
        ld a, $80
        ld (HudOr), a
        jp start

; The interrupt (from InitInterrupts). The VDP's frame interrupt does not
; reach the Z80, so the CTC asks it: channel 2, a timer on the 4 MHz clock,
; /16, 250 counts, interrupts every 1 ms (vector base 0: channel 2's vector
; is 4, IM2_TABLE + 4 -> Isr), and each time the handler reads the VDP's
; status. Its frame flag (set as the picture ends, cleared by the read)
; starts a TV frame: the Spectrum's 50 Hz interrupt, at most 1 ms late.
; Channel 3 (MOS's clock) is stopped.
ELongWait:      db 0            ; (the CTC on its 16 ms wait)
EFirstPoll:     db 0            ; (this poll: the first after that wait)
        IFNDEF EIN_MIN_FRAMES   ; (-D: the benchmark measures the work unlocked)
EIN_MIN_FRAMES  EQU 4           ; a frame sent at most every 4 TV frames: a
        ENDIF                   ; steady 12.5 fps (the Spectrum: MIN_FRAMES)

EinCtcInit:
        xor a
        ld (ELongWait), a
        out (EIN_CTC0), a       ; the vector (bit 0 clear: not a control word)
        ld a, %00000011         ; channel 3: reset, no interrupt
        out (EIN_CTC3), a
        ld a, %10000111         ; channel 2: interrupt, timer, /16, a time
        out (EIN_CTC2), a       ; constant follows, reset
        ld a, 250
        out (EIN_CTC2), a
        in a, (EIN_VDP_CTRL)    ; (a frame flag from before: gone)
        ret

; Each millisecond: a new TV frame? Then as the Spectrum's interrupt: count
; it, send a frame that is ready (src/einstein/flip.asm EinUpload: in this
; vertical blank, at least MIN_FRAMES after the last), and the sound.
EinIsr:
        push af
        ld a, (ELongWait)       ; the 16 ms wait over: 1 ms ticks again
        or a
        jr z, .tick
        xor a
        ld (ELongWait), a
        inc a
        ld (EFirstPoll), a      ; (this poll: the first after it)
        ld a, %10000111
        out (EIN_CTC2), a
        ld a, 250
        out (EIN_CTC2), a
.tick:  ld a, (EFrontOn)        ; (the front end: the VDP is the main code's,
        or a                    ; a frame every 20 ticks)
        jr nz, .front
        in a, (EIN_VDP_CTRL)
        rla
        jr c, .seen
        xor a
        ld (EFirstPoll), a
.out:   pop af
        ei
        reti
.front: ld a, (ETick)
        inc a
        cp 20
        jr c, .tk
        xor a
.tk:    ld (ETick), a
        jr nz, .out
        jr .frame
.seen:  ld a, (EFirstPoll)       ; a frame seen: the next is ~19.9 ms on, so
        or a                    ; no polls for 16 ms (timer /256, 250, reset);
        jr nz, .late            ; but not if it was there at the first poll
        ld a, %10100111         ; after a wait (it may have been waiting a
        out (EIN_CTC2), a       ; while: the next poll 1 ms on, as ever)
        ld a, 250
        out (EIN_CTC2), a
        ld a, 1
        ld (ELongWait), a
.late:  xor a
        ld (EFirstPoll), a
.frame: push hl
        push bc
        push de
        push ix
        push iy
        ld hl, FrameCount
        inc (hl)
        ld a, (FlipPending)
        or a
        jr z, .snd
        ld a, (hl)
        ld hl, LastFlip
        sub (hl)
        cp EIN_MIN_FRAMES
        jr c, .snd
        ld a, (FrameCount)
        ld (hl), a
        call EinUpload
        xor a
        ld (FlipPending), a
.snd:   call SoundTick
.over:  ld a, (EFrontOn)        ; a frame begun meanwhile (a long one: a full
        or a                    ; car, a tunnel's sky)? Counted, with its sound;
        jr nz, .done            ; and 1 ms polls again (the phase lost)
        in a, (EIN_VDP_CTRL)
        rla
        jr nc, .done
        ld hl, FrameCount
        inc (hl)
        xor a
        ld (ELongWait), a
        ld a, %10000111
        out (EIN_CTC2), a
        ld a, 250
        out (EIN_CTC2), a
        call SoundTick
        jr .over
.done:  pop iy
        pop ix
        pop de
        pop bc
        pop hl
        pop af
        ei
        reti

; D = a coarse tone period (the Spectrum's D * 256 at 1.77 MHz) -> DE = the
; same pitch on the Einstein's 2 MHz AY: D * 289 (AF kept; HL spent)
EinCoarse:
        push af
        ld l, d
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl              ; 32 D
        ld a, l
        add a, d
        ld e, a
        ld a, h
        adc a, d
        ld d, a                 ; + 257 D
        pop af
        ret
