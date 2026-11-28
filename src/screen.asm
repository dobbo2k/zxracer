; ---------------------------------------------------------------------------
; Screen buffers: A = bank 5 at $4000, B = bank 7 (paged at $C000)
; ---------------------------------------------------------------------------

; Page in the back buffer and point the renderer at it.
        IFNDEF ZX48
SelectBackBuffer:
        ld a, (BackBuf)
        or a
        jr nz, .bufB
        ld a, P7FFD_ROM48 | P7FFD_SHADOW | 7    ; B displayed, draw into A (bank 7 stays paged for the theme cache)
        ld e, 0
        ld d, high StateA1
        ld c, $58
        jr .set
.bufB:  ld a, P7FFD_ROM48 | 7                ; A displayed, bank 7 at $C000
        ld e, $80
        ld d, high StateB1
        ld c, $D8
.set:   ld (Port7FFD), a
        push bc
        ld bc, PORT_7FFD
        out (c), a
        pop bc
        ld a, e
        ld (BufHiOr), a
        ld (RunCommand.bufOr + 1), a
        push bc
        ld hl, CmdListA
        ld bc, PanoLastA
        or a
        jr z, .cmdA
        ld hl, CmdListB
        ld bc, PanoLastB
.cmdA:  ld (CmdList), hl
        ld (PanoLast), bc
        ld hl, MsgLastA
        ld bc, HudCacheA
        or a
        jr z, .msgA
        ld hl, MsgLastB
        ld bc, HudCacheB
.msgA:  ld (MsgLast), hl
        ld (HudCache), bc
        ld hl, CarShownA
        or a
        jr z, .carA
        ld hl, CarShownB
.carA:  ld (CarShown), hl
        pop bc
        ld a, e
        ld a, d
        ld (StatePage), a
        ld a, c
        ld (AttrHi), a
        ret

; Ask the interrupt handler to display the buffer just drawn (at least
; MIN_FRAMES after the last flip) and swap roles. Does not wait: the next
; frame's logic runs meanwhile.
RequestFlip:
        ld a, (BackBuf)
        or a
        ld a, P7FFD_ROM48 | 7                ; show A
        jr z, .set
        ld a, P7FFD_ROM48 | P7FFD_SHADOW | 7 ; show B
.set:   ld (FlipValue), a
        ld a, 1
        ld (FlipPending), a
        ld a, (BackBuf)
        xor 1
        ld (BackBuf), a
        ret

; Wait until a requested flip has happened (before drawing into the back
; buffer, or touching the paging or the screens).
WaitFlip:
.wait:  ld a, (FlipPending)
        or a
        ret z
        halt
        jr .wait
        ELSE
; Synchronise single-screen drawing to the clock. Poll with interrupts
; enabled so an interrupt between the test and a HALT cannot cost a tick.
WaitRaceFrame:
        ld a, (LastFlip)
        add a, MIN_FRAMES
        ld b, a
        ld a, (FrameCount)
        sub b
        jp p, .ready
        call RacePitch
        call ToneUntil
.ready: ld a, (FrameCount)
        ld (LastFlip), a
        ret

; B = target tick (modulo 256), C = half-period in polling loops (0 silent).
; The ULA speaker shares port FE with the border. Poll the clock between
; speaker samples and finish with the speaker off and the border black.
ToneUntil:
        ld de, 1
.poll:  ld a, (FrameCount)
        sub b
        jp p, .end
        ld a, c
        or a
        jr z, .poll
        dec e
        jr nz, .poll
        ld e, c
        inc a                   ; $FF selects a noisy crash burst
        jr nz, .level
        ld a, r
        and 63
        add a, 12
        ld e, a
.level:
        ld a, d
        xor $10
        ld d, a
.edge:  out ($FE), a
        jr .poll
.end:   ld a, d
        or a
        ret z
        xor a
        out ($FE), a
        ret
        ENDIF

; A = value, B = count (0-32), HL = destination; advances L only.
FillA:
        ex af, af'
        ld a, b
        or a
        jr z, .none
        add a, a
        neg
        ld (.jump + 1), a
        ex af, af'
.jump:  jp FILL_END - 256       ; low byte patched: FILL_END - 2*count
.none:  ex af, af'
        ret
