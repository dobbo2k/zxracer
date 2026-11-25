; ---------------------------------------------------------------------------
; Speed Run - entry point and main loop
; Target: ZX Spectrum 128K, assembled with sjasmplus; with -DEINSTEIN the
; Tatung Einstein (docs/port_einstein.md): the same game at the same
; addresses in a flat 64K, with src/einstein/ in place of the Spectrum's
; screen, input, sound out, interrupt and paging; with -DCPC the Amstrad
; CPC 6128 (docs/port_cpc.md): bank 2's code and tables where they are,
; bank 5's residents $4000 lower, src/cpc/ for the rest.
; ---------------------------------------------------------------------------
        IFDEF EINSTEIN
        DEVICE NOSLOT64K
        ELSE
        IFDEF CPC
        DEVICE AMSTRADCPC6128
        ELSE
        DEVICE ZXSPECTRUM128
        ENDIF
        ENDIF
        INCLUDE "defs.asm"
        IFDEF EINSTEIN
        INCLUDE "einstein/platform.asm" ; the COM file's entry at $0100, the platform code
        ENDIF
        IFDEF CPC
        INCLUDE "cpc/platform.asm"      ; base 0: the CPC's code (bank 7 at $C000)
        ENDIF

        ORG $8000
start:
        di
        ld sp, STACK_TOP
        IFNDEF NATIVE_GFX
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
        call EinReadInput       ; (ReadInput, the Einstein's way)
        call UpdatePlayer
        call RoadPrepare
        call WaitFlip           ; (the last frame sent: its buffers free)
        call EinErase           ; traffic and scenery into screen B, as ever
        call DrawSprites        ; (EinErase: src/einstein/sprites.asm)
        call EinCarPrep         ; select the native Spider pose for this frame
        call DrawPortal         ; (a tunnel's mouth, the gantry: screen B's attributes)
        call EinSprCells        ; the cells they cover (src/einstein/sprites.asm)
        call EinPortal          ; and the portal's (src/einstein/portal.asm)
        call EinHorizon
        call EinDraw            ; the frame into RAM: names, patterns (src/einstein)
        call EinCarGroundSync
        call DrawHud            ; (into screen B: the cells it writes are sent)
        call EinFlash           ; (the timer's last ten seconds)
        call RequestFlip        ; then into VRAM, in the vertical blank
        jr MainLoop
        ENDIF
        IFDEF CPC
MainLoop:
        call CheckPause
        call ReadInput
        call UpdatePlayer
        call RoadPrepare
        call WaitFlip           ; (the last frame shown: the hidden screen at $4000)
        call CpcDraw            ; the road and the panorama (src/cpc)
        call DrawPortal         ; (a tunnel's mouth, the gantry: screen B's attributes)
        call CpcPortal          ; (its cells: src/cpc/draw.asm)
        call DrawSprites        ; traffic and scenery projected: the command list
        call DrawHud            ; (into screen B: the cells it writes are noted)
        call CpcCells           ; the noted cells into the hidden screen
        call CpcObjects         ; the objects from the list, then the car (src/cpc)
        call RequestFlip        ; shown from the next VSYNC due
        jr MainLoop
        ENDIF
        IFNDEF NATIVE_GFX
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
        BORDER 2                ; red: road
        call DrawRoad
        BORDER 4                ; green: horizon
        call DrawHorizonIfTime
        call DrawPortal         ; (a tunnel's mouth or way out)
        BORDER 3                ; magenta: sprites
        call DrawSprites
        IFDEF ZX_OBJINK
        call THEME_CACHE + 28   ; their inks (src/objink.asm, in the theme pack)
        ENDIF
        call DrawCar
        BORDER 5                ; cyan: HUD
        call DrawHud
        call RequestFlip
        jr MainLoop
        ENDIF

        INCLUDE "interrupt.asm"
        IFDEF NATIVE_GFX
        INCLUDE "einstein/screen.asm"   ; (FillA: the rest is the platform's)
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
        IFDEF EINSTEIN
        INCLUDE "tunnelaside.asm"   ; (the Spectrum's: in bank 5, src/tunnel.asm)
        ENDIF
        INCLUDE "vars.asm"
        IFDEF EINSTEIN          ; (in the room the Spectrum's drawing code leaves)
        INCLUDE "pause.asm"
        INCLUDE "beep.asm"
        INCLUDE "gap4.asm"
        INCLUDE "einstein/keys.asm"
        INCLUDE "einstein/disc.asm"
        INCLUDE "einstein/front.asm"
        INCLUDE "einstein/car.asm"
        INCLUDE "einstein/dash.asm"     ; (the tail lamps; -DEIN_DASH: the centre line)
        INCLUDE "einstein/objcolour.asm"    ; (an object's ground in a two-colour cell)
        IFDEF EIN_KERB
        INCLUDE "einstein/kerbrow.asm"  ; (a prototype: the near kerbs exact)
        ENDIF
        IFDEF EIN_SLOPE
        INCLUDE "einstein/slope.asm"    ; (a sloped row of the near road)
        ENDIF
        ENDIF
        IFDEF CPC               ; (in the room the Spectrum's drawing code leaves)
        INCLUDE "pause.asm"
        INCLUDE "beep.asm"
        INCLUDE "gap4.asm"
        INCLUDE "cpc/bank2.asm"
        ENDIF
CodeEnd:
        ASSERT CodeEnd <= TABLES

        ORG TABLES
        INCLUDE "tables.asm"
TablesEnd:
        ASSERT TablesEnd <= PANO_LDI_END - 64
        INCLUDE "tyres.asm"     ; (in the gap before the panorama's chain)
        IFDEF CPC               ; (no panorama bitmap nor road pass 2: their
        INCLUDE "cpc/chains.asm"        ; chains' room for the CPC's)
        ENDIF
        IFDEF EINSTEIN          ; (no panorama bitmap nor road pass 2: their
        INCLUDE "einstein/static.asm"   ; chains' room for code)
        ASSERT $ <= PANO_LDI_END - 64
; Unrolled OUTI chain for VRAM in the blank (src/einstein/flip.asm
; EinWrite): entered at OutiEnd - 2*n for n bytes
        ORG PANO_LDI_END - 64
        DUP 32
        outi
        EDUP
OutiEnd:
        ret
        INCLUDE "einstein/reset.asm"    ; (more of the display reset)
        ENDIF
        IFNDEF NATIVE_GFX
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
        ENDIF
        INCLUDE "respawn.asm"   ; (small pieces in the gap before the XOR chain)
        INCLUDE "lights.asm"
Gap2Free:                       ; (src/holes.asm uses the rest)
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
; Projected segment boundaries in the gap between the hill tables.
CurveList:      ds 2 + 3 * MAX_BOUNDS + 1
        ASSERT $ <= SrcLine
        ORG SrcLine
hv      DEFL 0
        DUP ROAD_LINES
        db hv
hv      DEFL hv + 1
        EDUP
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
        IFNDEF NATIVE_GFX
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
GateWas:        db 0            ; it or a tunnel's portal was drawn, or Ceiling changed the sky: buffers
                                ; whose sky rows are to be painted afresh (src/tunnelb2.asm Gate.gone)
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
        IFDEF EINSTEIN
        INCLUDE "einstein_objects.asm"
        ELSE
        IFDEF CPC
        INCLUDE "cpc_objects.asm"       ; (build/cpc: the resident objects in Mode 0)
        ELSE
        INCLUDE "resident_data.asm"
        ENDIF
        ENDIF
        INCLUDE "font_data.asm"
        IFDEF EINSTEIN
        INCLUDE "spider.asm"
        INCLUDE "einstein/ground.asm"
        ELSE
        IFDEF CPC
        INCLUDE "cpc_car.asm"           ; (build/cpc: the Spider in Mode 0)
        ELSE
        INCLUDE "car_data.asm"
        ENDIF
        ENDIF
        INCLUDE "screens.asm"   ; title and goal screens (not time-critical)
        INCLUDE "stage.asm"     ; stage loading, checkpoints (between stages only)
        INCLUDE "lampdraw.asm"  ; the starting lights' lamps
        INCLUDE "pics.asm"      ; the front end's picture unpacker
        INCLUDE "music.asm"     ; the music player
        INCLUDE "extend.asm"    ; stage times, extended play, weaving traffic
        INCLUDE "tunnel.asm"    ; tunnels
        IFNDEF EINSTEIN
        INCLUDE "tunnelaside.asm"   ; (the Einstein's: in bank 2)
        ENDIF
        IFDEF CPC
        INCLUDE "cpc/resident.asm"  ; (the CPC's code that is not time-critical)
        ENDIF
PrevHillInputs: ds 2 + 3 * MAX_BOUNDS + 1
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
        IFDEF CPC
; The between-stages overlay and the front end, for the disc
; (tools/make_cpc.py: packed into SPEED.DAT, read when needed)
        ORG $4000
        OUTPUT "build/cpc/stageov.bin"
        INCLUDE "stageov.asm"
        OUTEND
        ASSERT $ <= ART_INPUT
        ORG $C000
        OUTPUT "build/cpc/frontend.bin"
        DISP THEME_CACHE
        INCLUDE "frontend.asm"
        ENT
        OUTEND
        ; the game's image: base 0 and base 2 (bank 7 starts empty)
        SAVEBIN "build/cpc/base0.bin", $0000, $4000
        SAVEBIN "build/cpc/base2.bin", $8000, $4000
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
        ENDIF
