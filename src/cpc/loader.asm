; ---------------------------------------------------------------------------
; The CPC disc's loader, SPEED.BIN (assembled on its own: make cpc).
;
; RUN"SPEED" has AMSDOS load this at $1000 and run it: it moves itself to
; $C000 (base 3, the firmware's screen: the firmware clears that as it
; starts a program, so it is not loaded there). With the firmware and both
; ROMs gone and interrupts off for
; good, it reads the game's image from SPEED.DAT with the game's own disc
; code (src/cpc/fdc.asm): base 0's part, packed, into bank 4 and base 2's
; into bank 5 (each at $4000, RAM configurations C4 and C5, which keep base
; 3 at $C000), then unpacks them to $0000 and $8000 (tools/zpack.py's
; format) and starts the game (src/cpc/boot.asm CpcBoot, by the jump at
; $0000). Bank 7 starts empty: the game fills it.
; ---------------------------------------------------------------------------
        DEVICE NOSLOT64K
        DEFINE FDC_LOADER       ; (fdc.asm: interrupts stay off)
        INCLUDE "loader_defs.asm"       ; (build/cpc: where the image is)

GA_PORT         EQU $7F00
GA_COLOUR       EQU $40
HW_BLACK        EQU $14
PPI_CONTROL     EQU $F700

LOAD_AT         EQU $1000

        ORG LOAD_AT
        di
        ld hl, LOAD_AT + Moved - Start
        ld de, $C000
        ld bc, LoaderEnd - Loader
        ldir
        jp Loader
Moved:
Start   EQU LOAD_AT
        DISP $C000
Loader:
        ld sp, 0                ; (from $FFFF down: base 3, the loader's)
        ld bc, GA_PORT | $8C    ; mode 0, both ROMs off
        out (c), c
        ld e, 16                ; every pen and the border black
.pen:   out (c), e
        ld a, GA_COLOUR | HW_BLACK
        out (c), a
        dec e
        jp p, .pen
        ld bc, PPI_CONTROL | $82
        out (c), c
        ld hl, Crtc             ; the game's screen: 64 bytes a line, 24 rows
        ld e, 0
.crtc:  ld b, $BC
        out (c), e
        ld b, $BD
        ld a, (hl)
        out (c), a
        inc hl
        inc e
        ld a, e
        cp 14
        jr c, .crtc
        call FdcStart
        ld a, $C0               ; the loading screen: packed into base 0, then
        ld hl, LOADING_SECTOR   ; into base 1 (C0) and shown, its inks with it
        ld b, LOADING_SECTORS
        call ReadBase0
        ld hl, $0000
        ld de, $4000
        call Unpack
        ld hl, $4600
        ld bc, GA_PORT
        xor a
.ink:   out (c), a
        ld e, (hl)
        inc hl
        set 6, e
        out (c), e
        inc a
        cp 17
        jr c, .ink
        ld a, $C4               ; base 0's part into bank 4
        ld hl, IMAGE_BASE0_SECTOR
        ld b, IMAGE_BASE0_SECTORS
        call Read
        ld a, $C5               ; base 2's into bank 5
        ld hl, IMAGE_BASE2_SECTOR
        ld b, IMAGE_BASE2_SECTORS
        call Read
        call FdcStop
        ld bc, GA_PORT | $C4
        out (c), c
        ld hl, $4000
        ld de, $0000
        call Unpack
        ld bc, GA_PORT | $C5
        out (c), c
        ld hl, $4000
        ld de, $8000
        call Unpack
        jp $0000                ; (jp CpcBoot)

; HL = a logical sector, B = how many: read to $0000 on (C0)
ReadBase0:
        ld de, $0000
        jr ReadAt
; A = a RAM configuration, HL = a logical sector, B = how many: read to
; $4000 on
Read:   ld de, $4000
ReadAt: ld (.to + 1), de
        ld (.n + 1), a
        ld a, b
        ld (Count), a
.n:     ld bc, GA_PORT          ; (C patched)
        out (c), c
        call FdcPlace
.to:    ld hl, $4000
.sec:   call FdcReadSector
        jr nc, .sec             ; (till it reads)
        call FdcNext
        ld a, (Count)
        dec a
        ld (Count), a
        jr nz, .sec
        ret
Count:  db 0
; R0-R13: the game's (src/cpc/boot.asm CpcCrtc), base 1 shown
Crtc:   db 63, 32, 42, $8E, 38, 0, 24, 30, 0, 7, 0, 0, $10, 0

; A sector that will not read: the border red till one does
FdcFailed:
        ld a, GA_COLOUR | $0C
        jr Border
FdcRecovered:
        ld a, GA_COLOUR | HW_BLACK
Border: ld bc, GA_PORT | $10
        out (c), c
        out (c), a
        ret

        INCLUDE "fdc.asm"

; HL = packed data, DE = where it goes: unpacked (src/loader.asm's Unpack)
Unpack: ld a, $80
.lit:   call Gamma              ; a literal run
        ldir
        call GetBit
        jr c, .new
        call Gamma              ; a repeat match: the last offset again
.copy:  push hl
        push bc
        ld bc, (LastOff)
        ld h, d
        ld l, e
        or a
        sbc hl, bc
        pop bc
        ldir
        pop hl
        call GetBit
        jr nc, .lit
.new:   call Gamma              ; a match: offset's high part + 1 (256: the end)
        inc b
        dec b
        ret nz
        dec c
        ld b, c
        ld c, (hl)
        inc hl
        inc bc
        ld (LastOff), bc
        call Gamma
        inc bc                  ; length
        jr .copy
; -> BC: an interlaced Elias-gamma number
Gamma:  ld bc, 1
.g:     call GetBit
        ret c
        call GetBit
        rl c
        rl b
        jr .g
; -> carry: the next bit
GetBit: add a, a
        ret nz
        ld a, (hl)
        inc hl
        rla
        ret
LastOff:        dw 0
LoaderEnd:
        ASSERT LoaderEnd <= $C600       ; (the first 2K's shown part)
        ENT
SpeedEnd:

        SAVEBIN "build/cpc/speed.bin", LOAD_AT, SpeedEnd - LOAD_AT
