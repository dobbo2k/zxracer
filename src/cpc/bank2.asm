; ---------------------------------------------------------------------------
; CPC: code in bank 2 (in the room the Spectrum's drawing code leaves)
; ---------------------------------------------------------------------------
        INCLUDE "front.asm"
        INCLUDE "reset.asm"

; (The tests, tests/cpc_check.py) A = 1 + a stage: the demo from its start
CStageReq:      db 0
CStageGo:
        dec a
        push af
        xor a
        ld (CStageReq), a
        pop af
        jp RestartAt
