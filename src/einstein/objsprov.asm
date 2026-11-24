; ---------------------------------------------------------------------------
; Einstein: the object sprites' patterns (-DEIN_OBJSPR; src/einstein/
; objspr.asm), in the stage overlay: from OvResetDisplay, before
; EinResetDisplay unpacks the sky over the overlay (that leaves VRAM's
; sprite patterns as they are). The stage's object sizes (types 0-9: the
; tunnel sign is not in every theme pack) as 16 x 16 patterns, the sizes
; that take fewest first, into patterns 0-62 (63: the tail lamps'). An
; image is width / 2 patterns across (its last byte column is the
; pre-shifted copies' padding) and height / 16 down, rounded up, aligned
; to its bottom line. ESprBase: each type's 9 sizes' first pattern ($FF:
; none); a size with its predecessor's image shares its patterns.
; ---------------------------------------------------------------------------
OvSprPatterns:
        di                      ; (the interrupt reads the VDP's status)
        ld hl, ESprBase
        ld b, 10 * 9
.cl:    ld (hl), $FF
        inc hl
        djnz .cl
        ld a, $D0               ; (no object sprites yet)
        ld (ESprAttr), a
        ld a, 1
        ld (ESprLen), a
        ld de, VRAM_SPRPAT
        call VdpAddr
        xor a
        ld (ESprNext), a
        inc a                   ; the patterns an image takes: 1, then 2 ... 9
.pass:  ld (ESprPass), a
        ld c, 0                 ; type
.type:  ld a, c
        add a, a
        ld hl, (StTypeDir)
        add a, l
        ld l, a
        jr nc, .td
        inc h
.td:    ld a, (hl)
        inc hl
        ld h, (hl)
        ld l, a
        push hl
        pop ix                  ; IX = its sizes
        ld b, 0                 ; size
.size:  call OvSprCount          ; E = its patterns (src/einstein/objsprhi.asm)
        ld a, (ESprPass)
        cp e
        jr nz, .next
        ld a, c                 ; ESprBase + type * 9 + size
        add a, a
        add a, a
        add a, a
        add a, c
        add a, b
        ld l, a
        ld h, high ESprBase
        ld a, b                 ; the size before's image: its patterns
        or a
        jr z, .new
        ld a, (ix + 4)
        cp (ix - 4)
        jr nz, .new
        ld a, (ix + 5)
        cp (ix - 3)
        jr nz, .new
        dec l
        ld a, (hl)
        inc l
        ld (hl), a
        jr .next
.new:   ld a, (ESprNext)
        add a, e
        cp 64
        jr nc, .next            ; (no room)
        ld (ESprNext), a
        sub e
        ld (hl), a
        call OvSprImage         ; (src/einstein/objsprhi.asm)
.next:  ld de, 8
        add ix, de
        inc b
        ld a, b
        cp 9
        jr nz, .size
        inc c
        ld a, c
        cp 10
        jr nz, .type
        ld a, (ESprPass)
        inc a
        cp 10
        jp nz, .pass
        ret
