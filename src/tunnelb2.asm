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
        ld hl, $4840            ; going in: the backdrop's pixels cleared (both
        call .clear             ; screens; drawn again on the way out)
        ld hl, $C840
        call .clear
        ld a, $FF
        ld (PanoLastA), a
        ld (PanoLastB), a
.sky:   ld hl, $5800 + 3 * 32   ; both screens' sky and backdrop rows
        call .paint
        ld hl, $D800 + 3 * 32
.paint: ld a, (PalSky)
        ld b, 32 * (PANO_ROW0 - 3)
.s:     ld (hl), a
        inc hl
        djnz .s
        ld a, (PalPano)
        ld b, 32 * (ROAD_ROW0 - PANO_ROW0)
.p:     ld (hl), a
        inc hl
        djnz .p
        ret
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
        ld (GateWas), a
        jp DrawPortal.atLine
.gone:  ld hl, GateWas
        ld a, (hl)
        or a
        ret z
        ld (hl), 0
        jp Ceiling.sky          ; the sky it used, both screens

; PortalRow for a gantry: C = row, HL = its attributes. Beside it the sky
; (on road rows: the road's own); the beam above the opening's top, the
; posts either side below it.
GateKind:
        push hl
        ld a, c
        ld b, S_
        cp ROAD_ROW0
        jr nc, .x
        ld hl, PalPano
        cp PANO_ROW0
        jr nc, .p
        dec hl                  ; (PalSky)
.p:     ld b, (hl)
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
PatRoad:        db F_, A_, S_, A_, F_
PatOut:         db C_, C_, 0, C_, C_    ; (the sky, set per frame)
                db D_, D_, S_, D_, D_
PatCeil:        db C_, C_, C_, C_, C_   ; (the way out: above the opening)
