; ---------------------------------------------------------------------------
; Tape loader for zxracer.tap (assembled on its own by tools/make_tap.py).
;
; The BASIC loader shows the loading screen, loads this to $BF00 and calls
; it. It checks for 128K paging, then loads the headerless data blocks with
; the ROM's LD-BYTES ($0556; under 128 BASIC the 48K BASIC ROM is paged in
; during USR): the loading screen, then the compressed pack banks (each
; loaded to $8000 and unpacked to $C000 in its bank), bank 2 (loaded into
; bank 7, unpacked to $8000) and last the resident part of bank 5 (likewise,
; to $5B00), which overwrites BASIC itself - so it never returns, but jumps
; into the game.
;
; While loading, interrupts (the ROM loader re-enables them) go through an
; IM2 table at $BE00 to a bare EI / RETI at $BFBF, so nothing writes to the
; BASIC system variables that the last block replaces. The table's 257th
; byte is this loader's first byte, $BF (CP A).
; ---------------------------------------------------------------------------
        ORG $BF00
Loader:
        cp a                    ; ($BF: last byte of the IM2 vector table)
        ; 128K? page bank 1 and bank 3 in turn and see if they differ; if
        ; not, back to BASIC, which says why
        ld bc, $7FFD
        ld a, $11
        out (c), a
        ld a, $55
        ld ($C000), a
        ld a, $13
        out (c), a
        ld a, $AA
        ld ($C000), a
        ld a, $11
        out (c), a
        ld a, ($C000)
        cp $55
        ret nz
        di
        ld sp, $C000
        ld hl, $BE00            ; IM2 table -> $BFBF: EI, RETI
        ld de, $BE01
        ld bc, 256
        ld (hl), $BF
        ldir
        ld a, $BE
        ld i, a
        im 2
        ld hl, Blocks
.blk:   ld a, (hl)              ; $7FFD value while loading ($FF: end)
        inc a
        jr z, .go
        dec a
        ld bc, $7FFD
        out (c), a
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)              ; length on tape
        inc hl
        ld c, (hl)
        inc hl
        ld b, (hl)              ; load address
        inc hl
        push hl
        push bc
        push bc
        pop ix
        ld a, $FF               ; data block
        scf                     ; load (not verify)
        call $0556              ; LD-BYTES
        pop bc
        pop hl
        jp nc, 0                ; tape error: start again
        ld a, (hl)              ; $7FFD value while unpacking ($FF: stored)
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)              ; unpack to
        inc hl
        inc a
        jr z, .blk
        dec a
        push hl
        push bc
        ld bc, $7FFD
        out (c), a
        pop hl
        call UnLZ
        pop hl
        jr .blk
.go:    di
        jp GAME_START

; GAME_START; Blocks: per block the $7FFD value while loading, the length,
; the load address, the $7FFD value while unpacking ($FF: stored as it is)
; and where to unpack it; $FF ends
        INCLUDE "loader_table.asm"

        ASSERT $ <= $BFBF
        ORG $BFBF
        ei
        reti

; HL = packed data (tools/make_screens.py format), DE = destination
UnLZ:   ld a, (hl)
        inc hl
        cp $FF
        ret z
        cp $80
        jr nc, .match
        inc a
        ld c, a
        ld b, 0
        ldir
        jr UnLZ
.match: sub $80 - 3
        ld c, a
        ld b, 0
        ld a, (hl)
        inc hl
        push hl
        ld h, (hl)
        ld l, a
        push de
        ex de, hl
        or a
        sbc hl, de
        pop de
        ldir
        pop hl
        inc hl
        jr UnLZ
LoaderEnd:
        ASSERT $ <= $BFEC               ; (the stack is above: at most ~14 bytes deep)
