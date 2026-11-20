; ---------------------------------------------------------------------------
; Game states: attract (demo driver), playing (timer counts down, each
; checkpoint adds time), game over or goal (the car rolls to a stop, then
; back to attract mode on stage 1).
; Runs before the player update with the raw input.
; ---------------------------------------------------------------------------
ST_ATTRACT      EQU 0
ST_PLAYING      EQU 1
ST_OVER         EQU 2
START_TIME      EQU $68             ; BCD seconds
OVER_FRAMES     EQU 200             ; 50 Hz frames on the game-over screen
FORK_WARN       EQU 6500            ; units before the end of a stage
MSG_FRAMES      EQU 100             ; how long a checkpoint message shows

GameUpdate:
        ld a, (StageDone)       ; reached the end of a stage last frame
        or a
        jr z, .noCheck
        ld a, (GameState)
        cp ST_OVER
        call nz, Checkpoint     ; (after the goal the car just rolls on)
.noCheck:
        ld a, (GameState)
        cp ST_PLAYING
        jr z, .playing
        cp ST_OVER
        jp z, .over
        ; ---- attract: any key starts a game
        ld a, (Input)
        and (1 << IN_LEFT) | (1 << IN_RIGHT) | (1 << IN_UP) | (1 << IN_FIRE)
        jp nz, StartGame
        ld a, 1
        ld (DemoMode), a
        ld hl, (AttractTimer)   ; now and then, the title screen
        dec hl
        ld (AttractTimer), hl
        ld a, h
        or l
        ret nz
        jp GoTitle
.playing:
        ld a, (Lights)          ; the stage's clock (once the lights are green)
        cp LIGHTS_GO
        jr nc, .held
        ld a, (Elapsed)
        ld hl, (StageClock)
        add a, l
        ld l, a
        jr nc, .clk
        inc h
.clk:   ld (StageClock), hl
.held:  ; timer: one second per 50 frames
        ld a, (Elapsed)
        ld hl, SecTick
        add a, (hl)
        ld (hl), a
        cp 50
        jr c, .noSec
        sub 50
        ld (hl), a
        ld a, (Time)
        sub 1
        daa
        ld (Time), a
        cp $11
        jr nc, .noSec
        call TimeWarn           ; the last 10 seconds: the timer flashes, a pip each second
        ld a, (Time)
        or a
        jr nz, .noSec
        ; out of time
        ld a, ST_OVER
        ld (GameState), a
        ld a, OVER_FRAMES
        ld (StateTimer), a
        ld hl, MsgOver
        ld (Message), hl
        ret
.noSec: ; approaching a fork: tell the player to choose
        ld a, (StageRow)
        cp NUM_ROWS
        jr nc, .noFork          ; the last row ends at the goal
        ld hl, (StageLen)
        ld de, (Pos)
        or a
        sbc hl, de
        ld de, FORK_WARN
        or a
        sbc hl, de
        jr nc, .noFork
        ld hl, MsgFork
        ld (Message), hl
        ret
.noFork:
        ld a, (StateTimer)       ; message timer
        or a
        ret z
        ld hl, Elapsed
        sub (hl)
        jr nc, .st
        xor a
.st:    ld (StateTimer), a
        ret nz
        ld hl, (MsgThen)        ; the next message queued, or none
        ld a, h
        or l
        jr nz, .then
        ld hl, MsgNone
        ld (Message), hl
        ret
.then:  ld (Message), hl
        ld hl, (MsgThen + 2)
        ld (MsgThen), hl
        ld hl, 0
        ld (MsgThen + 2), hl
        ld a, MSG_FRAMES
        ld (StateTimer), a
        ret
.over:  xor a                   ; no control: the car rolls to a stop
        ld (Input), a
        ld a, (StateTimer)
        ld hl, Elapsed
        sub (hl)
        jr nc, .ov
        xor a
.ov:    ld (StateTimer), a
        ret nz
        jp EndGame

; Score += Speed * Elapsed / 4 (while playing)
AddScore:
        ld a, (GameState)
        cp ST_PLAYING
        ret nz
        ld a, (Speed)
        ld b, a
        ld a, (Elapsed)
        ld c, a
        xor a
.m:     add a, b
        dec c
        jr nz, .m
        rrca
        rrca
        and $3F                 ; 0..20: binary -> BCD
        ld b, 0
.bcd:   cp 10
        jr c, .add
        sub 10
        inc b
        jr .bcd
.add:   ld c, a
        ld a, b
        rlca
        rlca
        rlca
        rlca
        or c                    ; BCD value
        ld hl, Score
        add a, (hl)
        daa
        ld (hl), a
        ld b, 3
.carry: inc hl
        ld a, (hl)
        adc a, 0
        daa
        ld (hl), a
        djnz .carry
        ret
