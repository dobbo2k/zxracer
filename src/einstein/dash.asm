; ---------------------------------------------------------------------------
; Einstein: the centre line's sprites (src/einstein/roadgfx.asm calls
; EinDashRow, EinDashNone and EinDashFinish for its rows; flip.asm
; EinDashSend and EinDashReset). In bank 2's code: the platform code below
; $4000 is full.
; The centre line: a 16x16 sprite a road row (sprite k for row 12 + k, its
; patterns 4k on; the top two quarters used), so its pixels are exact at
; any x and cost no slot. Per row drawn (EinDashRow): the dashes of its
; line pairs 0 and 2, each for 4 lines (light bands only, in road cells
; [b, c-1) as the Spectrum), from its leftmost dash pixel, the cells the
; car, a silhouette or a tunnel's mouth covers taken out. A row not drawn
; again is done again only if what covers it changed (EinDashFinish). What
; changed is sent at the start of the next vertical blank (EinDashSend).
EinDashRow:
        ld a, (ERow)
        ld e, a
        ld d, 0
        ld hl, EDashNew
        add hl, de
        ld (hl), 1
        ld hl, EDashB
        add hl, de
        ld a, (ERB)
        ld (hl), a
        ld hl, EDashC
        add hl, de
        ld a, (ERC)
        ld (hl), a
EinDashRedo:                    ; (ERow, EI, ERB, ERC)
        ld a, (ERC)             ; its x in [ERB * 8, (ERC - 1) * 8)
        sub 1
        jp c, .none             ; (no road on the row)
        ld hl, ERB
        cp (hl)
        jp c, .none
        jp z, .none
        add a, a
        add a, a
        add a, a
        ld e, a                 ; E: the end
        ld a, (hl)
        add a, a
        add a, a
        add a, a
        ld d, a                 ; D: the start
        ld a, (EI)
        ld c, a                 ; C: the line (pairs 0 and 2)
        ld hl, EDashP
        ld b, $FF               ; B: the leftmost x
        call .pair
        ld a, c
        add a, 4
        ld c, a
        call .pair
        ld a, b
        cp $FF
        jp z, .none
        ld (EDashXk), a
        call EinDashHideRow     ; (EDashHideNow, EDashHideAny: B kept)
        ld de, $FFFF            ; D, E: the left and right bytes' masks
        ld a, (EDashHideAny)
        or a
        jr z, .full
        ld a, b                 ; the three cells under its 16 pixels
        rrca
        rrca
        rrca
        and 31
        ld c, a
        call .cell
        ld d, a
        inc c
        call .cell
        ld e, a
        inc c
        call .cell
        ld l, a                 ; D E L, shifted left by x & 7
        ld a, b
        and 7
        jr z, .full
        ld b, a
.sh:    sla l
        rl e
        rl d
        djnz .sh
.full:  ld a, d
        ld (EDashML), a
        ld a, e
        ld (EDashMR), a
        ld hl, EDashP           ; ---- its 4 bytes into EDashV
        ld de, EDashV
        call .pat
        call .pat
        ld hl, EDashV           ; any shown?
        ld a, (hl)
        inc hl
        or (hl)
        inc hl
        or (hl)
        inc hl
        or (hl)
        ld (EDashAnyB), a
        ld a, (ERow)            ; ---- against VRAM's
        add a, a
        add a, a
        ld l, a
        ld h, 0
        ld bc, EDashOut
        add hl, bc
        ld de, EDashV
        ld b, 4
.cmp:   ld a, (de)
        cp (hl)
        jr nz, .diff
        inc de
        inc hl
        djnz .cmp
        jr .same
.diff:  ld (hl), a              ; (the rest copied)
        inc de
        inc hl
        djnz .cp
        jr .sent
.cp:    ld a, (de)
        ld (hl), a
        inc de
        inc hl
        djnz .cp
.sent:  ld a, (ERow)            ; its sprite's bytes: EDashQ + row * 32
        ld l, a                 ; (lines 0-7 left, 8 clear, 0-7 right)
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ld de, EDashQ
        add hl, de
        ld de, (EDashV)         ; E: lines 0-3 left, D: right
        ld bc, (EDashV + 2)     ; C: 4-7 left, B: right
        ld (hl), e
        inc l
        ld (hl), e
        inc l
        ld (hl), e
        inc l
        ld (hl), e
        inc l
        ld (hl), c
        inc l
        ld (hl), c
        inc l
        ld (hl), c
        inc l
        ld (hl), c
        ld a, l
        add a, 9
        ld l, a
        ld (hl), d
        inc l
        ld (hl), d
        inc l
        ld (hl), d
        inc l
        ld (hl), d
        inc l
        ld (hl), b
        inc l
        ld (hl), b
        inc l
        ld (hl), b
        inc l
        ld (hl), b
        ld a, (ERow)
        ld c, a
        ld b, 0
        ld hl, EDashSend
        add hl, bc
        ld (hl), 1
        ld a, 1
        ld (EDashAny2), a
.same:  ld a, (ERow)            ; ---- where it is, and what hides it
        ld c, a
        ld b, 0
        ld hl, EDashX
        add hl, bc
        ld a, (EDashXk)
        ld (hl), a
        ld a, (EDashAnyB)
        or a
        jr z, .hide
        ld a, (ERow)
        add a, ROAD_ROW0
        add a, a
        add a, a
        add a, a
        dec a                   ; Y: the line above its top
        ld d, a
        ld a, (EDashXk)
        ld e, a
        jr .attr
.none:  ld a, (ERow)
        ld c, a
        ld b, 0
        ld hl, EDashX
        add hl, bc
        ld (hl), $FF
.hide:  ld de, 192 * 256        ; (below the picture)
.attr:  ld a, (ERow)
        add a, a
        add a, a
        ld c, a
        ld b, 0
        ld hl, EDashAttr
        add hl, bc
        ld a, (hl)
        cp d
        jr nz, .newA
        inc hl
        ld a, (hl)
        cp e
        jr nz, .newA1
        inc hl
        inc hl
        ld a, (ERoadInkT)       ; (its colour: the road's ink)
        cp (hl)
        ret z
        jr .newA3
.newA:  ld (hl), d
        inc hl
.newA1: ld (hl), e
        inc hl
        inc hl
.newA3: ld a, (ERoadInkT)
        ld (hl), a
        ld a, 1
        ld (EDashAttrNew), a
        ret
; C = the line, D/E = the start / end of its x, B = the leftmost so far,
; HL = its x and width (x 8) to be noted ($FF: none)
.pair:  push hl
        ld a, c
        add a, low Band
        ld l, a
        ld h, high Band
        bit 6, (hl)             ; (STRIPE_BIT: a dark band)
        jr nz, .pn
        ld l, c
        ld h, high LaneX
        ld a, (hl)              ; ($FF, none: past the end)
        cp d
        jr c, .pn
        cp e
        jr nc, .pn
        cp b
        jr nc, .pw
        ld b, a
.pw:    ex af, af'
        set 7, l                ; width: LaneW of the depth line shown
        ld h, high SrcLine
        ld a, (hl)
        or $80
        ld l, a
        ld h, high LaneW
        ld a, (hl)
        add a, a
        add a, a
        add a, a
        pop hl
        ex af, af'
        ld (hl), a
        inc hl
        ex af, af'
        ld (hl), a
        inc hl
        ret
.pn:    pop hl
        ld (hl), $FF
        inc hl
        inc hl
        ret
; HL = a pair's x and width: its 4 lines' left and right bytes, masked,
; into DE (then DE on 2)
.pat:   ld a, (EDashXk)
        ld c, a
        ld a, (hl)
        inc hl
        cp $FF
        jr z, .p0
        sub c                   ; its offset from the leftmost
        cp 8
        jr nc, .pfar
        add a, (hl)             ; + width x 8
        inc hl
        push hl
        add a, low LaneM1
        ld l, a
        ld h, high LaneM1
        ld c, (hl)              ; C: left
        add a, low LaneM2 - low LaneM1
        ld l, a
        ld b, (hl)              ; B: right
        jr .pm
.pfar:  sub 8                   ; (8 or more on: its first byte on the right)
        add a, (hl)
        inc hl
        push hl
        add a, low LaneM1
        ld l, a
        ld h, high LaneM1
        ld b, (hl)
        ld c, 0
        jr .pm
.p0:    inc hl
        push hl
        ld bc, 0
.pm:    ld a, (EDashML)
        and c
        ld (de), a
        inc de
        ld a, (EDashMR)
        and b
        ld (de), a
        inc de
        pop hl
        ret
; C = a cell -> A: its pixels' mask, FF if shown, 0 if hidden (or past 31)
.cell:  ld a, c
        cp 32
        ld a, 0
        ret nc
        push hl
        push de
        ld a, c
        rrca
        rrca
        rrca
        and 3
        add a, low EDashHideNow
        ld l, a
        ld a, high EDashHideNow
        adc a, 0
        ld h, a
        ld a, c
        and 7
        add a, low EBitTab
        ld e, a
        ld a, high EBitTab
        adc a, 0
        ld d, a
        ld a, (de)
        and (hl)
        pop de
        pop hl
        ld a, 0
        ret nz
        dec a
        ret

; The row (ERow): no centre line
EinDashNone:
        ld a, (ERow)
        ld e, a
        ld d, 0
        ld hl, EDashNew
        add hl, de
        ld (hl), 1
        jp EinDashRedo.none

; ERow -> EDashHideNow: its cells this frame's silhouettes, the portal or
; the car cover; EDashHideAny: any
EinDashHideRow:
        ld a, (ERow)
        add a, ROAD_ROW0
        add a, a
        add a, a                ; x MASK_ROW
        ld e, a
        ld d, 0
        ld hl, EMaskN
        add hl, de
        push hl
        ld hl, EMaskP
        add hl, de
        ex de, hl
        pop hl
        ld bc, EDashHideNow
        ld a, (de)
        or (hl)
        ld (bc), a
        inc hl
        inc de
        inc bc
        ld a, (de)
        or (hl)
        ld (bc), a
        inc hl
        inc de
        inc bc
        ld a, (de)
        or (hl)
        ld (bc), a
        inc hl
        inc de
        inc bc
        ld a, (de)
        or (hl)
        ld (bc), a
        ld a, (ERow)            ; the car's (rows 20-23: columns 12-19)
        cp CAR_ROW - ROAD_ROW0
        jr c, .any
        ASSERT (CAR_COL & 7) == 4 && CAR_W == 8
        ld hl, EDashHideNow + CAR_COL / 8
        ld a, (hl)
        or $F0
        ld (hl), a
        inc hl
        ld a, (hl)
        or $0F
        ld (hl), a
.any:   ld hl, EDashHideNow
        ld a, (hl)
        inc hl
        or (hl)
        inc hl
        or (hl)
        inc hl
        or (hl)
        ld (EDashHideAny), a
        ret

; Each frame, after the rows: a row not drawn again that something covers
; now or covered last frame is done again
EinDashFinish:
        xor a
.row:   ld (ERow), a
        ld e, a
        ld d, 0
        ld hl, EDashNew
        add hl, de
        ld a, (hl)
        ld (hl), 0
        or a
        jr nz, .next            ; (done as it was drawn)
        ld hl, EDashX
        add hl, de
        ld a, (hl)
        cp $FF
        jr z, .next             ; (none: nothing to hide)
        ld a, (ERow)            ; anything over it now or last frame?
        add a, ROAD_ROW0        ; (silhouettes: EMaskU; the portal: EMaskP,
        add a, a                ; EMaskPOld)
        add a, a
        ld e, a
        ld d, 0
        ld hl, EMaskU
        add hl, de
        call EinMaskAny
        jr nz, .redo
        ld hl, EMaskP
        add hl, de
        call EinMaskAny
        jr nz, .redo
        ld hl, EMaskPOld
        add hl, de
        call EinMaskAny
        jr z, .next
.redo:  ld a, (ERow)            ; its line, its range as drawn
        ld e, a
        ld d, 0
        add a, a
        add a, a
        add a, a
        ld (EI), a
        ld hl, EDashB
        add hl, de
        ld a, (hl)
        ld (ERB), a
        ld hl, EDashC
        add hl, de
        ld a, (hl)
        ld (ERC), a
        call EinDashRedo
.next:  ld a, (ERow)
        inc a
        cp 12
        jr nz, .row
        ret

; In the vertical blank (EinUpload): the sprites' patterns and attributes
; that changed
EinDashSend:
        ld a, (EDashAny2)
        or a
        jr z, .attr
        xor a
        ld (EDashAny2), a
        ld c, 0
.k:     ld b, 0
        ld hl, EDashSend
        add hl, bc
        ld a, (hl)
        or a
        jr z, .nk
        ld (hl), 0
        push bc
        ld l, c                 ; EDashQ + k * 32 -> VRAM_SPRPAT + k * 32:
        ld h, b                 ; its first 24 bytes (the right quarter's
        add hl, hl              ; top the last 8)
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        push hl
        ld de, VRAM_SPRPAT
        add hl, de
        ex de, hl
        pop hl
        ld bc, EDashQ
        add hl, bc
        ld b, 24
        call EinWrite
        pop bc
.nk:    inc c
        ld a, c
        cp 12
        jr nz, .k
.attr:  ld a, (EDashAttrNew)
        or a
        ret z
        xor a
        ld (EDashAttrNew), a
        ld hl, EDashAttr
        ld de, VRAM_SPRATTR
        ld b, 12 * 4 + 1
        jp EinWrite

; At a display reset (VRAM cleared): every row's sprite hidden, its
; patterns clear; the attributes sent
EinDashReset:
        ld hl, EDashX
        ld b, 12
.x:     ld (hl), $FF
        inc hl
        djnz .x
        ld hl, EDashNew         ; (and EDashB, C, Send, Out, Q)
        ld de, EDashNew + 1
        ld bc, EDashAttr - EDashNew - 1
        ld (hl), 0
        ldir
        ld hl, EDashAttr
        ld b, 0
.a:     ld (hl), 192            ; Y: below the picture
        inc hl
        ld (hl), 0
        inc hl
        ld (hl), b              ; pattern 4k
        inc hl
        ld (hl), 15
        inc hl
        ld a, b
        add a, 4
        ld b, a
        cp 12 * 4
        jr nz, .a
        ld (hl), $D0            ; (no more sprites)
        xor a
        ld (EDashAny2), a
        inc a
        ld (EDashAttrNew), a
        ret

EDashP:         ds 4            ; pairs 0 and 2: x ($FF: none), width x 8
EDashXk:        db 0
EDashML:        db 0            ; the masks of its left and right bytes
EDashMR:        db 0
EDashAnyB:      db 0            ; any of its pixels shown
EDashAny2:      db 0            ; any row's patterns to be sent
EDashAttrNew:   db 0            ; the attributes to be sent
EDashHideAny:   db 0
EDashHideNow:   ds 4
EDashV:         ds 4            ; a row's bytes: lines 0-3 left, right; 4-7
        ASSERT MASK_ROW == 4
