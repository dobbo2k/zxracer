; ---------------------------------------------------------------------------
; CPC: the frame's drawing (phase 0: stubs, docs/port_cpc.md section 8)
; ---------------------------------------------------------------------------

; The road and the panorama into the hidden screen
CpcDraw:
        ret

; Traffic and scenery from the command list, then the car
CpcSprites:
        ret

; The shadow's noted cells into the hidden screen
CpcCells:
        ret

; The shared code's hooks (NATIVE_GFX, src/defs.asm)
GfxMarkCell:                    ; a HUD cell written (src/hud.asm)
GfxMarkBig:                     ; a big digit's four (src/extend.asm)
        ret
GfxLampCells:                   ; the starting lamps' (src/lampdraw.asm)
        ret
GfxScreensEnter:                ; the front end's screens (src/frontend.asm)
        ret
GfxFrontOn:                     ; screen A shown
        ret
GfxPicture:                     ; a picture (src/pics.asm)
        ret

; (The end of OvResetDisplay) the shadow into both screens, the stage's pens
CpcResetDisplay:
        ret
