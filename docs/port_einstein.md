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
- **Frame rate:** the Spectrum's 16.7 fps where possible. It's about 8 fps
  now in the attract demo's worst stretch (steering, curves, hills and
  scenery every frame): see section 7.

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
  row is grass, kerb, road, kerb, grass. Solid cells are one name byte;
  kerb cells with the road's edge in them, and road cells with the centre
  line, get pattern slots (8 bytes, one colour byte), worked out in line
  pairs as the Spectrum draws them. A slot is sent only when it differs
  from what VRAM holds. A row is drawn again only if pass 1 ran or its
  bands moved.
- **The fork:** rows with both branches (`RowFork`) get both spans' kerbs
  and road, and kerb cells hold both branches' pixels.
- **Tunnels and the gantry** (`src/einstein/portal.asm`): the Spectrum's
  `DrawPortal`, `Ceiling` and `Gate` paint screen B's attributes. Cells
  that change in the sky rows are mirrored. In the road rows, a cell
  whose attribute isn't its row's own is the portal's, a solid cell of its
  paper. Inside, the walls (from the band's tunnel bit), their lamps and
  the ceiling.
- **Traffic and scenery** (`src/einstein/sprites.asm`): see 3.8.
- **The sky and HUD** (`src/einstein/sky.asm`): the Spectrum code's cells
  are mirrored, at most 48 a frame (the rest wait). The panorama is sent
  once a stage and scrolls by its names alone.
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
- **The player's car:** the Spectrum's `DrawCar`, its 32 cells mirrored
  (all of them when the frame changes, otherwise only the cockpit's
  colours over a new colour underneath).
- **Writing VRAM:** a frame goes in during one vertical blank, row by row
  (a row's slots, then its names), so no row shows new names over old
  patterns. What doesn't fit in the blank is written paced (32 T), and the
  harness counts no access that comes too fast.

Not yet:

- the crew's crash close-ups (their portraits are left out of the Einstein
  build, for room)
- drum and engine pitches, which are still the Spectrum's periods, so a
  little high at 2 MHz
- speed (section 6)

## 5. Graphics: the name table does the work

As planned, with the details above. Per third (256 patterns each):

| Third | Patterns |
|---|---|
| top (rows 0-7) | rows 0-7 mirrored, one pattern a cell |
| middle (rows 8-15) | 0-15 solid colours, 16-63 road slots (rows 12-15, 12 each), 64-127 rows 8-9 mirrored, 128-191 the panorama (2 rows x 32), 192-255 the panorama's cells under a silhouette |
| bottom (rows 16-23) | 0-15 solid colours, 16-207 road slots (24 a row: the road's, then its silhouettes'), 208-239 the player's car, 240-255 free |

Colours come from the Spectrum's attributes. Each Spectrum colour (with
bright) maps to the nearest TMS colour (`SpecTms` in
`src/einstein/vdp.asm`). Each theme's palette still wants picking for the
TMS colours, as the plan said.

## 6. Speed

In the attract demo's worst stretch (`make test-einstein`, which wants at
least 7), a game frame takes about 6 TV frames: 8 fps against the
Spectrum's 16.7. The shared game logic (pass 1, the hill mapping, the
projection) costs the same T-states as on the Spectrum. The rest is the
Einstein's: the kerb cells, the slot commits, the silhouettes' cells, and
the writes that spill past the vertical blank. Ideas, roughly in order:

- leave a row's kerb cells alone when only its bands moved (only colours
  change then)
- a silhouette cell: XOR into the slot only where its mask has pixels, and
  keep a cell's slot from frame to frame
- compare slots in their line pairs (4 bytes, not 8) and unroll the loops
- fewer writes past the blank: send the colour of a slot only when it
  changes, and spread the sky's cells over frames (done: 48 a frame)
- memory: the Spectrum's drawing code that the Einstein never calls
  (road pass 2, the fork's row drawer, the panorama's bitmap, the rolling
  tyres, the crew's close-ups) is left out of its build (`IFNDEF
  EINSTEIN`). That made room for the Einstein's keys, disc and front-end
  code in bank 2. Left: about 1.4K in bank 2, 750 bytes in bank 5 and 440
  under $4000 (assertions check each).

## 7. Building and testing

| Command | Does |
|---|---|
| `make einstein` | `build/einstein/speedrun.dsk` (and `.com`, `.sym`, `.lst`) |
| `make test-einstein` | boots it in Albert's core and checks it (`tests/einstein_check.py`); builds the harness first if needed |
| `make run-einstein` | opens it in Albert; type `SPEEDRUN` at the `0:` prompt |

They need, from the einstein repository (`EINSTEIN_REPO` in `local.mk`):
XtalDOS 1.31's `SYSTEM131.CPM`, the MOS 1.2 ROM, and Albert's
`ein_core.lib` (`emulator/build`). The harness also needs Visual Studio's
C++ tools (`tests/einstein/build_harness.cmd`).

The harness (`build/einstein/speedrun_check.exe <rom> <dsk> <sym>
commands...`) boots the disc and runs commands. Its header lists them:
`boot` (to the main loop, after the title screens), `frames`, `hold`, `joy`, `peek8`, `vram`, `shot`, `record` (pictures and
sound), `rec_start`/`rec_stop` (record whatever runs between them, the
boot too), `type`, `until`, `profile` (T-states per routine) and `stats`
(VRAM accesses that came too fast).

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
