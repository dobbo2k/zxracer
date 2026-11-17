; ---------------------------------------------------------------------------
; HUD in the sky rows: SCORE (left), big TIME (centre), SPEED (right), and a
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
        ld b, 2
.ta:    ld (hl), ATTR_TIME
        inc l
        ld (hl), ATTR_TIME
        inc l
        ld (hl), ATTR_TIME
        inc l
        ld (hl), ATTR_TIME
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
        jp PrintAt

DrawHud:
        ld a, (BufHiOr)
        ld (HudOr), a
        ; ---- score: 7 digits from the 8-digit BCD score
        ld bc, $0101
        call CellAddr
        ld de, Score + 3
        ld a, (de)
        call PrintLowNib
        ld b, 3
.sc:    dec de
        ld a, (de)
        push bc
        call PrintBcd
        pop bc
        djnz .sc
        ; ---- time: two big digits
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
        ; ---- speed: Speed * 14 km/h, 3 digits
        ld a, (Speed)
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
MsgNone:        db "                    ", 0
MsgAttract:     db "  PRESS ANY KEY !   ", 0
MsgOver:        db "     GAME  OVER     ", 0
MsgExtend:      db "   EXTENDED PLAY!   ", 0
