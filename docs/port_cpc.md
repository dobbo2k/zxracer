# Porting Speed Run to the Amstrad CPC

A plan, not yet started. The first draft (21 November 2026) was reviewed on
22 November 2026 against three things that did not exist when it was
written: the Einstein port (`docs/port_einstein.md`), which showed how the
shared code really ports; the Wonder Boy project's two CPC ports
(`C:\ZX Spectrum\Wonderboy`: `docs/cpc-guide.md`, `docs/cpc-port-plan.md`,
`docs/cpc6128-port-plan.md`), which settle most of the CPC hardware
questions and supply tested code and tools; and Speed Run's own code and
measurements (`PLAN.md` 2.1 and 3.6). It was checked again on 24 November
2026 against the Einstein's later speed work and profile. Section 3 lists
what changed both times. Facts still marked *(verify)* must be checked in
MAME and WinAPE before the work that depends on them.

## 1. Target

- **Machine:** CPC 6128 (128K, the built-in 3" drive). A 464 or 664 with a
  64K expansion that uses the 6128's RAM configurations, and a disc drive
  (DDI-1 on the 464), runs it too. A 64K version would need the Einstein's
  approach (stages read at each checkpoint) and smaller caches; it is not
  planned.
- **Media:** a `.dsk` in AMSDOS DATA format (one side: 40 tracks of 9
  sectors of 512 bytes, 178K after the directory). Disc only: no tape
  (decided, section 10).
- **Frame rate:** the Spectrum's own pace, not the 25 fps the first draft
  gave. The Spectrum locks a game frame to 3 TV frames (16.7 fps,
  `MIN_FRAMES`), and its heaviest quarter of frames (hills, forks and
  traffic together) take 4 (`PLAN.md` 3.6: 15.6 fps over a whole game). The
  CPC aims for the same lock, with late frames made up as the Einstein's
  are (5.2). The estimate in section 6 says it will be marginal: expect
  12.5-16.7 fps. The Einstein, at a lock of 4 TV frames, reaches 12.35 fps
  in normal play (`docs/port_einstein.md` section 6).
- **Build:** `make cpc` gives `build/cpc/speedrun.dsk`. The Spectrum build
  stays byte-identical to `release/` at every step.

## 2. What to reuse

| From | What | Use here |
|---|---|---|
| Spectrum | the game: `player`, `track`, `hills`, `fork` (its pass-1 part), `traffic`, `game`, `extend`, `respawn`, `tunnel` logic, `scenery`'s projection, the music sequencer, `stages.yaml` and the stage tools | Assembled unchanged from the same `src/main.asm` (section 4) |
| Einstein port | the `-DEINSTEIN` pattern (one `main.asm`; about 70 switches in 24 shared files by now, section 4); `KEY_IN` and `FRAME_WAIT` macros; `AYN`/`AYD` periods; Spectrum-format screen B as a shadow that platform code converts; `make_einstein.py`'s gen/dat/patch data build; the fixed-step benchmark (`FIXED_ELAPSED`); the frame grid that makes up late frames (`EGrid`, `EIN_DEBT`); its exact speed-ups of the shared projection (`ApplyCurve`, the hill mapping's loop); its colour artwork (`tools/einstein_illustration.py`, `einstein_art.py`) as a reference for what each picture shows, not as the CPC's art (5.6) | The same mechanisms with `-DCPC` |
| Wonder Boy CPC | `hardware.inc` (ports, Gate Array commands, RAM configurations); `screen.asm` (interrupts, CRTC, the flip); `input.asm` (`read_key_row`); `sound.asm` (`ay_write` through the PPI, the register shadow); `sprites.asm` (masks by pen 0 through a table); `fdc.asm` and `disk_loader.asm` (the uPD765 reader, the AMSDOS boot); `tools/cpc/make_dsk.py`; `tools/cpc_harness.py` with `tools/mame/cpc_harness.lua`; `tools/winape_run.py`; `tools/cpc_profile.py` | Copied into this repository and adapted, as `make_einstein_disk.py` was. Wonder Boy assembles with z80asm, so the sources need sjasmplus syntax |

## 3. Review of the first draft

1. **No platform layer first.** The draft's step 0 split the Spectrum code
   behind an interface. The Einstein found that this would move most of
   bank 2's tightly packed layout (page-aligned tables, the chains at
   `PANO_LDI_END`, `XOR_END`, `FILL_END`, the IM2 table at `$BE00`), and
   instead assembles the same `main.asm` with `-DEINSTEIN`. The CPC does
   the same with `-DCPC` (section 4).
2. **The frame rate** was given as 25 fps, never below 16.7. The Spectrum
   runs at a 16.7 fps lock with 12.5 fps frames (section 1).
3. **The CPU** was "about the same speed in practice". Every instruction
   rounds up to whole microseconds (NOPs): about 3.3 MHz in practice
   (Wonder Boy's measure), against the Spectrum 128's 3.55 MHz with the
   game's code in uncontended bank 2. Expect the shared code to take 5-10%
   longer *(measure in phase 0)*.
4. **The screen** was Mode 0 at 160 x 200. 128 x 192 (64 bytes a line, as
   Wonder Boy's) is better: every x the game computes is a Spectrum pixel,
   and halving it gives the Mode 0 pixel, so the projection, the road's
   edges and the sprites' positions need no new scaling. The picture keeps
   the Spectrum's shape and size on the TV. A screen is 12K, not 16K, and
   leaves 512 bytes free at the end of every 2K (4K a screen). A line is 64
   bytes to fill, not 80.
5. **The memory map** put code at `$0000-$7FFF` and the screens at `$8000`
   and `$C000`. That breaks the shared code's fixed addresses in
   `$8000-$BFFF`. Section 5.3 keeps bank 2's layout as it is.
6. **The packs** were to go into the 6128's 64K of banks. The Spectrum's
   pack banks 0, 1, 3, 4 and 6 hold about 76K (measured in
   `build/tape_ram.bin`: banks 0, 1, 3 and 4 nearly full, bank 6 to
   `$2F8A`), and only banks 4-6 are free for them here (48K). They must be
   kept packed (section 5.11).
7. **Colour cycling** for the road bands does not fit the draft's own pen
   budget. With N phases, grass, kerbs and the centre line each need N
   pens (a kerb pen must follow its grass pen's light and dark), so 4
   phases take 13 of the 16 pens before the sky, the panorama, the car and
   the scenery. The draft's "kerbs 2" breaks the scheme. It also saves
   nothing on curves and hills, where the edges move every frame anyway:
   in the Einstein's attract demo 11 of the 12 road rows change shape every
   frame. Section 5.4 redraws the road instead.
8. **The fill cost** was "about 5.5 us for two bytes" and "roughly half a
   frame" for 96 lines of 80 bytes. `PUSH` takes 4 us: 2 us a byte. 96 x 80
   bytes would take 15.4 ms (77% of a TV frame) in `PUSH`es alone; 96 x 64
   take 12.3 ms.
9. **The interrupt** was "IM 1". Either mode works: the Gate Array's
   interrupt is acknowledged by the Z80's acknowledge cycle in any mode.
   The Spectrum's IM 2 table (257 bytes of `$BD` at `$BE00`, `JP Isr` at
   `$BDBD`) works whatever byte the bus holds, so it stays *(verify on a
   real 6128 if one is available)*.
10. **Testing** budgeted about 1,000 lines of C for a CPC mode in zxsim.
    Wonder Boy's MAME harness and WinAPE runner exist and are proven
    (section 7).
11. **Tape** was "make_tap.py's TZX blocks with CPC pulse lengths". The
    CPC's loader is the firmware's own format, which Wonder Boy's
    `make_cdt.py` writes. With 128K needed, tape matters less; it is not
    made (disc only, section 10).
12. **The verify list** is mostly settled: the PPI's port C bits (0-3 the
    keyboard row, 4 the cassette motor, 6-7 the AY's function), the
    interrupts' positions (2 lines after VSYNC begins, then every 52) and
    the start address's latching (section 5.2).

Checked again on 24 November 2026:

13. **The Einstein's switches** have grown to about 70, and are of three
    kinds, which the `NATIVE_GFX` step must keep apart: some mean "not the
    Spectrum's screen", some are exact speed-ups the CPC can share, and
    some fit only the Einstein's drawing (section 4).
14. **The shared work is measured:** the Einstein's profile puts the game's
    logic, the road's projection and hills and the objects' projection at
    about 79K T a game frame, not the 105K first guessed (section 6).
15. **The residents are smaller:** the crew's close-ups are gone from the
    game, leaving 635 bytes free in bank 5 (section 5.3).
16. **Late frames made up:** the Einstein's frame grid (a frame that comes
    late lets the next come a TV frame sooner, up to 4 TV frames) gained
    about 0.3 fps there for a few bytes, and suits the CPC too (5.2).
17. **The heavy frames set the rate:** on the Einstein the frames with big
    objects near the car (16% of them) are the ones that miss the lock.
    The CPC's estimate must hold for those, not only on average (section 6).
18. **The unlocked benchmark** can't be built with `-DMIN_FRAMES=1` as
    written: `MIN_FRAMES` in `defs.asm` has no `IFNDEF` guard (section 7).

## 4. The build: `-DCPC`

`src/main.asm` with `-DCPC` and `src/cpc/` for the platform code, as the
Einstein's `src/einstein/`. The shared files' switches today, and what the
CPC needs at each:

| File | The Einstein's switch | The CPC |
|---|---|---|
| `road.asm`, `fork.asm`, `horizon.asm`, `car.asm`, `tyres.asm` | the Spectrum's drawing left out | the same: drawn by `src/cpc` |
| `road.asm` `RoadPrepare` | every row's shape marked to draw | not needed if the road is redrawn every frame |
| `interrupt.asm` | the CTC's tick; `Isr` is `EinIsr` | the Gate Array's six interrupts; `Isr` is `CpcIsr` |
| `sound.asm` `AyWrite`, `EngineUpdate` | the Einstein's ports; revs x 56 | the PPI sequence; revs x 28 (50 x 0.564) |
| `holes.asm` (the crash's thud) | `EinCoarse` | a 1 MHz equivalent |
| `input.asm` | `EinJoy` | the joystick from matrix line 9 |
| `hud.asm`, `extend.asm`, `lampdraw.asm` | `EinMarkCell`, `EinMarkBig`, `EinLampCells` | the same hooks: cells to convert |
| `lampdraw.asm`, `tunnelb2.asm`, `holes.asm`, `pause.asm` | screen B only (screen A's memory holds buffers) | the same |
| `scenery.asm` | the object's type in the draw command; the car's overlap test out | the same |
| `player.asm` | `Elapsed` up to 8 | the same, if frames take 5 or more |
| `road.asm` pass 1, `hills.asm` `HillStore`, `defs.asm` | `EIN_NOLANE`: no centre line, so pass 1 and the hill mapping leave it out (its registers do other work) | not if the CPC draws the centre line (5.4); then the Spectrum's pass 1 |
| `road.asm` `RoadBands` | outside tunnels, the bands of lines 0 and 4 of each row only (all the Einstein's road reads) | not this: the CPC draws every line pair's band |
| `track.asm` `ApplyCurve`, `hills.asm` `HillMap` | exact speed-ups: the same results, quicker | the same |
| `stage.asm`, `stageov.asm`, `pics.asm` | packs and pictures read from the disc | packs unpacked from banks 4-6 (section 5.11) |
| `frontend.asm` | screen A shown as a bitmap | section 5.9 |

The switches are of three kinds. Most mean "not the Spectrum's screen".
Before the CPC work starts, give that a name of its own: `defs.asm`
defines `NATIVE_GFX` when `EINSTEIN` or `CPC` is defined, and the shared
files test it. The exact speed-ups (`ApplyCurve`, `HillMap`) get a name of
their own too, for both ports. The rest stay `EINSTEIN`: `EIN_NOLANE`, the
bands of lines 0 and 4, `EinShape`. A blanket rename of `EINSTEIN` to
`NATIVE_GFX` would give the CPC a road without its other line pairs'
bands. The Spectrum's bytes don't change; check with `make
build/speedrun.tap` and `cmp` against `release/`.

The generated files come from `tools/make_cpc.py` in the Einstein's three
steps (`gen` before the stage packs are assembled, `dat` after, `patch`
after the game), into `build/cpc`, last on the include path.

## 5. Design

### 5.1 The hardware, as Wonder Boy found it

| | Spectrum 128 | CPC 6128 |
|---|---|---|
| CPU | Z80 3.5469 MHz, 70,908 T a frame | Z80 4 MHz rounded to whole us: a frame is 19,968 us (312 lines of 64 us). `PUSH` 4 us, `POP` 3, `LDI` 5, `LD (HL),r` 2, `OUT (C),r` 4 |
| Screen | 256x192 bitmap, attributes, banks 5 and 7 | CRTC 6845 (five types, 0-4, differ in details) and Gate Array. A screen is any of the four base 16K blocks; a character row's 8 lines are 2K apart; the start address counts words and wraps within each 2K |
| Modes | - | Mode 0: 2 pixels a byte, 16 pens; Mode 1: 4 pixels, 4 pens. A mode change takes effect at the next HSYNC |
| Colours | 15 fixed | 27; 16 pens and the border, any pen any colour at any time (Gate Array `%010ccccc` after `%000ppppp`) |
| Memory | bank 5 at `$4000`, 2 at `$8000`, any at `$C000` | Gate Array `$C0`-`$C7`: C0 = base 0,1,2,3; C1 = 0,1,2,7; C2 = 4,5,6,7; C3 = 0,3,2,7; C4-C7 = 0,(4-7),2,3. The CRTC reads the base 64K only |
| Interrupt | 50 Hz, IM 2 | 300 Hz: 2 lines after VSYNC begins, then every 52 lines. The VSYNC one is found by PPI port B bit 0. A request waits while interrupts are off and is acknowledged when taken *(verify: none lost when off for up to a line pair's fill)* |
| Sound | AY at 1.7734 MHz, ports `$FFFD`/`$BFFD` | AY-3-8912 at 1 MHz through the PPI: port A (`$F4xx`) its bus, port C (`$F6xx`) bits 6-7 its function: 6 `OUT`s a register |
| Keyboard | 8 half-rows, port `$xxFE` | 10 lines of 8, the line on PPI port C bits 0-3, read from the AY's register 14 (port A). The mixer must keep port A an input (register 7 bit 6 clear) |
| Joystick | Kempston | matrix line 9: up 0, down 1, left 2, right 3, fire 4, second fire 5 |
| Ports | - | all addressed by B (`OUT (C)`), so B can't count a loop around them |
| Disc | - | uPD765: status `$FB7E`, data `$FB7F`, motor `$FA7E` |
| ROMs | - | switched off with the Gate Array's `%100iurmm` (`$8C`: mode 0, both off). Firmware and AMSDOS use `$A700-$BFFF` while they run |

### 5.2 The screen and the CRTC

- **Geometry:** R1 = 32 (64 bytes a line), R6 = 24 rows, R9 = 7, R4 = 38
  (39 rows, 312 lines). Mode 0: 128 x 192 pixels, each two Spectrum pixels
  wide. A screen uses offsets `$000-$5FF` of each 2K; `$600-$7FF` of each
  is free (4K a screen).
- **Layout, as the Spectrum's:** rows 0-9 sky, with the HUD in rows 0-5
  (score row 1, the big timer, speed and gear, the message line row 5) and
  the starting lights; rows 10-11 the panorama (`PANO_Y` 80); rows 12-23
  the road (`ROAD_Y0` 96, 96 lines).
- **The interrupts' lines** follow from R7 (VSYNC's row). With R7 = 30
  (VSYNC at line 240) they come at display lines 34, 86, 138 and 190, and
  242 and 294 in the border. With R7 = 31 (line 248): 42, 94 and 146, and
  198, 250 and 302 in the border. R7 also moves the picture on the TV: choose it
  in WinAPE with the picture centred, then place any raster work (5.7).
- **Two screens:** screen A in base block 1 (R12 bits 4-5 = `%01`), screen
  B in base block 3 (`%11`). The hidden one is always at `$4000` for the
  CPU: C1 while A is hidden, C3 while B is (Wonder Boy's key). Bank 7 is at
  `$C000` in both.
- **The flip:** the VSYNC interrupt writes R12 and R13. The CRTC takes the
  start address when the next frame starts (line 0, 60-70 lines later),
  and the lines between are border, so the screen just hidden may be drawn
  into as soon as the interrupt has written them *(verify on each CRTC type
  in WinAPE; Wonder Boy's flip, written at its interrupt index 2, works on
  types 0 and 3 and was seen working on 1 and 4; 2 is untested)*. The
  interrupt changes only what is shown: the main code selects C1 or C3
  itself, after `WaitFlip` and before it draws.
- **Blanking** (the Spectrum's blanked screen B during a stage load): all
  16 pens black, 32 Gate Array writes.
- **The frame lock:** a frame is shown at the VSYNC interrupt once
  `MIN_FRAMES` (3) TV frames are due, on a grid as the Einstein's (`EGrid`
  in `src/einstein/boot.asm`): after a late frame the next may come a TV
  frame sooner, but never less than 2 apart, till the grid is kept again,
  owing at most a few TV frames. `LastFlip` stays the real flip (the
  stage's jingle waits for it).

### 5.3 Memory (CPC 6128)

| CPU address in play (C1 or C3) | Contents |
|---|---|
| `$0000-$3FFF` base 0 | what the Spectrum keeps resident in bank 5 at `$5B00-$7FFF` (8.0K to `$7B24`: scenery and car data, font, the music player, the stage loader's ways in, the tunnels' mouths; then 635 bytes free and the 640-byte track cache), assembled here under `-DCPC`; the CPC code: the interrupt, road and sprite drawers, cell conversion, keys, disc; page-aligned tables (pen-0 masks, mixed-pen bytes, 1-bit-to-Mode-0) |
| `$4000-$7FFF` the hidden screen | base 1 (A) or base 3 (B). The stage overlay runs here as on the Spectrum (`StageOv` at `$4000`, the other screen shown and blanked). Each screen's 4K of gaps holds that screen's own state (what it shows: lines' spans, the sky cells objects covered). The overlay (about 1.9K) runs past the first gap at `$4600`; the display reset sets the gaps afresh after it |
| `$8000-$BFFF` base 2 | the Spectrum's bank 2 as it is: code, tables, chains, IM2 table, stack |
| `$C000-$FFFF` bank 7 | `$C000-$DAFF`: the Spectrum's screen B as a shadow (5.7); `$DB00-$FFFF`: the theme cache (Mode 0 sprites, panorama, palette) or the front end, at `THEME_CACHE` as on the Spectrum |
| banks 4-6 | 48K: every stage pack, the pictures and the front end, packed |

Rules:

- **The interrupt** and everything it calls (the music player, its tunes,
  the key scan) must be in base 0 or base 2. Stage loads page a pack bank
  in at `$4000` (C4-C6), which also puts base 3 in place of bank 7 at
  `$C000`. The Spectrum has the same problem, its pack banks taking bank
  7's place at `$C000`, and its loader bounces theme packs through the
  track cache: the CPC keeps that, with the track cache in base 0.
- **Base 0 is the budget to watch:** 16K for the Spectrum's 8.7K of
  residents and track cache (some of them graphics, whose Mode 0 size differs) and the CPC
  code (estimate 6-8K). The fallback is the gaps in base 2 (`holes.asm`)
  and bank 7 below the theme cache. Measure in phase 0.
- **Sizes of the Mode 0 art:** a Spectrum sprite stores 2 bits a pixel
  (bits and mask) in 2-4 pre-shifted copies. In Mode 0 at half width it is
  4 bits per two Spectrum pixels (2 a Spectrum pixel), pen 0 standing for
  the mask, and the same steps need half the copies (a byte is 4 Spectrum
  pixels; two copies give 2-pixel steps). So a theme's sprites should take
  about what they take now, or less. The panorama (512 Spectrum pixels by
  16 lines) is 2K a copy.

### 5.4 The road

The Spectrum colours its bands with attributes, a band per character row
(from the row's middle line), and writes only kerb bytes and the centre
line. A CPC has no attributes: every pixel carries its colour. The plan:

- **Shape:** `RoadPrepare` (curves, fork, pass 1, hills, bands) runs as on
  the Spectrum, in the time the last frame waits for its flip.
- **Every game frame, the road's 96 lines are drawn again** into the hidden
  screen, a line pair at a time (pass 1's resolution): grass, kerb, road,
  centre line, road, kerb, grass, from `D`/`E`, the kerb's width and the
  pair's band. Bands are per line pair, not per row: smoother than the
  Spectrum's, at no extra cost. A fork line pair has two roads (up to nine
  runs). A tunnel's line pairs have walls and lamps in place of grass (the
  band's tunnel bit), and the portal and the gantry are spans too.
- **Why not draw only what changed:** at speed a line pair's band changes
  every few frames, and on curves and hills its edges move every frame. A
  full redraw costs the same every frame, so the frame rate is steady. It
  also means sprites in the road need no saving or erasing: the next
  redraw covers them. A per-pair check (spans, band, covered last time in
  this screen) to skip unchanged pairs at low speed is an optimisation for
  phase 7.
- **Filling:** each run with `PUSH` from an unrolled chain entered at its
  length, both lines of a pair from one set-up (the second line is `$800`
  on). A boundary at an odd pixel is a mixed byte from a 16 x 16 table (left
  pen, right pen). Interrupts are off for a line pair at a time (about
  0.3 ms), so an interrupt can be that late; the PUSHes would otherwise
  write its return address into the picture.
- **Cost:** 96 lines x 32 `PUSH`es x 4 us = 12.3 ms, plus about 40-60 us of
  set-up a line: 16-18 ms a game frame *(measure in phase 2)*.
- **The centre line:** the Einstein leaves it out, for speed
  (`EIN_NOLANE`). In a full redraw it is a run or two more a line pair, so
  the CPC keeps it unless phase 2's measure says otherwise; without it the
  CPC could share the Einstein's pass 1 and `HillStore` (section 4).
- **Colour cycling** stays a later experiment for straight, flat road
  only, if the pens allow (3.7).

### 5.5 Pens

A starting budget, each theme and stage setting the colours (a
`cpc_palette` in `assets/stages.yaml`, as `einstein_palette`):

| Pen | Use |
|---|---|
| 0 | road (pen 0 is also the sprites' transparent pixel: no sprite needs the road's colour) |
| 1 | black: outlines, tyres |
| 2 | white: centre line, the light kerb, text |
| 3 | red: the dark kerb, the car, the timer |
| 4, 5 | grass light and dark (tunnel: the walls' light and dark) |
| 6 | sky (the sunset theme can change it at the sky's interrupts) |
| 7, 8 | the panorama: far and near |
| 9-15 | scenery, traffic and the car's other colours, per theme |

### 5.6 Sprites: scenery, traffic, the car

- **The draw commands stay the shared code's.** `scenery.asm` and
  `traffic.asm` project and clip as now (the crest clip, `ProjClip`), and
  write their draw commands; the CPC draws them from the command list in
  place of the Spectrum's XOR chain, far to near, then the car.
- **Masked by pen 0** through a 256-byte table (Wonder Boy's): no stored
  masks. Erasing: none in the road (5.4). Where a sprite reaches rows
  10-11 or the sky, its bytes are noted in that screen's gaps and put back
  from the clean panorama or sky before that screen is drawn again.
- **Art:** new art for the CPC (decided, section 10), not converted from
  the Einstein's: drawn for Mode 0's pixels, twice as wide as tall, and
  for the CPC's 27 colours, each theme within its pens (5.5). New tools,
  `tools/cpc_illustration.py` for the masters and `tools/cpc_art.py` for
  the theme packs' bytes, as the Einstein's pair; `docs/cpc_artwork.md`
  describes it, as `docs/einstein_artwork.md` does the Einstein's. The
  Spectrum's and the Einstein's pictures show what each object, sky and
  backdrop is. The sizes stay those `make_scenery.py` gives the Spectrum
  (the projection and the clipping depend on them). Pre-shifted copies:
  one for the near sizes (4-pixel steps, as the Spectrum's), two for the
  far ones.
- **Placeholder art** while the new art is drawn: the Spectrum's sprites
  converted to one pen, so that the drawer, the clipping and the speed
  can be built and measured in phase 3 without waiting for it.
- **The car:** the Riviera Spider's poses (straight, steering, smoke) in
  Mode 0, drawn last. The rolling tyres are left out at first, as on the
  Einstein (the crew's close-ups are gone from the game).

### 5.7 Sky, panorama, HUD and text

- **The Spectrum's code draws them, into a shadow.** The HUD, the message
  line, the starting lights, the pause message and the tunnel's sky rows
  draw into the Spectrum's screen B format at `$C000` (bank 7), as on the
  Einstein. The cells they write are marked (the Einstein's hooks), and
  the CPC converts each marked cell into both screens: 8 bytes of bits and
  an attribute become 8 lines of 2 Mode 0 bytes, each pair of Spectrum
  pixels one Mode 0 pixel, ink and paper mapped to pens.
- **The font** for that halving: `make_font.py` gives the CPC build a font
  drawn 4 pixels wide with each pixel doubled, so halving gives exactly the
  4-pixel design. Text keeps the Spectrum's layout and size on the TV.
- **The sky and the panorama:** the sky artwork in Mode 0 from the theme
  pack, drawn into both screens at a stage start; the panorama redrawn
  only when it scrolls (a byte is a 4-pixel step, the Spectrum's near
  step) or where a sprite covered it.
- **The HUD in Mode 0** (decided, section 10): the whole screen is Mode 0,
  with no mode change part way down. A Mode 1 band for rows 0-5 (the
  Spectrum's cells exactly, 4 pens) was weighed and not taken: it needed a
  mode change at line 48 timed from an interrupt, about 0.4 ms of waiting a
  TV frame, and holding on every CRTC type.

### 5.8 Sound

- **Periods:** `AYN`/`AYD` = 564/1000 (1,000,000 / 1,773,400) in
  `defs.asm`, as the Einstein's 1128/1000; the tune's notes from their own
  table (`music_notes.asm`, made as the Einstein's is for its 2 MHz AY, for
  1 MHz); the engine's step 28 a rev (50 x 0.564); the crash's thud as `EinCoarse`
  does it for 2 MHz. Periods get smaller, so high notes lose a little
  precision (a C7 is period 30 at 1 MHz).
- **`AyWrite`:** the PPI sequence (register on port A, port C select,
  inactive, value, write, inactive). Register 7 is masked with `$3F`
  (ports A and B inputs), as the Einstein's `AyWrite` forces its own bits.
  Wonder Boy's shadow of the registers skips writes that change nothing
  (each write is about 30 us).
- **`SoundTick`** runs at the VSYNC interrupt (one in six).

### 5.9 Input

- **`KEY_IN`**, as on the Einstein, answers the Spectrum's half-row reads
  from the CPC's matrix: a table from each Spectrum half-row and bit to a
  CPC line and bit. Q, A, O, P, SPACE, H (pause) and ENTER (options) all
  exist on the CPC. The redefine screen keeps the Spectrum's key names; the
  CPC's extra keys are not offered.
- **The scan runs in the VSYNC interrupt**, after `SoundTick`, all 10
  lines into a buffer that `KEY_IN` reads. A scan in the main code would be
  broken by the interrupt's AY writes, which change the selected register
  and port A's direction. 10 lines cost about 0.15 ms.
- **The joystick** (line 9) gives the Kempston's bits (`IN_RIGHT` and the
  rest) and always works, as the Kempston does.

### 5.10 The front end

The front end draws Spectrum screens into screen A (`$4000`), and on the
Einstein the whole of screen A is shown as a bitmap. On the CPC:

- **Text screens** (high scores, options, the route map's names, initials):
  drawn into the shadow and converted as in 5.7, in Mode 0 with the
  doubled-pixel font, as the HUD.
- **Pictures** (the loading screen, the title, the five goal postcards):
  native Mode 0, 16 pens, new art as the sprites' (5.6), packed, unpacked
  into the hidden screen and flipped to. The
  printed parts (score, bonus, the blinking prompt) go through the shadow.
- `FRAME_WAIT` (the Einstein's frame wait, which sends changed cells)
  becomes the CPC's convert-and-flip.

### 5.11 Discs, packs and loading

- **The disc:** a BASIC stub (`RUN"SPEED"`) loads a first stage through
  AMSDOS. It shows the loading screen (the cover in Mode 0), loads the
  game and the packs into the banks with AMSDOS's own calls while the
  firmware is alive, then switches both ROMs off and starts the game.
  Code for `$8000-$BFFF` (which overlaps the firmware's RAM) is loaded
  packed into a bank and unpacked there only once the firmware is off.
- **Everything in RAM:** after the boot the game never reads the disc, as
  the Spectrum never reads the tape. The packs stay packed in banks 4-6
  (`zpack`: the Spectrum's whole image packs 95.7K to 52.9K) and are
  unpacked into the caches at a stage start through the `$4000` window.
  **If they don't fit** (measure in phase 0), the fallback is the
  Einstein's: each stage's packs read from the disc at a checkpoint, with
  Wonder Boy's `fdc.asm`.
- **Space:** the whole game packed should be well under one side's 178K.
- **No tape:** disc only (section 10). A `.cdt` (Wonder Boy's
  `make_cdt.py`, 4-6 minutes to load) is not made.

## 6. The frame budget (estimate)

A game frame at the 3-TV-frame lock has 59.9 ms on the CPC (Spectrum:
212,700 T). Shares, from the Spectrum's and the Einstein's measurements:

| Work | Spectrum | CPC (estimate) |
|---|---|---|
| Shared: logic, pass 1, hills, the sprites' projection | about 105K T (the first guess); the Einstein's profile: about 79K T | 24-28 ms |
| Interrupts: sound, key scan | about 9K T | 3 ms |
| The road, 96 lines | 48K T (rows and lines) | 16-18 ms |
| Scenery and traffic | 16K T | 6-12 ms (twice the bytes, each masked) |
| The car | 7K T | 2-3 ms |
| HUD and sky cells, the panorama | 10K T | 1-3 ms |
| **Total** | about 205-260K T | **52-66 ms** |

So the light frames should keep the 16.7 lock and the heavy ones take 4 TV
frames, as on the Spectrum, if these estimates hold. The shared figure is
the Einstein's profile of 300 fixed-step game frames (24 November 2026:
the road's projection and hills 57K T, the game's logic and sound 14K, the
objects' projection about 8K), at the CPC's 3.3 MHz in practice. The shared
work is the biggest share; the Einstein changed it only where the results
are exactly the same. Phase 0 measures it on the CPC before anything is
drawn.

The averages hide the frames that set the rate. On the Einstein the frames
with big objects near the car, 16% of them, take 5 to 7 TV frames where
the rest take 4. On the CPC the cost of an object grows with its bytes
(each masked), so the scenery and traffic row can reach twice its average
in those frames: phase 3 measures the slowest frames (the frame histogram
and the costliest routines of the frames that miss the lock), not only the
average.

## 7. Tools and tests

- **Emulators:** MAME 0.288 (`C:\ZX Spectrum\Wonderboy\tools\vendor\mame0288`)
  headless as `cpc6128`, with Wonder Boy's ROM set
  (`C:\ZX Spectrum\Wonderboy\build\mame\roms\cpc6128`: `cpc6128.rom` and
  `cpcados.rom`, not committed in either project). `local.mk` gets
  `CPC_MAME` and `CPC_ROMS`, as `EINSTEIN_REPO`. WinAPE
  (`C:\ZX Spectrum\Wonderboy\build\winape\WinApe.exe`) for play and the
  CRTC types; ZEsarUX also has a 6128 for a third opinion.
- **Harness:** `tools/cpc_harness.py` and `tools/mame/cpc_harness.lua` from
  Wonder Boy: `frames`, `hold`, `release`, `peek`, `poke`, `shot`, `ay`,
  `until`, `disk eject`/`insert`. Wonder Boy's traps apply: one MAME at a
  time, MAME's `-state` hangs (load states from Lua), wait on a game state
  rather than a frame count.
- **`make test-cpc`** (`tests/cpc_check.py`):
  - the disc boots to the title, then the attract demo runs 2,000 frames;
  - a game starts, the lights count down, the clock and score run;
  - the AY log has the tune, at the right pitches for 1 MHz, and register
    7's bit 6 is always clear;
  - every stage and theme loads (`-DFIRST_STAGE`, checkpoints), with a
    screenshot each (`build/cpc/stage_NN.png`);
  - a rendercheck: screenshots of a `FIXED_ELAPSED` run against saved ones;
  - the frame histogram: VSYNCs between flips over 300 game frames (the
    Einstein's `fliphist`), which must stay at or above a set rate;
  - the Spectrum's build still byte-identical.
- **The benchmark:** the Einstein's, with `-DFIXED_ELAPSED=1`: 300 game
  frames of the attract demo, in TV frames, locked and unlocked
  (`-DMIN_FRAMES=1`: that needs an `IFNDEF MIN_FRAMES` guard in `defs.asm`,
  the Spectrum's bytes the same, or a `CPC_MIN_FRAMES` as the Einstein's
  `EIN_MIN_FRAMES`). Each phase records it.
- **Pictures that don't depend on speed:** the Einstein's checks slow the
  lock (8 TV frames, nothing made up), because its sky over a tunnel's
  mouth is sent over several TV frames and a faster build was pictured
  part way through it. The CPC flips whole screens, so a picture taken as
  a game frame is drawn should always show the one before in full: check
  that in phase 1, and slow the lock for the rendercheck if not.
- **Profiling:** MAME's debugger trace counted by label
  (`tools/cpc_profile.py`). MAME gives no T-state profile like zxsim's or
  Albert's; the trace's PC counts serve.

## 8. Phases

| Phase | Work | Done when | Size |
|---|---|---|---|
| 0 | `NATIVE_GFX`; `-DCPC` assembling with the drawing stubbed; the Wonder Boy tools copied; `local.mk`. **Measure:** the shared work's time on the CPC (the benchmark with nothing drawn), base 0's fill, the packs' packed size, the Mode 0 art's size | The Spectrum's build is byte-identical; the measures decide 5.3 and 5.11 (packs in RAM or from the disc) | S |
| 1 | Boot from the `.dsk`; firmware off; C1/C3; IM 2 and the six interrupts; the flip with test patterns; the key scan; `AyWrite`; a tune | In MAME the demo's logic runs (`GameFrames` counts), keys start a game, the tune is in the AY log at 1 MHz pitches; WinAPE shows the flip on types 0-4 | M |
| 2 | The road: line pairs every frame, bands, kerbs, centre line, hills, the fork, tunnel walls, the portal and gantry | Screenshots of all 15 stages; the benchmark. **Decision:** the road's cost against 16-18 ms; if far over, the skip of unchanged pairs or colour cycling on straights | L |
| 3 | Scenery, traffic and the car: the masked drawer, the crest clip, crashes, with the placeholder art (5.6) | Every theme's objects in screenshots; the benchmark: the 3-TV-frame lock in most frames | L |
| A | The CPC's art, alongside phases 2-6: `cpc_illustration.py`, `cpc_art.py`, `docs/cpc_artwork.md`; one theme (the coast, stage 1: its scenery, traffic, the car, sky and backdrop, palette) first, for the owner's approval, then the other themes, the signs, the tunnels' mouths and the gantry, the loading screen, the title and the goal postcards | Each theme approved from screenshots in MAME; the placeholders gone; the theme packs within their caches | XL |
| 4 | The sky, the panorama, the shadow and its conversion, the HUD, the message line, the starting lights, pause, the font | The HUD reads right at every stage, in Mode 0 | M |
| 5 | Stage loads from the banks, checkpoints, palettes per theme and stage, the front end (title, high scores, options and keys, goal and route screens) | A whole game plays through in MAME, front end included; `make test-cpc` passes | M |
| 6 | The loading screen, the disc's boot files, `release/` (the `.dsk`, a README) | Boots from the release `.dsk` in MAME and WinAPE | S |
| 7 | Speed, WinAPE across the CRTC types, a real 6128 if one is available | The benchmark recorded; plays through on real hardware | M |

The road (phase 2) is the heart of the port and the biggest risk: build it
first after the basics, and measure it before the rest. Phase 0's
measurements come first of all: they decide the memory map's fallbacks.

## 9. Risks

| Risk | Plan |
|---|---|
| The shared work alone takes half the frame (section 6) | Measured in phase 0. As on the Einstein it is left alone; the CPC's own drawing is where time is won. A rate of 12.5 fps, as the Einstein's, is the floor to accept |
| The road costs more than 18 ms | Phase 2's decision: skip unchanged pairs, colour cycling on straights, a narrower road area |
| Base 0 too small for the residents and the CPC code | Phase 0's measure; then base 2's holes and bank 7 below the theme cache |
| The packs don't fit banks 4-6 packed | Stages from the disc at each checkpoint (the Einstein's way, Wonder Boy's `fdc.asm`) |
| Half width loses detail (a centre-line dash is 2 Spectrum pixels wide at least, the kerb's steps are coarser) | Judged in phase 2's screenshots. Mode 0 at 160 wide is the fallback, at the cost of scaling every x by 5/8 |
| The heavy frames (big objects near the car) miss the lock though the average fits | Measured in phase 3 from the slowest frames; late frames made up (5.2); then the objects' drawer tuned first |
| Interrupts late or lost while the fills have them off | Verified in phase 1 in MAME and WinAPE; fills split into shorter stretches if needed |
| The flip on some CRTC types | WinAPE on types 0-4 in phase 1 (Wonder Boy's flip already holds on 0 and 3); no mode split to test, the HUD being Mode 0 |
| The new art is the largest single job | Its own phase (A), beside the code, which builds on placeholders; one theme first, for approval, before the rest; the sizes and shifts stay `make_scenery.py`'s; each theme pack's size checked against its cache as it is made |
| Wonder Boy's code is z80asm, Speed Run's sjasmplus | Copied file by file with their tests' behaviour as the check |

## 10. Decisions (the owner, 24 November 2026)

1. **Media:** the 6128 and disc only; no tape (5.11).
2. **The screen:** Mode 0 at 128 x 192 (5.2).
3. **The HUD:** Mode 0, with the doubled-pixel font; no Mode 1 band (5.7).
4. **The art:** new art for the CPC, not converted from the Einstein's
   (5.6, phase A).

## 11. Progress

### Phase 0 (25 November 2026)

- **`NATIVE_GFX` and `FAST_PROJ`** (`src/defs.asm`): the shared files test
  `NATIVE_GFX` where they mean "not the Spectrum's screen", `FAST_PROJ`
  for the exact speed-ups (`ApplyCurve`, `HillMap`); `EIN_NOLANE` and the
  bands of lines 0 and 4 stay the Einstein's. The hooks the shared code
  calls are named for no platform (`GfxMarkCell`, `GfxMarkBig`,
  `GfxLampCells`, `GfxScreensEnter`, `GfxFrontOn`, `GfxPicture`,
  `GfxJoy`): the Einstein's `platform.asm` points them at its own. The
  Spectrum's tape and the Einstein's `SPEEDRUN.COM` and `STAGES.DAT` are
  byte-identical to before. `MIN_FRAMES` has its `IFNDEF` guard.
- **`make cpc`** builds `build/cpc/speedrun.dsk` (`tools/make_cpc.py`: gen,
  the stage packs, dat, the game, patch, the loader, dsk): `RUN"SPEED"`.
  `src/cpc/`: `platform.asm` (the map), `boot.asm` (`CpcBoot`, the
  interrupt, the frame grid), `flip.asm`, `keys.asm` (the scan in the
  interrupt, `CpcSpecIn` for `KEY_IN`, the joystick), `disc.asm` and
  `fdc.asm` (Wonder Boy's reader), `loader.asm` (`SPEED.BIN`), and the
  drawing's stubs (`draw.asm`). Sjasmplus can't use labels that begin
  `CPC_` (the define `CPC` is put in their place): the frame grid's are
  `FLIP_DEBT` and `FLIP_GAP`.
- **The tools:** `tools/cpc/make_dsk.py`, `tools/cpc_harness.py` with
  `tools/mame/cpc_harness.lua` (Wonder Boy's, without its autoplay; with
  `reg`, `frame`, `save`), `CPC_MAME` and `CPC_ROMS` in `local.mk`.
- **The packs don't fit in RAM** (5.11's measure): the Einstein's packs
  alone pack to about 61K, and the CPC's Mode 0 art and pictures will be
  more, against the 48K of banks 4-6. So the fallback: the packs are on
  the disc, in `SPEED.DAT`, each packed (`zpack`) from a sector of its
  own, and read when needed (`CpcLoad`: into bank 4, then unpacked from
  there a byte at a time with bank 4 paged in, to wherever it goes). The
  stage table holds (first sector, packed bytes) where the Spectrum has
  (bank, address, length), as the Einstein's. `SPEED.DAT` is the disc's
  first file (from sector 4), so its packs' places don't depend on the
  loader's size; the game's image is last in it. The disc: 122 of 356
  sectors so far.
- **The loader:** AMSDOS loads `SPEED.BIN` at $1000 and it moves itself to
  $C000 (base 3). Loaded at $C000 it was cleared by the firmware as the
  program started (the screen is reset).
- **Base 0:** the CPC's code $0000-$0479 so far; the residents $1B00-$3209
  (5.9K: without the Spectrum's car); 2.9K free before the track cache at
  $3DA0; 5.7K free between. **Bank 2:** `CodeEnd` $97FE, 2.8K free before
  the tables.
- **The benchmark with nothing drawn** (`-DFIXED_ELAPSED=1`, game frames
  20-320 of the attract demo): locked, 3.000 TV frames a game frame (16.67
  fps); unlocked (`-DMIN_FRAMES=1`), 1.480: the shared work, the interrupt
  and the HUD into the shadow take 29.6 ms a game frame, as section 6
  estimated (27-31 ms with the interrupts). About 30 ms a game frame are
  left for the CPC's drawing at the 3-TV-frame lock.

### Phases 1-5 so far (25 November 2026)

- **Phase 1:** the disc boots in MAME (`RUN"SPEED"`), the firmware off,
  C1/C3, IM 2 and the six interrupts (the VSYNC one counted, or the sixth
  since it if taken late), the frame grid, the key scan in the interrupt,
  `AyWrite` through the PPI. SPACE starts a game; the AY log has the engine
  at period 790 (1400 x 0.564) and the tune at 1 MHz periods, the mixer's
  bit 6 never set. WinAPE across the CRTC types: still to do (phase 7).
- **Phase 2, the road** (`src/cpc/road.asm`): every line pair redrawn each
  game frame, a word at a time with PUSH: the four edges' "special" words
  from a table (by the band's class, the edge, its pixel in the word), the
  runs between them unrolled chains entered at their lengths, every step's
  jump patched so a run can be left out (the road off the screen's edge, a
  kerb inside one word). The far road in one word and a fork's two roads go
  a slow way (grass through the program, then a byte at a time). Bands,
  kerbs, the centre line, hills, forks, tunnels' walls; the portal and the
  gantry from the shadow's attributes (`CpcPortal`: road rows' cells drawn
  solid, the sky's changed cells converted). Not yet: a tunnel's lamps.
  **Measured:** the road takes about 40 ms a game frame against section 6's
  16-18: the PUSHes themselves 14.7 ms, the setting up of 48 pairs the
  rest. `-DROAD_QUADS` sets up a pair of pairs at a time (4-line steps, as
  the Einstein's kerbs): 29 ms.
- **Phase 4** (`src/cpc/cells.asm`): the shadow's cells, marked by the
  shared code's hooks, converted into each screen (a bit per cell and
  screen); the panorama made Mode 0 at a display reset and scrolled a byte
  at a time (in a tunnel its rows are the ceiling's cells); the font 3
  pixels wide with each pixel doubled (`tools/cpc_art.py FONT`), the HUD's
  top strip in it.
- **Phase 3** (`src/cpc/sprites.asm`, `src/scenery.asm`'s CPC way): the
  commands in Mode 0 columns, drawn far to near masked by pen 0, the sky's
  cells and the panorama under them made again the next time that screen
  is drawn; the car last. Placeholders: the Spectrum's silhouettes in one
  pen, its car's poses.
- **Phase 5:** stage loads and checkpoints through the overlay as on the
  Spectrum, each pack read from the disc (`CpcLoad`); the palette per stage
  from the Spectrum's attributes (placeholders: `CpcPalette`); the front end
  (`src/cpc/front.asm`): it draws the Spectrum's screen A into base 1, base
  3 is shown converted from it (a copy in bank 7, a share of cells compared
  each frame wait), the pens the Spectrum's colours. `make test-cpc`
  (`tests/cpc_check.py`): the demo, a game, the AY, 14 stages' screenshots.
- **The benchmark** (`-DFIXED_ELAPSED=1`, game frames 20-320): with the
  road, the HUD, the objects and the car, 4.52 TV frames a game frame
  (11.1 fps); with `-DROAD_QUADS` 3.99 (12.5 fps). The car alone, masked a
  byte at a time, is about 7 ms.
- **Memory:** base 0's CPC code to $17F6 (of $1B00); its residents to
  $3D25 (of $3DA0, the car's poses' tops and bottoms stored once); bank 2's
  code to $98FA (of $A300).

### Speed, phase 6, phase A begun (25 November 2026)

- **Speed:** the road's first `ROAD_QUAD_ROWS` rows (6, the far half) set up
  a 4-line step at a time, the rest line pairs; the car's lines as runs
  (opaque bytes copied, only the edges masked); an unrolled LDI chain for
  the panorama and the car; the panorama's all-paper lines left alone when
  it only scrolls. The benchmark: 3.98 TV frames a game frame, 12.55 fps
  (from 4.52). The road is still the most of it (about 35 ms); the shared
  work 30 ms.
- **Phase 6:** the loader sets the game's CRTC and shows a loading screen
  (until phase A's: the Spectrum's title, "FOR THE AMSTRAD CPC 6128").
  `make release-cpc` copies the disc to `release/speedrun_cpc.dsk`: not run
  yet, the art being unfinished.
- **Phase A:** `docs/cpc_artwork.md`. The coast's scenery and palette, the
  signs, the traffic and the Spider drawn for the CPC; the other themes
  still the placeholders. Waiting for the owner's approval of the coast
  before the rest.
- **Still to do:** the other four themes' art; a native sky and panorama
  (now the Spectrum's converted); the title, goal postcards and loading
  screen; a tunnel's lamps; WinAPE on CRTC types 0-4 and a real 6128
  (phase 7: WinAPE has no headless mode, its window must be in front).

### Phase A's art done; the release (25 November 2026)

- **Phase A:** the owner approved the coast and the far road's 4-line steps.
  The other four themes' scenery and palettes, the title, the five goal
  postcards and the loading screen drawn for the CPC (`docs/cpc_artwork.md`).
  The sky's clouds and the panorama stay the Spectrum's 1-bit drawings in
  the CPC's pens. A tunnel's lamps drawn.
- **Phase 6:** `release/speedrun_cpc.dsk` (`make release-cpc`) and the
  README's CPC lines; the disc boots in MAME. WinAPE across the CRTC types
  and a real 6128 are still to do (phase 7).
- **The benchmark:** 4.01 TV frames a game frame, 12.47 fps (the new art's
  objects a little larger than the placeholders).

### Speed: the keys, the AY and the car (25 November 2026)

- **The keys:** each Spectrum half-row is made from the CPC's matrix once a
  scan, by its own unrolled code (`src/cpc/keyrows.asm`, in bank 2), and
  kept (`CRowVal`, `CRowOk`); a one-row read (the game's) goes straight to
  its value.
- **The AY:** `AyWrite` keeps the registers as last written (`CAyShadow`)
  and skips a write that changes nothing (but the envelope's shape, which
  restarts it): about one real write a frame in play.
- **The car:** each of the Spider's lines compiled to straight code
  (`tools/cpc_art.py car_code`: 118 lines for the 7 poses, 4.4K: the
  runs' 3.5K and most of the room after the residents); each line ends
  in a jump that `CCarPatch` points
  at the pose's next line when the pose changes. Pixel for pixel the same.
- **The benchmark:** 3.69 TV frames a game frame, 13.54 fps (was 4.01,
  12.47).

### The tunnels' mouths and ways out (25 November 2026)

With a tunnel's mouth or its way out in view a game frame took 6.6-10 TV
frames (4 elsewhere): the portal's cells were found by scanning every
attribute of rows 3-23 each frame, and each changed cell converted on its
own. Now:

- `CpcPortal` looks only when `GateWas` says the shared code painted
  something, this frame or the last; rows 3-11 only those it painted
  (`RowAttrHL` and `PaintRaceSky` note them under `IFDEF CPC`:
  `CSkyPainted`), rows 10 on only above `PtRow`.
- `DrawPortal` runs before the road; the road leaves out the rows the
  portal covers edge to edge (`CpcPortalRows`, `CRowFull`).
- The portal's cells and the sky's one-colour cells (ink as paper: the
  face, the arch, the dark) drawn a run at a time, with `PUSH` from three
  cells on (`CpcSolidRun`, `CGroupSolid`); a converted cell with no ink
  pixels drawn as its paper (`CCellSolid`).

The approach now takes 5 TV frames a game frame (6 just before the mouth),
inside 3.5. The yellow row under the HUD and the missing message line on
the first two frames inside, and the way out's blocky opening, are the
Spectrum's too (the shared code's).
