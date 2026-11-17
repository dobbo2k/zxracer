; ---------------------------------------------------------------------------
; Variables
; ---------------------------------------------------------------------------
FrameCount:     db 0
LastFlip:       db 0
FlipPending:    db 0
FlipValue:      db 0
Port7FFD:       db 0
BackBuf:        db 1            ; buffer being drawn: 0 = A, 1 = B
BufHiOr:        db 0
AttrHi:         db 0
StatePage:      db 0

Input:          db 0
PlayerX:        dw 0
Speed:          db 0
Pos:            dw 0
LastLogic:      db 0
Elapsed:        db 0

; road renderer scratch
CurI:           db 0
CurRow:         db 0
RowCols:        ds 4
RowA:           db 0            ; RowA..RowD must stay consecutive
RowB:           db 0
RowC:           db 0
RowD:           db 0
RowBand:        db 0
RowForced:      db 0
RowMerged:      db 0
LcOL:           db 0
LcOR:           db 0
LcRL:           db 0
OldA:           db 0
OldB:           db 0
OldC:           db 0
OldD:           db 0
