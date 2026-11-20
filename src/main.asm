; ---------------------------------------------------------------------------
; ZX Racer - entry point and main loop
; Target: ZX Spectrum 128K, assembled with sjasmplus
; ---------------------------------------------------------------------------
        DEVICE ZXSPECTRUM128
        INCLUDE "defs.asm"

        ORG $8000
start:
        di
        ld sp, STACK_TOP
        ld a, P7FFD_ROM48 | 7   ; display bank 5, bank 7 paged at $C000
        ld (Port7FFD), a
        ld bc, PORT_7FFD
        out (c), a
        xor a                   ; black border
        out ($FE), a
        call Restart            ; stage 1: packs, display, track state
        call InitInterrupts
        ei
        call GoTitle

; Each game frame: logic and the road's shape first - none of it touches
; the screen, so it runs while the last frame still waits for its flip -
; then, once that buffer is on show, draw the other one and ask for a flip.
MainLoop:
        call CheckPause
        BORDER 1                ; blue: game logic
        call ReadInput
        call UpdatePlayer
        BORDER 2                ; red: road
        call RoadPrepare
        BORDER 0                ; black: waiting for the last flip
        call WaitFlip
        call SelectBackBuffer
        BORDER 3                ; magenta: sprites
        call EraseSprites
        call DrawCrew
        BORDER 2                ; red: road
        call DrawRoad
        BORDER 4                ; green: horizon
        call DrawHorizonIfTime
        BORDER 3                ; magenta: sprites
        call DrawSprites
        call DrawCar
        BORDER 5                ; cyan: HUD
        call DrawHud
        call RequestFlip
        jr MainLoop

        INCLUDE "interrupt.asm"
        INCLUDE "screen.asm"
        INCLUDE "input.asm"
        INCLUDE "player.asm"
        INCLUDE "road.asm"
        INCLUDE "track.asm"
        INCLUDE "car.asm"
        INCLUDE "scenery.asm"
        INCLUDE "horizon.asm"
        INCLUDE "hud.asm"
        INCLUDE "game.asm"
        INCLUDE "sound.asm"
        INCLUDE "traffic.asm"
        INCLUDE "fork.asm"
        INCLUDE "hills.asm"
        INCLUDE "vars.asm"
CodeEnd:
        ASSERT CodeEnd <= TABLES

        ORG TABLES
        INCLUDE "tables.asm"
TablesEnd:
        ASSERT TablesEnd <= PANO_LDI_END - 64

; Unrolled LDI chain for the panorama: entered at PanoLdiEnd - 2*n
        ORG PANO_LDI_END - 64
        DUP 32
        ldi
        EDUP
PanoLdiEnd:
        ret

; Dual-write chain for the road's kerb bytes: entered at DualEnd - 7*n to
; copy n bytes (HL) -> (DE) and (DE + 256), the two lines of a line pair
        DUP STRIP_PAD
        ld a, (hl)
        ld (de), a
        inc d
        ld (de), a
        dec d
        inc l
        inc e
        EDUP
DualEnd:
        ret
        ASSERT high (DualEnd - 7 * STRIP_PAD) == high DualEnd
        INCLUDE "respawn.asm"   ; (small pieces in the gap before the XOR chain)
        INCLUDE "lights.asm"
        ASSERT $ <= XOR_END - 5 * 8

; Unrolled XOR chain for sprites: entered at XorEnd - 5*n for n bytes
        ORG XOR_END - 5 * 8
        DUP 8
        ld a, (de)
        xor (hl)
        ld (hl), a
        inc l
        inc de
        EDUP
XorEnd: jp (iy)

; Hill mapping (see hills.asm), starting as identities
        ORG ProjClip
        ASSERT ProjClip >= XorEnd + 2
hv      DEFL 1
        DUP ROAD_LINES / 2
        db $81, hv
hv      DEFL hv + 2
        EDUP
        INCLUDE "beep.asm"      ; (in the gap before SrcLine)
        ASSERT $ <= SrcLine
        ORG SrcLine
hv      DEFL 0
        DUP ROAD_LINES
        db hv
hv      DEFL hv + 1
        EDUP
        INCLUDE "crewtraffic.asm"   ; (in the gap before the fill block)
        INCLUDE "lightshold.asm"
        ASSERT $ <= FILL_END - 64

; Unrolled fill: entered at FILL_END - 2*n to write n bytes (see FillA)
        ORG FILL_END - 64
FillBlock:
        DUP 32
        ld (hl), a
        inc l
        EDUP
        ret
        INCLUDE "pause.asm"     ; (in the gap before the interrupt vector)
        INCLUDE "pics.asm"
        ASSERT $ <= ISR_JP

        ORG ISR_JP
        jp Isr

        INCLUDE "holes.asm"     ; small data in the unused ends of the table pages

; Resident graphics in the spare part of bank 5 (always paged): the traffic
; sprite, the font and the player's car; then code that is not time-critical
; (bank 5 is contended). The track cache follows.
        ORG SCN_DATA
        INCLUDE "resident_data.asm"
        INCLUDE "font_data.asm"
        INCLUDE "car_data.asm"
        INCLUDE "screens.asm"   ; title and goal screens (not time-critical)
        INCLUDE "stage.asm"     ; stage loading, checkpoints (between stages only)
        INCLUDE "stages.asm"
        INCLUDE "crew.asm"      ; the crew's crash close-ups
        INCLUDE "lampdraw.asm"  ; the starting lights' lamps
ScnEnd:
        ASSERT ScnEnd <= TRACK_CACHE

; Stage packs in banks 0, 1, 3, 4 and 6 (copied to the caches at a stage start)
        INCLUDE "packs.asm"

        IF AUTOPLAY
        SAVESNA "build/video.sna", start
        ELSE
        IFDEF RELEASE
        SAVESNA "build/release.sna", start     ; (no timing bars: the tape is made from this)
        ELSE
        SAVESNA "build/zxracer.sna", start
        ENDIF
        ENDIF
