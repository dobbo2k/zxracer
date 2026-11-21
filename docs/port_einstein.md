# Porting Speed Run to the Tatung Einstein

The plan, reviewed against the hardware as Albert's emulation core models
it, and the port as far as it has got. Build and test with `make einstein`
and `make test-einstein` (see "Building and testing" at the end).

## 1. Target

- **Machine:** Tatung Einstein TC-01: Z80 at 4 MHz, 64K RAM, a TMS9129
  video chip with its own 16K, an AY-3-8910, a built-in 3" disc drive.
- **Media:** a disc image (the Einstein has no tape port): XtalDOS 1.31's
  system tracks, `SPEEDRUN.COM` and `STAGES.DAT`. At the `0:` prompt, type
  `SPEEDRUN`.
- **Frame rate:** a steady 12.5 fps (a frame every 4 TV frames) where it
  can; the Spectrum's is 16.7. In the attract demo's worst stretch
  (steering, curves, hills and scenery every frame) about 8 frames in 10
  make it and most of the rest take 5 TV frames: 11.8 fps on average. See
  section 6.

## 2. The hardware, as found

The first draft of this plan left several facts to verify. The Wonder Boy
port (`C:\ZX Spectrum\Wonderboy`, `src/platform/einstein`) and Albert's core
(the einstein repository's `emulator/src/core`) settle them:

| | Spectrum 128 | Tatung Einstein |
|---|---|---|
| CPU | Z80 3.55 MHz | Z80 4 MHz; a PAL frame is 79,749 T (313 lines of 254.8 T) |
| Screen | 256x192 in main memory, a colour per 8x8 cell | TMS9129 Graphics II: 256x192 in its own 16K, a colour pair per 8x1 line of a cell; reached through ports $08 (data) and $09 (control, status) |
| VRAM timing | - | with the picture on, accesses at least 32 T apart (8 us), or the chip loses them; the vertical blank is about 30,800 T |
| Colours | fixed 15 | fixed 15 (the TMS palette) |
| Sprites | none | 32 hardware sprites, 16x16 in one colour, 4 on a line |
| Sound | AY at 1.7734 MHz | AY at **2 MHz** (derived from MOS's beep: Albert `ay38910.h`); register latch port $02 (also the read port), data $03 |
| Interrupt | 50 Hz IM2 from the ULA | the VDP's frame interrupt is **not wired** to the Z80. A Z80 CTC at $28-$2B: channels 0-2 count a 2 MHz clock (their timers the 4 MHz system clock), channel 2's ZC/TO drives channel 3. IM2 through the CTC's daisy chain |
| Keyboard | ports $xxFE | through the AY's I/O ports: the row selected (active low) on register 14 (port A, an output), the columns read (active low) from register 15 (port B). Register 7 must keep bit 6 set and bit 7 clear |
| Joystick | Kempston | analogue, an ADC0844 at $38; fire on port $20 bit 0 |
| Memory | 128K in 16K banks | 64K flat; the 8K MOS ROM pages over $0000-$1FFF (port $24 toggles it); writes under it reach RAM |
| Storage | tape | 3" disc, 40 tracks x 10 sectors x 512 bytes; 190K free after XtalDOS |

## 3. Review of the first plan

What held, and what changed:

1. **Testing tools already exist (phase 1 is done).** The plan budgeted
   about 1,500 lines of C for an Einstein mode in `tools/zxsim`. Albert's
   core is a complete Einstein, with VRAM timing checks (it counts every
   access that comes too fast) and the disc controller. The harness
   `tests/einstein/speedrun_check.cpp` links against it, as the Wonder Boy
   port's does. The disc builder (`tools/make_einstein_disk.py`, from More
   Burgers! by way of Wonder Boy) is proven against real XtalDOS.
2. **No separate platform layer (phase 0, changed).** Splitting the
   Spectrum code behind an interface first would have meant moving most of
   bank 2's tightly packed layout. Instead the Einstein assembles the same
   `src/main.asm` with `-DEINSTEIN` and the game runs at its Spectrum
   addresses ($4000-$BFFF). About 20 `IFDEF EINSTEIN`s in the shared files
   swap out what touches the hardware, and `src/einstein/` holds the rest.
   The Spectrum build stays byte-identical (`make` then `cmp` against
   `release/`).
3. **The frame tick: the CTC asks the VDP.** The VDP's interrupt doesn't
   reach the Z80. So CTC channel 2 (a timer, /16, 250) interrupts every
   millisecond, through the Spectrum's own IM2 table (vector base 0;
   `$BE04` holds `$BDBD`, `JP Isr`). The handler (`EinIsr`) reads the VDP's
   status each time, and its frame flag starts a TV frame, at most 1 ms
   late. Then it does what the Spectrum's 50 Hz interrupt does: it counts
   the frame, sends a frame that is ready (in that vertical blank), and
   plays the music. The main loop asks for a frame (`RequestFlip`) and
   waits (`WaitFlip`) only before touching what is being sent.
4. **The panorama is in the middle third, not the top.** The plan's "the
   upper third's patterns are otherwise unused, so there is room" was
   wrong: rows 10-11 share the middle third with road rows 12-15. The
   budget there: 16 solid colours, 48 road slots, 64 patterns for sky rows
   8-9, 64 for the panorama (one copy: it scrolls in 8-pixel steps, not
   the Spectrum's 4) and 64 for cells there under a silhouette.
5. **Most of the sky and HUD comes free.** The plan had the HUD rebuilt from
   font cells. Instead the Spectrum's own HUD, message line, sky artwork
   and starting lights still draw into its screen B (plain RAM at $C000
   here). The Einstein mirrors the cells they write, each with its own
   pattern. Rows 0-7 are the top third's 256 patterns, one each. The car's
   32 cells work the same way.
6. **Memory: the plan's map, rearranged.** The shared code keeps
   $4000-$BFFF. The theme cache moves to $0120 (the Spectrum's $DB00 would
   collide with XtalDOS, which stays at $EC00 for loading). The platform
   code sits after the panorama cache, and the Einstein's buffers at
   $DB00-$EBFF. The Spectrum's screen B ($C000-$DAFF) stays as the
   mirror's source. Writes into screen A's memory ($4000-$5AFF) must not
   happen, because the stage overlay lives there; `LampDraw` was one.
7. **Stages load from the disc (the plan's option 2).** All 35 packs (5
   themes, 15 tracks, 15 stages' art) are in `STAGES.DAT` (56K). At a
   checkpoint the race stops for a moment while the next stage is read.
   The BDOS needs MOS's own interrupts to time the disc, so each read
   switches back to MOS's set-up (I = $FB, CTC channels 2 and 3 as
   `ZZTIME` sets them) and then back to the game's. A theme or track
   already in its cache isn't read again.
8. **Traffic and scenery: the Spectrum's silhouettes, composited.** The
   plan wanted hardware sprites for traffic. Instead the Spectrum's own
   code projects traffic and scenery and XORs its silhouettes into screen
   B. Below the sky, screen B holds nothing else (the Spectrum's road
   isn't drawn there), so every cell a draw command covers is the road's
   (or the panorama's) cell XOR the silhouette, in a slot of its row's own.
   A silhouette takes the cell's ink, as on the Spectrum: black on grass
   and kerbs, white on the road. No 4-a-line limit, and no flicker.
9. **Interrupt sources on real hardware:** the keyboard, ADC and fire
   buttons have interrupt masks (ports $20, $21, $25). Albert doesn't model
   those interrupts. If MOS leaves one enabled, the game's IM2 table (every
   entry `Isr`) would count extra 50 Hz ticks. Check on a real machine and
   mask them if needed.

## 4. What is done

Run `make einstein`, then `make run-einstein` (Albert) or `make
test-einstein`.

- **Start-up:** XtalDOS loads the 48K `SPEEDRUN.COM` (about 9 s), and
  `EinBoot` takes over the machine: Graphics II, the AY, the CTC tick. The
  first stage loads from `STAGES.DAT`.
- **The game:** the attract demo drives, and a key starts a game (Q/A/O/P/
  SPACE, as on the Spectrum). The lights count down, the clock and score
  run, and each stage's tune plays (the AY's tone periods for 2 MHz).
  Checkpoints load the next stage, and all 15 stages and 5 themes work.
- **The road** (`src/einstein/roadgfx.asm`): pass 1 is the Spectrum's
  (`RoadPrepare`). Per character row, as the Spectrum's `DrawRoadRow`, the
  row is grass, kerb, road, kerb, grass. Solid cells are one name byte.
  The kerb's edges are ready-made patterns, already in VRAM: each edge is
  upright within its row, at the mean of the row's top and bottom lines,
  so a kerb edge costs one name and nothing else is sent (the exact way,
  in line pairs, made a slope of 2-line steps, at a slot of 8 pattern
  bytes and a colour byte per cell). A tunnel's rows, a fork's, and a row
  whose road fits in one cell are still drawn the exact way, in slots,
  each sent only when it differs from what VRAM holds. A row is drawn
  again only if its bands moved or what its cells come from changed: its
  line pairs' edges, centre line and depth line, kept per row (`ERowSig`).
- **The centre line:** a hardware sprite a road row (16x16, the top half
  used): its dashes at any pixel, slanted in 4-line steps, from line pairs
  0 and 2 of the row (light bands only, in road cells, as the Spectrum).
  Where the car, a silhouette or a tunnel's mouth covers a cell, the
  sprite's pixels there are taken out. Only what changed is sent.
- **The fork:** rows with both branches (`RowFork`) get both spans' kerbs
  and road, and kerb cells hold both branches' pixels.
- **Tunnels and the gantry** (`src/einstein/portal.asm`): the Spectrum's
  `DrawPortal`, `Ceiling` and `Gate` paint screen B's attributes. Cells
  that change in the sky rows are mirrored. In the road rows, a cell
  whose attribute isn't its row's own is the portal's, a solid cell of its
  paper. Inside, the walls (from the band's tunnel bit), their lamps and
  the ceiling.
- **Traffic and scenery** (`src/einstein/sprites.asm`): see 3.8.
- **The sky and HUD** (`src/einstein/sky.asm`): the cells the Spectrum
  code writes are noted in a bitmap, a bit a cell, so none is dropped or
  sent twice, and all of them are mirrored with the frame. A tunnel's way
  in and out changes the whole sky at once (about 3 TV frames of paced
  writes, inside the interrupt): a TV frame that begins meanwhile is
  counted and its sound played, so the clock and the music keep time. (A
  queue of 240, 48 a frame, used to overflow there and leave the portal's
  colours in the sky, and took 5 game frames over the change.) The
  panorama is sent once a stage and scrolls by its names alone.
- **The front end** (`src/einstein/front.asm`): the Spectrum's title,
  high scores, options (key redefinition too), game-over and goal screens,
  unchanged. They draw into screen A ($4000) as on the Spectrum, and screen
  A is shown as a full-screen bitmap: each third's 256 patterns are its
  cells in order. Each frame wait (`FRAME_WAIT`, `EinHalt`) compares 96 of
  its cells with a copy (in screen B's memory, the game's mirror source,
  which a display reset makes afresh), and sends the ones that changed.
  Meanwhile the interrupt counts frames on the CTC alone, so the VDP is
  the main code's. The front end's code and its pictures are in
  `STAGES.DAT`. The stage overlay, which the front end draws over, is read
  back from there (`StageOv`).
- **Keys and joystick** (`src/einstein/keys.asm`): the Spectrum's key reads
  (`KEY_IN`: `ReadInput` with its redefinable keys, the front end, the
  pause key) are answered from the Einstein's keyboard. Each Spectrum key is
  where the same key sits on the Einstein; the two shifts have none. The
  analogue joystick (ADC0844) gives the Kempston's bits, and works any
  time.
- **Game time:** a game frame takes longer than the Spectrum's 4 TV frames
  at most, so `Elapsed` goes up to 8 here and the clock and the car keep
  real time.
- **The player's car:** the Spectrum's `DrawCar`, its 32 cells mirrored.
  A new frame of it (steering) is made ready by the main code
  (`EinCarPrep`) and sent as two 256-byte blocks, its patterns and
  colours; otherwise only the cockpit's colours over a new colour
  underneath.
- **Writing VRAM:** a frame goes in during one vertical blank, row by row
  (a row's slots, then its names), so no row shows new names over old
  patterns. What doesn't fit in the blank is written paced (32 T), and the
  harness counts no access that comes too fast. The CTC's 1 ms interrupt
  asks the VDP for the frame; once one is seen, it waits 16 ms before
  asking again (the next comes 19.9 ms on), unless it was seen at the
  first poll after such a wait (it may have been waiting). A frame that
  begins while the interrupt is still busy is counted, with its sound, at
  its end, and the polls go back to every 1 ms. (Without these, one long
  interrupt left every later frame's sending late for several frames, too
  late for the blank.)

- **Sound:** the AY runs at 2 MHz, against the Spectrum 128's 1.77, so
  every tone and noise period is 1.128 times the Spectrum's for the same
  pitch: constants as `(p * AYN + AYD / 2) / AYD` (`src/defs.asm`; 1 / 1 on
  the Spectrum, so its bytes are the same), and the computed ones in
  Einstein code: the engine's 56 a rev (50), the crash's thud
  (`EinCoarse`). The tune's notes come from their own table.

Not yet:

- the crew's crash close-ups (their portraits are left out of the Einstein
  build, for room)
- speed (section 6)

## 5. Graphics: the name table does the work

As planned, with the details above. Per third (256 patterns each):

| Third | Patterns |
|---|---|
| top (rows 0-7) | rows 0-7 mirrored, one pattern a cell |
| middle (rows 8-15) | 0-15 solid colours, 16-35 slots (rows 12-15, 5 each: silhouettes', and the road's where it is drawn the exact way), 36-63 the kerb's edges, 64-127 rows 8-9 mirrored, 128-191 the panorama (2 rows x 32), 192-255 the panorama's cells under a silhouette |
| bottom (rows 16-23) | 0-15 solid colours, 16-191 slots (22 a row), 192-219 the kerb's edges, 220-223 free, 224-255 the player's car |

The kerb's edges: 7 left edges (road from pixel 1-7) and 7 right (road to
pixel 0-6), in the light kerb and the dark, in each of the road's thirds
(`EinStaticInit`, at a display reset). The sprites: 12, one a road row,
their patterns 4k on.

Colours come from the Spectrum's attributes. Each Spectrum colour (with
bright) maps to the nearest TMS colour (`SpecTms` in
`src/einstein/vdp.asm`). The TMS9129 has one cyan and one magenta, where
the Spectrum has a plain and a bright of each, so where a palette tells
two things apart by brightness alone, `einstein_palette` in
`assets/stages.yaml` (a theme's or a stage's) changes it for the Einstein
only (`tools/make_einstein.py`): the sunset theme's dark grass bands
(dark blue, not the sky's magenta) and the beacon coast's (grey, not the
sky's cyan). All 15 stages were checked in the harness for the rest.

## 6. Speed

A frame is sent at most every 4 TV frames (`EIN_MIN_FRAMES` in
`src/einstein/boot.asm`): a steady 12.5 fps when the work fits, 10 when a
frame takes longer. In the attract demo, over 300 frames sent, 244 come 4
TV frames after the last, 45 after 5, 10 after 6 and 1 after 7: 11.8 fps on
average (`make test-einstein` wants at least 7). The harness's `fliphist N`
gives that histogram, and the costliest routines of each frame that took 6
or more.

**The benchmark.** A game's speed changes what it does (the time step, the
demo driver's steering), so ordinary runs don't compare. Assemble with
`-DFIXED_ELAPSED=1` (every update counts 3 TV frames: the same game at any
speed), boot, and time 300 game frames of the attract demo with the
harness: `wait16 GameFrames 20`, then `wait16 GameFrames 320` prints the
TV frames they took. With `-DEIN_MIN_FRAMES=3` too, the lock is off and it
measures the work alone. Taken so:

| | TV frames |
|---|---|
| the start of the speed work | 1,955 |
| the first speed commit | 1,857 |
| the second | 1,653 (5.5 a game frame, 9.1 fps) |
| the third, locked at 4 | 1,287 (4.29, 11.7 fps) |
| now, locked at 4 | 1,268 (4.23, 11.8 fps) |
| now, unlocked | 1,166 (3.89, of which about 0.1 waits for the flip) |

`profile N` in the harness gives each routine's T-states and calls over N
TV frames (`profilel N`: local labels apart). A game frame's work is
about 320K T now: the shared game logic about 130K (pass 1, the hill
mapping, the projection, the sprites' XOR chain into screen B), which
costs the same as on the Spectrum and is left alone so the Spectrum's
build stays the same; the road's rows about 45K; writing VRAM about 45K
(the paced bytes' 32 T is VRAM's own limit); the silhouettes about 35K;
the centre line's sprites about 20K. In the attract demo the road's shape
changes nearly every frame, so 11 of the 12 road rows are built again a
frame. Tried and measured:

- cut, for 12.5 fps: the kerb's exact edges (2-line steps) for ready-made
  ones (upright in each row: 8-line steps), in all rows but a tunnel's or
  a fork's
- kept: the centre line as sprites (exact, slanted in 4-line steps); the
  car's new frames as two blocks, made ready outside the interrupt (one
  every 8 frames or so had taken 37 ms in it, the cells one by one);
  silhouettes' cells set a row's run at a time; a row's slots from a
  table; the key reads stopping after the last half-row asked for; a
  slot's 16 bytes in one go, and its own paced path; a row's colours once
  a frame (4 sets); slot commits onto the dirty list by pointer; rows with
  no silhouette or portal cell sent straight from `BaseNames`; the
  row-shape check stopping at the first difference; the interrupt's 16 ms
  wait; whole empty mask bytes and rows skipped; unrolled slot compares;
  name rows filled with the Spectrum's unrolled `FillA`
- dropped: the centre line as ready-made cells too (upright in each row,
  a dash on a bend became separate squares; the sprites cost about 15K
  more, and look as the exact way did); clearing a mask with the stack
  (interrupts off for 600 T made the frame's interrupt late: writes in the
  picture); comparing each row of names with what VRAM holds; sending what
  doesn't fit in one blank in the next (the main loop waits for the frame
  to be sent: 1,772 became 3,006); a bigger blank budget (1,000 units: 4
  frames fewer in 1,700, with less margin; 1,250 writes too fast)

A row drawn the ready-made way is made in one pass (`EinRowFast`: its
ranges, colours, names and kerb edges, about 1.7K T with its fills, where
the separate routines took 3.1K); a row nothing covers skips the
silhouettes' compositing outright. Tried and dropped: keeping each row's
centre-line inputs to skip remaking its sprite (they change nearly every
frame: the check cost 8K a frame and saved little); a fully covered
silhouette cell as a solid name (traffic is outlines: few such cells); a
shorter scenery distance (800, not 1,200: 255 frames in 300 at 4, not 244)
and fewer scenery objects (6: no change).

The frames that take 6 TV frames are the ones with big objects near the
car: each silhouette cell costs about 2.2K T (its mask from screen B, the
cell made, committed to a slot and sent), and the Spectrum's own sprite
drawing into screen B grows with them. A solid 12.5 would need that path
made much cheaper, or fewer silhouetted cells.

**Memory.** The Spectrum's drawing code that the Einstein never calls
(road pass 2, the fork's row drawer, the panorama's bitmap, the rolling
tyres, the crew's close-ups) is left out of its build (`IFNDEF
EINSTEIN`). That made room for the Einstein's keys, disc and front-end
code in bank 2. The Einstein's own buffers (the names, the sky's
attributes, the masks, the panorama's sprite cells, the rows' signatures)
are in screen A's memory, above the stage overlay ($4800-$5AFF): the game
code never writes screen A here (`Ceiling` and `TimeWarn` skip it). Left:
140 bytes in bank 2 (the centre line's sprites are there:
`src/einstein/dash.asm`), 750 bytes in bank 5, 300 under $4000, 460 in the
Einstein's buffers ($DB00-$EBFF) and 320 bytes in
screen A (assertions check each).

## 7. Building and testing

| Command | Does |
|---|---|
| `make einstein` | `build/einstein/speedrun.dsk` (and `.com`, `.sym`, `.lst`) |
| `make test-einstein` | boots it in Albert's core and checks it (`tests/einstein_check.py`); builds the harness first if needed (Visual Studio's C++ tools) |
| `make run-einstein` | opens it in Albert; type `SPEEDRUN` at the `0:` prompt |

They need, from the einstein repository (`EINSTEIN_REPO` in `local.mk`):
XtalDOS 1.31's `SYSTEM131.CPM`, the MOS 1.2 ROM, and Albert's
`ein_core.lib` (`emulator/build`). The harness also needs Visual Studio's
C++ tools (`tests/einstein/build_harness.cmd`).

The harness (`build/einstein/speedrun_check.exe <rom> <dsk> <sym>
commands...`) boots the disc and runs commands. Its header lists them:
`boot` (to the main loop, after the title screens), `frames`, `hold`, `joy`, `wait16`, `peek8`, `vram`, `shot`, `record` (pictures and
sound), `rec_start`/`rec_stop` (record whatever runs between them, the
boot too), `type`, `until`, `profile` (T-states and calls per routine, the
80 costliest; `profilel` with local labels), `fastpc` (where VRAM writes
came too fast, and on which raster lines), `linehist SYM` (the raster
lines the PC reaches SYM on), `fliphist` (above), `flagtrace SYM` (the
interrupts and the CPU
before SYM is reached late in the blank) and `stats` (VRAM accesses that
came too fast).

For a tunnel, assemble with `-DAUTOPLAY=1 -DFIRST_STAGE=3` (the first
alpine stage; the demo driver plays the game) and record from about TV
frame 1,250.

The game's Einstein-specific generated files (`packs.asm`, `stages.asm`,
`stageov_pack.asm`, `screens_data.asm`, `music_notes.asm`) and
`STAGES.DAT` come from `tools/make_einstein.py`, into `build/einstein`.
It runs in three steps: `gen` before assembling every stage pack
(`stagepacks.asm`), `dat` after (the packs and pictures, with room for the
front end and the overlay), and `patch` after the game is assembled (its
`frontend.bin` and `stageov.bin` into that room). It's last on the
include path because sjasmplus 1.21 searches the last `-I` first.

For testing a later stage or a place in one, assemble with
`-DFIRST_STAGE=n` and `-DSTART_POS=units` as the Spectrum build allows
(the attract demo starts there), make a disc with
`tools/make_einstein_disk.py`, and `touch src/main.asm` afterwards.
