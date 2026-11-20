; ---------------------------------------------------------------------------
; Starting lights: at the start of a game three lamps over the road light up
; red one by one, with a beep each, then all turn green - GO - with a higher
; one. Until then the car is held and the clock stands still.
; Small pieces in the gaps of bank 2 (src/main.asm): this file,
; lightshold.asm; LampDraw and the lamp in bank 5 (lampdraw.asm).
; ---------------------------------------------------------------------------
LIGHTS_TIME     EQU 230             ; 50 Hz frames
LIGHTS_GO       EQU 40              ; green (and go) from here; the lamps go at 0
LAMP_ROW        EQU 3
LAMP_COL        EQU 11              ; lamps at columns 11, 15, 19 (2 x 2 cells)
BEEP_RED        EQU 400             ; tone periods
BEEP_GREEN      EQU 200

; StartGame: the lights from the start
LightsStart:
        ld a, LIGHTS_TIME
        ld (Lights), a
        ld a, $FF
        ld (LampState), a
        ret

; A = C = the new lamp state: beep, draw
LampChange:
        or a
        jp z, LampDraw          ; (all off, at first: no beep)
        cp 5
        jp z, LampDraw          ; (gone)
        ld de, BEEP_RED
        cp 4
        jr c, .bp
        ld de, BEEP_GREEN
.bp:    push bc
        call StartBeep
        pop bc
        jp LampDraw
