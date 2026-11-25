; ---------------------------------------------------------------------------
; Horizon panorama: a 256-pixel tiling band of mountains in character rows
; 10-11, scrolled sideways by the road's curvature. Two copies are stored,
; pre-rotated by 0 and 4 pixels; a copy plus a whole-byte rotation (two LDI
; runs per line) gives any scroll position in 4-pixel steps. Redrawn only
; when the scroll position changed since this buffer last showed it.
; ---------------------------------------------------------------------------
PANO_Y          EQU 80                  ; first line (character row 10)

        IFNDEF NATIVE_GFX       ; (the Spectrum's drawing: not in the Einstein's or the CPC's)
; When this game frame already runs late (2 TV frames since the last flip)
; and the panorama is only one step (4 pixels) behind, skip it: it is a
; distant band and catching up a frame later is invisible. Further behind
; always redraws.
DrawHorizonIfTime:
        ld a, (TunInside)       ; (in a tunnel: hidden)
        or a
        ret nz
        ld a, (HorizonX + 1)
        and $FC
        ld hl, (PanoLast)
        sub (hl)
        ret z                   ; up to date
        add a, 4
        cp 9
        jr nc, DrawHorizon      ; 8+ pixels behind: always redraw
        IF FIXED_ELAPSED
        jr DrawHorizon          ; (testing: nothing depends on the timing)
        ENDIF
        ld a, (FrameCount)      ; only one step behind: skip if running late
        ld hl, LastFlip
        sub (hl)
        cp MIN_FRAMES
        ret nc

DrawHorizon:
        ld a, (HorizonX + 1)            ; scroll in pixels
        and $FC
        ld hl, (PanoLast)
        cp (hl)
        ret z
        ld (hl), a
        ld c, a
        ; copy = (scroll >> 2) & 1  ->  source base = Panorama + copy * 512
        rrca
        rrca
        and 1
        ld hl, (StPano)
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
        ENDIF
