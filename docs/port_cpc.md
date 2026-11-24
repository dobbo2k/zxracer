# Porting Speed Run to the Amstrad CPC

A plan, not yet started. The first draft (21 November 2026) was reviewed on
22 November 2026 against three things that did not exist when it was
written: the Einstein port (`docs/port_einstein.md`), which showed how the
shared code really ports; the Wonder Boy project's two CPC ports
(`C:\ZX Spectrum\Wonderboy`: `docs/cpc-guide.md`, `cpc-port-plan.md`,
`cpc6128-port-plan.md`), which settle most of the CPC hardware questions and
supply tested code and tools; and Speed Run's own code and measurements
(`PLAN.md` 2.1 and 3.6). Section 3 lists what changed. Facts still marked
*(verify)* must be checked in MAME and WinAPE before the work that depends
on them.

## 1. Target

- **Machine:** CPC 6128 (128K, the built-in 3" drive). A 464 or 664 with a
  64K expansion that uses the 6128's RAM configurations, and a disc drive
  (DDI-1 on the 464), runs it too. A 64K version would need the Einstein's
  approach (stages read at each checkpoint) and smaller caches; it is not
  planned.
- **Media:** a `.dsk` in AMSDOS DATA format (one side: 40 tracks of 9
  sectors of 512 bytes, 178K after the directory). Tape (`.cdt`) is
  optional and last (section 5.11).
- **Frame rate:** the Spectrum's own pace, not the 25 fps the first draft
  gave. The Spectrum locks a game frame to 3 TV frames (16.7 fps,
  `MIN_FRAMES`), and its heaviest quarter of frames (hills, forks and
  traffic together) take 4 (`PLAN.md` 3.6: 15.6 fps over a whole game). The
  CPC aims for the same lock. The estimate in section 6 says it will be
  marginal: expect 12.5-16.7 fps, as the Einstein's 11.5-12.
- **Build:** `make cpc` gives `build/cpc/speedrun.dsk`. The Spectrum build
  stays byte-identical to `release/` at every step.

## 2. What to reuse

| From | What | Use here |
|---|---|---|
| Spectrum | the game: `player`, `track`, `hills`, `fork` (its pass-1 part), `traffic`, `game`, `extend`, `respawn`, `tunnel` logic, `scenery`'s projection, the music sequencer, `stages.yaml` and the stage tools | Assembled unchanged from the same `src/main.asm` (section 4) |
| Einstein port | the `-DEINSTEIN` pattern (one `main.asm`, about 20 switches); `KEY_IN` and `FRAME_WAIT` macros; `AYN`/`AYD` periods; Spectrum-format screen B as a shadow that platform code converts; `make_einstein.py`'s gen/dat/patch data build; the fixed-step benchmark (`FIXED_ELAPSED`); the native colour artwork masters (`tools/einstein_illustration.py`, `einstein_art.py`) | The same mechanisms with `-DCPC` |
| Wonder Boy CPC | `hardware.inc` (ports, Gate Array commands, RAM configurations); `screen.asm` (interrupts, CRTC, the flip); `input.asm` (`read_key_row`); `sound.asm` (`ay_write` through the PPI, the register shadow); `sprites.asm` (masks by pen 0 through a table); `fdc.asm` and `disk_loader.asm` (the uPD765 reader, the AMSDOS boot); `tools/cpc/make_dsk.py`, `make_cdt.py`; `tools/cpc_harness.py` with `tools/mame/cpc_harness.lua`; `tools/winape_run.py`; `tools/cpc_profile.py` | Copied into this repository and adapted, as `make_einstein_disk.py` was. Wonder Boy assembles with z80asm, so the sources need sjasmplus syntax |

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
    `make_cdt.py` writes. With 128K needed, tape matters less (section
    5.11).
12. **The verify list** is mostly settled: the PPI's port C bits (0-3 the
    keyboard row, 4 the cassette motor, 6-7 the AY's function), the
    interrupts' positions (2 lines after VSYNC begins, then every 52) and
    the start address's latching (section 5.2).

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
| `stage.asm`, `stageov.asm`, `pics.asm` | packs and pictures read from the disc | packs unpacked from banks 4-6 (section 5.11) |
| `frontend.asm` | screen A shown as a bitmap | section 5.9 |

Most of these switches mean "not the Spectrum's screen". Before the CPC
work starts, give that a name of its own: `defs.asm` defines `NATIVE_GFX`
when `EINSTEIN` or `CPC` is defined, and the shared files test it. The
Spectrum's bytes don't change; check with `make build/speedrun.tap` and
`cmp` against `release/`.

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

### 5.3 Memory (CPC 6128)

| CPU address in play (C1 or C3) | Contents |
|---|---|
| `$0000-$3FFF` base 0 | what the Spectrum keeps resident in bank 5 at `$5B00-$7FFF` (9.25K: scenery and car data, font, the music player, the stage loader's ways in, the track cache), assembled here under `-DCPC`; the CPC code: the interrupt, road and sprite drawers, cell conversion, keys, disc; page-aligned tables (pen-0 masks, mixed-pen bytes, 1-bit-to-Mode-0) |
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
- **Base 0 is the budget to watch:** 16K for the Spectrum's 9.25K of
  residents (some of them graphics, whose Mode 0 size differs) and the CPC
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
- **Art:** in colour, made by a new `tools/cpc_art.py` from the Einstein's
  colour masters (`einstein_illustration.py`, `einstein_art.py`), reduced
  to the theme's pens, at the sizes `make_scenery.py` gives the Spectrum.
  Pre-shifted copies: one for the near sizes (4-pixel steps, as the
  Spectrum's), two for the far ones.
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
- **Option: a Mode 1 band for the HUD** (rows 0-5, 256 pixels across, the
  Spectrum's cells exactly, 4 pens). It needs a mode change at line 48:
  with R7 = 31, the interrupt at line 42 then 6 lines' wait (about 0.4 ms a
  TV frame), and it must hold on every CRTC type. Decide in phase 4 from
  screenshots of both.

### 5.8 Sound

- **Periods:** `AYN`/`AYD` = 564/1000 (1,000,000 / 1,773,400) in
  `defs.asm`, as the Einstein's 1128/1000; the tune's notes from their own
  table (the Einstein's `music_notes.asm`, generated for 1 MHz); the
  engine's step 28 a rev (50 x 0.564); the crash's thud as `EinCoarse`
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
  drawn into the shadow and converted as in 5.7. They could use Mode 1
  whole (no split), giving the Spectrum's cells exactly: decide with 5.7.
- **Pictures** (the title, the five goal postcards): native Mode 0, 16
  pens, from the Einstein's postcard builder or `make_screens.py`'s RGB
  scenes, packed, unpacked into the hidden screen and flipped to. The
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
- **Tape (optional, last):** a `.cdt` in the firmware's format at 2,000
  baud (Wonder Boy's `make_cdt.py`), for a 6128 or an expanded 464. At
  about 220 bytes a second the game would take 4-6 minutes to load.

## 6. The frame budget (estimate)

A game frame at the 3-TV-frame lock has 59.9 ms on the CPC (Spectrum:
212,700 T). Shares, from the Spectrum's and the Einstein's measurements:

| Work | Spectrum | CPC (estimate) |
|---|---|---|
| Shared: logic, pass 1, hills, the sprites' projection | about 105K T | 30-33 ms |
| Interrupts: sound, key scan | about 9K T | 3 ms |
| The road, 96 lines | 48K T (rows and lines) | 16-18 ms |
| Scenery and traffic | 16K T | 6-12 ms (twice the bytes, each masked) |
| The car | 7K T | 2-3 ms |
| HUD and sky cells, the panorama | 10K T | 1-3 ms |
| **Total** | about 205-260K T | **58-72 ms** |

So the light frames should keep the 16.7 lock and the heavy ones take 4 TV
frames, as on the Spectrum, if these estimates hold. The shared work is
the biggest share, and the Einstein left it alone so that the Spectrum's
build stays the same. Phase 0 measures it on the CPC before anything is
drawn.

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
  (`-DMIN_FRAMES=1`). Each phase records it.
- **Profiling:** MAME's debugger trace counted by label
  (`tools/cpc_profile.py`). MAME gives no T-state profile like zxsim's or
  Albert's; the trace's PC counts serve.

## 8. Phases

| Phase | Work | Done when | Size |
|---|---|---|---|
| 0 | `NATIVE_GFX`; `-DCPC` assembling with the drawing stubbed; the Wonder Boy tools copied; `local.mk`. **Measure:** the shared work's time on the CPC (the benchmark with nothing drawn), base 0's fill, the packs' packed size, the Mode 0 art's size | The Spectrum's build is byte-identical; the measures decide 5.3 and 5.11 (packs in RAM or from the disc) | S |
| 1 | Boot from the `.dsk`; firmware off; C1/C3; IM 2 and the six interrupts; the flip with test patterns; the key scan; `AyWrite`; a tune | In MAME the demo's logic runs (`GameFrames` counts), keys start a game, the tune is in the AY log at 1 MHz pitches; WinAPE shows the flip on types 0-4 | M |
| 2 | The road: line pairs every frame, bands, kerbs, centre line, hills, the fork, tunnel walls, the portal and gantry | Screenshots of all 15 stages; the benchmark. **Decision:** the road's cost against 16-18 ms; if far over, the skip of unchanged pairs or colour cycling on straights | L |
| 3 | Scenery, traffic and the car: `cpc_art.py`, the masked drawer, the crest clip, crashes | Every theme's objects in screenshots; the benchmark: the 3-TV-frame lock in most frames | L |
| 4 | The sky, the panorama, the shadow and its conversion, the HUD, the message line, the starting lights, pause, the font | The HUD reads right at every stage. **Decision:** Mode 0 HUD or a Mode 1 band | M |
| 5 | Stage loads from the banks, checkpoints, palettes per theme and stage, the front end (title, high scores, options and keys, goal and route screens) | A whole game plays through in MAME, front end included; `make test-cpc` passes | M |
| 6 | The loading screen, the disc's boot files, `release/` (the `.dsk`, a README); the `.cdt` if wanted | Boots from the release `.dsk` in MAME and WinAPE | S |
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
| Interrupts late or lost while the fills have them off | Verified in phase 1 in MAME and WinAPE; fills split into shorter stretches if needed |
| The flip, or a Mode 1 HUD split, on some CRTC types | WinAPE on types 0-4 in phases 1 and 4 (Wonder Boy's flip and split already hold on 0 and 3) |
| The colour art is a large job | It reuses the Einstein's colour masters; the scenery's sizes and shifts stay `make_scenery.py`'s |
| Wonder Boy's code is z80asm, Speed Run's sjasmplus | Copied file by file with their tests' behaviour as the check |

## 10. Decisions for the owner

1. **The 6128 and disc only**, or the tape (`.cdt`) too? The plan: disc,
   tape last if wanted.
2. **128 x 192 Mode 0** (recommended) or 160 x 200?
3. **The HUD:** Mode 0 with the doubled-pixel font (recommended to start),
   or a Mode 1 band (decided in phase 4)?
4. **Colour art** from the Einstein's masters (recommended), or a CPC art
   pass of its own?
