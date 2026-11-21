# Porting Speed Run to the Amstrad CPC

A plan, not a commitment: what carries over, what has to be rebuilt, and in
what order. Hardware facts marked *(verify)* should be checked against the
CPC documentation before the work that depends on them starts.

## 1. Target

- **Machine:** CPC 6128 (and 464/664 with a 64K memory expansion): 128K is
  needed, as on the Spectrum. A 64K version is possible later with stages
  loaded from disc per row (§9).
- **Media:** 3" disc image (`.dsk`) first; tape (`.cdt`) second.
- **Frame rate:** the same aims as the Spectrum: 25 fps, never below
  16.7 fps.

## 2. The two machines side by side

| | Spectrum 128 (now) | Amstrad CPC 6128 |
|---|---|---|
| CPU | Z80 3.55 MHz, 70,908 T a frame | Z80 4 MHz, but every instruction rounds up to a whole microsecond: about the same speed in practice |
| Screen | 256×192, 1 bit a pixel, colour per 8×8 cell (attributes) | Mode 0: 160×200, 16 pens per pixel, 4 bits a pixel; Mode 1: 320×200, 4 pens |
| Palette | fixed 15 colours | 27 colours, any pen to any colour at any time (gate array) |
| Double buffering | two screens, flipped by port $7FFD | the CRTC's screen start (R12/R13): screens at $C000 and $8000 |
| Memory | 128K in 16K banks at $C000 | 64K + 64K in 16K banks at $4000 (gate array $7FC4-$7FC7) |
| Sound | AY at 1.7734 MHz, ports $FFFD/$BFFD | the same AY at **1 MHz**, through the PPI ($F4xx data, $F6xx control) |
| Interrupt | 50 Hz, IM 2 | **300 Hz** (every 52 lines), IM 1 |
| Keyboard, joystick | ports $xxFE, Kempston | a matrix read through the AY's port A; the joystick is matrix row 9 |

## 3. What carries over unchanged

Most of the game is plain Z80 with no hardware in it, and moves across as is:

- the game itself: `player.asm`, `track.asm`, `hills.asm`, `fork.asm`,
  `traffic.asm`, `game.asm`, `extend.asm` (times, extended play, weaving),
  `respawn.asm`, the crash and crew logic;
- the road's shape pass (pass 1 in `road.asm`: road edges and centre line
  per line), the scenery projection in `scenery.asm`, the tunnel logic
  (`UpdateTunnel`);
- the music sequencer (`music.asm`'s `MusicStep`, `Pitch`) and every tune;
- the stage data and its tools: `make_stages.py`, `make_music.py`,
  `track.py`, `zpack.py` (packs and their compression);
- the stage overlay system (`stage.asm`, `stageov.asm`): the CPC's 64K of
  banks take the packs that the Spectrum keeps in banks 0, 1, 3, 4 and 6.

## 4. Step 0: a platform layer (shared with the Einstein port)

Before either port, split the Spectrum-specific code out behind a small
interface, selected by `-DPLATFORM=ZX|CPC|EINSTEIN`:

- **screen:** select the back buffer, flip, address a line, clear;
- **road output:** the per-row drawing in `road.asm`'s pass 2 (the part that
  writes attributes and kerb bytes);
- **sprites:** draw and erase scenery, traffic and the car;
- **HUD and text:** `hud.asm`, `PrintBig`, the message line;
- **sound out:** `AyWrite` (the sequencer above it stays);
- **input:** `ReadInput` and the redefinable keys;
- **interrupt and paging:** `interrupt.asm`, the bank macros;
- **loader and media:** `loader.asm`, `make_tap.py`.

The Spectrum build must stay byte-identical: `make test`, `rendercheck` and
`tapecheck` prove it at every step.

## 5. Graphics: Mode 0 with colour cycling

**Mode 0** (160×200, 16 pens) is the right mode. It has enough colours for
the road, the scenery and the car together without the Spectrum's colour
clash. Its wide pixels suit a racer, and 160 columns are fewer bytes a line
to fill than Mode 1. The play area keeps the Spectrum's layout: the HUD at
the top, sky and backdrop, then 96 lines of road.

### The road: draw shape, cycle colour

The Spectrum gets its bands for free from attributes: grass and road are
blank pixels, and the colour comes from one attribute row per 8 lines. A
CPC has no attributes, so every pixel is coloured. Repainting the light and
dark bands every frame as they stream past would cost far too much. Instead,
use **palette cycling**, the classic way to do this on the CPC:

- each road line is drawn with pens that depend on its depth, not on time:
  grass in one of 4 "phase" pens (the line's depth band mod 4), kerbs in one
  of 2 or 4 phase pens, and the centre line in phase pens that are either
  white or road-coloured;
- moving forward is then just **re-colouring those pens** each frame (a
  dozen gate-array writes), with no pixels touched;
- pixels are only redrawn when the road's *shape* changes: the player
  steers, a curve, a hill or the fork. That is exactly when the Spectrum
  runs pass 1 today, and only the lines whose edges moved are redrawn;
- line fills use the stack (PUSH) for speed, about 5.5 µs for two bytes.
  A full road redraw is about 96 lines × 80 bytes ≈ 7.7 KB, roughly half a
  frame, and a typical frame redraws far fewer lines.

Pen budget (16): sky 1, backdrop 2, grass 4 (phases), kerbs 2,
road 1, centre line 2, and black, white, red, yellow and two spare for the
car, traffic and scenery. Each theme sets its own colours (the
`THEME_CACHE + 6` palette bytes become CPC colour numbers), and so does a
tunnel (walls and lamps are just other colours on the same pens).

### Backdrop and sky

- The mountain band (`horizon.asm`) becomes a Mode 0 band, about 30 lines.
  It scrolls sideways in 2-pixel steps (one byte) by redrawing it from a
  pre-shifted copy, as now.
- The sky is one pen; the sunset theme can change that pen at the 300 Hz
  interrupts for a 3-step sky gradient for free.

### Sprites (scenery, traffic, the car)

The CPC has no hardware sprites, so all three stay software sprites, but
they must be **masked** (AND mask, OR colour) rather than XOR'd, because the
background is no longer blank. That means:

- erasing by restoring the background: save what is under each sprite
  (per buffer), or redraw the road lines it covered. The road's per-line
  edge data makes the second option cheap;
- `make_scenery.py` and `make_car.py` emit Mode 0 bytes. Two pixels a byte,
  interleaved bits, so an odd x needs a second, pre-shifted copy (twice the
  data, about 12 KB for the scaled scenery sets: it fits in the banks);
- scenery gains colour (trees green and brown, signs in their colours), which
  the Spectrum could not do.

### HUD and text

- The font is drawn in Mode 0 at 4 bytes a character (8 pixels: wide, but
  readable). Alternatively the top 52 lines can be Mode 1 for sharper text,
  switching mode at the first 300 Hz interrupt.
- The front end screens (`frontend.asm`, the title and route pictures) are
  converted to Mode 0 by `png2zx.py`'s CPC twin, from the same PNG sources.

## 6. Sound

The CPC has the same AY chip, so the music is free, apart from:

- **the clock:** 1 MHz instead of 1.7734 MHz. `make_music.py` and the drum
  tables (`DrumTab`, `DrumTom` and the rest) generate their periods from
  `AY_CLOCK`, so set it to 1,000,000. The detune and the engine pitch scale
  the same way;
- **`AyWrite`:** six `OUT`s through the PPI per register instead of two;
- **the interrupt:** 300 Hz, so `SoundTick` runs on every 6th interrupt; the
  other 5 do the raster work (pens for the sky gradient, a Mode 1 HUD).

## 7. Input

- `ReadInput` scans the 10×8 matrix: select the row on PPI port C, read the
  AY's port A. The defaults become Q/A/O/P/Space as now; the joystick is
  matrix row 9.
- The redefine-keys screen keeps its logic and gets the CPC key names.

## 8. Memory map (CPC 6128)

| Range | Use |
|---|---|
| $0000-$3FFF | code: the game, the road, the sequencer (bank 0) |
| $4000-$7FFF | code and tables, or a paged bank (4-7) while loading a stage |
| $8000-$BFFF | screen B |
| $C000-$FFFF | screen A |
| banks 4-7 | the theme packs, track packs, overlays and front end (now in Spectrum banks 0, 1, 3, 4, 6) |

Two screens take 32K of the base 64K. That leaves 32K for code, tables and
the caches, against about 30K of code and tables on the Spectrum today. It is
tight, so the firmware is switched off and its RAM reclaimed after loading.

## 9. Loading

- **Disc:** a BASIC stub `RUN"SPEED"` loads a loader that reads the packs
  into the banks through AMSDOS, then switches the firmware off.
- **Tape:** a `.cdt` (TZX blocks with CPC timing). `make_tap.py` already
  writes TZX turbo blocks; it needs CPC pulse lengths and a CPC loader.
- A 64K CPC could load each row's packs from disc at a checkpoint instead.

## 10. Tools and tests

- **Emulator:** extend `tools/zxsim` with a CPC mode, or drive an existing
  CPC emulator headless. The tests depend on a scriptable emulator: key
  presses at frames, screenshots, memory watches and the AY log. The Z80
  core is reused; the new parts are the gate array (pens, mode, banking), a
  simple CRTC (screen start), the PPI/AY/keyboard and a Mode 0 renderer.
  That is about 1,000 lines of C.
- **Tests:** smoke, carcheck, stagecheck and a CPC rendercheck, all run for
  `PLATFORM=CPC`; `make_video.py` with a 1 MHz AY.

## 11. Phases

| Phase | Work | Size |
|---|---|---|
| 0 | the platform layer; the Spectrum build unchanged (§4) | M |
| 1 | CPC emulation in zxsim (or a headless emulator), screenshots and AY log | M |
| 2 | boot, memory map, banking, the 300 Hz interrupt, the screen flip, input | S |
| 3 | the road in Mode 0 with colour cycling, the bands, hills and the fork | L |
| 4 | the backdrop, masked sprites (scenery, traffic, car), HUD | L |
| 5 | sound at 1 MHz, front end screens, options | M |
| 6 | the tunnel, gantries and stage changes on the new renderer | M |
| 7 | disc and tape images, a loading screen, release packaging | S |
| 8 | speed tuning to 25 fps, playtesting | M |

The road (phase 3) is the heart of the port and the biggest risk: build it
first after the basics and measure its cost before the rest.

## 12. Risks and open questions

- **Speed:** masked sprites on a colour background cost more than the
  Spectrum's XOR on blank grass. Traffic counts may need trimming on the
  busiest stages.
- **Hills:** a hill changes every line's depth, which defeats colour cycling
  and forces full road redraws while hills are in view. The Spectrum has
  the same slow case today (curves and hills run nearer 16.7 fps).
- **Memory:** code and tables must fit in 32K beside two screens. Fall back
  to a 64-byte-wide screen (128 pixels in Mode 0, 12K a screen) if not.
- **Hardware details** *(verify)*: the CRTC screen-start latch timing for
  tear-free flips; the 300 Hz interrupt's position against the CRTC's
  vertical sync; PPI port C bit use for the AY on the 464 and 6128.
