; ---------------------------------------------------------------------------
; Einstein: tunnels' mouths and ways out, and the goal's gantry
;
; The Spectrum paints them in attributes (src/tunnel.asm DrawPortal, every
; frame from the line where the road meets the tunnel; src/tunnelb2.asm
; Ceiling and Gate) and lets the road's redraw put its rows' attributes
; back. Here that code still paints screen B's attributes, and each frame
; (on a stage with a tunnel or the gantry):
;   rows 3-9 (the sky): the cells whose attribute changed are mirrored
;   rows 10-19: a cell whose attribute is not its row's own (the road's
;     rows: as the display reset left them; the panorama's: PalPano) is
;     the portal's: a solid cell of its paper (its ink is the same, so
;     nothing shows through). The attribute is then put back, for the next
;     frame's painting. Those rows are put together again (EMaskU), and
;     again the frame after, when the portal has moved on.
; In a tunnel the panorama's rows are its ceiling (EinHorizon).
; ---------------------------------------------------------------------------

EinPortal:
        ld hl, (TunEnd)         ; a tunnel or the gantry on this stage?
        ld a, h
        or l
        jr nz, .scan
        ld hl, (GateZ)
        ld a, h
        and l
        inc a
        jr nz, .scan
        ld a, (EPortalAny)      ; (or the last frame's to take away)
        or a
        ret z
.scan:  ; ---- the sky's rows: changed attributes
        ld hl, $D800 + 3 * 32
        ld de, ESkyAttr
        ld bc, 3 * 256          ; B: row, C: column
.sk:    ld a, (de)
        cp (hl)
        jr z, .skn
        ld a, (hl)
        ld (de), a
        call EinMarkRC
.skn:   inc hl
        inc de
        inc c
        ld a, c
        cp 32
        jr nz, .sk
        ld c, 0
        inc b
        ld a, b
        cp PANO_ROW0
        jr nz, .sk
        ; ---- rows 10-23: the portal's cells
        ld hl, EMaskP           ; last frame's -> EMaskPOld
        ld de, EMaskPOld
        ld bc, 24 * MASK_ROW
        ldir
        ld hl, EMaskP
        ld de, EMaskP + 1
        ld bc, 24 * MASK_ROW - 1
        ld (hl), 0
        ldir
        xor a
        ld (EPortalAny), a
        ld ix, EMaskP
        ld hl, $D800 + PANO_ROW0 * 32
        ld b, PANO_ROW0
.r:     ld a, b                 ; the row's own attribute
        cp ROAD_ROW0
        ld a, (PalPano)
        jr c, .own
        ld a, (EBaseRoad)
.own:   ld e, a
        ld c, 0
.c:     ld a, (hl)
        cp e
        jr z, .cn
        push hl
        call EinMaskSet
        pop hl
        ld a, 1
        ld (EPortalAny), a
.cn:    inc hl
        inc c
        ld a, c
        cp 32
        jr nz, .c
        inc b
        ld a, b
        cp CAR_ROW              ; (the portal stops above the car's rows:
        jr nz, .r               ; their attributes are the car's)
        ; ---- those rows, and last frame's, to be put together again
        ld hl, EMaskP + PANO_ROW0 * MASK_ROW
        ld de, EMaskU + PANO_ROW0 * MASK_ROW
        ld bc, EMaskPOld + PANO_ROW0 * MASK_ROW
        ld a, (24 - PANO_ROW0) * MASK_ROW
.u:     push af
        ld a, (bc)
        or (hl)
        ex de, hl
        or (hl)
        ld (hl), a
        ex de, hl
        or a
        jr z, .un
        ld a, 1
        ld (EPortalAny), a
.un:    inc hl
        inc de
        inc bc
        pop af
        dec a
        jr nz, .u
        ret

; B = row (10-23), HL = its NameBuf row: after its silhouettes, the
; portal's cells (EMaskP) as solid cells of their paper, and their
; attributes put back. (B kept)
EinPortalCells:
        ld a, (EPortalAny)
        or a
        ret z
        push bc
        ld (EPNames), hl
        ld ix, EMaskP
        call EinMaskRow
        call EinMaskAny
        jr z, .done
        ld (EPMask), hl
        ld a, b                 ; HL = its attributes: $D800 + row * 32
        rrca
        rrca
        rrca
        ld c, a
        and $E0
        ld l, a
        ld a, c
        and 3
        or $D8
        ld h, a
        ld a, b                 ; the row's own attribute, to put back
        cp ROAD_ROW0
        ld a, (PalPano)
        jr c, .own
        ld a, (EBaseRoad)
.own:   ld (.put + 1), a
        ld ix, (EPMask)
        ld de, (EPNames)
        ld c, MASK_ROW
.byte:  ld a, (ix + 0)
        inc ix
        ld b, 8
.bit:   rrca
        jr nc, .no
        push af
        ld a, (hl)              ; the portal's paper
        call AttrPaper
        ld (de), a
.put:   ld (hl), 0              ; (patched: the row's own attribute)
        pop af
.no:    inc hl
        inc de
        djnz .bit
        dec c
        jr nz, .byte
.done:  pop bc
        ret

EPNames:        dw 0
EPMask:         dw 0

; At a display reset: the attributes as they are now
EinPortalReset:
        ld hl, $D800 + 3 * 32
        ld de, ESkyAttr
        ld bc, (PANO_ROW0 - 3) * 32
        ldir
        ld a, ($D800 + ROAD_ROW0 * 32)
        ld (EBaseRoad), a
        xor a
        ld (EPortalAny), a
        ld hl, EMaskP
        ld de, EMaskP + 1
        ld bc, 2 * 24 * MASK_ROW - 1
        ld (hl), 0
        ldir                    ; (EMaskPOld follows)
        ret

EPortalAny:     db 0
EBaseRoad:      db 0

