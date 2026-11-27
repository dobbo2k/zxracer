; ---------------------------------------------------------------------------
; CPC: two screens and the flip
;
; Screen A is base 1, screen B base 3. The one being drawn is at $4000 for
; the CPU (RAM configuration C1 while A is hidden, C3 while B is): the main
; code selects it after WaitFlip, before it draws. RequestFlip marks the
; frame ready; the VSYNC interrupt shows it when it is due (CpcShow: the
; CRTC's start address, taken as the next frame starts, 70 lines on, with
; only border between), and from then on the other screen is the hidden one.
; ---------------------------------------------------------------------------

; The Spectrum's per-buffer pointers, for the parts of its drawing code
; that still run: all at buffer B, whose screen ($C000) is the shadow.
SelectBackBuffer:
        ld a, $80
        ld (BufHiOr), a
        ld (RunCommand.bufOr + 1), a
        ld hl, CmdListB
        ld (CmdList), hl
        ld hl, PanoLastB
        ld (PanoLast), hl
        ld hl, MsgLastB
        ld (MsgLast), hl
        ld hl, HudCacheB
        ld (HudCache), hl
        ld hl, CarShownB
        ld (CarShown), hl
        ld a, high StateB1
        ld (StatePage), a
        ld a, $D8
        ld (AttrHi), a
        ret

GameFrames:     dw 0            ; (for the tests: game frames drawn)
CpcHidden:      db 0            ; the screen being drawn: 0 A, 1 B

; Until the frame asked for is shown; then the other screen at $4000
WaitFlip:
.w:     ld a, (FlipPending)
        or a
        jr z, CpcSelect
        halt
        jr .w

; The hidden screen at $4000 (A kept)
CpcSelect:
        push af
        push bc
        ld a, (CpcHidden)
        add a, a
        or RAM_A                ; C1, or C3 with B hidden
        ld (CRamNow), a         ; (known: src/cpc/tyres.asm)
        ld b, high GA_PORT
        out (c), a
        pop bc
        pop af
        ret

; This frame is ready: shown from the VSYNC it is due at (src/cpc/boot.asm
; CpcIsr). The next frame's logic runs meanwhile.
RequestFlip:
        ld hl, (GameFrames)
        inc hl
        ld (GameFrames), hl
        ld a, 1
        ld (FlipPending), a
        ret

; (From the interrupt at VSYNC) the hidden screen shown, the other hidden.
; A, BC used.
CpcShow:
        ld a, (CpcHidden)
        or a
        ld a, CRTC_A
        jr z, .a
        ld a, CRTC_B
.a:     ld bc, CRTC_SELECT + 12
        out (c), c
        ld b, high CRTC_WRITE
        out (c), a
        ld a, (CpcHidden)
        xor 1
        ld (CpcHidden), a
        ld a, (CCarLast)        ; (its pose, its tyres as drawn:
        ld (CTyrePose), a       ; src/cpc/tyres.asm)
        ld a, $FF
        ld (CTyreShown), a
        ret
