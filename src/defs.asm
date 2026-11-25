; ---------------------------------------------------------------------------
; Speed Run - global constants and macros
; ---------------------------------------------------------------------------

; The platform: the Spectrum, or with -DEINSTEIN the Tatung Einstein
; (docs/port_einstein.md), or with -DCPC the Amstrad CPC 6128
; (docs/port_cpc.md). Both draw their own screens: NATIVE_GFX leaves the
; Spectrum's drawing code out and calls theirs. Both share the road's
; projection's exact speed-ups (FAST_PROJ: the same results, quicker).
        IFDEF EINSTEIN
        DEFINE NATIVE_GFX
        DEFINE FAST_PROJ
        ENDIF
        IFDEF CPC
        DEFINE NATIVE_GFX
        DEFINE FAST_PROJ
        ENDIF

; Build options
        IFNDEF PROFILE
        IFDEF NATIVE_GFX
PROFILE         EQU 0           ; (no border bars: the Spectrum's port $FE)
        ELSE
PROFILE         EQU 1           ; 1 = border colour timing bars
        ENDIF
        ENDIF
        IFNDEF AUTOPLAY
AUTOPLAY        EQU 0           ; 1 = the attract-mode driver also plays the game (videos)
        ENDIF
        IFNDEF FIXED_ELAPSED
FIXED_ELAPSED   EQU 0           ; 1 = (testing) every update counts 3 TV frames and nothing
        ENDIF                   ; drawn depends on the timing: identical runs at any speed
        IFDEF EINSTEIN          ; the Einstein draws no centre line (but with -DEIN_DASH):
        IFNDEF EIN_DASH         ; pass 1 and the hill mapping leave it out (LaneX
        DEFINE EIN_NOLANE       ; stays $FF), src/road.asm, src/hills.asm
        ENDIF
        ENDIF

; Memory map (bank 2, $8000-$BFFF, always paged)
TABLES          EQU $A300       ; page-aligned lookup tables (build/tables.asm)
PANO_LDI_END    EQU $BA00       ; unrolled 32-LDI chain for the panorama
XOR_END         EQU $BB00       ; unrolled XOR chain ends here (with JP (IY))
        IFDEF CPC
SCN_DATA        EQU $1B00       ; (the CPC: bank 5's part $4000 lower, in base 0)
        ELSE
SCN_DATA        EQU $5B00       ; scenery sprites: spare RAM in bank 5 (always paged)
        ENDIF
FILL_END        EQU $BD00       ; unrolled fill block ends here (with RET)
ISR_JP          EQU $BDBD       ; IM2 lands here: JP Isr
HILL_TABLES     EQU $BB00       ; hill mapping (gaps between the unrolled chains)
ProjClip        EQU HILL_TABLES + $02   ; per depth line: screen line, pairs / clip line
SrcLine         EQU HILL_TABLES + $80   ; per screen line: depth line shown
IM2_TABLE       EQU $BE00       ; 257-byte vector table, all bytes = $BD
STACK_TOP       EQU $C000       ; stack grows down from here ($BF01-$BFFF)

; 128K paging
PORT_7FFD       EQU $7FFD
P7FFD_ROM48     EQU $10
P7FFD_SHADOW    EQU $08         ; display bank 7 instead of bank 5
        IFNDEF MIN_FRAMES       ; (-D: the benchmark measures the work unlocked)
MIN_FRAMES      EQU 3           ; locked 16.7 fps: steadier than a 25/16.7 mix
        ENDIF

; Screen layout
ROAD_Y0         EQU 96          ; first screen line of the road
ROAD_LINES      EQU 96
ROAD_ROW0       EQU 12          ; first character row of the road

; Attributes: bit 6 bright, bits 5-3 paper, bits 2-0 ink
ATTR_SKY        EQU %01101000   ; bright cyan paper, black ink (silhouettes)
ATTR_PANO       EQU %01101001   ; bright cyan paper, blue ink (distant mountains)
ATTR_HUD        EQU %01101001   ; HUD text: blue ink on the sky
ATTR_TIME       EQU %01101010   ; big timer: red ink on the sky
PANO_ROW0       EQU 10          ; panorama rows 10-11
ATTR_GRASS_L    EQU %01100000   ; bright green paper, black ink
ATTR_GRASS_D    EQU %00100000   ; green paper, black ink
ATTR_ROAD       EQU %01000111   ; black paper, bright white ink
ATTR_KERB_L     EQU %01111000   ; bright white paper, black ink
ATTR_KERB_D     EQU %01010000   ; bright red paper, black ink

STRIPE_BIT      EQU $40         ; bit of (z + position) selecting light/dark band

; AY periods: the Spectrum's AY runs at 1.7734 MHz, the Einstein's at 2 MHz,
; the CPC's at 1 MHz, so there a period is AYN / AYD as long for the same
; pitch: write a period as (p * AYN + AYD / 2) / AYD
        IFDEF EINSTEIN
AYN             EQU 1128
AYD             EQU 1000
        ELSE
        IFDEF CPC
AYN             EQU 564
AYD             EQU 1000
        ELSE
AYN             EQU 1
AYD             EQU 1
        ENDIF
        ENDIF

; Input bits (same layout as Kempston)
IN_RIGHT        EQU 0
IN_LEFT         EQU 1
IN_DOWN         EQU 2
IN_UP           EQU 3
IN_FIRE         EQU 4

; Wait for the next TV frame (the Einstein's interrupt comes every 1 ms,
; the CPC's six times a frame)
        MACRO FRAME_WAIT
        IFDEF EINSTEIN
        call EinHalt
        ELSE
        IFDEF CPC
        call CpcHalt
        ELSE
        halt
        ENDIF
        ENDIF
        ENDM

; A = keyboard half-rows to read (as port $FE's high byte) -> A = their keys
; (bits 0-4, 0: pressed); the Einstein and the CPC answer from their own
; keyboards
        MACRO KEY_IN
        IFDEF EINSTEIN
        call EinSpecIn
        ELSE
        IFDEF CPC
        call CpcSpecIn
        ELSE
        in a, ($FE)
        ENDIF
        ENDIF
        ENDM

        MACRO BORDER col
        IF PROFILE
        ld a, col
        out ($FE), a
        ENDIF
        ENDM
