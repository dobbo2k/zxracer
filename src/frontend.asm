; ---------------------------------------------------------------------------
; Front-end overlay: the title, high-score, goal, route-map, initials and
; options screens. Assembled to run at THEME_CACHE in bank 7 and stored in a
; pack bank (tools/make_stages.py); LoadFrontEnd copies it in. The pictures
; are stored compressed in the pack banks (build/screens_data.asm says
; where) and unpacked by ShowPic, which is resident: it pages their banks
; over this.
;
; Everything is drawn in screen A ($4000) - a picture is unpacked with the
; screen's attributes blacked out first - and the game's sound is muted
; (Mute): the screens beep on their own. On return screen A is still on show
; and the game draws into B first.
; ---------------------------------------------------------------------------
TITLE_FRAMES    EQU 400             ; 8 s, then the high scores
TABLE_FRAMES    EQU 300             ; 6 s, then the demo
GOAL_FRAMES     EQU 600             ; 12 s after the bonus count
ROUTE_FRAMES    EQU 400
ENTRY_FRAMES    EQU 1500            ; 30 s to enter initials
START_KEYS      EQU (1 << IN_LEFT) | (1 << IN_RIGHT) | (1 << IN_UP) | (1 << IN_FIRE)
ENTER_ROW       EQU $BF             ; ENTER L K J H (ENTER: bit 0)

; The demo hands over: the title, then the high scores. Returns A = 1 to
; start a game, 0 to go back to the demo.
TitleScreen:
        call ScreensEnter
TitleCycle:
        call DrawTitle
        ld a, (MusicOn)         ; the title tune (on from the options too)
        or a
        ld hl, TitleTune
        call z, MusicStart
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
        call StartPressed
        jr nz, .start
        ld a, ENTER_ROW         ; ENTER: the options
        in a, ($FE)
        rra
        jr nc, .opt
        dec de
        ld a, d
        or e
        jr nz, .lp
        ld a, $FF               ; then the table
        call HiScreen
        jp ScreensLeave
.start: ld a, 1
        jp ScreensLeave
.opt:   call Options
        jr TitleCycle

; End of a game: the goal screen if the goal was reached, the route taken,
; the initials if the score made the table, then the title. Returns A = 1 to
; start a game.
GameOverScreens:
        call ScreensEnter
        ld a, (GoalPending)
        or a
        jr z, .route
        xor a
        ld (GoalPending), a
        ld hl, StageTimes + 2 * NUM_ROWS - 2   ; the last stage's time
        ld de, (StageClock)
        ld (hl), e
        inc hl
        ld (hl), d
        call GoalScreen
.route: call RouteScreen
        call NewHiScore
        jp TitleCycle

DrawTitle:
        call BlankAttrs
        ld a, (ScrTitle)
        ld hl, (ScrTitle + 1)
        call ShowPic
        ld bc, HISCORE_ROW * 256 + HISCORE_COL
        call CellAddr
        ld ix, HiTable
        call PrintScore7
        ld bc, 23 * 256 + 3
        ld de, TxtTitleKeys
        call PrintAt
        jp WaitRelease

; Z clear if a start key is pressed (any control but the brake)
StartPressed:
        push de
        call ReadInput
        pop de
        ld a, (Input)
        and START_KEYS
        ret

; ---------------------------------------------------------------- high scores
; A = entry to pick out ($FF: none): the table. Returns A = 1 if a start
; key was pressed, else 0 after a while.
HiScreen:
        ld (HiMark), a
        ld a, $07
        call ClearA
        call Stripes
        ld bc, 2 * 256 + 10
        ld de, TxtBest
        call TallAt
        ld bc, 2 * 256 + 10
        call SunsetAttrs
        ld ix, HiTable
        ld b, 7                 ; screen row
        ld c, 0                 ; entry
.row:   push bc
        ld a, c                 ; the place: 1ST ... 5TH
        add a, a
        add a, a
        add a, low TxtPlaces
        ld e, a
        adc a, high TxtPlaces
        sub e
        ld d, a
        ld c, 6
        call TallAt
        pop bc
        push bc
        ld c, 12                ; the initials
        ld a, (ix + 4)
        call TallChar
        inc c
        ld a, (ix + 5)
        call TallChar
        inc c
        ld a, (ix + 6)
        call TallChar
        ld c, 18                ; the score
        call TallScore
        pop bc
        ; the row's colour (the one just entered flashes)
        push bc
        ld a, c
        and 1
        ld a, $45               ; bright cyan / bright white
        jr z, .col
        ld a, $47
.col:   ld e, a
        ld a, (HiMark)
        cp c
        jr nz, .nm
        ld e, $C6               ; flashing bright yellow
.nm:    ld c, 0
        call AttrAddr
        ld a, e
        ld b, 64
.fa:    ld (hl), a
        inc hl
        djnz .fa
        pop bc
        ld de, HI_SIZE
        add ix, de
        inc b
        inc b
        inc b
        inc c
        ld a, c
        cp HI_ENTRIES
        jr c, .row
        call WaitRelease
        ld de, TABLE_FRAMES
; DE = frames: wait for a start key (A = 1) or the time (A = 0)
WaitStart:
.lp:    halt
        call StartPressed
        ld a, 1
        ret nz
        dec de
        ld a, d
        or e
        jr nz, .lp
        ret

; The score just finished: if it beats the table's last entry, make room for
; it in its place and ask for the initials, then show the table with it.
NewHiScore:
        ld ix, HiTable
        ld b, 0                 ; the place
.find:  call ScoreBeats         ; carry: Score > this entry
        jr c, .place
        ld de, HI_SIZE
        add ix, de
        inc b
        ld a, b
        cp HI_ENTRIES
        jr c, .find
        ret                     ; not in the table
.place: ld a, b
        ld (HiMark), a
        ; move the entries below down one (the last drops off)
        cp HI_ENTRIES - 1
        jr z, .copy
        ld a, HI_ENTRIES - 1
        sub b
        ld l, a                 ; entries to move
        ld h, 0
        ld e, l
        ld d, h
        add hl, hl
        add hl, hl
        add hl, hl
        or a
        sbc hl, de              ; * 7
        ld b, h
        ld c, l
        ld hl, HiTable + (HI_ENTRIES - 1) * HI_SIZE - 1
        ld de, HiTable + HI_ENTRIES * HI_SIZE - 1
        lddr
.copy:  push ix
        pop de
        ld hl, Score
        ld bc, 4
        ldir
        ld a, "."
        ld (de), a
        inc de
        ld (de), a
        inc de
        ld (de), a
        call Initials
        ld a, (HiMark)
        call HiScreen
        ret

; Carry set if Score is higher than the score at IX (BCD, from the top)
ScoreBeats:
        push bc
        ld hl, Score + 3
        push ix
        pop de
        inc de
        inc de
        inc de
        ld b, 4
.c:     ld a, (de)
        cp (hl)
        jr nz, .done            ; carry if the entry's digit is lower
        dec hl
        dec de
        djnz .c
        or a                    ; equal: not higher
.done:  pop bc
        ret

; IX = the new entry: three letters picked with left / right, taken with
; accelerate or fire (brake goes back a letter)
Initials:
        ld a, $07
        call ClearA
        call Stripes
        ld bc, 2 * 256 + 10
        ld de, TxtNewHi
        call TallAt
        ld bc, 2 * 256 + 10
        call SunsetAttrs
        ld bc, 6 * 256 + 9
        ld de, TxtYourScore
        call PrintAt
        ld bc, 6 * 256 + 20
        call CellAddr
        call PrintScore7
        ld bc, 9 * 256 + 6
        ld de, TxtInitials
        call PrintAt
        ld bc, 18 * 256 + 3
        ld de, TxtPick
        call PrintAt
        ld bc, 19 * 256 + 3
        ld de, TxtTake
        call PrintAt
        ld b, 18
        ld a, $05
        call AttrRow
        ld b, 19
        ld a, $05
        call AttrRow
        ld hl, TuneHigh
        call Tune
        call WaitRelease
        xor a
        ld (HiSlot), a
        ld (Letter), a
        call PutLetter
        ld hl, ENTRY_FRAMES
        ld (EntryTime), hl
        ld a, $FF
        ld (EntryWas), a        ; (keys held from the game are not presses)
.show:  call DrawSlots
.lp:    halt
        ld hl, (EntryTime)
        dec hl
        ld (EntryTime), hl
        ld a, h
        or l
        ret z                   ; out of time: as it is
        call ReadInput
        ld a, (EntryWas)
        cpl
        ld c, a
        ld a, (Input)
        ld (EntryWas), a
        and c                   ; newly pressed
        jr z, .held
        ld b, a
        ld a, 16                ; held: repeats after a third of a second
        ld (EntryRep), a
        ld a, b
        jr .press
.held:  ld a, (Input)           ; left / right held: repeat
        and (1 << IN_LEFT) | (1 << IN_RIGHT)
        jp z, .lp
        ld hl, EntryRep
        dec (hl)
        jp nz, .lp
        ld (hl), 5
.press: bit IN_RIGHT, a
        jr nz, .next
        bit IN_LEFT, a
        jr nz, .prev
        bit IN_DOWN, a
        jr nz, .back
        and (1 << IN_UP) | (1 << IN_FIRE)
        jr z, .lp
        ; take the letter
        ld a, 40
        call Beep
        ld a, (HiSlot)
        inc a
        ld (HiSlot), a
        cp 3
        jr c, .keep
        call DrawSlots
        ld b, 50
.w:     halt
        djnz .w
        ret
.keep:  call PutLetter          ; (the next one starts from the same letter)
        jr .show
.next:  ld a, (Letter)
        inc a
        cp ALPHA_LEN
        jr c, .set
        xor a
        jr .set
.prev:  ld a, (Letter)
        sub 1
        jr nc, .set
        ld a, ALPHA_LEN - 1
.set:   ld (Letter), a
        call PutLetter
        jp .show
.back:  ld a, (HiSlot)
        or a
        jp z, .lp
        dec a
        ld (HiSlot), a
        call SlotLetter
        jp .show

; Letter = the alphabet position of the letter in the current slot
SlotLetter:
        call SlotAddr
        ld a, (hl)
        ld hl, Alphabet
        ld bc, ALPHA_LEN * 256
.f:     cp (hl)
        jr z, .got
        inc hl
        inc c
        djnz .f
        ld c, 0
.got:   ld a, c
        ld (Letter), a
        ret

; the letter at Letter into the current slot
PutLetter:
        ld a, (Letter)
        add a, low Alphabet
        ld e, a
        adc a, high Alphabet
        sub e
        ld d, a
        ld a, (de)
        push af
        call SlotAddr
        pop af
        ld (hl), a
        ret

; HL = the current slot's letter in the entry IX
SlotAddr:
        push ix
        pop hl
        ld a, (HiSlot)
        add a, 4
        add a, l
        ld l, a
        adc a, h
        sub l
        ld h, a
        ret

; the three letters, big, the current one flashing
DrawSlots:
        ld bc, 12 * 256 + 13
        ld a, (ix + 4)
        call TallChar
        ld c, 15
        ld a, (ix + 5)
        call TallChar
        ld c, 17
        ld a, (ix + 6)
        call TallChar
        ld e, 0                 ; slot
.s:     ld a, e
        add a, a
        add a, 13
        ld c, a
        ld b, 12
        call AttrAddr
        ld a, (HiSlot)
        cp e
        ld a, $46               ; bright yellow, the current one flashing
        jr nz, .put
        ld a, $C6
.put:   ld (hl), a
        push de
        ld de, 32
        add hl, de
        pop de
        ld (hl), a
        inc e
        ld a, e
        cp 3
        jr c, .s
        ret

; ---------------------------------------------------------------- the route
; The stage pyramid, the route taken through it, and the stages' names.
RouteScreen:
        ld a, $07
        call ClearA
        call Stripes
        ld bc, 1 * 256 + 11
        ld de, TxtRoute
        call TallAt
        ld bc, 1 * 256 + 11
        call SunsetAttrs
        ; every stage: a dim box
        ld b, NUM_STAGES
        ld c, 0
.all:   push bc
        ld a, c
        call StageBox           ; HL = its top-left attribute, A = its colour
        ld a, $08               ; blue, not bright
        call FillBox
        pop bc
        inc c
        djnz .all
        ; the stages driven: bright, in the theme's colour, numbered, joined
        ld de, Route
        ld b, 0                 ; row
.rt:    ld a, (de)
        cp $FF
        jp z, .names
        push de
        push bc
        call StageBox
        call FillBox
        pop bc
        push bc
        ld a, b                 ; the row's number in the box
        add a, "1"
        ld b, (iy + 0)
        ld c, (iy + 1)
        inc c
        push af
        call CellAddr
        pop af
        call PrintChar
        pop bc
        pop de
        ; joined to the next row's stage
        inc de
        ld a, b
        cp NUM_ROWS - 1
        jr nc, .last
        ld a, (de)
        cp $FF
        jr z, .last
        push de
        push bc
        call MapEntry           ; the next stage's column
        ld a, (hl)
        ld (MapTmp), a
        dec de
        ld a, (de)              ; this stage
        push af
        call StageBox           ; (IY: its box)
        pop af
        call MapEntry
        ld a, (MapTmp)
        sub (hl)                ; 0: down to the left, 1: to the right
        ld b, (iy + 0)
        ld c, (iy + 1)
        inc b
        inc b                   ; the gap row below the box
        or a
        jr nz, .right
        dec c                   ; (the boxes share a column: link there)
        jr .link
.right: inc c
        inc c
        inc c
.link:  call AttrAddr
        ld a, $70               ; bright yellow
        ld (hl), a
        inc hl
        ld (hl), a
        pop bc
        pop de
.last:  inc b
        ld a, b
        cp NUM_ROWS
        jp c, .rt
.names: ; the names, in order, in their theme's colour
        ld de, Route
        ld b, 18
.nm:    ld a, (de)
        cp $FF
        jr z, .wait
        push de
        push bc
        call MapEntry
        inc hl
        ld a, (hl)              ; theme
        ld l, a
        add a, a
        add a, l
        add a, low MapThemes
        ld l, a
        adc a, high MapThemes
        sub l
        ld h, a
        push hl
        ld a, (hl)              ; the box colour, as ink on black
        rrca
        rrca
        rrca
        and 7
        or $40
        call AttrRow
        pop hl
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)
        pop bc
        push bc
        ld c, NAME_COL
        call PrintAt
        pop bc
        push bc
        ld a, b                 ; its row number
        sub 18 - "1"
        ld c, NAME_COL - 2
        push af
        call CellAddr
        pop af
        call PrintChar
        pop bc
        push bc
        call RowTime            ; and its time
        pop bc
        pop de
        inc de
        inc b
        ld a, b
        cp 18 + NUM_ROWS
        jr c, .nm
.wait:  ld hl, (StageTimes + 2 * NUM_ROWS - 2)
        ld a, h
        or l
        jr z, .noTotal          ; (the total only at the goal)
        ld hl, StageTimes
        ld b, NUM_ROWS
        ld de, 0
.sum:   ld a, (hl)
        add a, e
        ld e, a
        inc hl
        ld a, (hl)
        adc a, d
        ld d, a
        inc hl
        djnz .sum
        ex de, hl
        ld b, 23
        call PrintTime
        ld a, $46               ; bright yellow
        ld b, 23
        call AttrRow
        ld bc, 23 * 256 + NAME_COL
        ld de, TxtTotal
        call PrintAt
.noTotal:
        call WaitRelease
        ld de, ROUTE_FRAMES
        jp WaitStart
NAME_COL        EQU 5
TIME_COL        EQU 23

; B = screen row 18-22: that row's stage time, if it has one
RowTime:
        ld a, b
        sub 18
        add a, a
        ld l, a
        ld h, 0
        ld de, StageTimes
        add hl, de
        ld e, (hl)
        inc hl
        ld d, (hl)
        ld a, d
        or e
        ret z
        ex de, hl
; HL = 50 Hz frames, B = row: the time at TIME_COL
PrintTime:
        push bc
        ld de, TimeBuf
        call FmtTime
        pop bc
        ld c, TIME_COL
        ld de, TimeBuf
        jp PrintAt
TimeBuf:        ds 7
                db 0

; A = stage -> HL -> its MapStages column byte (row before it, theme after)
MapEntry:
        ld l, a
        add a, a
        add a, l
        add a, low MapStages
        ld l, a
        adc a, high MapStages
        sub l
        ld h, a
        inc hl
        ret

; A = stage: its box (4 x 2 cells). IY = BoxPos (screen row, column),
; HL = the box's first attribute, A = the theme's colour.
BOX_TOP         EQU 4
StageBox:
        call MapEntry
        dec hl
        ld b, (hl)              ; row in the pyramid
        inc hl
        ld c, (hl)              ; column in the row
        inc hl
        ld e, (hl)              ; theme
        ld a, b                 ; screen row = BOX_TOP + 3 * row
        add a, a
        add a, b
        add a, BOX_TOP
        ld (BoxPos), a
        ld a, c                 ; column = 14 - 3 * row + 6 * column
        add a, a
        add a, c
        add a, a
        sub b
        sub b
        sub b
        add a, 14
        ld (BoxPos + 1), a
        ld iy, BoxPos
        ld a, e
        add a, a
        add a, e
        add a, low MapThemes
        ld l, a
        adc a, high MapThemes
        sub l
        ld h, a
        ld e, (hl)
        ld b, (iy + 0)
        ld c, (iy + 1)
        call AttrAddr
        ld a, e
        ret

; HL = top-left attribute, A = attribute: a 4 x 2 box
FillBox:
        ld de, 32 - 4
        ld b, 2
.r:     ld (hl), a
        inc hl
        ld (hl), a
        inc hl
        ld (hl), a
        inc hl
        ld (hl), a
        inc hl
        add hl, de
        djnz .r
        ret

; ---------------------------------------------------------------- goal
; Goal screen for the stage just finished: the ending, the time bonus
; (1000 points per second left) counted into the score.
GoalScreen:
        call BlankAttrs
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
        ld hl, TuneGoal
        call Tune
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
.done:  ld bc, GOAL_PRESS_ROW * 256 + 9
        ld de, TxtPress
        call PrintAt
        call WaitRelease
        ld de, GOAL_FRAMES
        jp WaitStart
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

; ---------------------------------------------------------------- options
; Controls: the keyboard, a Sinclair or Cursor joystick, or keys of the
; player's own (a Kempston joystick always works too).
Options:
        ld a, $07
        call ClearA
        call Stripes
        ld bc, 1 * 256 + 12
        ld de, TxtOptions
        call TallAt
        ld bc, 1 * 256 + 12
        call SunsetAttrs
        ld bc, 5 * 256 + 4
        ld de, TxtOptMenu
        call PrintLines
        ld b, 5
        ld a, $46
        call AttrCol4
        ld b, 9
        ld c, 4
        call AttrAddr
        ld (hl), $46
        ld b, 13
        ld a, $46
        call AttrRow
.redraw:
        call ShowKeys
        ld a, (SoundMode)       ; the sound setting
        add a, a
        add a, low SoundTxts
        ld l, a
        adc a, high SoundTxts
        sub l
        ld h, a
        ld e, (hl)
        inc hl
        ld d, (hl)
        ld bc, 9 * 256 + 14
        call PrintAt
        call WaitNoKey
.lp:    halt
        call ScanKey
        jr nc, .lp
        ld a, e
        cp KEY_1
        ld hl, MapKeys
        jr z, .preset
        cp KEY_2
        ld hl, MapSinclair
        jr z, .preset
        cp KEY_3
        ld hl, MapCursor
        jr z, .preset
        cp KEY_4
        jr z, .define
        cp KEY_5
        jr z, .sound
        cp KEY_ENTER
        jr nz, .lp
        jp WaitNoKey
.sound: ld a, (SoundMode)      ; music and effects / the engine
        inc a
        cp 2
        jr c, .sm
        xor a
.sm:    ld (SoundMode), a
        call MusicStop
        ld hl, TitleTune
        call MusicStart         ; (not in engine-only mode)
        ld a, 40
        call Beep
        jp .redraw
.preset:
        ld de, KeyMap
        ld bc, 10
        ldir
        ld a, 40
        call Beep
        jr .redraw
.define:
        ld b, 0                 ; the control (in ShowKeys' order)
.def:   push bc
        ld a, b                 ; flash its line
        add a, KEYS_ROW
        ld b, a
        ld a, $C6
        call AttrRow
        call WaitNoKey
.get:   halt
        call ScanKey            ; D = row port, C = bit, E = key number
        jr nc, .get
        ld a, e
        cp KEY_H                ; (H pauses, ENTER is the options)
        jr z, .no
        cp KEY_ENTER
        jr z, .no
        ld e, c                 ; DE = the key
        pop bc
        push bc
        ld a, b
        ld (MapTmp), a          ; the controls set already: 0 .. B - 1
        ld b, 0
.dup:   ld a, (MapTmp)
        cp b
        jr z, .new
        call MapOf
        ld a, (hl)
        cp d
        jr nz, .nd
        inc hl
        ld a, (hl)
        cp e
        jr z, .no               ; taken
.nd:    inc b
        jr .dup
.new:   pop bc
        push bc
        call MapOf              ; set it
        ld (hl), d
        inc hl
        ld (hl), e
        ld a, 40
        call Beep
        pop bc
        push bc
        ld a, b
        add a, KEYS_ROW
        ld b, a
        ld a, $07
        call AttrRow
        call ShowKeys
        pop bc
        inc b
        ld a, b
        cp 5
        jr c, .def
        jp .redraw
.no:    ld a, 200               ; a low beep: not that one
        call Beep
        pop bc
        jr .def

; B = control in ShowKeys' order (accelerate, brake, left, right, gear) ->
; HL = its KeyMap entry
MapOf:  ld a, b
        add a, low CtrlBits
        ld l, a
        adc a, high CtrlBits
        sub l
        ld h, a
        ld a, (hl)
        add a, a
        add a, low KeyMap
        ld l, a
        adc a, high KeyMap
        sub l
        ld h, a
        ret
CtrlBits:       db IN_UP, IN_DOWN, IN_LEFT, IN_RIGHT, IN_FIRE

; The five controls and their keys (rows KEYS_ROW..)
KEYS_ROW        EQU 15
ShowKeys:
        ld bc, KEYS_ROW * 256 + 6
        ld de, TxtCtrls
        call PrintLines
        ld b, 0
.k:     push bc
        call MapOf
        ld d, (hl)              ; row port
        inc hl
        ld e, (hl)              ; bit
        ld hl, KeyRows          ; -> key number: row * 5 + bit
        ld c, 0
.r:     ld a, (hl)
        cp d
        jr z, .rf
        inc hl
        ld a, c
        add a, 5
        ld c, a
        cp 40
        jr c, .r
.rf:    ld a, e
.b:     rra
        jr c, .bf
        inc c
        jr .b
.bf:    pop de                  ; D = control
        push de
        ld a, d
        add a, KEYS_ROW
        ld b, a
        ld a, c
        ld c, 20
        call KeyName
        pop bc
        inc b
        ld a, b
        cp 5
        jr c, .k
        ret

; A = key number, B = row, C = column: its name (padded to 5)
KeyName:
        push af
        push bc
        ld de, TxtBlank5
        call PrintAt
        pop bc
        pop af
        add a, low KeyNames
        ld l, a
        adc a, high KeyNames
        sub l
        ld h, a
        ld a, (hl)
        cp " "
        jr c, .word
        push af
        call CellAddr
        pop af
        jp PrintChar
.word:  dec a                   ; 1-4: CAPS, SYM, ENTER, SPACE
        add a, a
        add a, low KeyWords
        ld l, a
        adc a, high KeyWords
        sub l
        ld h, a
        ld e, (hl)
        inc hl
        ld d, (hl)
        jp PrintAt

; -> carry and E = key number (keyboard row * 5 + bit), D = the row's port
; high byte, C = the key's bit, for the first key held; no carry: none
ScanKey:
        ld hl, KeyRows
        ld e, 0
.row:   ld a, (hl)
        ld d, a
        in a, ($FE)
        cpl
        and $1F
        jr nz, .found
        inc hl
        ld a, e
        add a, 5
        ld e, a
        cp 40
        jr c, .row
        or a
        ret
.found: ld c, 1
.bit:   rra
        jr c, .got
        sla c
        inc e
        jr .bit
.got:   scf
        ret

WaitNoKey:
        halt
        call ScanKey
        jr c, WaitNoKey
        ret

KeyRows:        db $FE, $FD, $FB, $F7, $EF, $DF, $BF, $7F
KeyNames:       db 1, "ZXCV", "ASDFG", "QWERT", "12345", "09876", "POIUY"
                db 3, "LKJH", 4, 2, "MNB"
KeyWords:       dw TxtCaps, TxtSym, TxtEnter, TxtSpace
KEY_1           EQU 15
KEY_2           EQU 16
KEY_3           EQU 17
KEY_4           EQU 18
KEY_5           EQU 19
KEY_ENTER       EQU 30
KEY_H           EQU 34
MapKeys:        db $DF, $01, $DF, $02, $FD, $01, $FB, $01, $7F, $01     ; P O A Q SPACE
MapSinclair:    db $EF, $08, $EF, $10, $EF, $04, $EF, $02, $EF, $01     ; 7 6 8 9 0
MapCursor:      db $EF, $04, $F7, $10, $EF, $10, $EF, $08, $EF, $01     ; 8 5 6 7 0

; ---------------------------------------------------------------- helpers
; Mute the game's sound, keep the last game frame on show (screen B).
ScreensEnter:
        call WaitFlip
        call MusicStop
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

; Back to the game: screen A on show, the game draws into B next. Keeps A
; (1: a game starts - with a flourish).
ScreensLeave:
        push af
        call MusicStop
        dec a
        ld hl, TuneStart
        call z, Tune
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

; Black out screen A's attributes (a picture unpacked into it stays unseen
; until its own attributes arrive), and show A
BlankAttrs:
        ld hl, $5800
        ld de, $5801
        ld bc, 767
        ld (hl), 0
        ldir
ShowA:  ld a, P7FFD_ROM48 | 7
        ld (Port7FFD), a
        ld bc, PORT_7FFD
        out (c), a
        ret

; A = attribute: clear screen A to it, and show A
ClearA: push af
        call BlankAttrs
        ld hl, $4000
        ld de, $4001
        ld bc, 6143
        ld (hl), l
        ldir
        pop af
        ld hl, $5800
        ld de, $5801
        ld bc, 767
        ld (hl), a
        ldir
        ret

; Sunset stripes along the top and bottom rows
Stripes:
        ld hl, $5800
        ld de, $5800 + 23 * 32
        ld b, 32
.s:     ld a, l
        and 1
        ld a, $50               ; bright red / bright yellow paper
        jr z, .p
        ld a, $70
.p:     ld (hl), a
        ld (de), a
        inc l
        inc e
        djnz .s
        ret

; B = row, C = column: tall text there in yellow over red (two rows of 16)
SunsetAttrs:
        push bc
        ld a, $46
        call AttrRow
        pop bc
        inc b
        ld a, $42
; B = row, A = attribute: the whole row
AttrRow:
        push af
        ld c, 0
        call AttrAddr
        pop af
        ld b, 32
.r:     ld (hl), a
        inc hl
        djnz .r
        ret

; B = first row, A = attribute: columns 4-5 of four rows (the option keys)
AttrCol4:
        ld c, 4
        push af
        call AttrAddr
        pop af
        ld de, 32
        ld b, 4
.r:     ld (hl), a
        add hl, de
        djnz .r
        ret

; B = row, C = column -> HL = attribute address (screen A)
AttrAddr:
        ld a, b
        rrca
        rrca
        rrca
        ld l, a
        and $03
        or $58
        ld h, a
        ld a, l
        and $E0
        or c
        ld l, a
        ret

; B = row, C = column, DE = lines (each 0-terminated, an empty one ends)
PrintLines:
.l:     ld a, (de)
        or a
        ret z
        push bc
        call PrintAt
        pop bc
        inc de
        inc b
        jr .l

; B = row, C = column, DE = text: double-height letters over rows B, B+1
TallAt:
.ch:    ld a, (de)
        or a
        ret z
        call TallChar
        inc de
        inc c
        jr .ch

; A = character, B = row, C = column (all kept, and DE): double height
TallChar:
        push de
        push bc
        sub 32
        ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        ld de, Font
        add hl, de
        ex de, hl               ; DE = the glyph
        call CellAddr
        call .half
        inc b
        call CellAddr
        call .half
        pop bc
        pop de
        ret
.half:  push bc
        ld b, 4
.r:     ld a, (de)
        ld (hl), a
        inc h
        ld (hl), a
        inc h
        inc de
        djnz .r
        pop bc
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

; B = row, C = column, IX = 4-byte BCD score: 7 double-height digits
TallScore:
        ld a, (ix + 3)
        call .nib
        ld a, (ix + 2)
        call .two
        ld a, (ix + 1)
        call .two
        ld a, (ix + 0)
.two:   push af
        rrca
        rrca
        rrca
        rrca
        call .nib
        pop af
.nib:   and $0F
        add a, "0"
        call TallChar
        inc c
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

; HL = tune: per note dw tone period (0: the end), db 50 Hz frames
Tune:   ld e, (hl)
        inc hl
        ld d, (hl)
        inc hl
        ld a, d
        or e
        ret z
        ld b, (hl)
        inc hl
        push hl
        push bc
        push de
        xor a
        call AyPut            ; tone A fine
        pop de
        ld e, d
        ld a, 1
        call AyPut            ; coarse
        ld e, %00111110         ; tone A only
        ld a, 7
        call AyPut
        ld e, 12
        ld a, 8
        call AyPut
        pop bc
.h:     halt
        djnz .h
        ld e, 0                 ; a moment's silence between notes
        ld a, 8
        call AyPut
        halt
        pop hl
        jr Tune

; notes: AY tone periods (1.7734 MHz / 16 / frequency)
N_G4    EQU 283
N_C5    EQU 212
N_E5    EQU 168
N_G5    EQU 141
N_A5    EQU 126
N_C6    EQU 106
N_E6    EQU 84
N_G6    EQU 71
TuneStart:      dw N_C5
                db 3
                dw N_E5
                db 3
                dw N_G5
                db 3
                dw N_C6
                db 8, 0, 0
TuneGoal:       dw N_G4
                db 6
                dw N_C5
                db 6
                dw N_E5
                db 6
                dw N_G5
                db 12
                dw N_E5
                db 6
                dw N_G5
                db 30, 0, 0
TuneHigh:       dw N_E5
                db 5
                dw N_G5
                db 5
                dw N_C6
                db 5
                dw N_E6
                db 5
                dw N_G6
                db 20, 0, 0

; A = tone period (low byte): a short beep on channel A
Beep:   ld e, a
        xor a
        call AyPut
        ld e, 0
        ld a, 1
        call AyPut
        ld e, %00111110         ; tone A only
        ld a, 7
        call AyPut
        ld e, 12
        ld a, 8
        call AyPut
        halt
        ld e, 0
        ld a, 8
        jp AyPut

; ---------------------------------------------------------------- data
HiMark:         db $FF          ; the table's entry to pick out
HiSlot:         db 0            ; initials: the letter being picked
Letter:         db 0
EntryWas:       db 0
EntryRep:       db 0
EntryTime:      dw 0
BoxPos:         db 0, 0
MapTmp:         db 0
Alphabet:       db "ABCDEFGHIJKLMNOPQRSTUVWXYZ.!- "
ALPHA_LEN       EQU $ - Alphabet

TxtTitleKeys:   db "ENTER: OPTIONS   H: PAUSE", 0
TxtBest:        db "BEST DRIVERS", 0
TxtPlaces:      db "1ST", 0, "2ND", 0, "3RD", 0, "4TH", 0, "5TH", 0
TxtNewHi:       db "HIGH SCORE!", 0
TxtYourScore:   db "YOUR SCORE", 0
TxtInitials:    db "ENTER YOUR INITIALS", 0
TxtPick:        db "STEER: CHOOSE A LETTER", 0
TxtTake:        db "ACCELERATE: TAKE IT", 0
TxtRoute:       db "YOUR ROUTE", 0
TxtTotal:       db "TOTAL", 0
TxtOptions:     db "OPTIONS", 0
TxtOptMenu:     db "1  KEYBOARD  Q A O P SPACE", 0
                db "2  SINCLAIR JOYSTICK", 0
                db "3  CURSOR JOYSTICK", 0
                db "4  CHOOSE YOUR OWN KEYS", 0
                db "5  SOUND:", 0
                db "   KEMPSTON WORKS ANY TIME", 0
                db "   H PAUSES THE GAME", 0
                db " ", 0
                db "   ENTER: BACK", 0, 0
TxtCtrls:       db "ACCELERATE", 0
                db "BRAKE", 0
                db "STEER LEFT", 0
                db "STEER RIGHT", 0
                db "CHANGE GEAR", 0, 0
TxtBlank5:      db "     ", 0
SoundTxts:      dw TxtSnd0, TxtSnd1
TxtSnd0:        db "MUSIC AND EFFECTS", 0
TxtSnd1:        db "ENGINE           ", 0
TxtCaps:        db "CAPS", 0
TxtSym:         db "SYM", 0
TxtEnter:       db "ENTER", 0
TxtSpace:       db "SPACE", 0
TxtCongrats:    db "CONGRATULATIONS!", 0
TxtFinal:       db "SCORE", 0
TxtBonus:       db "TIME BONUS", 0
TxtTimes:       db " X 1000", 0
TxtPress:       db "PRESS ANY KEY", 0

        INCLUDE "screens_data.asm"
        INCLUDE "music_title.asm"   ; TitleTune (tools/make_music.py)
