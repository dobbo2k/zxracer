; ---------------------------------------------------------------------------
; Einstein: the front end (src/frontend.asm: the title, high scores, options,
; goal and game-over screens)
;
; The front end draws into the Spectrum's screen A ($4000, plain RAM here)
; just as on the Spectrum, and shows it (ShowA, ShowPic). Here that is a
; full-screen bitmap: each third's 256 patterns are its 256 cells, in
; order, each cell its 8 bitmap bytes and its attribute's ink over paper.
; Screen B's memory ($C000, the game's mirror source, which a display reset
; makes afresh) holds what VRAM shows; each frame (EinHalt: the front end's
; frame waits) a share of the cells is compared, and those that differ are
; sent. Meanwhile the interrupt counts frames on the CTC alone (20 ms), so
; the VDP is the main code's.
;
; Screen A's memory also holds the resident stage overlay: once the front
; end has drawn there, src/stage.asm StageOv reads it back from the disc.
; ---------------------------------------------------------------------------
FRONT_SHARE     EQU 96              ; cells compared a frame (all 768 in 8 frames)

; ScreensEnter: the front end will draw into screen A
EinScreensEnter:
        ld a, 1
        ld (EOvClobbered), a
        ret

; Show screen A (ShowA, ShowPic): every cell sent, with the display off
EinFrontOn:
        call EinFrontInit
        ld b, 0
        jr EinFrontRows

EinFrontInit:
        di
        ld a, 1
        ld (EFrontOn), a
        ld (EOvClobbered), a
        ld a, $40               ; cells from screen A
        ld (EinSendCell.scr + 1), a
        ld a, $58
        ld (EinSendCell.att + 1), a
        call VdpInit            ; (the display off; MOS may have been at it)
        ld hl, $7FFF            ; (any speed)
        ld (EBudget), hl
        ld de, VRAM_NAMES       ; the names: each third's patterns in order
        call VdpAddr
        ld b, 3
.t:     xor a
.n:     out (EIN_VDP_DATA), a
        inc a
        jr nz, .n
        djnz .t
        ld de, VRAM_SPRATTR     ; no sprites
        ld bc, 1
        ld l, $D0
        call VdpFill
        ret

EinFrontRows:                   ; send B..23, then start tracking screen A
.r:     ld c, 0
.c:     push bc
        call EinFrontCell
        pop bc
        inc c
        ld a, c
        cp 32
        jr nz, .c
        inc b
        ld a, b
        cp 24
        jr nz, .r
        ld hl, $4000            ; what VRAM shows
        ld de, $C000
        ld bc, 6912
        ldir
        xor a
        ld (EFrontCur), a
        ld (EFrontCur + 1), a
        call VdpOn
        ei
        ret

; Picture record count A, first record HL. While the display is off the
; pattern and ink streams share a 6K unpack buffer. The final stream is the
; editable footer; matching A/B shadows keep later text updates incremental.
EinPicture:
        ld b, a
        ld c, 0
        srl b
        rr c
        ld de, $C000
        call EinRead
        call EinFrontInit
        ld hl, $C000
        ld a, (hl)
        ld (.rows + 1), a
        inc hl
        ld de, VRAM_PAT
        call .plane
        ld de, VRAM_COL
        call .plane
        ld de, $4000
        call UnLZ
.rows:  ld b, 0
        jp EinFrontRows
.plane: push de
        ld de, $4000
        call UnLZ
        pop de
        push hl
        ld hl, $4000
        ld a, (.rows + 1)
.send:  push af
        push de
        ld b, 0
        call VdpWrite
        pop de
        inc d
        pop af
        dec a
        jr nz, .send
        pop hl
        ret

; B = row, C = column: screen A's cell into its pattern (third (B & $18),
; pattern (B & 7) * 32 + C: VRAM address / 8 = B * 32 + C)
EinFrontCell:
        ld a, b
        rrca
        rrca
        rrca
        ld l, a
        and $E0
        or c
        ld h, l
        ld l, a
        ld a, h
        and 3
        ld h, a
        jp EinSendCell

; A share of the cells: those screen A has changed are sent (paced: the
; display is on)
EinFrontSync:
        ld hl, 0
        ld (EBudget), hl        ; (no budget: every write paced)
        ld hl, (EFrontCur)
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
        ld (EFrontCur), hl
        ret
; B = row, C = column: if screen A's cell differs from screen B's copy,
; copy it and send it
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
        set 7, h                ; (screen B: + $8000)
        cp (hl)
        res 7, h
        jr nz, .diff
        inc h
        dec d
        jr nz, .ln
        ld a, b                 ; and its attribute
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
        ld a, (hl)
        set 7, h
        cp (hl)
        jr nz, .diffA
        pop hl
        ret
.diffA: ld (hl), a              ; (the copy: the attribute; the lines below)
.diff:  pop hl
        ld d, 8
.cp:    ld a, (hl)
        set 7, h
        ld (hl), a
        res 7, h
        inc h
        dec d
        jr nz, .cp
        ld a, b
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
        ld a, (hl)
        set 7, h
        ld (hl), a
        jp EinFrontCell

; The front end's frame wait (FRAME_WAIT): its share of cells, then the
; next TV frame. Everything kept.
EinHalt:
        push af
        push bc
        push de
        push hl
        push ix
        ld a, (EFrontOn)
        or a
        call nz, EinFrontSync
        ld hl, FrameCount
        ld a, (hl)
.w:     halt
        cp (hl)
        jr z, .w
        pop ix
        pop hl
        pop de
        pop bc
        pop af
        ret

; Back to the game's display (EinResetDisplay)
EinFrontOff:
        xor a
        ld (EFrontOn), a
        ld a, $C0               ; cells from screen B again
        ld (EinSendCell.scr + 1), a
        ld a, $D8
        ld (EinSendCell.att + 1), a
        ret

EFrontOn:       db 0            ; screen A on show
EOvClobbered:   db 0            ; the stage overlay drawn over
EFrontCur:      dw 0            ; the next cell to compare
ETick:          db 0            ; (the interrupt's 1 ms ticks, front end)

; The car's pose's cells' pixels (src/einstein/car.asm EinCarPrep; their
; colours as drawn, ECarSourceInks, are in screen A: src/einstein/platform.asm)
ECarPix:        ds 4 * CAR_W * 8
