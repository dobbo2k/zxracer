; ---------------------------------------------------------------------------
; Tatung Einstein platform (docs/port_einstein.md): included by src/main.asm
; when assembled with -DEINSTEIN. The game runs at its Spectrum addresses
; ($4000-$BFFF); this file adds the COM file's entry, the Einstein's own code
; below them and its buffers above.
;
; Memory:
;   $0100        the COM file's entry (a jump: XtalDOS runs a COM from here)
;   $0120        THEME_CACHE (build/einstein/packs.asm), then PANO_CACHE
;   EIN_CODE     this platform code, then the stage art
;   $4000-$5AFF  the between-stages overlay, resident, and its scratch
;   $5B00-$BFFF  the game, as on the Spectrum (bank 5's part and bank 2)
;   $C000-$DAFF  the Spectrum's screen B: drawing code that still runs here
;                writes into it, harmlessly (SelectBackBuffer points it there)
;   $DB00-$EBFF  the Einstein's buffers (EIN_BUF)
;   $EC00-       XtalDOS (kept, for loading from the disc later)
;
; Hardware facts are from Albert's core (the einstein repository's
; emulator/src/core) and the Wonder Boy port's src/platform/einstein.
; ---------------------------------------------------------------------------

; Ports
EIN_PSG_SELECT  EQU $02             ; AY register latch
EIN_PSG_READ    EQU $02             ; (read: the latched register)
EIN_PSG_WRITE   EQU $03             ; AY data
EIN_VDP_DATA    EQU $08             ; TMS9129 VRAM data
EIN_VDP_CTRL    EQU $09             ; TMS9129 address / register; read: status
EIN_CTC0        EQU $28             ; Z80 CTC channels 0-3
EIN_CTC2        EQU $2A
EIN_CTC3        EQU $2B

; VRAM (Graphics II)
VRAM_PAT        EQU $0000           ; patterns: three thirds of 256 x 8 bytes
VRAM_NAMES      EQU $1800           ; the name table (32 x 24)
VRAM_SPRATTR    EQU $1B00           ; sprite attributes
VRAM_COL        EQU $2000           ; colours: three thirds of 256 x 8 bytes
VRAM_SPRPAT     EQU $3800           ; sprite patterns

; The screen's patterns:
;   rows 0-9, the sky (the HUD, the message line, the sky's artwork): a
;     mirror of the Spectrum's screen B, which the game's own HUD and sky
;     code still draws; a cell is sent again when that code writes it
;     (EinMarkCell). Rows 0-7 are the top third's 256 patterns, one each;
;     rows 8-9 the middle third's 64-127.
;   rows 10-11, the panorama: the middle third's 128-255, its two copies
;     (4 pixels apart) sent once a stage; it scrolls by its names alone.
;   rows 12-23, the road: names 0-15 are solid cells of TMS colours 0-15
;     (pattern 0, the colour behind it) in the middle and bottom thirds, and
;     slots from 16, patterns made each frame (silhouettes', and the road's
;     where it is drawn the exact way: a fork's row, a tunnel's, one whose
;     road is in one cell): rows 12-15 5 each, rows 16-23 22 each. The kerb's
;     edges are ready-made patterns (EinStaticInit), 7 left edges and 7 right
;     in the open road's light and dark kerb: the middle third's KERB_T1 on,
;     the bottom third's KERB_T2 on. The player's car is CAR_PAT on (224).
;   the centre line: sprites, one a road row (src/einstein/roadgfx.asm
;     EinDashRow), its pixels exact at any x.
SLOTS_T1        EQU 5
SLOTS_T2        EQU 22
SLOT_FIRST      EQU 16
N_SLOTS         EQU 4 * SLOTS_T1 + 8 * SLOTS_T2     ; 196 in all
SLOT_SIZE       EQU 9               ; 8 pattern bytes, the colour byte
KERB_N          EQU 2 * 14                          ; kerb edges: light, dark
KERB_T1         EQU SLOT_FIRST + 4 * SLOTS_T1       ; 36: the middle third's
KERB_T2         EQU SLOT_FIRST + 8 * SLOTS_T2       ; 192: the bottom third's
        ASSERT KERB_T1 + KERB_N <= SKY_PAT_T1
SKY_PAT_T1      EQU 64              ; rows 8-9's patterns in the middle third
PANO_PAT        EQU 128             ; the panorama's
MIRROR_ROWS     EQU 10

; Buffers (not in the COM file)
EIN_BUF         EQU $DB00
NameBuf         EQU EIN_BUF                     ; the names as drawn (768)
SlotShadow      EQU NameBuf + 768               ; the slots in VRAM (N_SLOTS x 9)
DirtyList       EQU SlotShadow + N_SLOTS * SLOT_SIZE    ; per changed slot, row by row:
                                                ; its slot in the row, what changed
EDirtyRowN      EQU DirtyList + N_SLOTS         ; per road row: its changed slots
EMirrorBits     EQU EDirtyRowN + 12             ; the sky's cells to be sent: a bit each
EIN_CMDLISTB    EQU EMirrorBits + MIRROR_ROWS * 4   ; the Spectrum's buffer B commands
EIN_BUF_END     EQU EIN_CMDLISTB + 1 + MAX_SPR * CMD_SIZE
; The centre line's sprites, per road row (EinDashRow, EinDashFinish)
EDashX          EQU EIN_BUF_END                 ; its leftmost pixel ($FF: none)
EDashNew        EQU EDashX + 12                 ; drawn again this frame
EDashB          EQU EDashNew + 12               ; its road cells' range when drawn
EDashC          EQU EDashB + 12
EDashSend       EQU EDashC + 12                 ; its patterns to be sent
EDashOut        EQU EDashSend + 12              ; its pixels as VRAM holds them: lines
                                                ; 0-3's left and right bytes, 4-7's
EDashQ          EQU (EDashOut + 12 * 4 + 31) & $FFE0    ; the same as its sprite's
                                                ; first 24 bytes (32 a row): what
                                                ; EinDashSend sends
EDashAttr       EQU EDashQ + 12 * 32            ; the attributes, as VRAM holds them
EDashEnd        EQU EDashAttr + 12 * 4 + 1      ; (then $D0: no more sprites)
ECarCol         EQU (EDashEnd + 7) & $FFF8      ; the car's colours (a cell's 8 in
        ASSERT ECarCol + 4 * CAR_W * 8 <= $EC00 ; one page: EinCarGroundSync)

; Buffers in the Spectrum's screen A ($4000-$5AFF), around the resident stage
; overlay: every one is made afresh by EinResetDisplay, which follows every
; stage load (whose scratch, ART_INPUT on, they share) and the front end
; (which draws over all of screen A). Nothing else writes screen A in play
; (Ceiling and TimeWarn write screen B alone here).
STAGEOV_END     EQU $4800               ; (the overlay below: src/main.asm)
BaseNames       EQU $4800               ; rows 10-23 as the road and panorama draw them
        ASSERT (BaseNames & 31) == 0    ; (a row never crosses a page: EinFillRun)
ESkyAttr        EQU $4A00               ; sky rows 3-9's attributes sent (portal.asm)
EMaskP          EQU ESkyAttr + (PANO_ROW0 - 3) * 32     ; the portal's cells, this frame
EMaskPOld       EQU EMaskP + 24 * MASK_ROW              ; and the last
EMaskN          EQU EMaskPOld + 24 * MASK_ROW           ; the silhouettes' cells
EMaskU          EQU EMaskN + 24 * MASK_ROW              ; and last frame's with them
EPanoSpr        EQU $5680               ; the panorama's cells under silhouettes (64 x 8)
EPanoList       EQU EPanoSpr + 64 * 8   ; (64)
ERowSig         EQU EPanoList + 64      ; per road row: what it was drawn from
ERowFk          EQU ERowSig + 12 * SIG_SIZE ; per road row: drawn as a fork
        ASSERT BaseNames + (24 - PANO_ROW0) * 32 <= ESkyAttr
        ASSERT EMaskU + 24 * MASK_ROW <= EPanoSpr
ECarSourceInks  EQU $5A00               ; the car's pose's colours as drawn (paper
                                        ; 0: transparent; page-aligned: EinCarGroundSync
                                        ; steps L), made afresh with the pose after
                                        ; every display reset (CarShownB)
        ASSERT ERowFk + 12 <= ECarSourceInks
        ASSERT ART_BITMAP + 512 + 640 <= EPanoSpr

; The stage loader tail-calls resident code before its RAM becomes the sky.
ESkyPixels      EQU STAGEOV_AT
EPanoInkBuf     EQU $4D00
ESkyInks        EQU $4F00
EObjectUpper    EQU $4700       ; cells in rows 4..11
EObjectLower    EQU (ECarCol + 256 + 255) & $FF00 ; cells in rows 12..23
        ASSERT (EObjectUpper & 255) == 0       ; (page-aligned: EinMaterialCell)
EObjectInks     EQU ESkyInks + 7 * 256
        ASSERT ESkyPixels + 7 * 256 <= EObjectUpper
        ASSERT EObjectUpper + 256 <= BaseNames
        ASSERT EObjectLower + 384 <= $EC00
EGroundPatterns EQU EObjectInks + 33
EGroundPapers   EQU EGroundPatterns + 32
        ASSERT EGroundPapers + 2 <= EPanoSpr
        ASSERT EMaskU + 24 * MASK_ROW <= EPanoInkBuf
        ASSERT EPanoInkBuf + 512 <= ESkyInks
        ASSERT ESkyInks + 7 * 256 <= EPanoSpr
        ORG $0100
        jp EinBoot              ; (the theme cache follows at THEME_CACHE)

        ORG EIN_CODE
        INCLUDE "boot.asm"
        INCLUDE "vdp.asm"
        INCLUDE "roadgfx.asm"
        INCLUDE "flip.asm"
        INCLUDE "sky.asm"
        INCLUDE "sprites.asm"
        INCLUDE "portal.asm"
        ; (keys.asm, disc.asm, front.asm: in bank 2's code, src/main.asm)
EinArt:                         ; (the end of the platform code)
        ASSERT $ <= $4000              ; (the stage overlay: src/main.asm)
