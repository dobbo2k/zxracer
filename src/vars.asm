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
DemoMode:       db 1            ; attract mode until a steering key is pressed
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
RowRW0:         db 0
RowRW1:         db 0
Pass1PX:        dw $8000        ; PlayerX the pass-1 tables were built for
LastStraight:   db 0
RoadStraight:   db 0
CurveOr:        db 0
CurvePtr:       dw 0
CurC:           db 0            ; curvature of the current pass-1 chunk
CurK:           db 0            ; curvature zone (weight 2^k / 4)
ZonePtr:        dw 0
CurveList:      ds 1 + 2 * MAX_BOUNDS + 1

; track
SegPtr:         dw Track
SegStart:       dw 0
SegCurve:       db 0
PXFrac:         db 0
OldA:           db 0
OldB:           db 0
OldC:           db 0
OldD:           db 0

; scenery
ObjFirst:       dw Objects      ; first object not yet passed
ObjZ:           dw 0
ObjX:           db 0
ObjI:           db 0
SprW:           db 0
SprH:           db 0
SprMask:        db 0
SprN:           db 0
SprSkip:        db 0
SprSrc:         dw 0
SprStride:      dw 0
CmdPtr:         dw 0
CmdList:        dw CmdListA
CmdListA:       db 0
                ds MAX_SPR * CMD_SIZE
CmdListB:       db 0
                ds MAX_SPR * CMD_SIZE

; horizon
HorizonX:       dw 0            ; scroll, 8.8 pixels
PanoLast:       dw PanoLastA
PanoLastA:      db $FF          ; scroll each buffer shows ($FF: none yet)
PanoLastB:      db $FF

; game
GameState:      db ST_ATTRACT
Time:           db START_TIME   ; BCD seconds
SecTick:        db 0
LapFlag:        db 0
StateTimer:     db 0
Score:          ds 4            ; BCD, low byte first
Message:        dw MsgAttract
MsgLast:        dw MsgLastA
MsgLastA:       dw 0            ; message each buffer shows
MsgLastB:       dw 0
HudOr:          db 0
