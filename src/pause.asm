; (In a gap of bank 2 after the fill block.)
; H pauses a game (at the start of a game frame): the last frame stays on
; show with PAUSED on its message line, the sound off, until H is pressed
; again.
PAUSE_ROW       EQU $BF             ; ENTER L K J H
PAUSE_BIT       EQU $10             ; H
CheckPause:
        ld a, (GameState)
        cp ST_PLAYING
        ret nz
        ld a, PAUSE_ROW
        in a, ($FE)
        and PAUSE_BIT
        ret nz
        call WaitFlip           ; (the frame just drawn is on show)
        ld a, 1
        ld (Mute), a
        call Silence
        ld a, (HudOr)
        push af
        ld a, (BackBuf)         ; 1: B is drawn next, so A is on show
        dec a
        and $80
        ld (HudOr), a
        ld bc, MSG_ROW * 256 + MSG_COL
        ld de, MsgPaused
        call PrintAt
        pop af
        ld (HudOr), a
        call .release
.wait:  halt
        ld a, PAUSE_ROW
        in a, ($FE)
        and PAUSE_BIT
        jr nz, .wait
        call .release
        xor a
        ld (Mute), a
        ld h, a
        ld l, a
        ld (MsgLastA), hl       ; (the message line is redrawn)
        ld (MsgLastB), hl
        ld a, (FrameCount)      ; (no catching up on the time paused)
        ld (LastLogic), a
        ld (LastFlip), a
        ret
.release:
        halt
        ld a, PAUSE_ROW
        in a, ($FE)
        and PAUSE_BIT
        jr z, .release
        ret
MsgPaused:      db "       PAUSED       ", 0
