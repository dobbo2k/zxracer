; ---------------------------------------------------------------------------
; Einstein: more of the display reset (EinResetDisplay): every sky cell, and
; the panorama's patterns. Not time-critical: in bank 2, after the OUTI
; chain (src/main.asm).
; ---------------------------------------------------------------------------

; Every cell of rows 0-9 (a new stage, the display off)
EinMirrorAll:
        ld b, 0
.r:     ld c, 0
.c:     push bc
        call EinMirrorCell
        pop bc
        inc c
        ld a, c
        cp 32
        jr nz, .c
        inc b
        ld a, b
        cp MIRROR_ROWS
        jr nz, .r
        ld hl, EMirrorBits      ; (none left to send)
        ld b, MIRROR_ROWS * 4
        xor a
.z:     ld (hl), a
        inc hl
        djnz .z
        ld (EMirrorN), a
        ret

; The panorama's patterns: row r (0-1), column c is pattern PANO_PAT +
; r * 32 + c of the middle third (its first copy only: the second's 64
; patterns hold the cells under silhouettes, src/einstein/sprites.asm);
; matching scanline inks for the 64 scrolling patterns
EinPanoUpload:
        ld de, $0800 + PANO_PAT * 8
        call VdpAddr
        ld hl, PANO_CACHE
        ld b, 2                 ; row
.blk:   push bc
        ld c, 0                 ; column
.col:   push hl
        ld a, l
        add a, c
        ld l, a
        jr nc, .nc
        inc h
.nc:    ld b, 8
.ln:    ld a, (hl)
        out (EIN_VDP_DATA), a   ; (the display is off)
        ld de, 32
        add hl, de
        djnz .ln
        pop hl
        inc c
        ld a, c
        cp 32
        jr nz, .col
        ld de, 32 * 8           ; the next row of cells
        add hl, de
        pop bc
        djnz .blk
        ld hl, PANO_CACHE + 512
        ld de, VRAM_COL + $0800 + PANO_PAT * 8
        ld b, 0
        call VdpWrite
        ld de, VRAM_COL + $0800 + PANO_PAT * 8 + 256
        ld b, 0
        jp VdpWrite
