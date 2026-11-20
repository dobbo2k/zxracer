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
SpeedFrac:      db 0            ; (fraction: Speed.SpeedFrac is 8.8)
Speed:          db 0
OffRoad:        db 0
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
RowStaleCar:    db 0            ; stale kerb cells under the car (car rows)
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
CurveList:      ds 2 + 3 * MAX_BOUNDS + 1

; track
SegPtr:         dw 0
SegStart:       dw 0
SegCurve:       db 0
PXFrac:         db 0
LatVX:          dw 0            ; sideways speed, 1/256 pixel per 50 Hz frame
LatAcc:         dw 0            ; its change per frame this update
LatF:           dw 0            ; curvature * speed
Sliding:        db 0            ; past the grip limit
Gear:           db 0            ; 0 LOW, 1 HIGH
FireWas:        db 0            ; fire held last update (gear changes on a press)
CrewHerLine:    dw MsgNone      ; what they say after this crash
CrewHisLine:    dw MsgNone
CrewShownA:     db 0            ; the close-ups are on buffer A / B
CrewShownB:     db 0
OldA:           db 0
OldB:           db 0
OldC:           db 0
OldD:           db 0

; scenery
ObjFirst:       dw 0            ; first object not yet passed
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
StateTimer:     db 0
Score:          ds 4            ; BCD, low byte first
Message:        dw MsgAttract
MsgLast:        dw MsgLastA
MsgLastA:       dw 0            ; message each buffer shows
MsgLastB:       dw 0
HudOr:          db 0
HudCache:       dw HudCacheA
HudCacheA:      db $FF, $FF, $FF, $FF, $FF, $FF, $FF    ; score, time, speed, gear shown
HudCacheB:      db $FF, $FF, $FF, $FF, $FF, $FF, $FF

; traffic and collisions
Traffic:        ds N_TRAFFIC * CAR_SIZE
ObjType:        db 0
CrashTimer:     db 0
SfxTimer:       db 0
SfxType:        db 0
RandSeed:       dw $A5C3
EnginePeriod:   dw ENGINE_IDLE
CarDirty:       db 1            ; something wrote into the car block this frame
CarAttrDirty:   db 1
CarShown:       dw CarShownA
CarShownA:      db $FF          ; car frame each buffer shows
CarShownB:      db $FF
DemoNear:       dw 0
DemoAim:        dw 0

; stage
Stage:          db 0            ; index into StageTable
StageRow:       db 1            ; row of the pyramid (shown as STAGE n)
StageLen:       dw $FFFF
StageDone:      db 0
StTrack:        dw 0            ; from the track pack header
StObjects:      dw 0
StTypeDir:      dw 0            ; from the theme pack header
StPano:         dw 0
StName:         dw 0
Palette:                        ; from the theme pack header (9 bytes, this order)
PalSky:         db ATTR_SKY
PalPano:        db ATTR_PANO
PalHud:         db ATTR_HUD
PalTime:        db ATTR_TIME
PalGrassL:      db ATTR_GRASS_L
PalGrassD:      db ATTR_GRASS_D
PalKerbL:       db ATTR_KERB_L
PalKerbD:       db ATTR_KERB_D
PalRoad:        db ATTR_ROAD
MsgBuf:         ds MSG_LEN
                db 0
; hills
HillOr:         db 0            ; any hill in view
HillC:          db 0            ; hill value of the current pass-1 chunk
P1Hill:         db 0            ; the pass-1 tables were built with hills
HmPtr:          dw 0            ; HillMap: next boundary, zone, weight, increment
HmZone:         dw 0
HmK:            db 0
HillNf:         db 0            ; screen pairs 0 .. HillNf - 1 still free
HillTopJ:       db 0            ; furthest depth line on screen
FkD2:           db $FF          ; second span of the line ForkLine computed
FkE2:           db 0

; fork
HasFork:        db 0            ; this stage ends in a fork (not the last row)
ForkZ:          dw 0            ; where the road splits
ForkLim:        db 0            ; lines 0 .. ForkLim - 1 are past the split
P1ForkLim:      db 0            ; (even) ForkLim the pass-1 tables were built with
PlayerDx:       dw 0            ; how far the car's branch has moved out
ForkFD:         dw 0            ; depth of the split (negative: passed)
FkAcc:          ds 3            ; ForkLine's offset accumulator (16.8)
Fk2C1:          dw 0
FkOff:          dw 0
FkX1:           dw 0
ForkNK:         db 0
ForkNC:         db 0
ForkBL:         db 0
ForkBH:         db 0
HiScore:        db $00, $00, $02, $00   ; BCD, low byte first (20000 to beat)
Mute:           db 0            ; title / goal screens: the game's sound is off
GoalPending:    db 0            ; the goal was reached: show its screen
AttractTimer:   dw 0            ; game frames of demo left before the title
LdBank:         db 0
LdSrc:          dw 0
LdDst:          dw 0
LdLen:          dw 0
