; Small pieces in the gap before the interrupt vector (src/main.asm), moved
; here from bank 5 for room
Silence:
        ld e, 0
        ld a, 8
        call AyPut
        ld e, 0
        ld a, 9
        call AyPut
        ld e, 0
        ld a, 10
        jp AyPut

; Jingles (JingleTick, src/extend.asm): tone period, length (interrupts);
; 0 ends it. Extended play: a flourish (instead of the new stage's beep)
JingleExt:
        dw 212
        db 5                    ; C
        dw 168
        db 5                    ; E
        dw 141
        db 5                    ; G
        dw 106
        db 20                   ; C, an octave up
        dw 0
