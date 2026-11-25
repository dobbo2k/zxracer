; ---------------------------------------------------------------------------
; CPC: the frame's drawing, the palette and the display reset
; ---------------------------------------------------------------------------

        INCLUDE "road.asm"
        INCLUDE "cells.asm"
        INCLUDE "sprites.asm"

; The road and the panorama into the hidden screen
CpcDraw:
        call CpcRoad
        jp CpcHorizon


; (The shared code's hooks, NATIVE_GFX: GfxMarkCell, GfxMarkBig,
; GfxLampCells in src/cpc/cells.asm; GfxScreensEnter, GfxFrontOn, GfxPicture
; in src/cpc/front.asm)

; (The panorama, the portal, the palette and the display reset: src/cpc/reset.asm, in bank 2)
