; ---------------------------------------------------------------------------
; Tunnels (src/tunnel.asm): two pieces of DrawPortal, apart for room - on the
; Spectrum beside it in bank 5, on the Einstein in bank 2.
; ---------------------------------------------------------------------------

; The mouth's line not on the screen (behind a crest), or no road on it
; (round a bend): the mouth where its depth line lands (ProjClip, as the
; scenery is placed), its rows cut off at the road in front, as wide as the
; road there and centred on it (CXPage) even off the screen - its face all
; the same, and what of its arch and opening shows. (The face once came and
; went with the line, all at once.)
PortalHidden:
        ld a, (TunJN)
        dec a                   ; the mouth's depth line (from outside the way
        or 1                    ; out is never in sight: the tunnel's lines
        add a, low ProjClip     ; start at 0), its pair's odd line
        ld l, a
        ld h, high ProjClip
        ld a, (hl)              ; the screen line it lands on (0: at or above
        dec l                   ; the top of the road area - a climb up to it:
                                ; where the road goes off the top, then)
        ld c, (hl)              ; the road in front of it from this line on
        add a, ROAD_ROW0 * 8    ; ($80 +: in view, none)
        ld (PtY), a
        ld a, CAR_ROW           ; (in view after all: no cut)
        bit 7, c
        jr nz, .cut
        ld a, c
        add a, ROAD_ROW0 * 8 + 4
        call Cell               ; (rows above the one the road in front is
.cut:   ld (PtCut), a           ; nearest the top of)
.aside: ld a, (TunJN)           ; (PtY set) its depth line again
        dec a
        ld e, a
        ld d, high X1Page
        or 1
        ld l, a
        ld h, high CXLo
        ld a, (hl)
        set 7, l
        ld h, (hl)
        ld l, a                 ; HL = the road's centre there (signed)
        ld a, (de)              ; its half-width
        ld c, a
        add a, a
        jr nc, .w
        sbc a, a                ; (255 at most)
.w:     ld b, a                 ; B = width
        ld a, c
        srl a
        add a, c
        ld e, a
        ld d, 0                 ; DE = the opening's half-width, walls and all
        push hl
        add hl, de
        dec hl                  ; HL = its last pixel
        ld a, h
        or a
        jp m, .offL             ; (all of it left of the screen)
        ld a, l
        jr z, .rc
        ld a, 255               ; (past the right edge)
.rc:    call Cell
        ld c, a                 ; C = its last column
        pop hl
        or a
        sbc hl, de              ; HL = its first pixel
        ld a, h
        or a
        jp m, .lz               ; (left of the screen: from the first column)
        jr nz, .face            ; (all of it right of the screen)
        ld a, l
        jr .lc
.lz:    xor a
.lc:    call Cell
        ld d, a
        ld e, c
        jp DrawPortal.runs
.offL:  pop hl
.face:  ld hl, PtN + 4          ; none of it on the screen: face right across
        xor a
        ld (hl), a
        dec l
        ld (hl), a
        dec l
        ld (hl), a
        dec l
        ld (hl), a
        dec l
        ld (hl), 32
        jp DrawPortal.h

; This buffer's sky rows painted before above this frame's first (PtR): the
; sky again (the portal moved down the screen: hills, or the mouth hidden)
PortalClean:
        ld hl, PtTopA
        ld a, (AttrHi)
        rla
        jr nc, .ta
        inc hl
.ta:    ld a, (PtR)
        ld c, (hl)              ; the first row painted before ($FF: none)
        ld (hl), a
        ld b, a
.cl:    ld a, c
        cp b
        ret nc
        cp ROAD_ROW0
        ret nc                  ; (road rows: the road redraws them, marked)
        call RowAttrHL
        call SkyRowAttr
        push bc
        ld b, 32
        call FillA
        pop bc
        inc c
        jr .cl
