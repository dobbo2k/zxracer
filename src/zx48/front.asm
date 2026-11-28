; End screen: the five destinations, score and completed stage times.
GameOverScreens:
        ld a, (PalHud)
        call ClearFront
        ld bc, $0207
        ld a, (GoalPending)
        or a
        jr nz, .goal
        ld de, TimeUpText
        call FrontLarge
        ld de, (StName)
        jr .location
.goal:
        xor a
        ld (GoalPending), a
        call GoalBonus
        ld hl, (StageClock)
        ld (StageTimes + 8), hl
        ld de, FinishText
        call FrontLarge
        ld a, (Stage)
        sub NUM_STAGES - NUM_ROWS
        add a, a
        ld e, a
        ld d, 0
        ld hl, EndingNames
        add hl, de
        ld e, (hl)
        inc hl
        ld d, (hl)
.location:
        ld bc, $0505
        call PrintAt
        ld bc, $0705
        ld de, ScoreText
        call PrintAt
        ld de, Score + 3
        ld b, 4
.score: ld a, (de)
        call PrintBcd
        dec de
        djnz .score
        ld ix, StageTimes
        ld b, 10
.time:  ld l, (ix + 0)
        ld h, (ix + 1)
        ld a, h
        or l
        jr z, .next
        push bc
        ld de, ResultTime
        call FmtTime
        pop bc
        push bc
        ld c, 5
        ld de, ResultLabel
        call PrintAt
        pop bc
        ld a, b
        sub 9
        push bc
        call PrintDigit
        ld de, ResultTime
        call PrintAt.ch
        pop bc
.next:  inc ix
        inc ix
        inc b
        ld a, b
        cp 15
        jr nz, .time
ResultsReady:
        call RecordBest
        ld de, 300
        call FrontWait
        jp TitleScreen

FrontWait:
        FRAME_WAIT
        push de
        call ReadInput
        pop de
        ld a, (Input)
        and (1 << IN_UP) | (1 << IN_FIRE) | (1 << IN_LEFT) | (1 << IN_RIGHT)
        ret nz
        dec de
        ld a, d
        or e
        jr nz, FrontWait
        ret

FrontLarge:
        call CellAddr
.char:  ld a, (de)
        inc de
        or a
        ret z
        sub "0"
        call PrintBig
        inc l
        inc l
        jr .char

TimeUpText:     db "TIME UP", 0
FinishText:     db "FINISHED", 0
ScoreText:      db "SCORE ", 0
ResultLabel:    db "STAGE ", 0
ResultTime:     ds 8

RecordBest:
        ld de, Score + 3
        ld hl, BestScore + 3
        ld b, 4
.compare:
        ld a, (de)
        cp (hl)
        ret c
        jr nz, .record
        dec de
        dec hl
        djnz .compare
        ret
.record:
        ld hl, Score
        ld de, BestScore
        ld bc, 4
        ldir
        ret

BestScore:      db $00, $00, $06, $00
