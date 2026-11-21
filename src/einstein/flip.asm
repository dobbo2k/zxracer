; ---------------------------------------------------------------------------
; Einstein: frames into VRAM
;
; The Spectrum draws into a hidden screen and flips. Here the frame is built
; in RAM (EinDraw: NameBuf, SlotShadow) and RequestFlip sends what changed:
; the changed slots' patterns and colours, then each row of names that
; differs from what VRAM holds (NameVram). All writes are paced (32 T), so
; they are safe whenever they come.
;
; Milestone 1: one name table, written as the picture shows (a row can
; change mid-frame). Two name tables, flipped in the vertical blank, are the
; next step (docs/port_einstein.md).
; ---------------------------------------------------------------------------

; The Spectrum's per-buffer pointers, for the parts of its drawing code
; that still run: all at buffer B, whose screen ($C000) is not shown here.
SelectBackBuffer:
        ld a, $80
        ld (BufHiOr), a
        ld (RunCommand.bufOr + 1), a
        ld hl, CmdListB
        ld (CmdList), hl
        ld hl, PanoLastB
        ld (PanoLast), hl
        ld hl, MsgLastB
        ld (MsgLast), hl
        ld hl, HudCacheB
        ld (HudCache), hl
        ld hl, CarShownB
        ld (CarShown), hl
        ld a, high StateB1
        ld (StatePage), a
        ld a, $D8
        ld (AttrHi), a
        ret

GameFrames:     dw 0

; Until the frame asked for has gone into VRAM (before touching what it is
; sent from: NameBuf, the slots, screen B)
WaitFlip:
.w:     ld a, (FlipPending)
        or a
        ret z
        halt
        jr .w

; This frame is ready: the interrupt sends it at the start of a vertical
; blank, at least MIN_FRAMES after the last (the Spectrum's steady 16.7
; fps). The next frame's logic runs meanwhile.
RequestFlip:
        ld hl, (GameFrames)     ; (for the tests: game frames drawn)
        inc hl
        ld (GameFrames), hl
        ld a, 1
        ld (FlipPending), a
        ret

; From the interrupt, at most 1 ms into a vertical blank: VRAM at full
; speed, the picture not being drawn. Row by row, the row's changed slots
; and then its names, so a row never shows new names over old patterns.
EinUpload:
        ld hl, BLANK_UNITS
        ld (EBudget), hl
        ld hl, DirtyList
        ld (EDirtyPtr), hl
        ld a, (DirtyN)
        ld (EDirtyLeft), a
        call EinPanoSend        ; (the panorama's cells under silhouettes)
        ld c, MIRROR_ROWS       ; (the panorama's and the road's rows)
.row:   push bc
.slot:  ld a, (EDirtyLeft)      ; this row's changed slots
        or a
        jr z, .names
        ld hl, (EDirtyPtr)
        inc hl
        ld a, (hl)              ; what changed, the row above bit 2
        rrca
        rrca
        and $0F
        add a, ROAD_ROW0
        cp c
        jr nz, .names
        dec hl
        ld a, (hl)
        inc hl
        ld e, (hl)
        inc hl
        ld (EDirtyPtr), hl
        ld hl, EDirtyLeft
        dec (hl)
        push bc
        ld c, e
        call EinSendSlot
        pop bc
        jr .slot
.names: ld a, c                 ; then its names, if it was drawn again
        add a, low ERowDrawn
        ld l, a
        ld a, high ERowDrawn
        adc a, 0
        ld h, a
        ld a, (hl)
        or a
        jr z, .next
        ld (hl), 0
        ld l, c                 ; NameBuf + row * 32 -> VRAM_NAMES + row * 32
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        push hl
        ld de, VRAM_NAMES
        add hl, de
        ex de, hl
        pop hl
        ld bc, NameBuf
        add hl, bc
        ld b, 32
        call EinWrite
.next:  pop bc
        inc c
        ld a, c
        cp 24
        jr nz, .row
        call EinCarSync         ; ---- the car's cells
        jp EinMirror            ; ---- the sky's cells written

; The writes' budget in the vertical blank (about 30,800 T): units of a
; byte at OTIR's 21 T, each write costing ITEM_UNITS more for its address
; and calls. Past it, writes are paced (32 T) and safe in the picture.
BLANK_UNITS     EQU 750
ITEM_UNITS      EQU 40

; B = bytes about to be written: spend them (DE, HL, B kept). Carry: the
; budget is gone, write paced.
EinSpend:
        push hl
        push de
        ld hl, (EBudget)
        ld e, b
        ld d, 0
        or a
        sbc hl, de
        jr c, .out
        ld de, ITEM_UNITS
        sbc hl, de
        jr c, .out
        ld (EBudget), hl
        pop de
        pop hl
        ret
.out:   ld hl, 0
        ld (EBudget), hl
        pop de
        pop hl
        scf
        ret

; HL = source, DE = VRAM address, B = count (1-255): fast while the budget
; lasts, else paced. HL advances.
EinWrite:
        call EinSpend
        jp c, VdpWrite
        call VdpAddr
        ld c, EIN_VDP_DATA
        otir
        ret

; DE = VRAM address, B = count (1-255), L = value: as EinWrite
EinFill:
        call EinSpend
        jr c, .paced
        call VdpAddr
        ld a, l
        ld c, EIN_VDP_DATA
.f:     out (c), a
        djnz .f
        ret
.paced: ld c, b
        ld b, 0
        jp VdpFill

EBudget:        dw 0
EDirtyPtr:      dw 0
EDirtyLeft:     db 0

; A = slot (a SlotShadow index), C = what changed (bit 0 the pixels, bit 1
; the colour): from SlotShadow into VRAM
EinSendSlot:
        ld b, a
        ld d, high (VRAM_PAT + $800)    ; the middle third
        cp 4 * SLOTS_T1
        jr nc, .t2
        add a, SLOT_FIRST
        jr .p
.t2:    ld d, high (VRAM_PAT + $1000)   ; the bottom third
        add a, SLOT_FIRST - 4 * SLOTS_T1
.p:     ld l, a                 ; DE = the pattern's VRAM address
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        ld a, h
        add a, d
        ld d, a
        ld e, l
        ld a, b                 ; HL = SlotShadow + slot * 9
        ld l, a
        ld h, 0
        push de
        ld d, h
        ld e, l
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, de
        ld de, SlotShadow
        add hl, de
        pop de
        bit 0, c
        jr z, .col
        push bc
        push de
        push hl
        ld b, 8
        call EinWrite
        pop hl
        pop de
        pop bc
.col:   bit 1, c
        ret z
        ld bc, 8
        add hl, bc
        ld a, (hl)              ; the colour, on all 8 lines
        ld l, a
        ld a, d
        add a, high VRAM_COL
        ld d, a
        ld b, 8
        jp EinFill

; ---------------------------------------------------------------------------
; The display afresh (the end of OvResetDisplay, at a new stage, once the
; Spectrum's code has made screen B afresh): with the display off, VRAM
; cleared; the solid cells 0-15 in the middle and bottom thirds; the sky's
; rows mirrored, the panorama's patterns; the names: the sky's, the
; panorama's, grass below; no slot in use.
EinResetDisplay:
        di                      ; (the interrupt reads the VDP's status)
        call VdpInit            ; (a disc read may have let MOS at the VDP)
        call VdpOff
        ld hl, $FFFF            ; (the display off: any speed)
        ld (EBudget), hl
        ld de, 0                ; all of VRAM: 0
        ld bc, $4000
        ld l, 0
        call VdpFill
        ld de, VRAM_SPRATTR     ; no sprites
        ld bc, 1
        ld l, $D0
        call VdpFill
        ld de, VRAM_COL + $800  ; the solid cells' colours
        call .solids
        ld de, VRAM_COL + $1000
        call .solids
        call EinMirrorAll
        call EinPanoUpload
        ; the names: rows 0-7 the top third's patterns in order, rows 8-9
        ; the middle third's from SKY_PAT_T1, the panorama, grass
        ld hl, NameBuf
        xor a
.n0:    ld (hl), a
        inc hl
        inc a
        jr nz, .n0
        ld a, SKY_PAT_T1
.n1:    ld (hl), a
        inc hl
        inc a
        cp SKY_PAT_T1 + 64
        jr nz, .n1
        ld a, (HorizonX + 1)
        call EinHorizonNow
        ld hl, BaseNames + (ROAD_ROW0 - PANO_ROW0) * 32
        ld a, (PalGrassL)
        ld b, (24 - ROAD_ROW0) * 32 / 2
        call .fill
        ld a, (PalGrassL)
        ld b, (24 - ROAD_ROW0) * 32 / 2
        call .fill
        ld hl, BaseNames
        ld de, NameBuf + PANO_ROW0 * 32
        ld bc, (24 - PANO_ROW0) * 32
        ldir
        xor a                   ; no silhouettes on show
        ld (EOldCmds), a
        ld (EPanoN), a
        call EinPortalReset
        ld hl, NameBuf          ; (the display is off: any speed would do)
        ld de, VRAM_NAMES
        ld b, 0
        call VdpWrite
        ld de, VRAM_NAMES + 256
        ld b, 0
        call VdpWrite
        ld de, VRAM_NAMES + 512
        ld b, 0
        call VdpWrite
        ld hl, ERowDrawn        ; (all sent)
        ld b, 24
.d:     ld (hl), 0
        inc hl
        djnz .d
        ld a, 1                 ; the car: drawn again, sent again
        ld (CarDirty), a
        ld (EinCarDirty), a
        ld (EinCarFull), a
        ld hl, SlotShadow       ; the slots: as VRAM, all clear
        ld de, SlotShadow + 1
        ld bc, N_SLOTS * SLOT_SIZE - 1
        ld (hl), 0
        ldir
        xor a
        ld (DirtyN), a
        inc a
        ld (EinShape), a        ; every row to be drawn
        call VdpOn
        ei
        ret
; A = attribute: its paper's solid name, B times from HL
.fill:  call AttrPaper
.f:     ld (hl), a
        inc hl
        djnz .f
        ret
; DE = a third's colours: solid cell k has colour k behind clear pixels
.solids:
        call VdpAddr
        ld b, 0
.s:     ld a, b
        rrca
        rrca
        rrca
        and 15
        out (EIN_VDP_DATA), a   ; (the display is off)
        inc b
        ld a, b
        cp 128
        jr nz, .s
        ret
