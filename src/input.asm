; ---------------------------------------------------------------------------
; Input: keys O/P steer, Q accelerate, A brake, SPACE fire; Kempston joystick
; ---------------------------------------------------------------------------

ReadInput:
        ld c, 0
        ld a, $DF               ; P O I U Y
        in a, ($FE)
        rra
        jr c, .noP
        set IN_RIGHT, c
.noP:   rra
        jr c, .noO
        set IN_LEFT, c
.noO:   ld a, $FB               ; T R E W Q
        in a, ($FE)
        rra
        jr c, .noQ
        set IN_UP, c
.noQ:   ld a, $FD               ; G F D S A
        in a, ($FE)
        rra
        jr c, .noA
        set IN_DOWN, c
.noA:   ld a, $7F               ; B N M SS SPACE
        in a, ($FE)
        rra
        jr c, .noSp
        set IN_FIRE, c
.noSp:  in a, ($1F)             ; Kempston; ignore if the bus floats high
        ld b, a
        and $E0
        jr nz, .noKemp
        ld a, b
        or c
        ld c, a
.noKemp:
        ld a, c
        ld (Input), a
        ret
