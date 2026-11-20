; ---------------------------------------------------------------------------
; The crew. After a crash, while the car spins, close-ups of the two of them
; appear either side of the message line (tools/make_crew.py): she tells
; him off, he answers back sheepishly. Not time-critical (bank 5).
; ---------------------------------------------------------------------------
CREW_ROW        EQU 3               ; close-ups: rows 3-8, columns 0-5 and 26-31
CREW_HIM_COL    EQU 26
CREW_REPLY      EQU 70              ; she speaks until the crash timer drops below this

; At a crash: pick what they say
CrewPick:
        ld de, CrewLines
        ld c, 7
; DE = a table of line pairs, C = their number - 1 (a power of two - 1)
CrewPickDE:
        push de
        call Random
        and c
        add a, a
        add a, a
        ld l, a
        ld h, 0
        pop de
        add hl, de
        ld e, (hl)
        inc hl
        ld d, (hl)
        inc hl
        ld (CrewHerLine), de
        ld e, (hl)
        inc hl
        ld d, (hl)
        ld (CrewHisLine), de
        ret

; A = crash timer (each update of a crash): the line being said
CrewSay:
        ld hl, MsgNone
        or a
        jr z, .set
        cp CREW_REPLY
        ld hl, (CrewHisLine)
        jr c, .set
        ld hl, (CrewHerLine)
.set:   ld (Message), hl
        ret

; Each frame, before the sprites: the close-ups on the back buffer during a
; crash, gone again afterwards.
DrawCrew:
        ld hl, CrewShownA
        ld a, (BufHiOr)
        or a
        jr z, .buf
        inc hl
.buf:   ld a, (CrashTimer)
        or a
        jr z, .off
        ld a, (hl)
        or a
        ret nz                  ; already on this buffer
        ld (hl), 1
        ld hl, CrewHer
        ld c, 0
        call .draw
        ld hl, CrewHim
        ld c, CREW_HIM_COL
        jr .draw
.off:   ld a, (hl)
        or a
        ret z
        ld (hl), 0
        ld hl, 0                ; HL = 0: clear back to sky
        ld c, 0
        call .draw
        ld hl, 0
        ld c, CREW_HIM_COL
; HL = picture (48 lines of 6 bytes, 36 attributes) or 0 to clear back to
; sky, C = column
.draw:  ld b, CREW_ROW * 8
.ln:    push bc
        ld e, b
        ld d, high ScrLo
        ld a, (de)
        add a, c
        ld c, a
        inc d
        ld a, (de)
        ld e, a
        ld a, (BufHiOr)
        or e
        ld d, a
        ld e, c                 ; DE = the line's bytes on screen
        ld a, h
        or l
        jr z, .zero
        ld bc, 6
        ldir
        jr .nextLn
.zero:  ld b, 6
.z:     ld (de), a
        inc e
        djnz .z
.nextLn:
        pop bc
        inc b
        ld a, b
        cp CREW_ROW * 8 + 48
        jr nz, .ln
        ; attributes (rows 3-8 cross a 256-byte boundary)
        push hl
        ld a, (AttrHi)
        ld h, a
        ld l, CREW_ROW * 32
        ld b, 0
        add hl, bc
        ex de, hl
        pop hl
        ld b, 6
.ar:    push bc
        ld a, h
        or l
        jr z, .sky
        ld bc, 6
        ldir
        jr .nextAr
.sky:   ld a, (PalSky)
        ld b, 6
.s:     ld (de), a
        inc de
        djnz .s
.nextAr:
        ex de, hl
        ld bc, 32 - 6
        add hl, bc
        ex de, hl
        pop bc
        djnz .ar
        ret

        INCLUDE "crew_data.asm"
