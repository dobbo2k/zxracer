# ZX Racer — Development Plan

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
$5B00-$69FF  Bank 5: resident graphics (traffic sprite, font, player car) and
             the title / goal screen code
$7800-$7FFF  Bank 5: TRACK CACHE: the current stage's segments and objects
             (also the bounce buffer while a theme is loaded)
$8000-$BFFF  Bank 2: code, stage table, lookup tables, unrolled chains (hill
             tables in the gaps between them), IM2, stack
$C000-$DAFF  Bank 7: screen buffer B
$DB00-$FFFF  Bank 7: THEME CACHE: the current theme's sprites (scenery types,
             curve and fork signs), mountain backdrop, palette, name
```

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
- `src/screens.asm` (bank 5, between the resident graphics and the 2 KB track
  cache) unpacks a picture into screen A while B is on show, prints the high
  score / results with the HUD font and runs the screen's own loop; the game's
  sound is muted and the screens beep themselves.
- Flow: boot → title (8 s or a key) → demo (≈25 s, continuing where it left off)
  → title … A game ends with the car rolling to a stop, then the goal screen for
  the last-row stage reached (time bonus counted in), then the title with the
  updated high score.

### 3.2d Tape release (as built)

`make tap` builds `build/zxracer.tap` from a release snapshot (`-DRELEASE`, no timing
bars) with `tools/make_tap.py`:

1. BASIC `ZX RACER` (autostart 10): `BORDER 0: PAPER 0: INK 7: CLEAR 32767`,
   `LOAD "" CODE`, `LET e=USR 48640`, `IF e=1 THEN PRINT "128K ONLY"`,
   `IF e>1 THEN PRINT "TAPE ERROR, BLOCK ";e-10`.
2. CODE `loader` at `$BE00` (`src/loader.asm`): checks that banks 1 and 3 differ
   (else returns to BASIC, which prints the message), then reads the rest of the
   tape with **its own loading routine** - standard ROM-format blocks at the
   normal speed, but no ROM calls and interrupts off throughout, so it does not
   matter which ROM is paged (128K, +2, +2A, +3). (A first version called the
   ROM's LD-BYTES at `$0556`; it crashed back to BASIC in an emulator, most likely
   because the ROM paged in during `USR` was not the 48K BASIC ROM.) The blocks:
   the loading screen (raw, so it appears line by line), then the pack banks 0, 1,
   3, 4, 6 (each loaded to `$8000` and unpacked to `$C000` in its bank), bank 2
   (loaded into bank 7, unpacked to `$8000`) and the resident part of bank 5
   (likewise, to `$5B00`), and it jumps to the game. LZ compression (the screens'
   format) saves 30%: 67 KB, about 6½ minutes. On a 48K (returns 1) or a tape error
   (returns 10 + the block number) it goes back to BASIC - its stack, `BANK_M`
   paging and interrupts restored; nothing has been loaded over BASIC's memory
   before the last block - and BASIC says which.

`tests/tapecheck.py` boots the tape in zxsim (`-T`: does what `LOAD "" CODE: RANDOMIZE
USR` would, then plays the tape into the EAR input - no ROM image needed) and checks
that the game starts and shows its title, also with the tape 8% slow or fast and
with random bytes in memory. Not yet done: the BASIC
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
  frame the bend adds `−curvature × speed / 8`, steering ±64, and grip takes
  1/16 of it away, so it settles where the old direct push did (2 × curvature ×
  speed outwards; 4 px a frame when steering) but over about a third of a second,
  and drift carries on after a bend. Past the grip limit (|curvature × speed| >
  200, e.g. curvature 11 at top speed) the car slides: an extra outward push of a
  quarter of the excess, half the steering and grip, a tyre squeal, and holding
  the throttle no longer adds speed (it scrubs off until the tyres grip again).
- **Crew** *(as built)*: the car sprite's open cockpit row shows his head
  (white ink) and hers (yellow) over whatever lies under the car (ink turns
  black where it matches); his striped shirt and her hair sit on the rear deck.
  A crash (160 frames) shows their 48×48 close-ups (`tools/make_crew.py`) either
  side of the message line: one of 8 pairs of lines, hers then his reply.
- **Collisions:** roadside object → crash & tumble, restart from road centre;
  traffic → bump, spin or crash depending on speed and angle.
- **Traffic:** trucks, vans, small cars, bikes in lanes with simple lane-change AI;
  density rises in later stages.
- **Stages:** 15 original stages (coast, desert, alpine pass, forest, city night,
  canyon, lakeside, wheat fields, etc.) arranged as a 5-row branching pyramid; choose
  left/right at each fork. 5 distinct goal scenes.
- **Timer:** checkpoint extends time; run out = game over. Score from distance/speed,
  time bonus at goal.
- **Radio:** before the race, choose one of 3 original tunes (or engine-only).
- **High-score table** with initials entry; route map shown on results screen.

---

## 5. Audio

- AY-3-8912 at 50 Hz from the IM2 handler; Vortex Tracker II (PT3) format and an
  open-source PT3 player, so music can be composed in a tracker.
- Channel allocation in game: A+B music, C shared between engine note and SFX
  (SFX pre-empt engine briefly). Engine pitch follows RPM, noise mixed on gravel.
- 3 original in-game tunes, title tune, goal/ending tune, high-score jingle.
- 48K beeper is out of scope (128K only).

---

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
| **M9** | Audio | IM2 PT3 player, 3 radio tunes, engine note, SFX, radio-select screen | 🟡 engine note, gravel noise, tyre squeal; music to do |
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
