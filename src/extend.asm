; ---------------------------------------------------------------------------
; Stage times, extended play and weaving traffic: the resident pieces (bank
; 5). A stage's clock runs in GameUpdate; at a checkpoint the overlay
; (OvCheckpoint) records the time, gives extra time - more under the stage's
; par time (extended play) - and queues the messages below; the route screen
; (src/frontend.asm) shows every stage's time.
; ---------------------------------------------------------------------------
WEAVE_NEAR      EQU 600             ; a vehicle this far ahead of the player ...
WEAVE_SPAN      EQU 512             ; ... up to this much further may weave

; HL = 50 Hz frames -> DE: M'SS"CC (7 characters; minutes up to 9)
FmtTime:
        ld bc, -3000
        call .dig
        ld a, "'"
        ld (de), a
        inc de
        ld bc, -500
        call .dig
        ld bc, -50
        call .dig
        ld a, $22               ; "
        ld (de), a
        inc de
        ld bc, -5               ; hundredths: frames * 2
        call .dig
        ld a, l
        add a, a
        add a, "0"
        ld (de), a
        ret
; BC = -step: A = HL / step as a digit, at (DE); HL = the rest
.dig:   ld a, "0" - 1
.d:     inc a
        add hl, bc
        jr c, .d
        sbc hl, bc              ; (no carry: HL + step)
        ld (de), a
        inc de
        ret

; IX = a vehicle in one of the two lanes: if it is in reach ahead of the
; player (and before a fork's split), head for the player's line. Carry set
; if it does.
WeaveTo:
        ld a, (ix + 2)          ; only from a lane (not again while weaving)
        add a, LANE_X
        jr z, .lane
        sub 2 * LANE_X
        jr z, .lane
        or a                    ; (NC: no)
        ret
.lane:  ld l, (ix + 0)
        ld h, (ix + 1)
        ld a, (HasFork)
        or a
        jr z, .noFork
        ld de, (ForkZ)
        sbc hl, de
        ret nc                  ; past the split
        add hl, de
.noFork:
        ld de, (Pos)
        or a
        sbc hl, de
        ld de, -WEAVE_NEAR
        add hl, de
        ret nc                  ; too near, or behind
        ld a, h
        cp high WEAVE_SPAN
        ret nc                  ; too far
        ld hl, (PlayerX)        ; the player's line, x / 4, within the lanes
        sra h
        rr l
        sra h
        rr l
        ld a, l
        bit 7, a
        jr nz, .left
        cp LANE_X + 1
        jr c, .set
        ld a, LANE_X
        jr .set
.left:  cp -LANE_X
        jr nc, .set
        ld a, -LANE_X
.set:   ld (ix + 5), a
        scf
        ret

; ---------------------------------------------------------------------------
; Each interrupt in a game (SoundTick): a jingle's next note on channel C
; once the one before is nearly over (with a new stage's tune waiting:
; MusicWaitTick). A new stage's (OvCheckpoint sets
; JingleHold) waits for its first frame: the interrupt that flips to it
; (LastFlip = FrameCount, src/interrupt.asm).
JingleTick:
        ld a, (MusicWait)       ; a new stage's tune waiting (src/holes.asm)
        or a
        jp nz, MusicWaitTick
JingleRun:
        ld a, (JingleHold)
        or a
        jr z, .go
        ld a, (LastFlip)
        ld hl, FrameCount
        cp (hl)
        ret nz
        xor a
        ld (JingleHold), a
.go:    ld hl, (JinglePtr)
        ld a, h
        or l
        ret z
        ld a, (BeepTime)
        cp 2
        ret nc
        ld e, (hl)
        inc hl
        ld d, (hl)
        inc hl
        ld a, d
        or e
        jr z, .end
        ld a, (hl)
        inc hl
        ld (JinglePtr), hl
        jp BeepOn
.end:   ld (JinglePtr), de
        ret
; (JingleHold, JingleGo, Difficulty: src/holes.asm)

; ---------------------------------------------------------------------------
; A = digit, HL = top-left cell (preserved): the timer's big digit - the
; font's digit at double size, 16 x 16 over two cell rows (drawn once a
; second, so it is worked out here rather than stored)
PrintBig:
        push de
        push bc
        push hl
        add a, "0" - 32
        ld e, a
        ld d, 0
        ex de, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ld bc, Font
        add hl, bc
        ex de, hl               ; DE -> the glyph, HL = the screen
        ld c, 2                 ; two cell rows ...
.cell:  push hl
        ld b, 4                 ; ... of four font rows, each twice
.row:   push bc
        ld a, (de)
        inc de
        push de
        push hl
        ld c, a                 ; each pixel twice: a nibble at a time
        rrca
        rrca
        rrca
        rrca
        and $0F
        add a, low DblNib
        ld l, a
        ld h, high DblNib
        ld d, (hl)
        ld a, c
        and $0F
        add a, low DblNib
        ld l, a
        ld e, (hl)
        sla e                   ; (the font's pixels are bits 6-2)
        rl d
        pop hl
        ld (hl), d
        inc l
        ld (hl), e
        inc h
        ld (hl), e
        dec l
        ld (hl), d
        inc h
        pop de
        pop bc
        djnz .row
        pop hl
        ld a, l
        add a, 32
        ld l, a
        dec c
        jr nz, .cell
        pop hl
        pop bc
        pop de
        ret
