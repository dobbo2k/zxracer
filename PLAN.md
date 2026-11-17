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

### 2.1 Memory map

```
$0000-$3FFF  ROM (48K BASIC ROM, unused after boot; IM2 vector table lives in RAM)
$4000-$5AFF  Bank 5 screen  (buffer A)
$5B00-$7FFF  Bank 5 low RAM: per-stage SPRITE CACHE (~9K) + interrupt vector table
$8000-$BFFF  Bank 2: engine code, line-address tables, road tables, stack
$C000-$FFFF  Paged: bank 7 (screen buffer B) or asset banks 0,1,3,4,6
```

| Bank | Use |
|---|---|
| 0 | Music: AY player + 3 tunes, SFX |
| 1 | Track data for all 15 stages (compressed), traffic tables |
| 3 | Scenery sprites set 1 (pre-scaled, masked, ZX0-compressed) |
| 4 | Scenery sprites set 2 + player car frames + crash animation |
| 6 | Front-end: title screen, loading-screen art, fonts, goal scenes |
| 7 | Shadow screen (buffer B) — the rest of the bank holds the horizon art |

**The paging problem:** when we draw into buffer B (bank 7 at `$C000`), no asset
bank is visible. Solution: on stage start, decompress that stage's sprite set into the
**sprite cache** in `$5B00-$7FFF` (bank 5) and spare space in bank 2/7, so every
graphic needed during play is reachable whichever buffer is being drawn. Drawing into
buffer A (`$4000`) is in contended memory — measured in M1 and compensated by doing
more of the heavy road fill while the beam is in the border.

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
   `x += dx` to bend the road; hills offset the per-line y mapping and move the horizon.
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

Optimisation backlog for M11 (by expected gain):
1. Sprites: about 32k on average, 63k at peak. Store per-line spans so that empty
   bytes are not XORed (palm trunks are 1-2 bytes wide).
2. Row overhead (~24k): fewer patched constants per row, inline the line loop.
3. Pass 1 (~25k on curves): accumulator-only steps for the even lines are still per line.
4. Horizon redraw (19k peak): split across frames or cut to 16 lines.

Border-colour timing bars (`PROFILE=1`) show each phase on screen; `make profile`
and `tools/hotspots.py` give exact T-state breakdowns from the emulator.

---

## 4. Gameplay

- **Car handling:** speed 0–290 km/h, LOW/HIGH gear (auto or manual option), engine
  RPM, acceleration curve, braking, off-road slowdown + grass shudder, centrifugal
  drift on curves (must steer into bends), skids with tyre squeal.
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
| **M2** | Curves & hills | Segment-based track, curves, hills, moving horizon; track compiler + 1 test stage | 🟡 curves, YAML track compiler and test loop done; hills to do |
| **M3** | Player car | Car with steering frames, no colour clash, basic steering/speed physics | ✅ car owns a fixed 8×4-cell block; centrifugal force; attract-mode driver |
| **M4** | Scenery | Pre-scaler pipeline, scaled sprites, hill clipping; palms/signs/rocks | 🟡 palms with XOR draw/erase; more object types and hills to do |
| **M5** | Horizon & palette | Pre-shifted parallax panorama + clouds, per-stage attribute palettes | 🟡 scrolling mountain band; clouds and per-stage palettes to do |
| **M6** | Physics & collisions | Gears, drift, off-road, crashes & tumble animation | |
| **M7** | Traffic | Traffic cars with lane AI, overtaking, collisions | |
| **M8** | Game structure | Timer, checkpoints, 15 stages, branching forks, HUD, goal scenes | 🟡 HUD, timer, lap bonus, score, game over, attract mode; stages and forks to do |
| **M9** | Audio | IM2 PT3 player, 3 radio tunes, engine note, SFX, radio-select screen | 🟡 engine note, gravel noise, tyre squeal; music to do |
| **M10** | Front end | Loading screen, title, attract/demo mode, options, redefine keys, high scores | |
| **M11** | Polish & release | Optimisation pass, border split, playtesting/difficulty tuning, `.tap`/`.tzx` release | |

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

1. M7: traffic cars (sprites on the road) and collisions with traffic and scenery
   (crash and recovery), which make it a game rather than a drive.
2. M4: more scenery types (signs, rocks, bushes) and per-stage variety.
3. M11 backlog items in §3.6, to get closer to 25 fps everywhere.
4. M9: music (PT3 player) with the engine moved to channel C.
