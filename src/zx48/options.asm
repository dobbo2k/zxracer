TitlePrompt:
        ld bc, $1511
        call CellAddr
        ld de, BestScore + 3
        ld a, (de)
        call PrintLowNib
        dec de
        ld b, 3
.score: ld a, (de)
        call PrintBcd
        dec de
        djnz .score
        ld bc, $1703
        ld de, TitleKeys
        call PrintAt
        ld bc, $1605
        ld de, TitlePress
        call PrintAt
        ld bc, $1507
        ld de, TitleScore
        call PrintAt
        ld hl, TitlePanel
        ld de, RACE_ATTRS + 21 * 32
        ld c, 3
.panel: ld a, (hl)
        inc hl
        ld b, 32
.attr:  ld (de), a
        inc de
        djnz .attr
        dec c
        jr nz, .panel
        ld hl, TitleTune48
        ld (TitleNext), hl
        xor a
        ld (TitleTicks), a
        call ReleaseKeys
        ld hl, 400
.wait:  push hl
        call TitleTick
        ld a, (FrameCount)
        and 16
        ld a, $46
        jr z, .blink
        ld a, $40
.blink: ld hl, RACE_ATTRS + 22 * 32
        call MenuAttrRow
        call ReadInput
        and (1 << IN_UP) | (1 << IN_FIRE) | (1 << IN_LEFT) | (1 << IN_RIGHT)
        pop hl
        jr nz, .start
        ld a, $BF
        KEY_IN
        rra
        jr nc, .opts
        dec hl
        ld a, h
        or l
        jr nz, .wait
        jr .leave
.start: ld a, 1
.leave: push af
        call BlankAttrs
        ld hl, Sprites_Shared
        ld de, SharedSprites
        call ExpandScenery
        pop af
        ret
.opts:  call Options48
        jp TitleScreen

Options48:
        ld a, $07
        call ClearFront
        call MenuDecor
        ld bc, $010C
        ld de, OptionsHeading
        call TallAt
        ld de, OptionsMenu
        ld bc, $0504
.line:  push bc
        call PrintAt
        inc de
        pop bc
        inc b
        ld a, (de)
        or a
        jr nz, .line
.redraw:
        call ShowBindings
        ld hl, LevelNames
        ld a, (Difficulty)
        ld bc, $0A0E
        call .item
        ld hl, SoundNames
        ld a, (SoundMode)
        ld bc, $090E
        call .item
        call ReleaseKeys
.read:  FRAME_WAIT
        call ScanKeys
        jr nc, .read
        ld a, e
        cp 30
        jp z, ReleaseKeys
        cp 24
        jr z, .level
        cp 19
        jr z, .sound
        cp 18
        jr z, .custom
        sub 15
        cp 3
        jr nc, .read
        ld e, a
        add a, a
        add a, a
        add a, e
        add a, a
        ld e, a
        ld d, 0
        ld hl, Presets
        add hl, de
        ld de, KeyMap
        ld bc, 10
        ldir
        jr .redraw
.level: ld a, (Difficulty)
        inc a
        cp 3
        jr c, .store
        xor a
.store: ld (Difficulty), a
        jr .redraw
.sound: ld a, (SoundMode)
        xor 1
        ld (SoundMode), a
        jr .redraw
.custom:
        call DefineKeys
        jp Options48
.item:  add a, a
        ld e, a
        ld d, 0
        add hl, de
        ld e, (hl)
        inc hl
        ld d, (hl)
        jp PrintAt

ShowBindings:
        ld bc, $0F06
        ld de, ControlNames
        ld ix, ControlOrder
.row:   push bc
        call PrintAt
        inc de
        push de
        ld e, (ix + 0)
        call KeyAddress
        ld d, (hl)
        inc hl
        ld e, (hl)
        ld a, $FE
        ld c, 0
.half:  cp d
        jr z, .bit
        rlca
        inc c
        inc c
        inc c
        inc c
        inc c
        jr .half
.bit:   rr e
        jr c, .glyph
        inc c
        jr .bit
.glyph: ld b, 0
        ld hl, BindingGlyphs
        add hl, bc
        pop de
        pop bc
        push bc
        push de
        ld a, (hl)
        push af
        ld c, 20
        ld de, BindingBlank
        push bc
        call PrintAt
        pop bc
        pop af
        cp 4
        jr nc, .char
        ld hl, BindingWords - 2
        call Options48.item
        jr .next
.char:  push af
        call CellAddr
        pop af
        call PrintChar
.next:  inc ix
        pop de
        pop bc
        inc b
        ld a, (de)
        or a
        jr nz, .row
        ret

; Scan the eight half-rows in the same order as the 128K options.
; Carry set: D = port high byte, C = one-bit mask, E = key number.
ScanKeys:
        ld d, $FE
        ld e, 0
.row:   ld a, d
        KEY_IN
        cpl
        and $1F
        jr nz, .found
        ld a, e
        add a, 5
        ld e, a
        rlc d
        jr c, .row
        ret
.found: ld c, 1
.bit:   rra
        ret c
        sla c
        inc e
        jr .bit

ReleaseKeys:
        FRAME_WAIT
        call ScanKeys
        jr c, ReleaseKeys
        ret

; Redefine the five controls in their on-screen order. Reject H, ENTER
; and collisions with any binding already accepted during this pass.
DefineKeys:
        ld a, $07
        call ClearFront
        ld ix, ControlOrder
        ld de, ControlNames
        ld bc, $0605
.control:
        push bc
        call PrintAt
        inc de
        push de
        call ReleaseKeys
.get:   FRAME_WAIT
        call ScanKeys
        jr nc, .get
        ld a, e
        cp 30
        jr z, .get
        cp 34
        jr z, .get
        ld hl, ControlOrder
.check: ld a, l
        cp ixl
        jr z, .set
        ld e, (hl)
        inc hl
        push hl
        call KeyAddress
        ld a, (hl)
        inc hl
        cp d
        jr nz, .next
        ld a, (hl)
        cp c
        jr z, .used
.next:  pop hl
        jr .check
.used:  pop hl
        call ReleaseKeys
        jr .get
.set:   ld e, (ix + 0)
        call KeyAddress
        ld (hl), d
        inc hl
        ld (hl), c
        inc ix
        pop de
        pop bc
        inc b
        ld a, (de)
        or a
        jr nz, .control
        jp ReleaseKeys

KeyAddress:
        ld a, low KeyMap
        add a, e
        ld l, a
        adc a, high KeyMap
        sub l
        ld h, a
        ret

TitlePanel:    db $45, $46, $07
TitleKeys:     db "ENTER: OPTIONS   H: PAUSE", 0
TitlePress:    db "PRESS ANY KEY TO START", 0
TitleScore:    db "HI-SCORE", 0
OptionsHeading: db "OPTIONS", 0
OptionsMenu:   db "1  KEYBOARD  Q A O P SPACE", 0
               db "2  SINCLAIR JOYSTICK", 0
               db "3  CURSOR JOYSTICK", 0
               db "4  CHOOSE YOUR OWN KEYS", 0
               db "5  SOUND:", 0
               db "6  LEVEL:", 0
               db "   KEMPSTON WORKS ANY TIME", 0
               db "   H PAUSES THE GAME", 0
               db "   ENTER: BACK", 0, 0
ControlOrder:  db 6, 4, 2, 0, 8
ControlNames:  db "ACCELERATE", 0, "BRAKE", 0, "STEER LEFT", 0
               db "STEER RIGHT", 0, "CHANGE GEAR", 0, 0
BindingGlyphs: db 1, "ZXCVASDFGQWERT1234509876POIUY LKJH", 3, 2, "MNB"
BindingBlank:  db "     ", 0
BindingWords:  dw BindingCaps, BindingSym, BindingSpace
BindingCaps:   db "CAPS", 0
BindingSym:    db "SYM", 0
BindingSpace:  db "SPACE", 0
SoundNames:    dw .full, .engine
.full:         db "MUSIC AND EFFECTS", 0
.engine:       db "ENGINE           ", 0
LevelNames:    dw .easy, .normal, .hard
.easy:         db "EASY  ", 0
.normal:       db "NORMAL", 0
.hard:         db "HARD  ", 0
Presets:       db $DF,1,$DF,2,$FD,1,$FB,1,$7F,1
               db $EF,8,$EF,16,$EF,4,$EF,2,$EF,1
               db $EF,4,$F7,16,$EF,16,$EF,8,$EF,1

TitleTick:
        ld a, (SoundMode)
        or a
        jr nz, .mute
        ld hl, TitleTicks
        dec (hl)
        jr z, .next
        bit 7, (hl)
        jr z, .play
.next:  ld hl, (TitleNext)
        ld a, (hl)
        or a
        jr nz, .event
        ld hl, TitleTune48
        ld a, (hl)
.event: ld (TitleTicks), a
        inc hl
        ld a, (hl)
        inc hl
        ld (TitleNext), hl
        ld (TitlePitch), a
.play:  ld a, (TitlePitch)
        ld c, a
        ld a, (FrameCount)
        inc a
        ld b, a
        jp ToneUntil
.mute:  FRAME_WAIT
        ret

TitleNext:  dw 0
TitleTicks: db 0
TitlePitch: db 0
SoundMode: db 0

        INCLUDE "../talltext.asm"
