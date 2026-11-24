# Speed Run artwork: a handover

This note is for whoever updates the game's graphics or its packaging art.
It says where every picture comes from, which file to change, the rules the
Spectrum and the game impose, how much memory each kind of graphic has left,
and how to check the result.

The current artwork uses the Riviera Spider design. Each of the fifteen route
entries has its own palette and panorama. The five regions supply the roadside
sprite families. The figures below describe the Riviera build.

---

## 1. The three things to know first

1. **Almost all the art is drawn by Python code, not by hand.** The scenery,
   traffic, car, crew, font, horizons, title and goal screens, cover, inlay
   and leaflet are all drawn by scripts in `tools/`. The PNGs in
   `assets/gfx/` are mostly **previews that the build overwrites**: editing
   them does nothing. Only a few files are real inputs (table below).
   Original artwork only: the game borrows nothing from other games.
2. **The Spectrum's colour rules apply everywhere in the game:** 15 colours
   (8 hues × normal/bright, black the same in both), and **two colours per
   8 × 8 cell**, both normal or both bright (black goes with either). Moving
   graphics (scenery, traffic) have no colour of their own at all: they are
   1-bit silhouettes in the ink colour of the cells they cross (black over
   grass, sky and kerbs, white over the road), except that each object type has
   an ink of its own in the plain grass and road cells it covers (`PLAN.md` 2.2;
   `make ZX_OBJINK=0` turns it off). The colours are `OBJ_INKS` in
   `tools/make_stages.py`; an ink the same as the ground's is drawn black.
3. **Memory is tight.** The car, traffic, font and the resident code share
   bank 5; about 630 bytes are free there now that the crew's close-ups are
   gone. Each region also has its own scenery budget in section 10.
   The pack builder and assembler check these limits.

## 2. Building and looking at the art

The build runs in MSYS2 on Windows (see `CLAUDE.md`) or any Unix shell:

```
make              # the game (build/zxracer.sna) and all generated art data; rewrites the previews
make test         # five tests; carcheck checks the player's car on screen against car.png
make run-tape     # the release tape in Fuse;  make run-realtape: in ZEsarUX at real tape speed
make video        # build/gameplay.mp4: the autopilot plays (with sound)
make release      # release/: tapes, inlays (with fresh screenshots)
make cover        # the cover and spine lettering   (needs Node + Playwright)
make leaflet      # the route map leaflet                             (needs Node + Playwright)
```

After `make`, look at the previews: `assets/gfx/screen_*.png` (title and goal
screens), `assets/gfx/<type>.png` (each scenery master), `horizon_<theme>.png`,
`crew.png`. The tape build also writes `loading_preview.png`. They are committed with the code, so `git
diff` shows the effect of a change. Commit previews together with the change
that made them.

For a screenshot of the game at any moment without an emulator, use zxsim
(`docs/zxsim.md`), for example the autopilot build at frame 3000:
`build/zxsim build/video.sna -n 3001 -k 250:Q -k 256:none -s 3000:shot.ppm`
(on Windows `build/zxsim.exe`). The picture is 320 × 288: the screen sits at
x 32-287, y 48-239.

## 3. Inventory: where each picture comes from

| Art | Source of truth (edit this) | Built by | Generated / preview files | In the game |
|---|---|---|---|---|
| Player car (7 frames) | `tools/make_car.py` → `assets/gfx/car.png` | `make_car.py` (run by make), then `png2zx.py` | `build/car_data.asm` | bank 5, `src/car.asm`, `src/tyres.asm` |
| Crew close-ups (crash) | `tools/make_crew.py` | `make_crew.py` (no longer run by `make`) | `assets/gfx/crew.png`, `build/crew_data.asm` | not in the game: taken out of the Spectrum for room (the Einstein never had them) |
| HUD lettering and numerals | `tools/make_font.py` and `round_art.dash_header` | `make_font.py` and `make_stages.py` | `build/font_data.asm`, `build/stages.asm` | bank 5 font and stage overlay header |
| Scenery, road signs | `tools/make_scenery.py` (one function per type) | `make_stages.py` calls `make_scenery.emit_type` | `assets/gfx/<type>.png`, packs in `build/packs.asm` | theme cache (bank 7) |
| Traffic (car, van, lorry) | `tools/make_scenery.py` (`car`, `van`, `truck`) | `make_stages.py` | `assets/gfx/traffic.png`, `van.png`, `truck.png` | bank 5 (resident) |
| Stage colours | `assets/stages.yaml` (region palette plus stage overrides) | `make_stages.py` | stage art packs | every road, sky and HUD row |
| Horizon backdrops | `assets/stages.yaml` (region, stage seed and vista) + `tools/round_art.py` | `make_stages.py` | `assets/gfx/horizon_<theme>.png` | theme cache |
| Title and 5 goal screens | `tools/make_screens.py` | `make_stages.py` calls `make_screens.build` | `assets/gfx/screen_*.png` | compressed in the pack banks |
| Starting-light lamp | `LampGlyph` in `src/holes.asm` (16 × 16, hex) | assembler | - | bank 2 |
| Tunnel mouth, finish gantry | colour constants in `src/tunnel.asm`, `src/tunnelb2.asm` | assembler | - | attributes only |
| Front-end text screens (high scores, route map, initials, options) | layout in `src/frontend.asm`, drawn with the HUD font; the route map's box colours are `MAP_PAPER` in `tools/make_stages.py` | assembler, `make_stages.py` | - | front-end overlay |
| Loading screen | `tools/make_screens.py` (loading version of the title) | `make tap` | `assets/gfx/loading_preview.png` | the tape |
| Cover | `tools/make_cover.py` → **`release/cover.png`** | `make cover` (Chromium) | `build/cover.svg` | inlay front |
| Spine lettering | `tools/make_cover.py` → **`assets/gfx/spine.png`** | `make cover` (Chromium) | `build/spine.svg` | inlay spine |
| Cassette inlay | `tools/make_inlay.py` + cover + spine + 4 screenshots | `make release` | `release/inlay_outside.png`, `inlay_inside.png` | print |
| Route map leaflet | `tools/make_leaflet.py` | `make leaflet` (Chromium) | `release/route_map.png` | print |

Files in **bold** are inputs that the normal build reads as they are: you can
replace them with hand-made art (sections 8 and 9). `car.png` is also an
input, but it is itself made by `make_car.py`; see section 4.

Leftovers to ignore: `tools/make_horizon.py` and `assets/gfx/horizon.png`
(the first horizon, no longer used), and `make_scenery.py`'s own `main()`
(stale: only `emit_type` and `type_bytes` are used).

## 4. The player's car

`make` runs `tools/make_car.py` to draw the seven frames in `assets/gfx/car.png`,
then `tools/png2zx.py` converts the sheet into the resident car data.

**Layout:** 7 frames side by side, each 64 × 32 pixels (8 × 4 cells), in this
order, which the code relies on (`CarFrame` in `src/car.asm`):

| Frame | | Frame | |
|---|---|---|---|
| 0 | straight | 3, 4 | drifting left, smoke puffs A and B |
| 1 | steering left | 5, 6 | drifting right, smoke puffs A and B |
| 2 | steering right | | |

The car always sits in the same block, columns 12-19 and rows 20-23 of the
screen, and is redrawn whole (no masking), so it never clashes.

**Colour rules:**
- Spectrum colours only, exactly: normal = components of 0 or 215, bright =
  0 or 255 (e.g. bright red `(255, 0, 0)`). Anything else stops `png2zx` with
  "non-Spectrum colour". At most two colours per cell ("three colours"), not
  bright and normal together ("bright and normal colours"). With black in a
  cell, black is the paper.
- **Top cell row (y 0-7) is the open cockpit:** only its *ink* colours are
  used. The paper is whatever lies under the car (grass, kerb or road), and
  where the ink matches that paper the game makes it black. So draw the
  crew's heads and the windscreen pillars there in one colour per cell, on
  black.
- Rows 1-3 (y 8-31) are drawn exactly as painted.

**Memory:** the converter stores each frame as a top part (rows 0-2) and a
bottom part (row 3), and stores identical parts once. Today frames 3 and 4
share their top part, and so do 5 and 6 (the smoke puffs differ only in the
bottom row). Bank 5 has **27 bytes** free, so:
- a change that keeps every frame the same size is fine;
- but if the two smoke frames' top rows stop being identical, that's 216
  bytes more and the build fails. Put any smoke animation in the bottom row.

**The rolling tyres** (`src/tyres.asm`) animate the tread on the rear tyres
by copying pixel rows of `car.png` itself. If you redraw the tyres, in
frames 0-2:
- the tyres are pixel rows 26-31 (rows 2-7 of the bottom cell row);
- row 27 is the **tread** row, row 28 a **plain** row, and rows 26, 29, 30
  and 31 must be plain too (the same as row 28 at the tyres);
- the tread may only use x 0-15 and x 48-63 (the car's first and last two
  bytes). The exhaust pipes and anything else in rows 26-31 must stay in
  x 16-47.

If the tyres no longer match these rules, the animation stops; nothing breaks.
`tests/carcheck.py` checks the car on screen against `car.png` (with the
tread in each of its three positions).

The title and goal screens also draw frame 0 of `car.png`.

## 5. Crew close-ups and the font

- **Crew** (`tools/make_crew.py`): her and him, 48 × 48 pixels (6 × 6 cells)
  each, once shown either side of the message line after a crash. Drawn as
  code; two colours per cell. No longer in the game: they (and the crew's
  lines) were taken out to make room for the tunnels' mouths. The tool
  and `assets/gfx/crew.png` are kept; `make build/crew_data.asm` still builds
  the data.
- **Font** (`tools/make_font.py`): the `G` table, 5 × 7 glyphs written as
  `#` and `.` strings, in 8 × 8 cells, for ASCII 32-90: space, digits,
  punctuation and **capitals only** (no lower case anywhere in the game).
  The seven-pixel instrument numerals come from `DASH_DIGITS`. The timer doubles those numerals. The same glyphs make the title
  logo and the inlay's lettering, so a font change shows there too. Fixed
  size in bank 5: adding characters needs memory there.

## 6. Scenery and traffic sprites

**How they work:** each type is a function in `tools/make_scenery.py` that
draws a large master image: mode `L`, the object white (255) on black (0),
standing on the bottom edge. The build scales the master to a ladder of
heights (`SIZES = 64, 48, 36, 27, 20, 15, 11, 8, 6` pixels, times the
type's factor; the 64 is never drawn) and stores 1-8 pre-shifted copies of
each size (the type's `SHIFTS_*` list). Tall roadside objects map to larger entries at a distance through `size_indices()`. A pixel is set if at least about a
third of it is covered (`scaled()`: threshold 80 of 255), so a line thinner
than a third of an output pixel disappears. For example, a 256-pixel master
drawn 6 pixels high needs lines about 14 master pixels thick to show.
`assets/gfx/<type>.png` is a preview of the master.

**On screen:**
- every sprite is a silhouette in the ink colour of the cells it crosses:
  black over grass, sky and kerbs, white over the road (traffic shows as
  white shapes). It is XORed onto the back buffer, so where it overlaps a
  kerb's road pixels it shows as a gap;
- it stands on its ground line and is centred on its position;
- there are no colours or masks: detail can only be shapes and holes.

**`TYPES`** (end of `make_scenery.py`) maps each name to
`(function, size factor, shift list)`. The factor scales the object against
the ladder: a palm is 1.0, a bush 0.35. Memory grows with the factor and
with the master's width-to-height ratio.

**Which types each theme uses:** `types` in `assets/stages.yaml`, four per
theme, in the order `[big, small, landmark, small2]`:
- *big* lines the road;
- *landmark* replaces 18% of the big ones;
- *small* and *small2* (40%) fill in.

Every theme pack also holds the curve signs (`sign_r`, `sign_l`) and the
fork sign (`fork`), and the Alpine pack the tunnel sign (`sign_tunnel`).

**Traffic** (`traffic`, `van`, `truck`) sits in bank 5 all the time.

**To redraw a type:** edit its function, run `make`, look at the preview and
in the game. **To use a hand-drawn master** instead, make the function
return `Image.open("assets/gfx/my_palm.png").convert("L")` (white object on
black, standing on the bottom edge, roughly 128-256 pixels high), and keep that
file out of the names the build writes (`<type>.png`).

**To add a type:** write a function, add it to `TYPES`, use it in a theme's
`types`. The game numbers types by their slot, so no assembly changes are
needed for scenery types.

**Memory:** see section 10. A theme's four types plus the shared signs must
fit its theme cache. Alpine has 206 bytes spare and Sunset 280 bytes. Traffic shares the 27 remaining resident bytes. `make_scenery.type_bytes(name)` gives a type's
cost.

## 7. Theme colours and horizons

**Colours** are Spectrum attribute bytes in `assets/stages.yaml`, under each
theme's `palette`. An attribute byte is `0b0BPPPIII`: B bright, PPP paper,
III ink; the colours are 0 black, 1 blue, 2 red, 3 magenta, 4 green,
5 cyan, 6 yellow, 7 white.

| Field | What it colours |
|---|---|
| `sky` | the sky rows (paper; scenery passing in front is black) |
| `pano` | the horizon backdrop: its ink is the mountains, its paper the sky behind them |
| `hud` | the HUD at the top of the screen (rows 0-2: score, stage, speed) |
| `time` | the big timer's cells (rows 1-2, columns 14-17) |
| `grass_l`, `grass_d` | the light and dark grass bands, alternating down the road |
| `kerb_l`, `kerb_d` | the kerb cells in the light and dark bands |
| `road` | road cells; the ink is the centre line |

Rules:
- the kerb attributes must differ from the grass and road ones (the build
  checks: the fork drawing finds kerb cells by their colour);
- scenery and traffic take the ink colour of the cells they cross: keep
  the ink of `sky`, the grass and the kerbs black (as now), or objects change
  colour from row to row. The road's ink (white) is also the traffic's
  colour.

Each stage can override individual fields of its theme palette under `rows`.
The last five route entries also supply the palettes and locations for the
five ending postcards.

**Horizons and sky.** `tools/round_art.py` draws a 256 × 16 scrolling band
and a 160 × 32 static sky panel. The region selects `harbour`, `mesas`,
`peaks`, `hills` or `skyline`. Each stage seed varies the composition.
The optional `vista` adds a feature such as a liner, gondola or rock arch.
The stage overlay unpacks the art, makes a second panorama shifted by four
pixels, and draws the sky panel at (48, 48). This leaves room for the message,
starting lamps (and once the crash portraits). Tunnel ceiling attributes
conceal it.

**Route screen:** the front end's route map (`src/frontend.asm`) colours each stage's box by its
theme, `MAP_PAPER` in `make_stages.py` (a paper colour number per theme).

## 8. Title, goal and loading screens

**Title and goal screens** (`tools/make_screens.py`, `title_screen()` and
`goal_screen()`): drawn in full colour, then converted to a Spectrum screen
by `to_zx()`. Per cell, the two most common colours win and other pixels
take the nearer of the two, so paint with Spectrum colours (`rgb()`) in
mind. They're built from the game's own parts: the font enlarged and
slanted for the logo (`logo_mask`), scenery masters as silhouettes, the
theme's horizon and colours, and the car (`car_frame()`, frame 0 of
`car.png`).

Rows the game writes into, which must stay clear:

| Screen | Rows | What the game prints there |
|---|---|---|
| Title | 21, 23 | the high score's digits (row 21 from column 17, after the picture's own HI-SCORE), the keys (row 23); row 22's PRESS ANY KEY is part of the picture |
| Goal | 18, 19, 21, 22, 23 | congratulations, the ending's name (`ENDINGS`), score, bonus, PRESS ANY KEY |

Their attributes are set by the `over` lists in each function. Each screen
is compressed and stored with the
stage packs. Busier pictures compress worse; section 10 has the room.

**Loading screen** (`assets/gfx/loading.scr`, 6,912 bytes, a standard
Spectrum `.scr`): shown while the tape loads. The tape loader fills
**row 23** with a bright yellow progress bar, so leave that row blank except
for the word LOADING. The tape build runs `tools/make_screens.py --loading`
when the title artwork or its inputs change. `make_loading.py` can also
convert a separate 4:3 picture by hand.

## 9. Packaging: cover, spine, inlay, leaflet

- **Cover** `release/cover.png` (1300 × 2000) and **spine lettering**
  `assets/gfx/spine.png` (1200 × 150): drawn by `tools/make_cover.py` as an
  SVG and rendered by Chromium through Node and Playwright (`make cover`).
  The drawing is code: hand-drawn-style lines, hatching, washes, and
  lettering built from letter skeletons (no fonts). It has three layouts:
  `portrait` (the cover), `wide` (1600 × 1200, for the loading screen) and
  `spine`. A painted cover can simply replace `release/cover.png` (keep the
  1300:2000 shape; the inlay crops the sides a little) and the spine
  `assets/gfx/spine.png`.
- **Inlay** (`tools/make_inlay.py`, `make release`): a J-card at 300 dpi,
  101.6 mm tall.
  - Outside: back flap 15 mm, spine 12.7 mm, front 65 mm.
  - Inside: four screenshots and how to play.
  - The screenshots are taken from an autopilot run at the frames in
    `SHOTS` in the `Makefile`.
- **Route map leaflet** (`tools/make_leaflet.py`, `make leaflet`): the stage
  pyramid as a printed 80s leaflet, 1748 × 2480; Chromium again.
- `release/README.txt`: the text that goes with the tapes.

**Chromium on this Windows machine is not set up** (Node is installed, but
not Playwright, and MSYS2 doesn't see Windows' Node). Until it is, either
use a machine that has it or replace the PNGs by hand. Setting it up probably
takes `npm install -g playwright`, `npx playwright install chromium`, Node on
MSYS2's PATH and `NODE_PATH` pointing at the global modules (untested).

## 10. Memory

`make` fails with a clear message when something doesn't fit:
- `theme X: N bytes, the cache holds M`;
- `stage packs do not fit in the free banks`;
- an `ASSERT` in `src/main.asm` (bank 5: `ScnEnd <= TRACK_CACHE`).

| Area | Holds | Free |
|---|---|---|
| Bank 5 (resident) | car, font, traffic sprites, code | **about 630 bytes** |
| Theme data (8,320 bytes before the stage panorama) | 4 scenery types, signs, tune and name | coast 686, desert 1,260, alpine 206, country 355, sunset 280 |
| Pack banks 0, 1, 3, 4, 6 | all theme and track packs, title and goal screens, the overlays | depends on compressed art sizes. See the bank totals printed by `make` |

Ways to make room for art:
- **Fewer shifts:** fewer pre-shifted copies for a type (`SHIFTS_*`), at the
  cost of coarser sideways movement.
- **A smaller factor or a narrower master:** a narrower object is cheaper
  at every size.
- **Swap types:** a theme can drop an expensive type for a cheaper one.

A sprite's cost is about width × height × copies, summed over the eight
sizes.

## 11. Checking a change

1. `make`: everything still fits.
2. Look at the previews in `assets/gfx/` (and `git diff` them).
3. `make test`. `carcheck` fails if the car on screen doesn't match
   `car.png`, which is expected only if the car's drawing code changed
   without `car.png` being regenerated.
4. See it move: `make run-tape` (Fuse), or `make video` for a recording.
   (`make run` loads the snapshot, which Fuse runs as a Pentagon: fine for
   a look, not for timing.)
5. `make release` before committing, so the tapes and inlay match, and
   commit previews and release files with the change.

`tests/rendercheck.py` is a pixel-exact before/after check for speed work.
Any art change makes it differ, by design, so don't use it for art changes.
