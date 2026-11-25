; ---------------------------------------------------------------------------
; CPC: the front end (src/frontend.asm: the title, high scores, options,
; goal and game-over screens; docs/port_cpc.md 5.10)
;
; The front end draws into the Spectrum's screen A ($4000) just as on the
; Spectrum. Here that is base 1 (screen A hidden, RAM configuration C1) as
; a buffer in the Spectrum's layout, and base 3 (screen B) is shown: each of
; its cells converted from screen A's (src/cpc/cells.asm CpcCell), the pens
; the Spectrum's 15 colours meanwhile. Bank 7's $C000 (the game's shadow,
; which a display reset makes afresh) holds a copy of what base 3 shows;
; each frame (CpcHalt: the front end's frame waits) a share of the cells is
; compared, and those that differ are copied and converted (C3: base 3 at
; $4000 and bank 7 at $C000). Until the CPC's own pictures (phase A) the
; title and the goal postcards are the Spectrum's, so shown.
; ---------------------------------------------------------------------------
FRONT_SHARE     EQU 96              ; cells compared a frame (all 768 in 8 frames)

CFrontOn:       db 0            ; the front end's screen on show
CFrontCur:      dw 0            ; the next cell to compare

; ScreensEnter: the front end will draw into screen A (base 1), screen B
; (base 3) still showing the last game frame
GfxScreensEnter:
        xor a
        ld (CpcHidden), a
        jp CpcSelect            ; (C1)

; Show screen A (ShowA, ShowPic): every cell converted into base 3, the
; pens black meanwhile, then the Spectrum's colours
GfxFrontOn:
        call CpcBlack
        ld a, 1
        ld (CFrontOn), a
        ld bc, CRTC_SELECT + 12 ; base 3 shown
        out (c), c
        ld bc, CRTC_WRITE + CRTC_B
        out (c), c
        xor a
        ld (CpcHidden), a
        ld hl, $4000            ; the copy: all of screen A
        ld de, $C000
        ld bc, 6912
        ldir
        ld bc, GA_PORT | RAM_B  ; every cell into base 3
        out (c), c
        ld b, 0
.r:     ld c, 0
.c:     push bc
        call CpcCell
        pop bc
        inc c
        bit 5, c
        jr z, .c
        inc b
        ld a, b
        cp 24
        jr c, .r
        call CpcSelect          ; (C1 again)
        ld hl, 0
        ld (CFrontCur), hl
; The pens the Spectrum's colours (pen k: colour k, BRIGHT x 8 + colour)
CpcSpecPens:
        ld hl, SpecHw
        ld de, CSpecPB
        ld bc, GA_PORT
        xor a
.p:     out (c), a              ; the pen
        push af
        ld a, (hl)
        or GA_COLOUR
        out (c), a
        pop af
        push hl
        ld hl, PenByte          ; and the colour's pen: itself
        add a, l
        ld l, a
        jr nc, .h
        inc h
.h:     ld a, (hl)
        ld (de), a
        pop hl
        ld a, e
        sub low CSpecPB
        inc a
        inc hl
        inc de
        cp 16
        jr c, .p
        ld a, 16                ; the border black
        out (c), a
        ld a, GA_COLOUR | HW_BLACK
        out (c), a
        ret

; (From CpcHalt, the front end's frame wait) a share of the cells: those
; screen A has changed copied and converted
CFrontSync:
        ld hl, (CFrontCur)
        ld b, FRONT_SHARE
.cell:  push bc
        push hl
        ld a, h                 ; HL = cell 0-767 -> B = row, C = column
        add a, a
        add a, a
        add a, a
        ld b, a
        ld a, l
        rlca
        rlca
        rlca
        and 7
        or b
        ld b, a
        ld a, l
        and 31
        ld c, a
        call .compare
        pop hl
        pop bc
        inc hl
        ld a, h
        cp 3
        jr c, .w
        ld hl, 0
.w:     djnz .cell
        ld (CFrontCur), hl
        ret
; B = row, C = column: if screen A's cell differs from the copy, copied
; and converted
.compare:
        ld a, b                 ; HL = screen A's first line of the cell
        and $18
        or $40
        ld h, a
        ld a, b
        and 7
        rrca
        rrca
        rrca
        or c
        ld l, a
        push hl
        ld d, 8
.ln:    ld a, (hl)
        set 7, h                ; (the copy: + $8000)
        cp (hl)
        res 7, h
        jr nz, .diff
        inc h
        dec d
        jr nz, .ln
        call .attr
        ld a, (hl)
        set 7, h
        cp (hl)
        pop de
        ret z
        jr .copyA
.diff:  pop hl
        ld d, 8
.cp:    ld a, (hl)
        set 7, h
        ld (hl), a
        res 7, h
        inc h
        dec d
        jr nz, .cp
        call .attr
.copyA: res 7, h
        ld a, (hl)
        set 7, h
        ld (hl), a
        push bc                 ; converted into base 3
        ld bc, GA_PORT | RAM_B
        out (c), c
        pop bc
        call CpcCell
        jp CpcSelect
; -> HL = screen A's attribute of cell B, C
.attr:  ld a, b
        rrca
        rrca
        rrca
        ld l, a
        and $E0
        or c
        ld e, a
        ld a, l
        and 3
        or $58
        ld h, a
        ld l, e
        ret

; A picture (ShowPic): A = its sectors, HL = its first (on the disc): the
; Spectrum's screen into screen A, then shown
GfxPicture:
        ld b, a
        ld c, 0
        sla b                   ; (x 512)
        ld de, $4000
        call CpcLoad
        call CpcMotorOff
        jp GfxFrontOn

; (CpcResetDisplay) the game's display again
CpcFrontOff:
        xor a
        ld (CFrontOn), a
        ret
