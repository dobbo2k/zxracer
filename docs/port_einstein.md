# Porting Speed Run to the Tatung Einstein

The plan, reviewed against the hardware as Albert's emulation core models
it, and the port as far as it has got. The code itself is described in
[einstein_code.md](einstein_code.md). Build and test with `make einstein`
and `make test-einstein` (see "Building and testing" at the end).

## 1. Target

- **Machine:** Tatung Einstein TC-01: Z80 at 4 MHz, 64K RAM, a TMS9129
  video chip with its own 16K, an AY-3-8910, a built-in 3" disc drive.
- **Media:** a disc image (the Einstein has no tape port): XtalDOS 1.31's
  system tracks, `SPEEDRUN.COM` and `STAGES.DAT`. At the `0:` prompt, type
  `SPEEDRUN`.
- **Frame rate:** a steady 12.5 fps (a frame every 4 TV frames) where it
  can; the Spectrum's is 16.7. With the kerbs drawn exactly, in 4-line
  steps (section 6), 243 of 306 displayed-frame intervals in the release
  attract demo meet the four-refresh target. The average is 11.81 fps.

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
   isn't drawn there), so every cell a draw command covers is made again in
   a slot of its row's own: the silhouette in the object's own inks (a
   third of its height each, from the native artwork) over the cell's
   ground colour. A cell of two colours (a kerb edge, or a slot drawn the
   exact way) gives the colour most of its pixels show
   (`src/einstein/objcolour.asm`), so objects keep their colours as they
   cross a kerb. (Until 22 November 2026 such a cell was XORed with the
   silhouette in its own two colours, so an object turned red, white or
   black there, as the Spectrum's take the cell's ink.) An ink the same as
   the ground's is drawn black, or white on black. No 4-a-line limit, and
   no flicker.
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
  The kerbs are exact (`src/einstein/kerbrow.asm`, `kerbcell.asm`): per
  row, from its lines' edges and the kerb's width, the cells of the left
  and right kerb runs are made pixel by pixel, both edges in 4-line steps
  (lines 0 and 4 of the row; `-DEIN_KERB2`: 2-line steps, from all 4 line
  pairs), each in a slot of the row's. A slot holds two colour pairs, kerb
  over grass and kerb over road, and a mask of the lines over the second
  (Graphics II has a colour pair a line). A cell all kerb, all road or all
  grass is a solid name. A row the kerb drawer can't draw (a line pair
  without road, beyond a crest; a run over 119 pixels wide), like a
  tunnel's rows and a fork's, is drawn the exact way, in slots. A slot is
  sent only when it differs from what VRAM holds. With `-DEIN_BLOCKS` the
  kerb's edges are ready-made patterns instead, already in VRAM: each
  edge upright within its row, at the mean of the row's top and bottom
  lines, the outer edge on a cell's edge (8 x 8 blocks), so a kerb edge
  costs one name and nothing else is sent. A row is drawn again only if
  its bands moved or what its cells come from changed: its line pairs'
  edges, centre line and depth line, kept per row (`ERowSig`).
- **No centre line** since the speed cut (section 6). With `-DEIN_DASH` it
  comes back, with the block kerbs only (`-DEIN_BLOCKS`: with the exact
  kerbs its buffers don't fit): a hardware sprite a road row (16x16, the top half used),
  its dashes at any pixel, slanted in 4-line steps, from line pairs 0 and
  2 of the row (light bands only, in road cells, as the Spectrum). Where
  the car, a silhouette or a tunnel's mouth covers a cell, the sprite's
  pixels there are taken out. Only what changed is sent.
- **The kerbs' look:** the exact kerbs are as wide as the Spectrum's
  (`RoadRW`), thinner than the blocks, which padded them out to whole
  cells. Where a far row's narrow road puts both kerbs in one cell, grass
  beside the road there is drawn as kerb; the grass in kerb cells has no
  verge texture. With `-DEIN_BLOCKS -DEIN_SLOPE=4`, a near row whose edge
  slopes more than 4 pixels is drawn the exact way, in 2-line steps
  (`src/einstein/slope.asm`), as before the speed cut.
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
- **The player's car** (`src/einstein/car.asm`): the native Spider, its
  32 cells the bottom third's last patterns. A line whose paper is 0 is
  transparent: it takes the paper of the ground under its cell, noted as
  each car row is drawn (`EinCarNames`). A new pose (steering, smoke) is
  selected by the main code (`EinCarPrep`). Generated transition records identify the
  pattern runs to send directly from resident art and the cells whose drawn colours
  changed. Ground changes also recolour cells with transparent lines.
- **Writing VRAM:** a frame goes in during one vertical blank, row by row
  (a row's slots, then its names), so no row shows new names over old
  patterns. Writes go at full speed (an unrolled OUTI, 16 T a byte) while
  the blank lasts by the clock: the CTC's 16 ms wait, started as the frame
  was seen, counts down 256 T a step (`EinSpend`, `BLANK_END`). Past it,
  and for a frame seen late, writes are paced (32 T), and the harness
  counts no access that comes too fast. The CTC's 1 ms interrupt
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

- speed (section 6)

## 5. Graphics: the name table does the work

The native race artwork, postcard format and current pattern allocations are documented in [Einstein artwork](einstein_artwork.md).

As planned, with the details above. Per third (256 patterns each):

| Third | Patterns |
|---|---|
| top (rows 0-7) | rows 0-7 mirrored, one pattern a cell |
| middle (rows 8-15) | 0-15 solid colours, 16-59 slots (rows 12-15, 11 each: the kerbs', silhouettes', and the road's where it is drawn the exact way), 60-63 free, 64-127 rows 8-9 mirrored, 128-191 the panorama (2 rows x 32), 192-255 the panorama's cells under a silhouette. (`-DEIN_BLOCKS`: 16-35 slots, 5 a row, 36-63 the kerb's edges) |
| bottom (rows 16-23) | 0-15 solid colours, 16-191 slots (22 a row), 192-219 the kerb's ready-made edges (used with `-DEIN_BLOCKS`), 220-221 the verges' textures, 222-223 free, 224-255 the player's car |

The kerb's ready-made edges (`-DEIN_BLOCKS`; the bottom third's are
written in any build): 7 left edges (road from pixel 1-7) and 7 right
(road to pixel 0-6), in the light kerb and the dark, in each of the road's
thirds (`EinStaticInit`, at a display reset). The sprites: the tail lamps' two
highlights (sprites 0 and 1, pattern 48). With `-DEIN_DASH` the centre
line's 12 come first, one a road row, their patterns 4k on, and the lamps
are sprites 12 and 13.

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
frame takes longer. In the attract demo with normal timing (`wait16
GameFrames 20`, then `fliphist 1300`), 243 intervals take 4 TV refreshes,
54 take 5 and 9 take 6. The average is 11.81 fps, and the longest gap is
120 ms. The harness's `fliphist N`
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
| the fourth, locked at 4 | 1,268 (4.23, 11.8 fps) |
| the fourth, unlocked | 1,166 (3.89, of which about 0.1 waits for the flip) |
| the native artwork, locked at 4 | 1,474 (4.91, 10.2 fps) |
| the native artwork, unlocked | 1,436 (4.79) |
| its speed work, locked at 4 | 1,343 (4.48, 11.2 fps) |
| its speed work, unlocked | 1,279 (4.26) |
| the objects' work, locked at 4 | 1,318 (4.39, 11.4 fps) |
| the objects' work, unlocked | 1,248 (4.16) |
| before the Spider pose deltas, locked at 4 | 1,310 (4.37, 11.45 fps) |
| before the Spider pose deltas, unlocked | 1,235 (4.12) |
| Spider pose deltas, locked at 4 | 1,301 (4.34, 11.53 fps) |
| Spider pose deltas, unlocked | 1,225 (4.08) |
| Tile-order panorama and batched uploads, locked at 4 | 1,290 (4.30, 11.63 fps) |
| Tile-order panorama and batched uploads, unlocked | 1,210 (4.03) |
| no centre line, ready-made near kerbs, locked at 4 | 1,220 (4.07, 12.30 fps) |
| no centre line, ready-made near kerbs, unlocked | 1,017 (3.39) |
| the kerbs exact, 4-line steps, locked at 4 | 1,315 (4.38, 11.41 fps) |
| the kerbs exact, 4-line steps, unlocked | 1,239 (4.13) |
| open-road band calculation and cached hill mapping, locked at 4 | 1,301 (4.34, 11.53 fps) |
| release with batched road uploads and compact kerbs, locked at 4 | 1,292 (4.31, 11.61 fps) |
| the same, unlocked | 1,200 (4.00) |
| the road's projection the Einstein's way, locked at 4 | 1,279 (4.26, 11.73 fps) |
| the road's projection the Einstein's way, unlocked | 1,176 (3.92) |

With normal game timing, `wait16 GameFrames 20` then `fliphist 1300` in Albert
gave 253/41/12/1 intervals of 4/5/6/7 TV refreshes before the change and
258/44/6/1 after it (11.84 to 11.93 fps). The fixed-step demo used the straight
and steering poses. In a separate fixed-step workload that alternated the two
left smoke puffs every game frame, the same 300 updates took 1,413 refreshes
before and 1,301 after. All timing runs recorded zero fast VRAM accesses.

The panorama change brought the same normal-timing sample to 264/38/7/1 intervals
of 4/5/6/7 refreshes (11.97 fps). On the 300 fixed-step updates, Albert attributed
1,204 T-states per TV refresh to `EinPanoCell` before the change and 684 after.
The panorama names and both silhouette planes matched the Spider-only build on
all 320 sampled updates, including 136 with objects across the horizon.

**The road's projection the Einstein's way** (23 November 2026). The
shared pass 1 and hill mapping had been left as the Spectrum's. Three
pieces now have Einstein versions (`IFDEF`: the Spectrum's build is byte
for byte the same), each checked against the pictures of the build before
at every 10th game frame of the fixed-step demo (all identical):

| Change | Locked | Unlocked |
|---|---|---|
| before | 1,292 | 1,200 |
| pass 1, `HillStore` and the hill mapping's ground without the centre line, which the Einstein never draws (`EIN_NOLANE`: `LaneX` stays $FF); the road's centre to the other register set by the stack, not IX; the slow path `Span`'s | 1,283 | 1,186 |
| the hill mapping's loop with `ProjClip + j` in HL' and the free pairs in C' (not IY, IXL), one test each for the events; `HillStore`'s depth line in C' | 1,280 | 1,178 |
| `ApplyCurve`: `<< (zone - 2)` where the zone is 2 or more (exactly the same), not `<< zone` then `>> 2` | 1,279 | 1,176 |

In normal timing (`wait16 GameFrames 20`, `fliphist 1300`) the frames came
238 / 59 / 8 / 0 at 4 / 5 / 6 / 7 TV frames before (11.78 fps) and 261 / 43 /
5 / 1 after (11.96 fps). Measured and not done: pass 1's event test as a
count down (about 0.5K T a frame, for a change to the shared `NextEvent`);
the empty silhouette cells (`EinSprMask`): 21 cells a game frame are read
back from screen B, 7 of them empty, at about 530 T each - about 3.7K T in
all, and knowing a cell empty without reading it costs most of that in time,
or more memory than there is. What is left is mostly traffic and scenery: a
plan for drawing them the Einstein's own way is in
[einstein_objects_plan.md](einstein_objects_plan.md). A prototype of hardware
sprites for them took normal play from 11.96 to 12.12 fps but made small objects
one colour (black palms), so it was dropped; the results are in its section 5.

**Einstein upload and kerb optimisations in the release.** Albert's
normal-timing attract demo was sampled for 1,300 TV refreshes after
`wait16 GameFrames 20`. The fixed-step benchmark times the same 300 game
updates in each build.

| Build | Fixed-step TV refreshes | Fixed-step fps | Normal intervals at 4 / 5 / 6 / 7 refreshes | Normal fps |
|---|---:|---:|---|---:|
| Previous release | 1,301 | 11.53 | 240 / 50 / 14 / 0 | 11.75 |
| Batched road uploads (P1) | 1,297 | 11.57 | 244 / 50 / 10 / 1 | 11.79 |
| Release with batched uploads and compact kerbs (P1 + P2) | 1,292 | 11.61 | 243 / 54 / 9 / 0 | 11.81 |

The combined build's entire 16 KB VRAM matched the previous release at the road upload
checkpoint (`EinMirror`) on 320 consecutive fixed-step updates. The harness
recorded zero fast VRAM accesses.

1. `EinSlotRuns` groups adjacent dirty slots by row and plane. `EinSendRun`
   streams each group from the lowest address, and the row's names follow
   both planes.
2. Four-line kerbs retain two pattern bytes during classification.
   `EinCommitKerb` expands them into the slot shadow only on a pixel change.
   All eight previous bytes are checked because a slot can have held scenery
   or a tunnel tile. Colour and mask changes are tracked independently.
3. Reduce silhouette reads on busy frames. `EinSprMask` took 33,059
   T-states in one six-refresh interval. Across 300 normal updates, the
   685 sprite commands covered 5,645 cells in rows 10ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Å“23, counting each
   cell once per update. At entry to `EinSprCells`, 2,213 of those cells
   (39.2%) held eight zero bytes in screen B. Precompute occupied cells
   for each shifted sprite, taking its vertical alignment and clipping into
   account. Use that information to skip empty cells when reading and
   clearing screen B. Preserve overlap colours, portal masks and erasure
   of cells occupied on the previous frame.

**The speed cut: no centre line, ready-made near kerbs.** At 1,290 locked
(210 frames at 4 TV frames, 61 at 5, 8 at 6 in the fixed-step demo), the
graphics that could be simplified were measured one by one (22 November
2026; each a build of the same tree, locked at 4; 1,200 is every frame at
4):

| Build | TV frames | fps |
|---|---|---|
| as it was | 1,290 | 11.63 |
| the near kerbs ready-made (`EIN_SLOPE` none) | 1,240 | 12.10 |
| exact only for edges past 8 pixels (`-DEIN_SLOPE=8`) | 1,271 | 11.80 |
| no centre line | 1,243 | 12.07 |
| the centre line in rows 16-23 only | 1,278 | 11.74 |
| **no centre line, near kerbs ready-made (`-DEIN_BLOCKS` now)** | **1,220** | **12.30** |
| that, and no scenery nearer than 200 | 1,214 | 12.36 |
| that, and no hills (pass 1 always flat) | 1,210 | 12.40 |
| no hills alone | 1,263 | 11.88 |
| scenery to depth 800, not 1,200 | 1,269 | 11.82 |
| at most 4 scenery objects, not 8 | 1,288 | 11.65 |
| no scenery nearer than 200 | 1,278 | 11.74 |
| no traffic | 1,266 | 11.85 |
| no scenery, or no objects at all | 1,200 | 12.50 |

The two cuts taken save about 23K T (`EinSlopeRow`) and 24K T (the centre
line's sprites) a game frame, and in the fixed-step demo 281 frames in 295
come at 4 (12 at 5, 2 at 6). Objects are the cost left: without them every
frame makes 4, but trimming them by distance or count gains little. With
the lock at 3 (`-DEIN_MIN_FRAMES=3`) the new build averages about 14.1 fps
in the fixed-step demo (224 frames at 3, 91 at 4, 22 at 5, 2 at 6): faster,
but uneven, so the lock stays at 4. Without objects as well it would hold
3 (16.7 fps). The old look built with `-DEIN_DASH -DEIN_SLOPE=4`, byte for
byte as before the cut, until the objects' colours filled bank 2 (below).

**The kerbs exact (the default since 22 November 2026).** The kerb's outer
edge had always been on a cell's edge (the Spectrum's kerb is a run of
attribute cells), and since the cut its inner edge was upright in each row
too: 8 x 8 blocks. `src/einstein/kerbrow.asm` draws every row of the open
road (12-23) with both edges exact, the kerb as wide as the Spectrum's
(`RoadRW`). A cell's line can be over grass or over road, so a slot holds
a second colour byte and a mask of the lines over it (`SLOT_SIZE` 11;
`EinCommitAt`, `EinSendSlot`, `EinSendCols`). The middle third's
ready-made kerb edges' patterns are slots (11 a row there, not 5); no row
is drawn the ready-made way, and one `EinKerbRow` can't draw goes the exact
way. Where the far rows' narrow road puts both kerbs in one cell, its
cells are made with both at once (`EinKerbMerged`). By default a cell's
kerb comes from lines 0 and 4 alone, each byte on 4 lines (4-line steps,
`EIN_KERB4`); `-DEIN_KERB2` uses all 4 line pairs (2-line steps); and
`-DEIN_BLOCKS` keeps the ready-made way. Measured (22 November 2026):

| Build | benchmark, locked | unlocked | attract demo, normal timing |
|---|---|---|---|
| block kerbs (`-DEIN_BLOCKS`) | 1,220 (12.30 fps) | 1,017 (3.39) | 318 / 3 / 1 at 4 / 5 / 6 TV frames (12.45 fps) |
| before the cut | 1,290 (11.63) | | 264 / 38 / 7 / 1 at 4 / 5 / 6 / 7 (11.97) |
| exact kerbs, rows 16-23 only (the first prototype) | 1,326 (11.31) | 1,257 (4.19) | 229 / 62 / 11 at 4 / 5 / 6 (11.69) |
| the same, the kerb twice as wide | 1,348 (11.13) | | |
| exact kerbs, rows 12-23, untuned | 1,461 (10.27) | 1,423 (4.74) | 140 / 95 / 40 / 3 at 4 / 5 / 6 / 7 (10.73) |
| exact kerbs, 2-line steps, tuned (`-DEIN_KERB2`) | 1,392 (10.78) | 1,338 (4.46) | 177 / 81 / 28 / 2 at 4 / 5 / 6 / 7 (11.12) |
| exact kerbs, 4-line steps, before the shared road optimisation | 1,315 (11.41) | 1,239 (4.13) | 231 / 60 / 12 at 4 / 5 / 6 (11.69) |
| exact kerbs, 4-line steps, previous release | 1,301 (11.53) | | 240 / 50 / 14 at 4 / 5 / 6 (11.75) |
| exact kerbs, 4-line steps, release | 1,292 (11.61) | | 243 / 54 / 9 at 4 / 5 / 6 (11.81) |

The untuned version cost about 108K T a game frame more than the block
kerbs: `EinKerbRow` about 86K (11.9 rows, 7.3K a row: IX-indexed loops and
a call a cell), the slots' commits about 17K more and their sends about 9K,
less `EinRowFast`'s 19K. Tuned (the same pixels, checked over 30 frames):
the line groups loaded unrolled, with the runs' extremes in registers
(`KLOAD`); each cell's groups unrolled straight into `EPat` with their AND
and OR, through a 256-byte table of a cell's pixels from v on (`EKGe`,
indexed by v - x0, which caps a run at 119 pixels); a commit of one colour
pair as cheap as before. In 2-line steps the drawer (`EinKerbRow`,
`EinKerbRight`, `EinKerbCell`) takes about 60K T a game frame, for about 43
kerb cells and 11.5 rows; each changed kerb cell costs about 600 T more to
commit to a slot and to send. 4-line steps halve the groups to load and
work out, and fewer kerb cells change a frame. The code is in
`kerbrow.asm` (bank 2), `kerbcell.asm` (below $4000, where the ready-made
rows' code is left out of the build) and `kerbmac.asm` (the macros of
both).

The slots run short. Over the benchmark's attract demo (`linehist
EinAllocSlot.full 1300`) a row found its slots all used 362 times with
the block kerbs (5 a row in rows 12-15), 185 with `-DEIN_KERB2` and 72 with
the 4-line kerbs (11 a row there). Each is a cell not drawn: with the
block kerbs, at the benchmark's frame 200, a lorry in row 12 shows its
wheels but not its body.

`profile N` in the harness gives each routine's T-states and calls over N
TV frames (`profilel N`: local labels apart). Before the speed cut, a
game frame's work was about 330K T (about 270K since): the shared game logic about 130K (pass 1, the hill
mapping, the projection, the sprites' XOR chain into screen B), which
costs the same as on the Spectrum and is left alone so the Spectrum's
build stays the same; the road's rows about 60K, of which the near rows'
sloped kerbs (below) about 30K; writing VRAM about 45K (half of it the
bytes, half each write's own work); the silhouettes about 40K; the centre
line's sprites about 22K; the car's colours about 10K. In the attract
demo the road's shape changes nearly every frame, so 11 of the 12 road
rows are built again a frame.

**The near rows' sloped kerbs** (only with `-DEIN_SLOPE=n` since the speed
cut above; the figures here are from before it). Since the native artwork, a row of 16-23
whose kerb edge slopes more than `EIN_SLOPE` (4) pixels between its top
and bottom lines is drawn the exact way, in slots (2-line steps), as a
tunnel's or a fork's is: about 4.7 rows a frame in the attract demo, at
about 7K T each more than a ready-made row. Such a row is drawn in one pass
(`EinSlopeRow`, `src/einstein/slope.asm`): its kerb cells straight from its
line pairs' edges in pixels, where each kerb run is crossed by its own edge
alone (else the generic way, as a tunnel's). Assembled with
`-DEIN_SLOPE=8` (only edges steeper than 45 degrees exact: a straight
road's near kerbs become 8-line steps) the benchmark takes 1,290 locked
(230 frames in 300 at 4) and 1,198 unlocked; with `-DEIN_SLOPE=127` (none,
the look before the native artwork) 1,253 (269 at 4) and 1,124.

Tried and measured since the native artwork (unlocked, from 1,436):

- kept: the car's colours made and sent only for the cells whose pose or
  ground changed, not all 256 bytes whenever any did (1,399); a row's
  road slots taken from the bottom up in a light band and the top down in
  a dark one, its silhouettes' on from them (`EinSlotRange`): a kerb
  slot keeps its colour as bands pass, and 8 colour bytes a slot are no
  longer sent (1,369; colour-only sends 8.6 a frame to 0.1); the dirty
  list a byte a slot, counted per row, its row's addresses worked out once
  (1,359); a sloped row's ranges made in `EinRowFast`, not again in
  `EinRowRanges` (1,350); the blank's budget by the CTC's clock, not in
  units (1,334); a kerb run's masks, classing and naming in one loop
  (1,331); the centre line's covered cells from the two mask bytes under
  its 16 pixels, not the row's 4 and three calls (1,321); a silhouette's
  mask straight into `EPat`, its mask bits set a byte at a time, its cells'
  inks only from row 10 (above, nothing reads them) and found by rotates
  (1,302); the game's keys looked up straight in the rows read
  (`EinReadInput`, 1,287); a row's ground name worked out once, and
  unrolled OUTIs in the blank (1,279); last frame's silhouettes XORed out
  of screen B above row 10 only, each cell below cleared as it is read
  back (`EinErase`, `EinSprMask`: 1,252); the rows with silhouette cells
  noted (`ENRows`, `EURows`), so that only they are copied, cleared and
  mirrored (1,248); a row drawn again for its bands only when those of its
  lines 0 and 4 move (its others are never used: 1,244); a sloped row in
  one pass (`EinSlopeRow`, 1,235: the kerb cells' work was near its floor
  already; the generic line-edge pass and some calls go)
- measured, not done: a row's names sent only where they changed. Of the
  12 road rows 9.5 change a frame, in 17 cells on average but spread over
  24.5, and 2.5 are sent unchanged: about 2-4K T to gain, and comparing
  names (about 42 T a byte) costs more than sending them (about 28)
- dropped: clearing the cells last frame's silhouettes covered in a pass of
  their own (no change: the pass cost what the XOR saved); a 2 ms wait
  after the 16 ms one, for fewer polls (one fewer a TV frame, no change);
  the panorama's silhouette cells in two passes, colours then pixels (no
  faster: the loops cost what the IX and IY work did)

**Objects, and an engine of the Einstein's own.** Without traffic and
scenery (a measuring build) the benchmark takes 941 unlocked and 1,200
locked: every frame at 4. They cost about 82K T a game frame: the
projection about 9K (`DrawObject`, `DrawTraffic`), the XOR into screen B
about 9K, reading the cells back 9K, the compositing (masks, inks, rows'
names, slots) about 25K, the slots' commits 7K and their sending about 15K.
In the attract demo 2.4 objects are drawn a frame, 38 lines and 143 bytes,
all but a fraction of a line below row 10, over 23 cells (1.2 of them
under two objects). An object path of the Einstein's own, the cells built
from the silhouettes without screen B, was weighed: built a cell at a time
its bytes cost what the XOR's do (a cell's lines are 8 bytes apart), and
every changed cell still needs a slot made and its 16 bytes sent, about
1.9K T: about 16-20K T to gain, of which the erase above is the most.
Hardware sprites are one colour and four a line (the centre line takes one
a row). The road's projection (pass 1, the hills: about 74K T) is used at
every line pair (each row's band check, the sloped kerbs), so one of the
Einstein's own would save little. Even without objects a frame's work is
3.14 TV frames, so 16.7 fps (3) is out of reach; a steady 12.5 needs about
25K T less a frame.

Before the native artwork:

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
tyres, the crew's close-ups, the car's drawing, and the panorama's and the
kerbs' unrolled chains) is left out of its build (`IFNDEF EINSTEIN`).
That made room for the Einstein's keys, disc and front-end code in bank
2, and at the chains' place ($B900-$BAD7) the ready-made kerb edges' set-up
(`src/einstein/static.asm`), the OUTI chain and the rest of the display
reset's set-up (`src/einstein/reset.asm`). The Einstein's own buffers
(the names, the sky's attributes, the masks, the panorama's sprite cells,
the rows' signatures) are in screen A's memory, above the stage overlay
($4800-$5AFF): the game code never writes screen A here (`Ceiling` and
`TimeWarn` skip it). The Spider now reads its pattern and colour sources directly
from resident art. The normal build (the exact kerbs, in 4-line steps) has
288 bytes free before the bank 2 tables, 268 below $4000, 128 at the end
of the Einstein's buffers (after `EObjectLower`), 25 before the bank 5
track cache and 324 at the end of screen A. `-DEIN_KERB2` leaves 92 in
bank 2; `-DEIN_BLOCKS` 1,104 (and 76 below $4000), with `-DEIN_DASH` 256,
with `-DEIN_SLOPE=4` 759. Two combinations no longer fit: the look before
the speed cut (`-DEIN_BLOCKS -DEIN_DASH -DEIN_SLOPE=4`: bank 2, since the
objects' colours took 144 bytes of it), and the centre line with the exact
kerbs (`-DEIN_DASH` alone: the buffers).

## 7. Building and testing

| Command | Does |
|---|---|
| `make einstein` | `build/einstein/speedrun.dsk` (and `.com`, `.sym`, `.lst`) |
| `make release-einstein` | copies the bootable disc to `release/speedrun.dsk` |
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
