# Speed Run — Development Plan

An original, arcade-style "sunny coast-road" racer for the **ZX Spectrum 128K**,
in the spirit of the late-80s sprite-scaling road racers: a convertible sports car,
pseudo-3D road with curves and hills, roadside scenery rushing past, traffic,
branching routes, a checkpoint timer and a car radio with choosable music.

> Everything here (name, car, stages, art, music) is **original**. We borrow the
> genre and mechanics, not any existing game's assets, characters, tracks or music.

---

## 1. Design goals

| Goal | Target |
|---|---|
| Frame rate | **25 fps** (one game frame per 2 TV frames), never below 16.7 fps |
| Smoothness | Full double buffering via the 128K shadow screen: no tearing or flicker |
| Visuals | Scanline-accurate road stripes, scaled scenery, parallax horizon, colour without clash |
| Audio | AY-3-8912: in-game music (3 "radio stations"), engine note, SFX |
| Content | 15 stages in a 5-level branching pyramid, 5 different endings/goal scenes |
| Controls | Keyboard (redefinable), Kempston, Sinclair (Interface 2), Cursor |
| Distribution | `.tap` / `.tzx` with loading screen; `.sna` for development |

---

## 2. Hardware constraints & how we beat them

**CPU:** Z80 @ 3.5469 MHz. A 128K frame is **70,908 T-states**, so at 25 fps we have
~141,800 T per game frame, minus ~2 × 3,000 T for the music interrupt.

**Display:** 256×192 bitmap (6,144 bytes, non-linear row order) + 32×24 attribute
cells (768 bytes, one ink + one paper colour per 8×8 cell). Attribute clash is the
enemy of colourful racers.

**Memory (128K):** eight 16K banks. Bank 5 is fixed at `$4000`, bank 2 at `$8000`,
any bank can be paged at `$C000` via port `$7FFD`. Banks 5 and 7 are both displayable
(bit 3 of `$7FFD` selects which) — this is our free double buffer.

### 2.1 Memory map (as built)

```
$4000-$5AFF  Bank 5: screen buffer A
$5B00-$788E  Bank 5: resident graphics (car, van and lorry sprites, font,
             player car, crew close-ups), the music player, the ways into
             the stage loader and the front end; 333 bytes free up to the
             track cache
$7D80-$7FFF  Bank 5: TRACK CACHE: the current stage's segments and objects
             (640 bytes; also the bounce buffer while a theme or the front end
             is loaded)
$8000-$BFFF  Bank 2: code, stage table, lookup tables, unrolled chains (hill
             tables in the gaps between them), IM2, stack
$C000-$DAFF  Bank 7: screen buffer B
$DB00-$FFFF  Bank 7: THEME CACHE: the current theme's sprites (scenery types,
             curve and fork signs), mountain backdrop, palette, name; or, while
             the front end runs, the front-end overlay
```

Freeing memory *(as built)*:

- **Between-stages overlay** (`src/stageov.asm`, 1.2 KB): stage loading
  (packs, track state, traffic set-up), the checkpoint's move onto the next
  stage (branch, extra time, the stage's name), a new game's set-up, the
  display reset (screen clear, HUD labels, per-buffer state) and the stage
  table only run at a stage change, at power-on and between games, and each
  time the screen is about to be cleared or replaced by the front end. So they
  are stored in a pack bank and run from screen A: `StageOv` (`src/stage.asm`)
  shows screen B (blanked first, except at a checkpoint, where the last game
  frame stays on show), copies the overlay to `$4000` and calls it. The
  display reset clears and labels screen B only and ends with a resident
  12-byte copy of screen B over screen A, which also wipes the overlay, so
  that copy is always the overlay's last act. Resident: the ways in, the goal
  check (the last row) and that copy.
- **Table-page holes** (`src/holes.asm`): most lookup tables fill 96 or 192
  bytes of their page. `zxsim -u` (a map of what a run reads, writes and
  executes) showed nothing touches the rest over whole games, apart from one
  byte after `ScrLo` / `ScrHi` and the state pages (cleared whole by
  `ResetDisplay`) and two tables read a little past their end. The crew's
  lines, the high-score table, the route and the lamp graphic live there;
  `gen_tables.py` marks each table's end and the build asserts nothing grows
  into them. About 390 bytes of holes are still free, the biggest piece
  164 bytes in the strip page.
- **Car frames** as shared top and bottom parts: the drift frames' two smoke
  puffs differ only in the bottom cell row (`png2zx.py` split mode).

Together: bank 5 went from 4 bytes free to 1265 (since spent on more
scenery, the music player and the crash sound). Moving the checkpoint, new
game set-up and display reset into the overlay later freed another 303 bytes
of bank 5 and 221 of bank 2's code area (which had none left).

- **The top of bank 2** *(as built)*: the tape loader loads bank 2 only up
  to `$BDC0` (it runs at `$BE00`), and `zxsim -u` over whole games (title,
  options, demo, a game, crashes) shows the stack never more than 46 bytes
  deep. So `$BDC0-$BDFF` (before the IM2 table) and `$BF01-$BF7F` (below the
  stack, which keeps 128 bytes) hold variables the game sets up itself: the
  traffic table, the tunnel's state, the per-run state and one sprite
  command list - 166 bytes out of the main code area, which had 9 left.
  (The jingle pointer stays there: the interrupt reads it from the start.)
- **Per-frame trims** *(as built)*: the engine pitch multiplies by 50 with
  shifts (was a 50-step loop, 1100 T a frame), `ApplyCurve` skips its sums
  on straight segments, and the timer's big digits double a nibble at a
  time from a 16-byte table. About 3500 T less work a game frame, but the
  frame rate does not move: frames are held to 3 TV frames when they fit,
  and the ones that do not (hills, curves, forks and traffic together,
  about 258k T against 213k) are over by far more than such trims save.

Bank 7 stays paged at `$C000` all the time. While buffer A is drawn, bank 7 is
the screen being shown, but paging it in only for memory access doesn't change
what is displayed. So the theme cache is always reachable.

| Bank | Use |
|---|---|
| 0, 1, 3, 4, 6 | Stage packs: 5 theme packs (~9 KB each) and 15 track packs (~0.5 KB), built by `tools/make_stages.py` and assembled to run in the caches; the compressed title and goal pictures |
| 2 | Code, tables |
| 5 | Screen A, resident graphics, track cache |
| 7 | Screen B, theme cache |

A stage start copies its theme pack (through the track cache, because the storage
banks share the `$C000` slot with bank 7) and its track pack, reads the pack
headers, and resets both screen buffers and all per-buffer render state.

### 2.2 Colour strategy (clash-free by construction)

Rather than fight clash, the play area uses a **per-character-row attribute palette**
and all moving objects are drawn as masked monochrome bitmaps that inherit it:

- **Sky rows:** bright cyan/blue paper, white ink for clouds and the horizon skyline.
- **Horizon/scenery band:** stage-specific (yellow desert, white snow, green forest,
  magenta sunset…). Rewritten when the horizon moves vertically over a hill crest.
- **Road rows (as built in M1):** each character row is split into five attribute runs:
  grass | kerb | road | kerb | grass.
  - *Grass* cells: green paper; bright/dark alternates with the light/dark bands.
  - *Kerb* cells (the cells the road edges pass through on that row): white/red paper
    alternating with the bands, black ink. The bitmap holds the road's pixels as black
    ink, so the road edge is pixel-smooth while the kerb colour fills the cell
    outside it — red/white kerbs with no clash.
  - *Road* cells: black paper, white ink for the centre line.
  - Grass and road bitmaps are zero, so the bands cost nothing: they are attribute
    changes. Only kerb-cell bytes and the centre line are ever written.
- **Player car:** cells *entirely* covered by the car's body get red ink (no clash
  possible — no background shows through them); edge cells stay in the row palette.
- **HUD:** top 2 rows in full colour (speed, time, score, stage), never overdrawn.
- **Border:** stretch goal — timed `OUT ($FE)` split so the border is sky-coloured
  above the horizon and grass-coloured below, extending the picture to the CRT edge.

---

## 3. Rendering engine

### 3.1 Pseudo-3D road ("segment + scanline" method)

1. Road lives in the bottom ~96–120 scanlines below a variable horizon.
2. Precomputed **Z table**: for screen line *y* below the horizon,
   `z(y) = cameraHeight × scale / (y − horizonY)`; also `1/z` for width/scale.
3. Track = list of **segments** (curve amount, hill slope, length, roadside objects,
   traffic spawns, fork marker).
4. Per frame, walk lines bottom→top accumulating `dx += curve(segment at z)` and
   `x += dx` to bend the road; hills offset the per-line y mapping (§3.2a).
5. Each line becomes a *span list*: grass | rumble | road | line | road | rumble | grass.
   Light/dark is chosen by `(z + trackPosition) & stripeBit`.

### 3.2 Road drawing (as built in M1)

- Pass 1: road centre `cx` per line from a 16.8 fixed-point accumulator (one
  multiply per frame), plus the band bit `(z + position) & STRIPE_BIT`.
- Pass 2, per character row: kerb cell ranges from the row's top and bottom lines;
  attributes rewritten only when ranges or band change.
- Per line: kerb bytes come from a prebuilt strip (`0…0, edge mask, $FF…$FF`) copied
  with an unrolled `LDI` chain; the centre line is two OR-mask bytes.
- **Per-buffer state** (each buffer is redrawn every second frame) records `cx`, the
  centre-line x and each row's kerb ranges, so unchanged lines are skipped and moved
  rows only clear the stale cells.
- Per-row constants are patched into the line routine (self-modifying code).

### 3.2a Hills (as built)

- Segments carry a hill value next to their curvature (`dw length; db curve, hill`).
  Going up the depth lines from the car, the hill value (weighted by depth zone,
  like curves) is added to a vertical speed and that to a vertical offset: depth
  line `j` lands on screen line `j − offset`. Positive values lift the road ahead
  (a climb), negative ones drop it away (a crest). The camera follows the road's
  slope at the car, so the horizon stays put; road that would rise above it is
  cut at the top of the road area.
- `HillMap` (before pass 1) works out, per depth line pair, the screen line it
  lands on and how many screen pairs it covers: a rising stretch covers several,
  one that falls behind nearer road (beyond a crest) none, and the pairs above the
  furthest visible road are ground without road. Pass 1 still computes the road
  in depth order and `HillStore` copies each line's edges onto its screen pairs.
- `SrcLine[screen line]` = the depth line shown, for kerb width, centre-line width
  and the light/dark band. Scenery and traffic stand on their depth line's screen
  line and are cut off below the road in front of them (crests).
- With no hill in view all of this is the identity and costs nothing; on hills
  the whole road moves every frame (about 4% slower than the same road flat).
- The generator adds hills per theme strength (`hills:` in `stages.yaml`): over a
  hill, through a dip, or a long climb, each ending level; the stage start and the
  run-in to the fork stay flat.

### 3.2c Title and goal screens (as built)

- `tools/make_screens.py` draws the title and five goal scenes in RGB with the
  Spectrum's 15 colours, converts them (two colours per 8×8 cell) and compresses
  them with a small LZ format (`$00-$7F` literals, `$80-$FE` back-references,
  `$FF` end): 1.8–3.8 KB each. They sit in the pack banks next to the stage packs.
- The front end is an overlay (`src/frontend.asm`): assembled to run at the
  theme cache and stored in a pack bank (7 KB kept for it), copied in by
  `LoadFrontEnd` (`src/screens.asm`, resident) when a game ends or the demo
  hands over to the title. It unpacks a picture into screen A while B is on
  show (`ShowPic` and the unpacker stay resident: they page the pictures' banks
  over the overlay), prints the high score / results with the HUD font and runs
  the screen's own loop; the game's sound is muted and the screens beep
  themselves. Afterwards the stage's packs are copied in again (`LoadPacks`).
- Flow: boot → title (8 s or a key; ENTER: options) → high-score table (6 s) →
  demo (≈25 s, continuing where it left off) → title … A game ends with the car
  rolling to a stop, then the goal screen for the last-row stage reached (time
  bonus counted in), the route map (the pyramid with the stages driven lit up
  in their theme's colour, numbered and linked, and their names), the
  initials entry if the score made the top five, the table with the new entry
  flashing, then the title.
- The table (5 × score and initials) and the route (the stage played on each
  row, recorded by `LoadPacks`) live in bank 5; the options screen sets
  `KeyMap` (a keyboard row and key bit per control, read by `ReadInput`):
  presets for Q/A/O/P/SPACE and the Sinclair and Cursor joysticks, or keys
  picked one by one (H and ENTER are kept for pause and the options; a key
  can't be used twice). A Kempston joystick always works.
- H pauses (`src/pause.asm`, in a gap of bank 2): the last frame stays on show
  with PAUSED on the message line and the sound off; no time passes in the
  game.

- Starting lights *(as built, `src/lights.asm`)*: a new game holds the car (no
  input, no time passing) for 230 frames while three lamps (16×16 circles in
  black 2×2-cell boxes, drawn into both screens) light red one by one, each
  with a beep on channel C, then all green with a higher one; they clear
  40 frames later. The front-end screens play short tunes on channel A.

### 3.2d Tape release (as built)

`make tap` builds `build/speedrun.tap` from a release snapshot (`-DRELEASE`, no timing
bars) with `tools/make_tap.py`:

1. BASIC `SPEED RUN` (autostart 10): `BORDER 0: PAPER 0: INK 7: CLEAR 32767`,
   `LOAD "" CODE`, `LET e=USR 48640`, `IF e=1 THEN PRINT "128K ONLY"`,
   `IF e>1 THEN PRINT "TAPE ERROR, BLOCK ";e-10`.
2. CODE `loader` at `$BE00` (`src/loader.asm`): checks that banks 1 and 3 differ
   (else returns to BASIC, which prints the message), then reads the rest of the
   tape with **its own loading routine** - standard ROM-format blocks at the
   normal speed, but no ROM calls and interrupts off throughout, so it does not
   matter which ROM is paged (128K, +2, +2A, +3). (A first version called the
   ROM's LD-BYTES at `$0556`; it crashed back to BASIC in an emulator, most likely
   because the ROM paged in during `USR` was not the 48K BASIC ROM.) The blocks:
   the loading screen (the cover art as a Spectrum screen, `assets/gfx/loading.scr`;
   to `$4000`), the pack banks 0, 1, 3, 4, 6 (each loaded to
   `$8000` and unpacked to `$C000` in its bank), bank 2 (loaded into bank 7,
   unpacked to `$8000`) and the resident part of bank 5 (likewise, to `$5B00`),
   and it jumps to the game. Compression (`tools/zpack.py`, decoded by
   `Unpack`): LZ77 with interlaced Elias-gamma lengths and offsets' high parts,
   a repeat-last-offset match and an optimal parse (two states per position:
   after a literal run, after a match) - 95.7 KB to 52.9 KB, near zlib's 52.3 KB;
   the screens' byte-level LZ managed 71.8 KB. The .tap loads in about 6
   minutes. The .tzx (same blocks) has BASIC and the loader at the ROM's speed
   and the rest as turbo blocks (TZX ID 11): bit pulses of 420 / 840 T instead
   of 855 / 1710, a 1600-pulse pilot and half a second's pause (time to
   unpack) - about 3 minutes. Its loader (`-DTURBO`) shortens the edge
   routine's settling delay for data bits and moves the bit threshold; the
   pilot and sync detection are unchanged. In zxsim both load from 80% to
   120% tape speed (the pilot detection sets that window). While it loads, a progress bar
   fills the loading screen's bottom row (a cell every 2 KB or so: a check every
   256 bytes, cheap enough for the edge timing). On a 48K (returns 1) or a tape error
   (returns 10 + the block number) it goes back to BASIC - its stack, `BANK_M`
   paging and interrupts restored; nothing has been loaded over BASIC's memory
   before the last block - and BASIC says which.

`tests/tapecheck.py` boots the tape in zxsim (`-T`: does what `LOAD "" CODE: RANDOMIZE
USR` would, then plays the tape into the EAR input - no ROM image needed) and checks
that the game starts and shows its title, that everything loaded matches the
snapshot byte for byte, also with the tape 8% slow or fast and with random bytes
in memory, and the same for the .tzx (zxsim plays TZX blocks 10 and 11). Not yet done: the BASIC
part under the real ROMs, and real hardware.

### 3.2b The road fork (as built)

- From `SPLIT_LEN` (5000) before the end of a stage, each branch's centre moves out
  from the old centre line by `dx(d) = d² / 65536` world units (`d` past the split):
  the road first widens, then a median opens (`dx` > the road's half-width, d ≈ 2900)
  and the branches part (~380 units apart each at the checkpoint).
- On screen line `k = i + 1` the branch offset is
  `24/k − FD/256 + C1·k` with `FD` the split's depth and `C1 = FD²/6291456`, so pass 1
  needs one table read and one add per line pair (`ForkFrame` works out `C1` with
  two 16×16 multiplies per frame).
- Lines where the branches overlap are one wide span and go through the normal
  renderer (no centre line). Rows where both branches are on screen (`RowFork`)
  go to `DrawForkRow`: it classifies the 32 cells from the four line pairs' spans,
  writes the attributes, and writes the bitmap only in kerb cells and in cells
  that were kerb before (found by their attributes: kerb colours are never grass
  or road colours). A row leaving fork mode clears its kerb cells the same way.
- The car is carried along the branch it is on (`PlayerX` moves out with `dx`), the
  off-road test, steering limit and crash recovery are relative to its branch,
  traffic follows the branch its lane is on, and the checkpoint takes the branch
  the car is on and re-centres it on the new stage's road.
- Cost: the split phase runs at ~12.5 fps for a couple of seconds (like a curvy
  section); the widening phase ~15 fps.

### 3.3 Horizon / background

- 512-pixel-wide panoramic skyline per stage (mountains, city, palms), stored as
  **8 pre-shifted copies** at 1-pixel steps → horizontal parallax when cornering
  costs only a block copy (`ldi` chain), **~10k T**.
- Second, slower parallax layer (clouds) in the sky rows at half speed.

### 3.4 Sprites (scenery, traffic, player)

*(As built:)* each theme has four scenery types: two common ones (ids 4, 5),
a landmark that takes the place of the big one 18% of the time (id 8) and a
second small one that takes 40% of the small places (id 9). To fit them in the
theme cache, scenery and signs keep fewer pre-shifted copies
(`SHIFTS_SCENERY`: 2 per size for the near sizes, 4 for the far ones, so
positions step by 4 or 2 pixels); that freed about 1.8 KB per theme.

- Every object exists at **8–12 pre-scaled sizes** (generated offline by the asset
  pipeline, hand-touched for the largest sizes), each with mask; chosen by `1/z`.
- Masked blit with **pre-rotated shift tables** (256-byte page per shift) so any x
  position costs one table lookup per byte instead of shift loops.
- Painter's algorithm: objects bucketed by segment, drawn far→near; clipped to
  the road's hill-crest line so objects disappear behind hills.
- Player car: 5 steering frames × 2 (uphill/downhill tilt) + braking-light variant;
  32×24-ish, drawn last. Crash: car tumble + spinning frames.
- Budget: **~50k T** for up to ~12 visible objects.

### 3.5 Frame pipeline

```
IM2 interrupt (50 Hz): music tick, input poll, frame counter, (border split)
Main loop @25 Hz:
  1. read input, update physics, advance track position
  2. update traffic & object list, collision tests
  3. draw horizon → road → sprites (far→near) → player car into BACK buffer
  4. update HUD cells that changed
  5. wait for frame counter ≥ 2, flip $7FFD bit 3 at the start of vertical blank
  (as built: logic and the road's shape run while the previous frame waits for
  its flip; see §3.6, "Overlapped frame pipeline")
```

### 3.6 Performance budget per game frame (25 fps)

| Task | Budget (T-states) |
|---|---|
| Interrupts (music ×2, input) | 6,000 |
| Game logic & physics | 10,000 |
| Horizon / sky | 10,000 |
| Road | 30,000 → revised to 60,000 (see below) |
| Scenery & traffic sprites | 50,000 |
| Player car | 8,000 |
| HUD | 3,000 |
| **Total** | **~141,800** |

**Measured** (zxsim, cycle-counted with 128K contention, T-states per game frame):

| Version | Situation | Road | Frame rate |
|---|---|---|---|
| M1 first version | steering | 274,000 | 11 fps |
| M1 | standing / straight / steering hard | 75,800 / 105,500 / 158,000 | 25 / 24 / 17.7 fps |
| M1b (v7) | standing / straight / steering hard | ~55,000 / 75,300 / 137,000 | 25 / 25 / 19 fps |
| M2+M3 | attract-mode lap of the curvy test track, road + car | 147,000 + 5,800 | 18.6 fps |
| M4+M5 | lap with scenery and panorama; road paired lines, depth-weighted curves | 117,400 (peak 160,000) | 19.3 fps (2 TV frames 43%, 3 frames 54%, 4 frames 3%) |
| M7 | traffic, signs, frame rate locked to 3 TV frames | 118,000 (peak 152,000) + sprites 43,000 | 15.7 fps (3 TV frames 83%, 4 frames 17%) |
| Before M11 | full autopilot game with hills, forks, momentum (work 220–250k on bends) | ~165,000 | 12.5–13 fps on bends and hills |
| M11 pass 1 | same: logic and road shape overlapped with the flip wait, dual-line kerb chain, unrolled pass 1, car redraw only when touched, table-based `ZLine` | ~155,000 | 15.6 fps over the whole game (16–16.5 on stage 1) |

**Overlapped frame pipeline (M11):** the main loop runs the game logic and the
road's shape for the next frame (`RoadPrepare`: curve list, fork, pass 1, hill
mapping, bands - nothing that touches the screen) while the frame just drawn
still waits for its flip, then `WaitFlip`, draws the back buffer and
`RequestFlip`s without waiting. A frame that needs a little over 3 TV frames no
longer costs a whole 4th: the rate averages out instead of dropping to 12.5 fps.
Anything that pages banks or writes the screens outside the drawing phase
(stage loads, title / goal screens, display resets) waits for a pending flip
first.

The 30k road budget was unrealistic for 96 scanlines on a 3.5 MHz Z80. **Decision:**
the guaranteed minimum is 16.7 fps (212,700 T per game frame) with scenery and
traffic. Straights run at 25 fps, and 25 fps everywhere stays the goal for the M11
optimisation pass. Averages hid a very uneven frame rate, so `make profile` now
reports per-phase peaks and how many TV frames each game frame took.

What the renderer does now (§3.2 still applies):
- Pass 1 (only when the road shape changes) computes each line's first and last
  road pixel and the centre-line x, clamped to the screen. A line is redrawn only
  when those change.
- **Paired lines:** pass 1 computes one line in two. Every kerb, edge and
  centre-line write goes to both lines of the pair, so edges have 2-pixel vertical
  steps. That halves the per-line logic, which was the dominant cost.
- The 8 pixel lines of a character row are 256 bytes apart, so the line address is
  `inc ixh`; stale kerb cells are cleared per row, a column at a time.
- **Curves:** one 16.8 accumulator per frame from the bottom line up,
  `dx += curvature × weight; x += dx`. The weight doubles in zones going up (¼ near
  the camera, 16 near the horizon) to follow how much depth each screen line spans.
  Bends therefore build up in the distance and unwind gradually. With a flat weight
  they snapped straight in a few frames, because the bottom half of the screen
  spans only about 170 depth units.

The frame rate is locked at 3 TV frames (16.7 fps): an even pace looks smoother
than a 25/16.7/12.5 mix. The remaining overruns come from sharp bends with traffic.

**Where the frame goes now** (autopilot game, per game frame): road ~152k
(pass 1 25k, row drawing 25k, line drawing 23k, hills ~20k when in view),
sprites ~44k (projection 9k, drawing 16k, the car 7k), logic 14k, horizon 7k,
HUD 3.5k, interrupt sound and music ~9k. A game frame holds the 3-TV-frame lock
when all its work fits about 203k T. The lightest three quarters average 207k
and mostly do; the heaviest quarter averages 258k (hills, forks, traffic all
at once: road +36-46k, sprites +11-15k) and takes 4 TV frames. So shaving the
average by a few percent hardly moves the frame rate (measured: a faster pass 1
and sprite projection, -2.5k, changed nothing visible); what counts is the work
that the heavy frames do and that can go. Scenery beyond depth 1200 (objects
6 pixels high just under the horizon, 30-70 pixels in all on screen) cost a full
projection each: drawing it from 1200 instead of 2000 cut the frames that take
4 TV frames from 21% to 13% (15.5 to 15.9 fps on the FIXED_ELAPSED autopilot).
A steady 16.7 fps would need the heavy frames ~25% faster - a new road renderer
rather than more tuning (tests/rendercheck.py guards any such work: identical
screens and tables after 300-1800 loops of a timing-independent run).

Optimisation backlog for M11 (by expected gain):
1. Road row setup (~5k patching, ~4k line loop, ~7k attributes per frame): table-driven
   row constants instead of self-modifying patches; patch the narrow-road path only when used.
2. Pass 1 (~25k on curves): unroll the line pair (no per-line parity test).
3. Sprites (~43k with traffic): skip erase+redraw when a buffer's command is
   unchanged (cars driving at the player's speed); cheaper projection.
4. Per-stage sprite cache in bank 5, loaded from the free banks (0, 1, 3, 4, 6), so
   that more object types fit.

Border-colour timing bars (`PROFILE=1`) show each phase on screen; `make profile`
and `tools/hotspots.py` give exact T-state breakdowns from the emulator.

---

## 4. Gameplay

- **Car handling:** speed 0–290 km/h, LOW/HIGH gear (auto or manual option), engine
  RPM, acceleration curve, braking, off-road slowdown + grass shudder, centrifugal
  drift on curves (must steer into bends), skids with tyre squeal.
  *As built:* the car has a sideways speed (1/256 px per frame). Each 50 Hz
  frame the bend adds its push P = curvature × speed² / 32 outwards (it grows
  with the square of the speed, as cornering force does), steering ±64, and grip
  takes 1/16 of it away, so it settles at 16 × P outwards against 4 px a frame
  when steering, building up over about a third of a second and carrying on
  after a bend. Steering into a bend holds the line only while P ≤ 64: at full
  speed (20) just the gentlest bends (curvature 4); curvature 6 needs speed 18,
  10 needs 14 (200 km/h), 16 needs 11 - so you lift off or brake, as in the
  arcade racers. (Before play testing asked for more inertia the push was
  curvature × speed / 4: steering held nearly everything at full speed.) Past
  the grip limit (P > 96) the car slides: an extra outward push of half the
  excess, half the steering and grip, tyre smoke, and holding the throttle no
  longer adds speed (it scrubs off until the tyres grip again). The demo driver
  lifts off above P = 60 and brakes above 84.
- **Gears and acceleration** *(as built)*: speed is 8.8 fixed point, changed every
  50 Hz frame. LOW / HIGH, changed with SPACE or fire (on a press). LOW pulls
  18 / 15 / 10 (1/256ths per frame) below 6 / 10 / 13 and tops out at 13 (182 km/h,
  about 5 s from a standstill); changed down above that, the engine brakes the car
  (32). HIGH pulls 4 below 6, 6 to 10, 8 to 16, 6 to 18, 4 to 20 (280 km/h, about
  6 s after changing up at 182; from a standstill 12 s to 182). A crash puts it
  back in LOW. Off the throttle it
  coasts down (16), braking 64, sliding past the grip limit 24 (the throttle does
  nothing). Engine revs: speed in HIGH, 1.5 × speed in LOW. HUD: LOW / HIGH. The
  demo driver changes up at 13 and down below 8. (The timer: 68 s at the start, 48 s per
  checkpoint since the cornering got harder.)
- **Drift you can see** *(as built)*: the car sprite has 7 frames - straight,
  left, right, and drifting left / right with tyre smoke (two puffs each, swung
  further round). On a bend with P ≥ 40 and no steering the car
  yaws into the bend; from 72 (past what steering holds, and while sliding) it
  shows the smoke frames (light smoke from both rear tyres), animated. The tyre
  squeal comes with the music (§5).
- **Crew** *(as built)*: the car sprite's open cockpit row shows his head
  (white ink) and hers (yellow) over whatever lies under the car (ink turns
  black where it matches); his striped shirt and her hair sit on the rear deck.
  A crash (160 frames) shows their 48×48 close-ups (`tools/make_crew.py`) either
  side of the message line: one of 8 pairs of lines, hers then his reply.
- **Collisions** *(as built)*: roadside object → crash (the car stops and
  swings about while the crew talk, then carries on from nearer the middle);
  traffic → a bump (the car drops below the vehicle's speed and it is nudged
  ahead), or, hitting one 7+ speed units slower, a spin-out: the crash, but the
  car slides on, slowing hard (48/256 a frame) with the drift-and-smoke frames
  slewing both ways.
- **Traffic** *(as built)*: cars, vans and lorries (`TrafficRows` /
  `ClassTab` in `src/traffic.asm`): per class a sprite, a contact half-width and
  a speed range (cars 7–14, vans 6–9, lorries 5–8); per row of the pyramid the
  number of vehicles (3, 3, 4, 4, 5), the van / lorry share and the chance of a
  lane change (a vehicle drifts to the other lane over about 2 s). The sprites
  are resident in bank 5 (fewer pre-shifts than the scenery to fit).
  Weaving: a vehicle in one of the lanes 600-1111 depth units ahead of the
  player (before a fork's split) may head for the player's line instead
  (`WeaveTo`, `src/extend.asm`): a chance per game frame of 0, 3, 5, 7 and 10
  in 256 by row, so from row 2 one or two swerve into your path each stage.
  With longer stages and sharper bends (`make_track`) and the traffic mix,
  that is the difficulty curve across the rows.
- **Tunnels** *(as built)*: the alpine theme has `tunnels: 1`; `make_stages.py`
  places one 3500-6000 units long on each of its stages (clear of the start
  and the fork or goal, with its own random generator so the track is
  otherwise unchanged) and keeps scenery out of it; the track pack's header
  holds its start and end. Each game frame `UpdateTunnel` finds the depth
  lines inside it (`ObjLine`, the scenery's depth-to-line lookup) and
  `RoadBands` sets bit 7 of their band: `RowAttrs` gives such rows the
  tunnel's walls and kerbs, and the road's per-row cache (which compares the
  band) repaints them by itself. In the tunnel the sky and backdrop rows take
  the ceiling's colours, the backdrop's pixels are cleared and it is not
  drawn. After the road, `DrawPortal` finds the screen line where the road
  meets the tunnel and paints, in attributes, five runs per row sized from
  the road's edges there: approaching, a rock face, a yellow arch and the
  dark mouth; inside, the sky round the far road and the ceiling round that.
  Road rows it paints are marked (their cached band set to 1) so the road
  redraws them. About 7% off the frame rate while a tunnel is in view. Room
  came from drawing the timer's big digits from the font (`PrintBig`,
  -250 bytes of bank 5) and moving small routines into bank 2's gaps.
- **The goal's gantry, tunnel signs, lamps and echo** *(as built)*: `GateZ`
  (set at a stage start: 150 units before the goal on the last row, $FFFF -
  none - elsewhere; the forks had gantries too, taken out after play
  testing) is drawn by the tunnel's mouth painter when no tunnel is in view
  and it is nearer than 1264 units, where the road is wide enough for its
  posts (`Gate`, `GateKind`: posts and a beam in the row runs; `Chequer`
  alternates the beam's cells); once past, the sky rows are painted afresh.
  The alpine theme has an extra scenery type (id 10, `sign_tunnel`), placed
  1700 and 1000 units before each tunnel. In a tunnel's light bands
  `RowAttrs` lights the wall cell beside each kerb (lamps, from inside
  only); in the engine sound mode C plays the engine 3 steps off its pitch
  at volume 9 (`TunEcho`). Room: buffer B's sprite command list moved to the
  top 120 bytes of bank 7, which every theme pack now leaves free
  (`THEME_TOP`).
- **Hills** *(as built)*: the hill value under the car changes the speed every
  frame (2/256 per unit: climbs slow it, descents help).
- **Stages:** 15 original stages (coast, desert, alpine pass, forest, city night,
  canyon, lakeside, wheat fields, etc.) arranged as a 5-row branching pyramid; choose
  left/right at each fork. 5 distinct goal scenes.
- **Timer:** checkpoint extends time; run out = game over. Score from distance/speed,
  time bonus at goal.
  *As built:* each stage has a clock (50 Hz frames, running once the lights
  are green). At a checkpoint the time is recorded and the message line shows
  "STAGE TIME 0'38"24", then the bonus, then the new stage's name (a queue of
  messages, `MsgThen`). The bonus is 48 s, or 58 s - EXTENDED PLAY - under the
  stage's par time: `make_stages.py` works it out from the stage's segments
  (17 depth units a frame on a straight, sqrt(1600 / |curve|) on a bend,
  fitted to the attract-mode driver's times, within about 3 s a stage) and
  stores it in the stage table. The route screen after a game lists every
  stage driven with its time, and the total at the goal; a time under the
  stage's record (`StageBest`, in a state-page hole) sets it and flashes.
  Extended play also plays a jingle on channel C (`JingleTick`, run each
  interrupt from `SoundTick`, chains beeps). In the last 10 seconds the big
  timer's cells get the FLASH attribute in both screens (no cost per frame;
  the next display reset clears it) and each second pips.
- **Levels** *(as built)*: `Difficulty` (options key 6) picks a row of
  `DiffTable` in the overlay (start time 80 / 68 / 60 s, checkpoint bonus
  55 / 48 / 44 s), scales the par time (+1/8 easy, -1/16 hard) and the
  weave chance (x0.5 easy, x1.5 hard).
- **Radio:** before the race, choose one of 3 original tunes (or engine-only).
- **High-score table** with initials entry; route map shown on results screen *(as built: §3.2c)*.

---

## 5. Audio

- AY-3-8912 at 50 Hz from the IM2 handler; Vortex Tracker II (PT3) format and an
  open-source PT3 player, so music can be composed in a tracker.
- Channel allocation in game: A+B music, C shared between engine note and SFX
  (SFX pre-empt engine briefly). Engine pitch follows RPM, noise mixed on gravel.
- 3 original in-game tunes, title tune, goal/ending tune, high-score jingle.
- 48K beeper is out of scope (128K only).

---


*(As built:)* `src/music.asm` holds the interrupt's sound (`SoundTick`). With
music (a game after the green light, the title screens): drums on A, bass on
B, melody on C, no engine. Without (the attract demo, waiting at the lights,
or the sound set to the engine): the engine note on A, gravel and hits on B.
Tunes are written in `tools/make_music.py` in sections (a bass pattern
following each bar's chord, a drum pattern with a fill for the last bar, and
the melody in sixteenths with slides `/E5`, arpeggios `@A5.m` and envelope
changes `!1`) and encoded as byte streams (note, rest, tie, length, loop,
and commands: arpeggio, envelope, slide, vibrato): 320-930 bytes each. The
player's effects: arpeggios cycle the chord's three notes every interrupt;
a slide moves from the last pitch to the new note in 2, 4 or 8 equal steps;
vibrato (melody) starts 10 interrupts into a note, a triangle of +-2 x
period/64; envelopes: pluck, sustained lead, soft, bass, heavy bass. Drums are per-interrupt programs on channel A
(kick: a falling tone; snare: noise with a tone hit; hi-hat: a click of high
noise; open hi-hat: a longer one; tom: a falling mid tone, for fills). Each theme's tune is in its theme pack (header +15; room made by
storing the horizon panorama in 2 pre-shifted copies instead of 4, so it
scrolls in 4-pixel steps), the title tune in the front-end overlay. A note
starts at volume 13 (melody) / 12 (bass), fades to 9 / 8 and is silent for its
last interrupt (not when tied on). Effects take a channel and the music keeps
time unheard: tyre squeal takes A (fully while sliding or spinning, held 12
interrupts over the flicker at the grip limit; with noise mixed in for grit;
near the limit a 24-interrupt
chirp at most every 128), a bump or off-road gravel takes B (and the
noise generator),
the green light's beep takes C. A crash (`CrashStart` with the speed at impact,
`CrashTick` in the state pages' holes) has the whole AY while it lasts, the
music keeping time unheard (`MusicKeep`): B a noise burst - a crack (noise
period 6) deepening to a rumble (31), held for speed/2 interrupts at volume
15, then fading one step every speed/4 + 1 (about 0.3 s at walking pace, 1.7 s
at full speed); A a falling, gritty thud (tone and noise, coarse period 2-9,
16 interrupts) above speed 6, or the squeal in a spin-out; C clattering
debris (a jumping high pitch on alternate interrupts, the first 40) above
speed 12. The player skips interrupts while another bank
is paged over the tune (`Paged`, set by `CopyFromBank` and `ShowPic`) and is
silent while the game is paused. Main-code AY writes go through `AyPut`
(interrupts off) so the interrupt's writes can't split them.
## 6. Toolchain & asset pipeline

| Tool | Purpose |
|---|---|
| **sjasmplus** | Z80 assembler; `DEVICE ZXSPECTRUM128`, banked `PAGE`/`SLOT`, writes `.sna` / `.tap` |
| **zxsim** (`tools/zxsim`) | Our own headless 128K emulator in C: cycle counting with contention, IM2, paging, scripted keys, screenshots, border-change log, per-PC T-state profiler, breakpoints, memory dumps |
| **Python 3 tools** (`tools/`) | `gen_tables.py` (screen/road/mask tables); `profile.py` (phase timings from border bars); `hotspots.py` (profile by routine/label); planned: sprite converter/pre-scaler, panorama pre-shifter, track compiler |
| **Tests** (`tests/`) | `cputest.asm` — Z80 core self-test (40 checks); `smoke.py` — headless run with screenshot checks |
| **ZX0** | Compression of graphics/track data; tiny, fast decompressor |
| **Vortex Tracker II** | Music authoring (PT3) |
| **Fuse / ZEsarUX** | Real emulators for playtesting |
| **GitHub Actions** | CI: builds sjasmplus, runs `make test` and `make profile`, uploads `.sna` and screenshots |
| **Make** | `make`, `make test`, `make profile`, `make run` |

Source layout:

```
src/        Z80 source: main, road, sprites, horizon, physics, traffic, hud, audio, frontend
tools/      Python asset/table generators
assets/gfx  Source PNGs (sprites at max size, panoramas, car, title screen)
assets/tracks  Stage descriptions (YAML)
assets/music   PT3 tunes
docs/       Technical notes, profiling results
```

---

## 7. Milestones

| # | Milestone | Deliverable / exit criterion | Status |
|---|---|---|---|
| **M0** | Toolchain & skeleton | `make` produces a bootable 128K `.sna`; CI builds it | ✅ done |
| **M1** | Road prototype | Straight striped road, Z table, double-buffered flip, measured with timing bars | ✅ done; 25 fps straight (see §3.6) |
| **M1b** | Road optimisation | Cut the road's per-line cost | ✅ v7 renderer; more in M11 |
| **M2** | Curves & hills | Segment-based track, curves, hills, moving horizon; track compiler + 1 test stage | ✅ curves, hills (climbs, dips, crests with occlusion), YAML track compiler; the horizon stays put (camera follows the road's slope) |
| **M3** | Player car | Car with steering frames, no colour clash, basic steering/speed physics | ✅ car owns a fixed 8×4-cell block; centrifugal force; attract-mode driver |
| **M4** | Scenery | Pre-scaler pipeline, scaled sprites, hill clipping; palms/signs/rocks | ✅ 10 types (palm, bush, cactus, rock, pine, tree, lamp, curve and fork signs, traffic), per-theme sets via the cache |
| **M5** | Horizon & palette | Pre-shifted parallax panorama + clouds, per-stage attribute palettes | ✅ 5 backdrop styles and palettes (coast, desert, alpine, valley, sunset); clouds to do |
| **M6** | Physics & collisions | Gears, drift, off-road, crashes & tumble animation | |
| **M7** | Traffic | Traffic cars with lane AI, overtaking, collisions | 🟡 3 cars in lanes, respawn ahead, bumps, palm crashes with spin-out; lane changes to do |
| **M8** | Game structure | Timer, checkpoints, 15 stages, branching forks, HUD, goal scenes | 🟡 15 stages in 5 rows, real road forks (the road splits in two), 5 themes, checkpoints with time bonus, GOAL; goal scenes to do |
| **M9** | Audio | IM2 PT3 player, 3 radio tunes, engine note, SFX, radio-select screen | 🟡 engine note (follows speed and gear), gravel noise, bump / crash noise; music to do |
| **M10** | Front end | Loading screen, title, attract/demo mode, options, redefine keys, high scores | 🟡 title screen with high score, title/demo cycle, 5 goal screens with time bonus; loading screen, options, key redefinition to do |
| **M11** | Polish & release | Optimisation pass, border split, playtesting/difficulty tuning, `.tap`/`.tzx` release | 🟡 speed pass (overlapped pipeline: 15.6 fps average over a whole game), `.tap` release with loading screen and compressed banks (tested in zxsim with ROM-routine emulation; still to test on a real ROM / hardware) |

**Risk-first ordering:** M1 is the make-or-break milestone — if the road plus a
representative sprite load can't hit 25 fps, we fall back to (a) narrower play area
(e.g. 24-column road window), (b) 2-line road resolution near the horizon, or
(c) 16.7 fps — decided before any content work starts.

---

## 8. Key risks

| Risk | Mitigation |
|---|---|
| Too slow at 25 fps | Profile from M1; change-skipping on road lines; narrower window fallback |
| Sprite memory (sizes × objects × masks) | ZX0 per-stage sets in banks 3/4; cap sizes per object; mirror symmetric objects at runtime |
| Paging vs. double buffer | Per-stage sprite cache in always-visible RAM (§2.1) |
| Attribute clash | Row-palette design (§2.2), designed in from day one |
| Contended memory slows buffer A drawing | Measure; schedule heaviest fills during border time; balance work between buffers |
| 128K model timing differences (+2/+2A/+3) | Avoid timing-critical effects in core loop; border split optional and model-detected |

---

## 9. Immediate next steps

1. Performance pass (§3.6 backlog): 15-16 fps on curvy stages with traffic.
2. Loading screen and a .tap with a BASIC loader; options / key redefinition.
3. M9: music and a radio-select screen (last).
