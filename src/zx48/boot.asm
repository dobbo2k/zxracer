; BASIC loads $8000 upwards, then the ROM reads the low resident block
; directly over BASIC. The ROM's loader uses the relocated machine stack.
TapeEntry:
        di
        ld sp, STACK_TOP
        ld ix, SCN_DATA
        ld de, ScnEnd - SCN_DATA
        ld a, $FF
        scf
        call $0556
        jp nc, 0
        xor a
        out ($FE), a
