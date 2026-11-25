; ---------------------------------------------------------------------------
; CPC: the frame's drawing, the palette and the display reset
; (docs/port_cpc.md section 8: the sprites, the sky and the HUD still to
; come)
; ---------------------------------------------------------------------------

        INCLUDE "road.asm"

; The road and the panorama into the hidden screen
CpcDraw:
        jp CpcRoad

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

; The Spectrum's colours (an attribute's paper or ink, with BRIGHT: 0-15)
; as the Gate Array's
SpecHw: db $14, $04, $1C, $18, $16, $06, $1E, $00     ; black blue red magenta green cyan yellow white
        db $14, $15, $0C, $0D, $12, $13, $0A, $0B     ; and bright

; A = an attribute -> A = its paper's hardware colour (with BRIGHT). HL used.
CpcPaper:
        ld l, a
        and $40
        rrca
        rrca
        rrca
        ld h, a
        ld a, l
        rrca
        rrca
        rrca
        and 7
        or h
        jr CpcHw
; A = an attribute -> A = its ink's hardware colour (with BRIGHT). HL used.
CpcInk: ld l, a
        and $40
        rrca
        rrca
        rrca
        ld h, a
        ld a, l
        and 7
        or h
CpcHw:  add a, low SpecHw
        ld l, a
        ld h, high SpecHw
        ld a, (hl)
        ret
        ASSERT high SpecHw == high (SpecHw + 15)

; The pens from the stage's palette (the Spectrum's attributes, Palette:
; src/vars.asm), until the CPC's own (docs/port_cpc.md phase A)
CpcPalette:
        ld ix, CPalSrc
        ld e, 0                 ; the pen
.pen:   ld l, (ix + 0)          ; its attribute's address (0: a colour)
        ld h, (ix + 1)
        ld a, h
        or l
        ld a, (ix + 2)          ; 0: its paper, 1: its ink; or the colour
        jr z, .set
        or a
        ld a, (hl)
        jr nz, .ink
        call CpcPaper
        jr .set
.ink:   call CpcInk
.set:   ld bc, GA_PORT
        out (c), e
        or GA_COLOUR
        out (c), a
        ld bc, 3
        add ix, bc
        inc e
        ld a, e
        cp 17
        jr c, .pen
        ret

; Per pen (and the border, 16): the attribute it takes its colour from, and
; 0 for its paper or 1 its ink; or 0 and the hardware colour
CPalSrc:
        dw PalRoad
        db 0                    ; 0 road: the road's paper
        dw 0
        db $14                  ; 1 black
        dw PalKerbL
        db 0                    ; 2 the light kerb
        dw PalKerbD
        db 0                    ; 3 the dark kerb
        dw PalGrassL
        db 0                    ; 4 light grass
        dw PalGrassD
        db 0                    ; 5 dark grass
        dw PalSky
        db 0                    ; 6 sky
        dw PalPano
        db 1                    ; 7 the panorama: its ink
        dw PalPano
        db 0                    ; 8 its paper
        dw TunWall
        db 0                    ; 9 a tunnel's light wall
        dw TunWall + 1
        db 0                    ; 10 its dark wall
        dw PalHud
        db 1                    ; 11 the HUD's ink
        dw PalTime
        db 1                    ; 12 the timer's ink
        dw PalRoad
        db 1                    ; 13 the centre line: the road's ink
        dw 0
        db $0A                  ; 14 a tunnel's lamps: bright yellow
        dw 0
        db $0B                  ; 15 bright white
        dw 0
        db $14                  ; the border: black

; Both screens cleared (A: the byte), C1 selected after
CpcClearBoth:
        ld e, a
        ld a, RAM_A
        call CpcClear
        ld a, RAM_B
        call CpcClear
        jp CpcSelect
; A = a RAM configuration: the screen it puts at $4000 cleared to E
CpcClear:
        ld bc, GA_PORT
        out (c), a
        ld (.sp + 1), sp
        ld b, e
        ld c, e
        di
        ld sp, $8000
        ld a, 32                ; 32 x 256 words
.l:     ld d, 0
.w:     push bc
        dec d
        jr nz, .w
        dec a
        jr nz, .l
.sp:    ld sp, 0
        ei
        ret

; (The end of OvResetDisplay) the stage's pens; both screens afresh
CpcResetDisplay:
        call CpcPalette
        ld a, (PenByte + PEN_SKY)
        jp CpcClearBoth
