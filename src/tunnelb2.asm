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
