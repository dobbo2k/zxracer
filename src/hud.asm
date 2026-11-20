; ---------------------------------------------------------------------------
; HUD in the sky rows: SCORE (left), big TIME (centre), SPEED and GEAR (right), and a
; message line. Static labels are printed into both buffers once; numbers
; are redrawn into the back buffer every frame; messages only when the
; message this buffer shows changes.
; ---------------------------------------------------------------------------
MSG_ROW         EQU 5
MSG_COL         EQU 6
MSG_LEN         EQU 20

; A = 0 (buffer A) or $80 (buffer B): print the static labels
InitHud:
        ld (HudOr), a
        ; red attribute cells for the big timer (rows 1-2, columns 14-17)
        or $58
        ld h, a
        ld l, 32 + 14
        ld a, (PalTime)
        ld c, a
        ld b, 2
.ta:    ld (hl), c
        inc l
        ld (hl), c
        inc l
        ld (hl), c
        inc l
        ld (hl), c
        ld a, l
        add a, 32 - 3
        ld l, a
        djnz .ta
        ld bc, $0001
        ld de, TxtScore
        call PrintAt
        ld bc, $000E
        ld de, TxtTime
        call PrintAt
        ld bc, $0019
        ld de, TxtSpeed
        call PrintAt
        ld bc, $011D
        ld de, TxtKmh
        call PrintAt
        ld bc, $0201            ; STAGE n
        ld de, TxtStage
        call PrintAt
        ld a, (StageRow)
        jp PrintDigit

DrawHud:
        ld a, (BufHiOr)
        ld (HudOr), a
        ld ix, (HudCache)       ; what this buffer shows: score (4), time, speed
        ; ---- score: 7 digits; redraw only the BCD bytes that changed
        ld a, (Score + 3)
        cp (ix + 3)
        jr z, .s3
        ld (ix + 3), a
        ld bc, $0101
        call CellAddr
        ld a, (Score + 3)
        call PrintLowNib
.s3:    ld a, (Score + 2)
        cp (ix + 2)
        jr z, .s2
        ld (ix + 2), a
        ld bc, $0102
        call CellAddr
        ld a, (Score + 2)
        call PrintBcd
.s2:    ld a, (Score + 1)
        cp (ix + 1)
        jr z, .s1
        ld (ix + 1), a
        ld bc, $0104
        call CellAddr
        ld a, (Score + 1)
        call PrintBcd
.s1:    ld a, (Score)
        cp (ix + 0)
        jr z, .s0
        ld (ix + 0), a
        ld bc, $0106
        call CellAddr
        ld a, (Score)
        call PrintBcd
.s0:    ; ---- time: two big digits
        ld a, (Time)
        cp (ix + 4)
        jr z, .t0
        ld (ix + 4), a
        ld bc, $010E
        call CellAddr
        ld a, (Time)
        rrca
        rrca
        rrca
        rrca
        and $0F
        call PrintBig
        inc l
        inc l
        ld a, (Time)
        and $0F
        call PrintBig
.t0:    ; ---- speed: Speed * 14 km/h, 3 digits
        ld a, (Speed)
        cp (ix + 5)
        jr z, .v0
        ld (ix + 5), a
        ld l, a
        ld h, 0
        add hl, hl
        ld d, h
        ld e, l                 ; 2x
        add hl, hl
        add hl, hl
        add hl, hl              ; 16x
        or a
        sbc hl, de              ; 14x
        ex de, hl
        ld bc, $011A
        call CellAddr
        ld bc, 100
        call .digit
        ld bc, 10
        call .digit
        ld a, e
        call PrintDigit
.v0:    ; ---- gear: LOW / HIGH
        ld a, (Gear)
        cp (ix + 6)
        jr z, .g0
        ld (ix + 6), a
        ld de, TxtLow
        or a
        jr z, .gl
        ld de, TxtHigh
.gl:    ld bc, $021A
        call PrintAt
.g0:
        ; ---- message line, only if it changed for this buffer
        ld hl, (MsgLast)
        ld de, (Message)
        ld a, (hl)
        cp e
        jr nz, .msg
        inc hl
        ld a, (hl)
        cp d
        ret z
        dec hl
.msg:   ld (hl), e
        inc hl
        ld (hl), d
        ld bc, MSG_ROW * 256 + MSG_COL
        jp PrintAt
; DE = value: print the digit for BC (100 or 10), DE -= digit * BC
.digit: ld a, -1
        ex de, hl
.dl:    inc a
        or a
        sbc hl, bc
        jr nc, .dl
        add hl, bc
        ex de, hl
        jp PrintDigit

; B = row, C = column -> HL = cell address in the buffer HudOr selects
CellAddr:
        ld a, b
        add a, a
        add a, a
        add a, a                ; y = row * 8
        push de
        ld e, a
        ld d, high ScrLo
        ld a, (de)
        add a, c
        ld l, a
        inc d
        ld a, (de)
        ld e, a
        ld a, (HudOr)
        or e
        ld h, a
        pop de
        ret

; B = row, C = column, DE = 0-terminated string
PrintAt:
        call CellAddr
.ch:    ld a, (de)
        or a
        ret z
        push de
        call PrintChar
        pop de
        inc de
        inc l
        jr .ch

PrintBcd:                       ; A = two BCD digits
        push af
        rrca
        rrca
        rrca
        rrca
        call PrintLowNib
        pop af
PrintLowNib:
        and $0F
PrintDigit:
        add a, "0"
        call PrintChar
        inc l
        ret

; A = ASCII 32-90, HL = cell address (preserved)
PrintChar:
        push de
        push bc
        sub 32
        ld e, a
        ld d, 0
        ex de, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ld bc, Font
        add hl, bc
        ex de, hl
        push hl
        ld b, 8
.l:     ld a, (de)
        ld (hl), a
        inc de
        inc h
        djnz .l
        pop hl
        pop bc
        pop de
        ret

; A = digit, HL = top-left cell (preserved): 16x16 digit over two cell rows
PrintBig:
        push de
        push bc
        ld e, a
        ld d, 0
        ex de, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ld bc, BigDigits
        add hl, bc
        ex de, hl
        push hl
        call .half
        pop hl
        push hl
        ld a, l
        add a, 32
        ld l, a
        call .half
        pop hl
        pop bc
        pop de
        ret
.half:  ld b, 8
.bl:    ld a, (de)
        ld (hl), a
        inc de
        inc l
        ld a, (de)
        ld (hl), a
        inc de
        dec l
        inc h
        djnz .bl
        ret

TxtScore:       db "SCORE", 0
TxtTime:        db "TIME", 0
TxtSpeed:       db "SPEED", 0
TxtKmh:         db "KM", 0
TxtLow:         db "LOW ", 0
TxtHigh:        db "HIGH", 0
TxtStage:       db "STAGE ", 0
MsgGoal:        db "  GOAL! WELL DONE!  ", 0
MsgFork:        db " << CHOOSE A ROAD >>", 0
MsgNone:        db "                    ", 0
MsgAttract:     db "  PRESS ANY KEY !   ", 0
MsgOver:        db "     GAME  OVER     ", 0

