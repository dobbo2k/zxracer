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

; The checkpoint's messages (filled in by OvCheckpoint)
MsgTime:        db " STAGE TIME 0'00", $22, "00 ", 0
MsgBonus:       ds MSG_LEN + 1
