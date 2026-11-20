; Starting lights, continued (see lights.asm). In a gap of bank 2.
; Each update, after the input: count down, show the lamps, hold the car
; (no control, no time passing) until green
LightsHold:
        ld a, (Lights)
        or a
        ret z
        ld hl, Elapsed
        sub (hl)
        jr nc, .t
        xor a
.t:     ld (Lights), a
        ld hl, LightSteps       ; -> C: 0 all off, 1-3 lamps red, 4 green, 5 gone
        ld c, 0
.s:     cp (hl)
        jr nc, .st
        inc hl
        inc c
        jr .s
.st:    ld a, (LampState)
        cp c
        ld a, c
        ld (LampState), a
        call nz, LampChange
        ld a, (LampState)
        cp 4
        ret nc
        xor a
        ld (Input), a
        ld (SecTick), a
        ret
LightSteps:     db 190, 140, 90, LIGHTS_GO, 1, 0
