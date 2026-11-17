; ---------------------------------------------------------------------------
; Horizon panorama: a 256-pixel tiling band of mountains in character rows
; 9-11, scrolled sideways by the road's curvature. Four copies are stored,
; pre-rotated by 0/2/4/6 pixels; a copy plus a whole-byte rotation (two LDI
; runs per line) gives any even scroll position. Redrawn only when the
; scroll position changed since this buffer last showed it.
; ---------------------------------------------------------------------------
PANO_Y          EQU 72                  ; first line (character row 9)

DrawHorizon:
        ld a, (HorizonX + 1)            ; scroll in pixels
        and $FE
        ld hl, (PanoLast)
        cp (hl)
        ret z
        ld (hl), a
        ld c, a
        ; copy = (scroll >> 1) & 3  ->  source base = Panorama + copy * 768
        rrca
        and 3
        ld hl, Panorama
        ld de, 32 * PANO_H
        jr z, .base
        ld b, a
.cp:    add hl, de
        djnz .cp
.base:  ld (.src + 1), hl
        ; byte rotation b = scroll >> 3: copy bytes [b, 32) then [0, b)
        ld a, c
        rrca
        rrca
        rrca
        and 31
        ld (.off + 1), a
        ld b, a
        ld a, 32
        sub b
        call PanoEntry
        ld (.call1 + 1), hl
        ld a, b
        call PanoEntry
        ld (.call2 + 1), hl
        ld a, (BufHiOr)
        ld (.bufOr + 1), a
        ld ixl, PANO_H
        ld ixh, PANO_Y
.src:   ld hl, 0
.ln:    push hl
        ; DE = screen line
        ld a, ixh
        ld l, a
        ld h, high ScrLo
        ld e, (hl)
        inc h
        ld a, (hl)
.bufOr: or 0
        ld d, a
        pop hl
        push hl
        ld a, l
.off:   add a, 0
        ld l, a
        jr nc, .nc
        inc h
.nc:
.call1: call PanoLdiEnd
        pop hl
        push hl
.call2: call PanoLdiEnd
        pop hl
        ld bc, 32
        add hl, bc
        inc ixh
        dec ixl
        jr nz, .ln
        ret

; A = byte count (0..32) -> HL = entry into the 32-LDI chain
PanoEntry:
        ld hl, PanoLdiEnd
        or a
        ret z
        add a, a
        neg
        ld l, a
        dec h
        ret
