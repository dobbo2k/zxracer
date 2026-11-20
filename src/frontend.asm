; ---------------------------------------------------------------------------
; Front-end overlay: the title and goal screens (and the other between-game
; screens). Assembled to run at THEME_CACHE in bank 7 and stored in a pack
; bank (tools/make_stages.py); LoadFrontEnd copies it in. The pictures are
; stored compressed in the pack banks (build/screens_data.asm says where)
; and unpacked by ShowPic, which is resident: it pages their banks over this.
;
; A picture is unpacked into screen A ($4000) while screen B (the last game
; frame) is on show, then screen A is shown and the text printed on it. The
; game's sound is muted (Mute) and the screens beep on their own. On return
; screen A is still on show and the game draws into B first.
; ---------------------------------------------------------------------------

; End of a game: the goal screen if the goal was reached, then the title.
; Returns A = 1 to start a game.
GameOverScreens:
        ld a, (GoalPending)
        or a
        jr z, TitleScreen
        xor a
        ld (GoalPending), a
        call GoalScreen

TITLE_FRAMES    EQU 400             ; 8 s, then the demo
GOAL_FRAMES     EQU 600             ; 12 s after the bonus count
START_KEYS      EQU (1 << IN_LEFT) | (1 << IN_RIGHT) | (1 << IN_UP) | (1 << IN_FIRE)

; Title screen. Returns A = 1 if a key was pressed (start a game), 0 if it
; timed out (back to the demo).
TitleScreen:
        call ScreensEnter
        call UpdateHiScore
        ld a, (ScrTitle)
        ld hl, (ScrTitle + 1)
        call ShowPic
        ld bc, HISCORE_ROW * 256 + HISCORE_COL
        call CellAddr
        ld ix, HiScore
        call PrintScore7
        call WaitRelease
        ld de, TITLE_FRAMES
.lp:    halt
        ld a, (FrameCount)      ; blink the prompt
        and 16
        ld a, $46
        jr z, .on
        ld a, $40
.on:    ld hl, $5800 + PRESS_ROW * 32
        ld b, 32
.at:    ld (hl), a
        inc l
        djnz .at
        call ReadInput
        ld a, (Input)
        and START_KEYS
        jr nz, .key
        dec de
        ld a, d
        or e
        jr nz, .lp
        jp ScreensLeave         ; (A = 0)
.key:   ld a, 1
        jp ScreensLeave

; Goal screen for the stage just finished: the ending, the time bonus
; (1000 points per second left) counted into the score.
GoalScreen:
        call ScreensEnter
        ld a, (Stage)
        sub NUM_STAGES - NUM_ROWS       ; the last row's stages
        jr nc, .g0
        xor a
.g0:    ld l, a
        add a, a
        add a, a
        add a, l
        ld l, a
        ld h, 0
        ld de, GoalTable        ; 5 bytes per ending: bank, picture, line
        add hl, de
        ld a, (hl)
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)
        inc hl
        push hl
        ex de, hl
        call ShowPic
        pop hl
        ld e, (hl)
        inc hl
        ld d, (hl)              ; DE -> column, text
        ld a, (de)
        ld c, a
        inc de
        ld b, GOAL_ENDING_ROW
        call PrintAt
        ld bc, GOAL_CONGRATS_ROW * 256 + 8
        ld de, TxtCongrats
        call PrintAt
        ld bc, GOAL_SCORE_ROW * 256 + 6
        ld de, TxtFinal
        call PrintAt
        ld bc, GOAL_BONUS_ROW * 256 + 6
        ld de, TxtBonus
        call PrintAt
        call .show
        ld b, 50
.w1:    halt
        djnz .w1
        ; the bonus: each second left is 1000 points
.count: ld a, (Time)
        or a
        jr z, .done
        sub 1
        daa
        ld (Time), a
        ld hl, Score + 1
        ld a, (hl)
        add a, $10
        daa
        ld (hl), a
        inc hl
        ld a, (hl)
        adc a, 0
        daa
        ld (hl), a
        inc hl
        ld a, (hl)
        adc a, 0
        daa
        ld (hl), a
        call .show
        ld a, 60                ; a short beep per second counted
        call Beep
        halt
        halt
        halt
        jr .count
.done:  call UpdateHiScore
        ld bc, GOAL_PRESS_ROW * 256 + 9
        ld de, TxtPress
        call PrintAt
        call WaitRelease
        ld de, GOAL_FRAMES
.lp:    halt
        call ReadInput
        ld a, (Input)
        and START_KEYS
        jr nz, .end
        dec de
        ld a, d
        or e
        jr nz, .lp
.end:   xor a
        jr ScreensLeave
.show:  ld bc, GOAL_SCORE_ROW * 256 + 18
        call CellAddr
        ld ix, Score
        call PrintScore7
        ld bc, GOAL_BONUS_ROW * 256 + 18
        call CellAddr
        ld a, (Time)
        call PrintBcd
        ld de, TxtTimes
        jp PrintAt.ch

; Mute the game's sound, keep the last game frame on show (screen B).
ScreensEnter:
        call WaitFlip
        ld a, 1
        ld (Mute), a
        call Silence
        xor a
        ld (HudOr), a           ; print into screen A
        ld a, P7FFD_ROM48 | P7FFD_SHADOW | 7
        ld (Port7FFD), a
        ld bc, PORT_7FFD
        out (c), a
        ret

; Back to the game: screen A on show, the game draws into B next. Keeps A.
ScreensLeave:
        push af
        call Silence
        xor a
        ld (Mute), a
        ld a, 1
        ld (BackBuf), a
        ld a, (FrameCount)
        ld (LastLogic), a
        ld (LastFlip), a
        pop af
        ret

; HL = cell address, IX = 4-byte BCD score (low byte first): 7 digits
PrintScore7:
        ld a, (ix + 3)
        call PrintLowNib
        ld a, (ix + 2)
        call PrintBcd
        ld a, (ix + 1)
        call PrintBcd
        ld a, (ix + 0)
        jp PrintBcd

; HiScore = Score if higher (BCD, compared from the top byte)
UpdateHiScore:
        ld hl, Score + 3
        ld de, HiScore + 3
        ld b, 4
.c:     ld a, (de)
        cp (hl)
        jr c, .copy             ; hi-score lower
        ret nz                  ; hi-score higher
        dec hl
        dec de
        djnz .c
        ret
.copy:  ld hl, Score
        ld de, HiScore
        ld bc, 4
        ldir
        ret

; Wait until the start keys are released (at most 2 s)
WaitRelease:
        ld b, 100
.w:     halt
        push bc
        call ReadInput
        pop bc
        ld a, (Input)
        and START_KEYS
        ret z
        djnz .w
        ret

; A = tone period (low byte): a short beep on channel A
Beep:   ld e, a
        xor a
        call AyWrite
        ld e, 0
        ld a, 1
        call AyWrite
        ld e, %00111110         ; tone A only
        ld a, 7
        call AyWrite
        ld e, 12
        ld a, 8
        call AyWrite
        halt
        ld e, 0
        ld a, 8
        jp AyWrite

Silence:
        ld e, 0
        ld a, 8
        call AyWrite
        ld e, 0
        ld a, 9
        call AyWrite
        ld e, 0
        ld a, 10
        jp AyWrite

TxtCongrats:    db "CONGRATULATIONS!", 0
TxtFinal:       db "SCORE", 0
TxtBonus:       db "TIME BONUS", 0
TxtTimes:       db " X 1000", 0
TxtPress:       db "PRESS ANY KEY", 0

        INCLUDE "screens_data.asm"
