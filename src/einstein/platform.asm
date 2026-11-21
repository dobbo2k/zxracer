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
;     the road's own patterns are slots from 16: rows 12-15 12 each, rows
;     16-23 24 each.
SLOTS_T1        EQU 12
SLOTS_T2        EQU 24
SLOT_FIRST      EQU 16
N_SLOTS         EQU 4 * SLOTS_T1 + 8 * SLOTS_T2     ; 240 in all
SLOT_SIZE       EQU 9               ; 8 pattern bytes, the colour byte
EPicBuf         EQU THEME_CACHE + 4352  ; a picture from the disc, after the front end's
                                        ; code (make_stages.py FRONTEND_RESERVE)
SKY_PAT_T1      EQU 64              ; rows 8-9's patterns in the middle third
PANO_PAT        EQU 128             ; the panorama's
MIRROR_ROWS     EQU 10
EMIRROR_MAX     EQU 240             ; cells waiting to be sent (a tunnel's ceiling: 224)

; Buffers (not in the COM file)
EIN_BUF         EQU $DB00
NameBuf         EQU EIN_BUF                     ; the names as drawn (768)
SlotShadow      EQU NameBuf + 768               ; the slots in VRAM (N_SLOTS x 9)
DirtyList       EQU SlotShadow + N_SLOTS * SLOT_SIZE    ; (slot, what) per changed slot
EMirror         EQU DirtyList + 2 * N_SLOTS     ; (row, column) per sky cell written
EIN_CMDLISTB    EQU EMirror + 2 * EMIRROR_MAX   ; the Spectrum's buffer B commands
EIN_BUF_END     EQU EIN_CMDLISTB + 1 + MAX_SPR * CMD_SIZE
        ASSERT EIN_BUF_END <= $EC00

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
