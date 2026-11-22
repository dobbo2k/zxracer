; ---------------------------------------------------------------------------
; Einstein: the part of src/screen.asm the game's own code still calls from
; bank 2's layout (the buffers and flips are in src/einstein/flip.asm).
; ---------------------------------------------------------------------------

; A = value, B = count (0-32), HL = destination; advances L only.
FillA:
        ex af, af'
        ld a, b
        or a
        jr z, .none
        add a, a
        neg
        ld (.jump + 1), a
        ex af, af'
.jump:  jp FILL_END - 256       ; low byte patched: FILL_END - 2*count
.none:  ex af, af'
        ret
