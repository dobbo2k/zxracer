; ---------------------------------------------------------------------------
; IM2 interrupt handling and tear-free screen flipping
; ---------------------------------------------------------------------------

InitInterrupts:
        ld hl, IM2_TABLE
        ld de, IM2_TABLE + 1
        ld bc, 256
        ld (hl), high ISR_JP
        ldir
        ld a, high IM2_TABLE
        ld i, a
        im 2
        IFDEF EINSTEIN
        jp EinCtcInit           ; the 50 Hz tick from the CTC (src/einstein/boot.asm)
        ELSE
        IFDEF CPC
        jp CpcIntInit           ; the Gate Array's six a frame (src/cpc/boot.asm)
        ELSE
        ret
        ENDIF
        ENDIF

; 50 Hz handler. Counts frames and performs a pending flip at the top of the
; frame (before the beam reaches the display), at most every MIN_FRAMES frames.
        IFDEF EINSTEIN
Isr     EQU EinIsr              ; (src/einstein/boot.asm: the VDP's frames, polled)
        ELSE
        IFDEF CPC
Isr     EQU CpcIsr              ; (src/cpc/boot.asm: six a frame, one at VSYNC)
        ELSE
Isr:
        push af
        push hl
        push bc
        push de
        ld hl, FrameCount
        inc (hl)
        ld a, (FlipPending)
        or a
        jr z, .done
        ld a, (hl)
        ld hl, LastFlip
        sub (hl)
        cp MIN_FRAMES
        jr c, .done
        ld a, (FrameCount)
        ld (hl), a
        ld a, (FlipValue)
        ld (Port7FFD), a
        ld bc, PORT_7FFD
        out (c), a
        xor a
        ld (FlipPending), a
.done:  call TyreTick              ; after the flip, which must beat the beam:
                                   ; the rolling tyres, then the sound
        pop de
        pop bc
        pop hl
        pop af
        ei
        reti
        ENDIF
        ENDIF
