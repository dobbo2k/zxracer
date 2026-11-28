; ---------------------------------------------------------------------------
; Tape loader for zxracer.tap (assembled on its own by tools/make_tap.py).
;
; The BASIC loader loads this to $BE00 and calls it (LET e = USR 48640).
; It checks for 128K paging (if there is none it returns 1, and BASIC says
; "128K ONLY"), then
; reads the rest of the tape itself - standard ROM-format blocks at the
; normal speed, but with its own loading routine, so it does not depend on
; which ROM is paged in (128K, +2, +2A, +3 alike) and keeps interrupts off
; throughout, filling a progress bar along the loading screen's bottom row.
; The blocks: the loading screen, then the compressed (tools/zpack.py) pack
; banks (each loaded to $8000 and unpacked to $C000 in its bank), bank 2
; (loaded into bank 7, unpacked to $8000) and last the resident part of
; bank 5 (likewise, to $5B00), which overwrites BASIC itself - so it never
; returns, but jumps into the game. A tape error returns 10 + the block's
; number to BASIC, which reports it (nothing has been loaded over BASIC's own
; memory before the last block, and BASIC's paging is restored from BANK_M).
; ---------------------------------------------------------------------------
; Bit timings (the turbo build, for the .tzx: data bits in 420 / 840 T
; pulses instead of 855 / 1710, and a shorter settling delay while reading
; them; the pilot and sync stay the ROM's)
        IFDEF TURBO
DATA_DELAY      EQU 6               ; Edge1's settling delay for data bits
BIT_B           EQU $B0             ; ReadByte's count start per bit ...
BIT_B0          EQU $B3             ; ... the first (after the byte's bookkeeping)
BIT_TH          EQU $BE             ; longer than this: a 1
        ELSE
DATA_DELAY      EQU 22
BIT_B           EQU $B0
BIT_B0          EQU $B2
BIT_TH          EQU $CB
        ENDIF
PILOT_DELAY     EQU 22

        ORG $BE00
Loader:
        di
        ld (BasicSP), sp
        ; 128K? page bank 1 and bank 3 in turn and see if they differ
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
        jr z, .is128
        ld bc, 1                ; (BASIC prints "128K ONLY")
        jr Back
.is128: ld sp, $C000
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
        ld a, (BlockNo)
        inc a
        ld (BlockNo), a
        call LoadBlock
        pop bc
        pop hl
        jr nc, .fail
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
        call Unpack
        pop hl
        jr .blk
.go:    xor a
        out ($FE), a            ; black border
        jp GAME_START
.fail:  ld a, (BlockNo)         ; tape error: 10 + the block number to BASIC
        add a, 10
        ld c, a
        ld b, 0
; BC = what USR returns: back to BASIC with its stack, paging and interrupts
Back:   ld sp, (BasicSP)
        ld a, ($5B5C)           ; BANK_M: BASIC's last $7FFD value
        push bc
        ld bc, $7FFD
        out (c), a
        pop bc
        xor a
        out ($FE), a
        ei
        ret

BasicSP:        dw 0
BlockNo:        db 0

; IX = address, DE = length: load the next standard data block (flag $FF,
; then the data, then a checksum making the XOR of all of them 0). Carry
; set if it loaded correctly. Keeps waiting while there is no signal.
LoadBlock:
        ld a, PILOT_DELAY
        ld (Edge1 + 1), a
        ld a, $7F
        in a, ($FE)
        rra
        and $20
        or $02                  ; C: bit 5 = last EAR level, bits 0-2 = border
        ld c, a
.wait:  ld h, 0                 ; leader: 256 cycles of the pilot tone in a row
.lead:  ld b, $9C
        call Edge2
        jr nc, .wait
        ld a, $C6
        cp b
        jr nc, .wait            ; too short for the pilot tone
        inc h
        jr nz, .lead
.sync:  ld b, $C9               ; then the short sync pulse
        call Edge1
        jr nc, .wait
        ld a, b
        cp $D4
        jr nc, .sync            ; still the pilot tone
        call Edge1
        ret nc
        ld a, DATA_DELAY        ; (the data bits' timing)
        ld (Edge1 + 1), a
        ld a, c
        xor $03                 ; blue / yellow stripes from now on
        ld c, a
        ld h, 0                 ; H: XOR of the bytes so far
        call ReadByte           ; the flag
        ret nc
        ld a, l
        inc a
        jr z, .data
        and a                   ; not a data block: carry clear
        ret
.data:  call ReadByte
        ret nc
        ld (ix + 0), l
        inc ix
        dec de
        ld a, e
        or a
        call z, Tick            ; every 256 bytes
        ld a, d
        or e
        jr nz, .data
        call ReadByte           ; the checksum
        ret nc
        ld a, h
        cp 1                    ; carry: the XOR is 0
        ret

; Every 256 bytes after the loading screen: every TICK_N-th time, one more
; cell of the progress bar along its bottom row
Tick:   ld a, (BlockNo)
        cp 2
        ret c
        push hl
        ld hl, TickN
        dec (hl)
        jr nz, .t
        ld (hl), TICK_N
        ld hl, (BarPtr)
        ld (hl), BAR_ATTR
        inc hl
        ld (BarPtr), hl
.t:     pop hl
        ret
BAR_ATTR        EQU $70             ; bright yellow
BarPtr:         dw $5AE0            ; row 23
TickN:          db TICK_N

; -> L = the next byte (H ^= it), carry set; carry clear on a timeout
ReadByte:
        ld l, 1                 ; marker bit: shifts out after 8 bits
        ld b, BIT_B0            ; (a little time was spent since the last bit)
.bit:   call Edge2              ; a full cycle: 855 T pulses for 0, 1710 T for 1
        ret nc
        ld a, BIT_TH
        cp b                    ; carry if it took longer than the threshold
        rl l
        ld b, BIT_B
        jr nc, .bit
        ld a, h
        xor l
        ld h, a
        scf
        ret

; Wait for two edges / one edge of the EAR signal, counting B up once per
; 59 T after a short settling delay; carry clear if B wraps (no edge in
; time) or SPACE is held. Each edge flips the border stripe colour.
Edge2:  call Edge1
        ret nc
Edge1:  ld a, PILOT_DELAY        ; (set per block part: LoadBlock)
.d:     dec a
        jr nz, .d
        and a
.lp:    inc b
        ret z
        ld a, $7F
        in a, ($FE)             ; bit 6: EAR; bit 0: SPACE
        rra
        ret nc
        xor c
        and $20
        jr z, .lp
        ld a, c                 ; an edge: note the new level
        cpl
        ld c, a
        and 7
        or 8
        out ($FE), a
        scf
        ret

        INCLUDE "unpack.asm"

; GAME_START; Blocks: per block the $7FFD value while loading, the length,
; the load address, the $7FFD value while unpacking ($FF: stored as it is)
; and where to unpack it; $FF ends
        INCLUDE "loader_table.asm"
LoaderEnd:
        ASSERT $ <= $BFE0               ; (the stack is above, from $BFFF)
