; ---------------------------------------------------------------------------
; Amstrad CPC 6128 platform (docs/port_cpc.md): included by src/main.asm
; when assembled with -DCPC. Bank 2's code and tables stay at $8000-$BFFF
; (base 2), bank 7 at $C000; the Spectrum's bank 5 residents move $4000
; lower, into base 0, with this platform code below them; the hidden screen
; is at $4000.
;
; Memory in play (Gate Array RAM configuration C1 or C3):
;   $0000        this platform code and its page-aligned tables
;   $1B00        SCN_DATA: bank 5's residents (src/main.asm)
;   $3DA0        TRACK_CACHE (build/cpc/packs.asm), to $3FFF
;   $4000-$7FFF  the hidden screen: base 1 (screen A, C1) or base 3
;                (screen B, C3). Mode 0, 128 x 192: line y at
;                $4000 + (y & 7) * $800 + (y >> 3) * 64; each 2K's last 512
;                bytes ($x600-$x7FF) are not shown: that screen's own state
;   $8000-$BFFF  base 2: the Spectrum's bank 2
;   $C000-$DAFF  bank 7: the Spectrum's screen B, never shown: a shadow the
;                shared code still draws the HUD, the messages and the
;                lamps into, converted cell by cell (src/cpc/cells.asm)
;   $DB00-$FFFF  THEME_CACHE, PANO_CACHE, CmdListB (as on the Spectrum)
;   banks 4-6    the disc's buffer (src/cpc/disc.asm)
;
; The hardware facts are from the Wonder Boy port's src/platform/cpc
; (C:\ZX Spectrum\Wonderboy: hardware.inc, screen.asm, sound.asm).
; ---------------------------------------------------------------------------

; Ports (every one addressed by B: OUT (C) with BC = port)
GA_PORT         EQU $7F00       ; Gate Array: %000ppppp pen (16: border),
GA_COLOUR       EQU $40         ; %010ccccc its colour, %100iurmm mode and ROMs,
GA_MODE0        EQU $8C         ; %11000ccc RAM configuration. $8C: mode 0, ROMs off
CRTC_SELECT     EQU $BC00
CRTC_WRITE      EQU $BD00
PPI_A           EQU $F400       ; the AY's bus
PPI_B           EQU $F500       ; bit 0: VSYNC
PPI_C           EQU $F600       ; bits 0-3 the keyboard's line, 6-7 the AY's function
PPI_CONTROL     EQU $F700
PPI_A_OUT       EQU $82         ; port A out, B in, C out
PPI_A_IN        EQU $92         ; port A in (the keyboard through the AY)
AY_SELECT       EQU $C0
AY_WRITE        EQU $80
AY_READ         EQU $40
FDC_MOTOR       EQU $FA7E

; RAM configurations: the hidden screen at $4000
RAM_A           EQU $C1         ; base 1 (screen A) at $4000, bank 7 at $C000
RAM_B           EQU $C3         ; base 3 (screen B) at $4000, bank 7 at $C000
RAM_BANK4       EQU $C4         ; bank 4 at $4000 (and base 3 at $C000)

; The CRTC's start: R12 bits 4-5 the 16K block shown
CRTC_A          EQU $10
CRTC_B          EQU $30

; The screen
SCR             EQU $4000       ; the hidden one, as the CPU sees it
SCR_LINE        EQU $800        ; a line's step within a character row
SCR_ROW         EQU 64          ; a character row's

; Hardware colours (the Gate Array's numbers)
HW_BLACK        EQU $14

        ORG $0000
        jp CpcBoot              ; (the disc's loader starts the game here)
CpcCode:
        INCLUDE "boot.asm"
        INCLUDE "flip.asm"
        INCLUDE "keys.asm"
        INCLUDE "draw.asm"
        INCLUDE "disc.asm"
CpcCodeEnd:
        ASSERT CpcCodeEnd <= SCN_DATA
