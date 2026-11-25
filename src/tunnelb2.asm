; Tunnels (src/tunnel.asm), the part in bank 2
; A = 1 in the tunnel: the sky is its ceiling; 0: the theme's sky
Ceiling:
        ld hl, TunInside
        cp (hl)
        ret z
        ld (hl), a
        or a
        ld hl, THEME_CACHE + 6  ; the theme's sky and backdrop colours
        jr z, .pal
        ld hl, TunSky
.pal:   ld de, PalSky
        ldi
        ldi
        jr z, .sky
        IFNDEF NATIVE_GFX       ; (the Einstein, the CPC: screen B only; screen A's memory
        ld hl, $4840            ; holds its buffers) going in: the backdrop's pixels
        call .clear             ; cleared (both screens; drawn again on the way out)
        ENDIF
        ld hl, $C840
        call .clear
        ld a, $FF
        ld (PanoLastA), a
        ld (PanoLastB), a
.sky:
        IFDEF EINSTEIN
        ld hl, $D800 + 3 * 32   ; the sky and backdrop rows (the frame is put
        jp PaintRaceSky         ; together from them after this)
        ELSE
        ld a, 2                 ; both buffers' sky and backdrop rows, each as
        ld (GateWas), a         ; it is drawn next (Gate.gone): not at once -
        ret                     ; the last frame, still to be shown, kept the
                                ; tunnel's mouth on its road rows under them
        ENDIF
; HL = the backdrop's first byte (character rows 10-11): its 8 pixel lines
.clear: ld b, 8
.cl:    push bc
        push hl
        ld d, h
        ld e, l
        inc de
        ld (hl), 0
        ld bc, 63
        ldir
        pop hl
        inc h
        pop bc
        djnz .cl
        ret

; ---------------------------------------------------------------------------
; The goal's gantry: a chequered beam on two red posts over the road at the
; end of the last stage (GateZ, set at a stage start: $FFFF elsewhere), drawn in
; attributes like a tunnel's mouth (src/tunnel.asm DrawPortal, PortalRow)
; when no tunnel is in view. Once it has gone past, the sky rows are painted
; afresh (the road rows it used were marked to be redrawn as it went).
; ---------------------------------------------------------------------------
GATE_POST       EQU $52             ; bright red (red ink: nothing shows through)
GATE_BEAM       EQU $7F             ; bright white, chequered with black
GATE_NEAR       EQU 240             ; nearer than this: gone past
GATE_FAR        EQU 1264            ; further than this: not drawn yet (its posts would
                                    ; not show: the road is under ARCH_MIN wide there)

Gate:
        ld hl, (GateZ)
        ld de, (Pos)
        or a
        sbc hl, de
        ld de, -GATE_NEAR
        add hl, de
        jr nc, .gone            ; (behind, or about to be)
        ld a, h
        cp high (GATE_FAR - GATE_NEAR)
        jr nc, .gone
        ld de, GATE_NEAR
        add hl, de
        ex de, hl
        call ObjLine            ; its depth line ...
        cp ROAD_LINES
        jr nc, .gone
        or 1
        ld l, a
        ld a, (P1Hill)
        or a
        ld a, l
        jr z, .line             ; ... on screen: the same line, or where the hills put it
        add a, low ProjClip
        ld l, a
        ld h, high ProjClip
        ld a, (hl)
        or a
        jr z, .gone             ; (over the top of a crest)
.line:  ld (PtGate), a
        ld c, a                 ; (under $80: not a tunnel's mouth, DrawPortal)
        jp DrawPortal.atLine
; Not drawn this frame (nor a tunnel's portal: src/tunnel.asm): the sky rows
; it was drawn on, or that Ceiling changed, painted afresh (GateWas: their
; buffers still to do, 2 for both; PortalRow sets it)
.gone:  ld hl, GateWas
        ld a, (hl)
        or a
        ret z
        IFDEF EINSTEIN
        ld (hl), 0
        ld a, $FF               ; (its whole sky: nothing of a portal left on it)
        ld (PtTopB), a
        jp Ceiling.sky
        ELSE
        dec a                   ; this buffer's now (its frame is drawn without
        jr z, .last             ; it), the other's next frame
        ld a, 1
.last:  ld (hl), a
        ld hl, PtTopA           ; (its whole sky: nothing of a portal left on it)
        ld a, (AttrHi)
        rla
        jr nc, .ta
        inc hl
.ta:    ld (hl), $FF
        ld a, (AttrHi)
        ld h, a
        ld l, 3 * 32
        jp PaintRaceSky
        ENDIF

; PortalRow for a gantry: C = row, HL = its attributes. Beside it the sky
; (on road rows: the road's own); the beam above the opening's top, the
; posts either side below it.
GateKind:
        push hl
        ld a, c
        ld b, S_
        cp ROAD_ROW0
        jr nc, .x
        call SkyRowAttr
        ld b, a
.x:     ld hl, GatePat
        ld (hl), b
        inc hl
        ld a, (PtTop)
        dec a
        cp c
        ld a, GATE_BEAM         ; a beam row: beam right across
        ld d, a
        jr nc, .k
        ld a, GATE_POST         ; a post row
        ld d, b
.k:     ld (hl), a
        inc hl
        ld (hl), d
        inc hl
        ld (hl), a
        inc hl
        ld (hl), b
        ld de, GatePat
        pop hl
        jp PortalRow.go

; After a gantry's row: a beam row's cells alternate white and black
Chequer:
        ld a, (PtGate)
        or a
        ret z
        ld a, (PtR)
        ld c, a
        ld hl, PtTop
        cp (hl)
        ret nc                  ; (a post row)
        call RowAttrHL
        ld de, PtN
        ld a, (de)              ; from the first post's column ...
        add a, l
        ld l, a
        inc de
        ld a, (de)              ; ... across the beam
        inc de
        ex de, hl
        add a, (hl)
        inc hl
        add a, (hl)
        ex de, hl
        ret z
        ld b, a
.c:     ld a, l
        xor c
        rra
        jr nc, .n
        ld (hl), 0
.n:     inc l
        djnz .c
        ret

; (DrawPortal's helpers and row patterns, src/tunnel.asm)
; A = row -> HL = its first attribute on the screen being drawn (A kept)
RowAttrHL:
        IFDEF CPC
        call CSkyPainted        ; (the sky rows painted: src/cpc/reset.asm)
        ENDIF
        ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        push af
        ld a, (AttrHi)
        add a, h
        ld h, a
        pop af
        ret

; A -> A / 8
Cell:   rrca
        rrca
        rrca
        and 31
        ret

PatFace:        db F_, F_, F_, F_, F_
PatArch:        db F_, A_, A_, A_, F_
PatSky:         db F_, A_, D_, A_, F_
PatRoad:        db F_, A_, D_, A_, F_    ; (inside: dark, the road beyond hidden too;
                                        ; close by, S_: src/tunnel.asm DrawPortal)
PatOut:         db C_, C_, 0, C_, C_    ; (the sky, set at a stage start: src/stageov.asm)
                db D_, D_, S_, D_, D_
PatCeil:        db C_, C_, C_, C_, C_   ; (the way out: above the opening)
