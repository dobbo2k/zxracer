; ---------------------------------------------------------------------------
; Speed Run - entry point and main loop
; Target: ZX Spectrum 128K, assembled with sjasmplus; with -DEINSTEIN the
; Tatung Einstein (docs/port_einstein.md): the same game at the same
; addresses in a flat 64K, with src/einstein/ in place of the Spectrum's
; screen, input, sound out, interrupt and paging.
; ---------------------------------------------------------------------------
        IFDEF EINSTEIN
        DEVICE NOSLOT64K
        ELSE
        DEVICE ZXSPECTRUM128
        ENDIF
        INCLUDE "defs.asm"
        IFDEF EINSTEIN
        INCLUDE "einstein/platform.asm" ; the COM file's entry at $0100, the platform code
        ENDIF

        ORG $8000
start:
        di
        ld sp, STACK_TOP
        IFNDEF EINSTEIN
        ld a, P7FFD_ROM48 | 7   ; display bank 5, bank 7 paged at $C000
        ld (Port7FFD), a
        ld bc, PORT_7FFD
        out (c), a
        xor a                   ; black border
        out ($FE), a
        ENDIF
        call InitInterrupts     ; (first: the music stops and starts with ei)
        ei
        call Restart            ; stage 1: packs, display, track state
        call GoTitle

; Each game frame: logic and the road's shape first - none of it touches
; the screen, so it runs while the last frame still waits for its flip -
; then, once that buffer is on show, draw the other one and ask for a flip.
        IFDEF EINSTEIN
MainLoop:
        call CheckPause
        call ReadInput
        call UpdatePlayer
        call RoadPrepare
        call WaitFlip           ; (the last frame sent: its buffers free)
        call EraseSprites       ; traffic and scenery into screen B, as ever
        call DrawSprites
        call DrawCar            ; (into screen B: its cells are sent)
        call DrawPortal         ; (a tunnel's mouth, the gantry: screen B's attributes)
        call EinSprCells        ; the cells they cover (src/einstein/sprites.asm)
        call EinPortal          ; and the portal's (src/einstein/portal.asm)
        call EinHorizon
        call EinDraw            ; the frame into RAM: names, patterns (src/einstein)
        call DrawHud            ; (into screen B: the cells it writes are sent)
        call EinFlash           ; (the timer's last ten seconds)
        call RequestFlip        ; then into VRAM, in the vertical blank
        jr MainLoop
        ELSE
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
        call DrawPortal         ; (a tunnel's mouth or way out)
        BORDER 3                ; magenta: sprites
        call DrawSprites
        call DrawCar
        BORDER 5                ; cyan: HUD
        call DrawHud
        call RequestFlip
        jr MainLoop
        ENDIF

        INCLUDE "interrupt.asm"
        IFDEF EINSTEIN
        INCLUDE "einstein/screen.asm"   ; (FillA: the rest is in src/einstein)
        ELSE
        INCLUDE "screen.asm"
        ENDIF
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
        INCLUDE "musicb2.asm"
        INCLUDE "traffic.asm"
        INCLUDE "fork.asm"
        INCLUDE "hills.asm"
        INCLUDE "tunnelb2.asm"
        INCLUDE "vars.asm"
        IFDEF EINSTEIN          ; (in the room the Spectrum's drawing code leaves)
        INCLUDE "pause.asm"
        INCLUDE "beep.asm"
        INCLUDE "gap4.asm"
        INCLUDE "einstein/keys.asm"
        INCLUDE "einstein/disc.asm"
        INCLUDE "einstein/front.asm"
        ENDIF
CodeEnd:
        ASSERT CodeEnd <= TABLES

        ORG TABLES
        INCLUDE "tables.asm"
TablesEnd:
        ASSERT TablesEnd <= PANO_LDI_END - 64
        INCLUDE "tyres.asm"     ; (in the gap before the panorama's chain)
        ASSERT $ <= PANO_LDI_END - 64

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
        ASSERT $ <= SrcLine
        ORG SrcLine
hv      DEFL 0
        DUP ROAD_LINES
        db hv
hv      DEFL hv + 1
        EDUP
        INCLUDE "crewtraffic.asm"   ; (in the gap before the fill block)
        INCLUDE "lightshold.asm"
Gap3Free:                       ; (src/holes.asm uses the rest)
        ASSERT $ <= FILL_END - 64

; Unrolled fill: entered at FILL_END - 2*n to write n bytes (see FillA)
        ORG FILL_END - 64
FillBlock:
        DUP 32
        ld (hl), a
        inc l
        EDUP
        ret
        IFNDEF EINSTEIN
        INCLUDE "pause.asm"     ; (in the gap before the interrupt vector)
        INCLUDE "beep.asm"
        INCLUDE "gap4.asm"
        ENDIF
        ASSERT $ <= ISR_JP

        ORG ISR_JP
        jp Isr

; Variables the game sets up itself before using them: the tape loader loads
; bank 2 only up to here (src/loader.asm sits at $BE00 while it loads), and
; the stack is never more than 46 bytes deep (zxsim -u over whole games), so
; the rest of its page is free.
Bss1:
TunStart:       dw 0            ; this stage's tunnel (0: none), src/tunnel.asm
TunEnd:         dw 0
TunInside:      db 0            ; the car is in it (the sky is its ceiling)
TunJ0:          db 0            ; road lines in it this frame: TunJ0 .. TunJ0 + TunJN - 1
TunJN:          db 0
GateZ:          dw 0            ; this stage's gantry (src/tunnelb2.asm)
GateWas:        db 0            ; it was drawn (its sky rows to be painted afresh)
GatePat:        ds 5            ; a gantry row's colours (src/tunnelb2.asm)
; (cleared together at a new run)
MsgThen:        dw 0, 0         ; the messages queued after this one (0: none)
StageClock:     dw 0            ; 50 Hz frames on this stage
StageTimes:     ds 5 * 2        ; per row: the stage's time (0: not finished)
MusicWait:      db 0            ; a new stage's tune: the gap to wait (src/holes.asm)
RUN_VARS        EQU 4 + 2 + 5 * 2 + 1   ; (5 rows: NUM_ROWS, defined later)
Traffic:        ds N_TRAFFIC * CAR_SIZE
        ASSERT $ <= IM2_TABLE
        ORG IM2_TABLE + 257
Bss2:
CmdListA:       db 0            ; buffer A's sprite commands
                ds MAX_SPR * CMD_SIZE
        ASSERT $ <= STACK_TOP - 128  ; (the stack keeps 128 bytes)
; Buffer B's: the top of bank 7, which no theme pack reaches (make_stages.py
; keeps THEME_TOP free; bank 7 is paged in all through a game)
THEME_TOP       EQU 120
        IFDEF EINSTEIN
CmdListB        EQU EIN_CMDLISTB    ; (src/einstein/platform.asm: above the shadow screen)
        ELSE
CmdListB        EQU $10000 - THEME_TOP
        ENDIF
        ASSERT 1 + MAX_SPR * CMD_SIZE <= THEME_TOP

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
        INCLUDE "crew.asm"      ; the crew's crash close-ups
        INCLUDE "lampdraw.asm"  ; the starting lights' lamps
        INCLUDE "pics.asm"      ; the front end's picture unpacker
        INCLUDE "music.asm"     ; the music player
        INCLUDE "extend.asm"    ; stage times, extended play, weaving traffic
        INCLUDE "tunnel.asm"    ; tunnels
ScnEnd:
        ASSERT ScnEnd <= TRACK_CACHE

; Stage packs in banks 0, 1, 3, 4 and 6 (copied to the caches at a stage start)
        INCLUDE "packs.asm"

        IFDEF EINSTEIN
; The between-stages overlay stays where the Spectrum runs it ($4000: its
; screen A, plain RAM here), resident: nothing pages over it.
        ORG $4000
        OUTPUT "build/einstein/stageov.bin"     ; (into STAGES.DAT too: the front
        INCLUDE "stageov.asm"                   ; end draws over it)
        OUTEND
        ASSERT $ <= STAGEOV_END                 ; (the Einstein's buffers above)
; The front end: run at THEME_CACHE, from STAGES.DAT (assembled here, out of
; the COM file's way, for its own file)
        ORG $C000
        OUTPUT "build/einstein/frontend.bin"
        DISP THEME_CACHE
        INCLUDE "frontend.asm"
        ENT
        OUTEND
        ; the COM file: $0100 up to the stack
        SAVEBIN "build/einstein/speedrun.com", $0100, STACK_TOP - 256 - $0100
        ELSE
        IF AUTOPLAY
        SAVESNA "build/video.sna", start
        ELSE
        IFDEF RELEASE
        SAVESNA "build/release.sna", start     ; (no timing bars: the tape is made from this)
        ELSE
        SAVESNA "build/zxracer.sna", start
        ENDIF
        ENDIF
        ENDIF
