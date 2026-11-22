# Speed Run on the Tatung Einstein: artwork handover

This note is for whoever redoes the artwork for the Einstein port. It covers:
- where each thing on the Einstein's screen comes from;
- what the Einstein's video chip can and can't show;
- what you can change today without touching code;
- what needs a programmer first;
- the limits (patterns, sprites, memory, frame rate);
- how to see your work in the emulator.

Read `docs/artwork.md` first: it describes the game's art as made for the
ZX Spectrum, and almost all of it is shared. `docs/port_einstein.md`
describes the port itself.

---

## 1. Three things to know first

1. **The Einstein shows the Spectrum's art, converted on the fly.** The
   port runs the Spectrum's own drawing code into a hidden Spectrum-format
   screen, then copies what changed to the Einstein's video chip (a TMS9129)
   every frame. So the scenery, car, font, HUD, sky panel, horizons, title
   and goal screens are the Spectrum's, with each Spectrum colour swapped
   for a TMS colour. Only the road (kerbs, centre line, grass bands) is
   drawn by the Einstein's own code, from the stage palettes.
2. **Shared art changes both machines.** The Spectrum version is released,
   and its build must stay byte-identical to `release/` unless a change is
   meant for it too. To change something on the Einstein only, there has
   to be an Einstein-only hook. Today there is one: `einstein_palette` in
   `assets/stages.yaml` (section 5). Anything else Einstein-only needs a
   hook adding first (section 6).
3. **The TMS9129's colours are not the Spectrum's.** It has 15 fixed
   colours, with no bright and normal pairs. Cyan and bright cyan come out
   the same, and so do magenta and bright magenta. Several hues shift
   noticeably (section 3). Judge the art on the Einstein's screen, not the
   Spectrum's.

## 2. What the Einstein's screen is made of

The picture is 256 × 192 pixels, 32 × 24 cells of 8 × 8, like the Spectrum.
The border is black.

| Rows | What | Comes from | Notes |
|---|---|---|---|
| 0-2 | HUD: score, stage, timer, speed | The Spectrum's HUD drawing, mirrored cell by cell | Colours from the palette's `hud` and `time` |
| 3-9 | Sky, clouds (the 160 × 32 sky panel), the message line, starting lights | Mirrored the same way | One pattern per cell: any picture fits |
| 10-11 | Horizon backdrop (the scrolling panorama) | The stage's 256 × 16 panorama, sent once a stage, in 2 copies 4 pixels apart | Scrolls by changing which patterns the cells use: 4-pixel steps |
| 12-23 | Road, grass, kerbs | The Einstein's own road drawing, from the stage palette | Section 4 |
| 12-23 | Centre line | 12 hardware sprites, one a road row | Colour: the road's ink. Hidden under the car, scenery, traffic and tunnel mouths |
| any | Scenery and traffic | The Spectrum's sprite drawing (1-bit silhouettes), cut into the cells under them | Black over grass, sky and kerbs; the road's ink over the road |
| 20-23 | The player's car (columns 12-19) | The Spectrum's car frames, mirrored as 32 patterns | Its colours as painted, two per cell; the cockpit row shows what's under the car |
| 12-23 | Tunnel mouths, the finish gantry | The Spectrum's attribute painting, turned into solid cells | Colour constants in `src/tunnel.asm`, `src/tunnelb2.asm` |
| whole screen | Title, high scores, options, route map, goal screens | The Spectrum's front end, drawn into a Spectrum screen and shown as a full bitmap | Two colours per cell, as on the Spectrum |

Not on the Einstein:
- **The crew's crash close-ups.** They were left out of the Einstein build
  for room. See section 6.
- **A loading screen.** The game loads from disc: XtalDOS's prompt, then
  the title.

## 3. The TMS9129's colours

### The 15 colours

These are the emulator's values (Albert, which uses the standard TMS9918A
palette). A real PAL Einstein on a real television will differ somewhat:
check on hardware before finalising.

| TMS | Name | RGB | Used for |
|---|---|---|---|
| 1 | black | `#000000` | Spectrum black |
| 2 | medium green | `#21C842` | **unused** |
| 3 | light green | `#5EDC78` | Spectrum bright green |
| 4 | dark blue | `#5455ED` | Spectrum blue |
| 5 | light blue | `#7D76FC` | Spectrum bright blue |
| 6 | dark red | `#D4524D` | Spectrum red |
| 7 | cyan | `#42EBF5` | Spectrum cyan **and** bright cyan |
| 8 | medium red | `#FC5554` | Spectrum bright red |
| 9 | light red | `#FF7978` | **unused** |
| 10 | dark yellow | `#D4C154` | Spectrum yellow |
| 11 | light yellow | `#E6CE80` | Spectrum bright yellow |
| 12 | dark green | `#21B03B` | Spectrum green |
| 13 | magenta | `#C95BBA` | Spectrum magenta **and** bright magenta |
| 14 | grey | `#CCCCCC` | Spectrum white |
| 15 | white | `#FFFFFF` | Spectrum bright white |

(0 is transparent: it shows the black border colour.)

The mapping is the table `SpecTms` in `src/einstein/vdp.asm`. Things it
means for the art:
- **No two shades of cyan or magenta.** Two things told apart only by
  brightness in those hues (sky and ground, light and dark bands) look the
  same. Stage palettes avoid that through `einstein_palette`.
- **Spectrum white is grey.** Only bright white is white.
- **The blues are lighter and more violet** than the Spectrum's. "Dark
  blue" is a mid blue, and light blue is lavender.
- **Spectrum yellow is mustard** (dark yellow). Bright yellow is a pale
  sand colour, not a lemon yellow.
- **Two colours are never used:** medium green and light red. A redo could
  use them, but only through Einstein-only art (section 6), since the
  Spectrum has no colours that map to them.

### Colour per cell, colour per line

The TMS9129's mode (Graphics II) allows **two colours for every 8-pixel
line of a cell**: 8 colour pairs per cell, where the Spectrum has one. The
port doesn't use that yet: everything it shows is converted from Spectrum
art with one pair per cell. A redo that wants per-line colour (sky
gradients, a more colourful car or title) needs Einstein-only data and code
(section 6).

## 4. The road, kerbs and centre line

These are the Einstein's own drawing, not the Spectrum's.

- **Colours** come from the stage palette (`assets/stages.yaml`, plus
  `einstein_palette`), as on the Spectrum: grass light and dark, kerb light
  and dark, road paper and ink. Section 5 lists what each region shows
  today.
- **Kerb edges** are ready-made patterns: 7 left edges and 7 right, in the
  light and the dark kerb. Each edge is upright within its 8-line row, so
  the road's edge climbs in 8-line steps. They're made at each stage start
  from the palette (`EinStaticInit` in `src/einstein/roadgfx.asm`), so a
  palette change recolours them; their shapes are fixed. The outer edge
  of the kerb (kerb against grass) is whole cells. In tunnels and on the
  fork's rows, the road is still drawn the exact way (2-line steps).
- **The centre line** is drawn with hardware sprites, single-coloured, in
  the road's ink (normally white). Its width and position follow the
  Spectrum's road tables, in 4-line steps.
- **Tunnels:** walls, kerbs and lamps use the fixed tunnel colours
  (`TunWall`, `TunKerbs`, `TUN_LAMP` in `src/holes.asm`) and the ceiling
  `TunSky`. These are shared with the Spectrum.

## 5. What you can change today without code

### 5.1 Einstein-only palettes

`assets/stages.yaml` takes an `einstein_palette` on any theme or any stage.
It overrides individual palette fields on the Einstein only.
`tools/make_einstein.py` applies it; the Spectrum's tools ignore it. The
fields are the same as `palette`'s (see `docs/artwork.md` section 7) and
are written as Spectrum attribute bytes: `0b0BPPPIII` (bright, paper, ink).
So you pick TMS colours through the table in section 3: for example,
paper 1 (blue) with bright clear is dark blue, `#5455ED`.

Example (already in the file):

```yaml
  sunset:
    palette: {...}
    einstein_palette: {grass_d: 0x08}   # dark bands: dark blue, not the sky's magenta
...
    - {theme: coast, seed: 5, vista: beacon, palette: {...},
       einstein_palette: {grass_d: 0x38}}
```

Rules (the same as on the Spectrum):
- **Kerbs:** the kerb attributes must differ from the grass and road ones
  (the build checks).
- **Inks:** keep the ink of `sky`, the grass and the kerbs black. Scenery
  and traffic take the ink of the cells they cross.
- **Road ink:** the road's ink is the traffic's colour and the centre
  line's.

What each region shows today on the Einstein (theme palette plus Einstein
overrides; stages can override further):

| Region | Sky | Horizon (ink on paper) | Grass light / dark | Kerb light / dark | Road | HUD |
|---|---|---|---|---|---|---|
| coast | cyan | light blue on cyan | light yellow / dark yellow | white / medium red | black, line white | white on light blue |
| desert | cyan | medium red on cyan | light yellow / dark yellow | white / medium red | black, line white | black on light yellow |
| alpine | cyan | light blue on cyan | white / grey | medium red / light blue | black, line white | white on light blue |
| country | cyan | light green on cyan | light green / dark green | white / medium red | black, line white | black on dark green |
| sunset | magenta | black on magenta | magenta / dark blue | cyan / light blue | black, line white | grey on dark blue |

The stages that override their region's palette are rows 1-4 of `rows` in
`assets/stages.yaml`: desert (1, 1), beacon coast (2, 1), arch desert
(2, 2), mill country (3, 0), gondola alpine (3, 1), needles desert (3, 3),
lodge alpine (4, 0), manor country (4, 1), liner coast (4, 2), bridge
sunset (4, 3) and ruins desert (4, 4). Each needs looking at on the
Einstein.

The palette also colours the ending postcards for the last five route
entries. On the Einstein those pictures are built with the Einstein
palettes; their previews go to `build/einstein/screen_goal_*.png`.

### 5.2 Shared art

Everything else (scenery masters, traffic, the car, the font, horizons,
the sky panel, title and goal screens, starting lights) is the Spectrum's,
made as `docs/artwork.md` describes. Changing it changes the Spectrum
build too. That's fine if the change is meant for both. If it's for the
Einstein only, add a hook first (section 6).

## 6. Einstein-only art: what needs a programmer first

Hooks that would let the Einstein's art differ, roughly from least to most
work:

| Hook | What it allows | What it takes |
|---|---|---|
| Einstein title and goal screens | Pictures drawn for the TMS colours | `make_einstein.py dat` already calls `make_screens.build` itself. It needs a variant (or Einstein inputs) and its own previews. Same format: a Spectrum screen, two colours per cell |
| Einstein scenery per region | Different masters or types | `make_einstein.py gen` builds the stage packs from the YAML. An `einstein_types` key, or per-type master overrides, applied like `einstein_palette`. Same budgets as the Spectrum (section 7) |
| Einstein car | A car drawn for the TMS colours | A second `png2zx` output for the Einstein build. The car's data size must not grow (bank 5) |
| Crew close-ups back | The crash portraits | Their data is 648 bytes; the Einstein has 752 free where they'd go (bank 5). Include `src/crew.asm` in the Einstein build and mirror the two 6 × 6-cell portraits. It may just fit; the build's checks will say |
| Per-line colour | Two colours per pixel line in a cell: gradients, more colourful sprites and screens | New Einstein-only data formats and the code to send them. Possible for fixed things (title, sky panel, panorama, car), not for anything the Spectrum code draws each frame |
| Hardware sprites for colour | Single-colour 16 × 16 overlays at any pixel: coloured detail on the car, lamps, signs | 20 of the 32 sprites are free. The chip shows at most 4 on one line; the centre line uses up to 2 on each road line, so 2 more are free per line in rows 12-23 and 4 above. Each sprite has one colour |

Any of these must leave the Spectrum build unchanged: `make
build/speedrun.tap`, then `cmp` it with `release/`.

## 7. Limits

### Patterns

The TMS9129 has 256 patterns for each third of the screen (rows 0-7, 8-15,
16-23). This is how the port shares them out (section 5 of
`docs/port_einstein.md`):

| Third | Patterns |
|---|---|
| top (rows 0-7) | one per cell: the HUD and sky, mirrored |
| middle (rows 8-15) | 0-15 solid colours; 16-35 road slots (rows 12-15); 36-63 kerb edges; 64-127 rows 8-9 mirrored; 128-191 the panorama; 192-255 the panorama's cells under a silhouette |
| bottom (rows 16-23) | 0-15 solid colours; 16-191 road slots (rows 16-23, 22 each); 192-219 kerb edges; 220-223 free; 224-255 the player's car |

What it means for the art:
- **Sky and HUD (rows 0-9):** any picture fits, one pattern per cell.
- **Panorama:** must stay 256 × 16 (2 rows × 32 cells).
- **The car:** must stay 8 × 4 cells (32 patterns).
- **Scenery over the road:** the cells it covers use the row's slots. A
  very wide object near the car on a row already busy with traffic can run
  out (22 a near row, 5 a far one). The cells that don't get a slot show
  the road without the object.

### Sprites

32 hardware sprites, 16 × 16 pixels, one colour each, at most 4 on a pixel
line. The centre line uses 12, one per road row.

### Memory

| Area | Holds | Free |
|---|---|---|
| Theme data (per region) | 4 scenery types, signs, tune, name | The same as on the Spectrum (`docs/artwork.md` section 10): the packs are shared |
| Bank 5 ($5B00-$7FFF) | car, font, traffic sprites, code | 752 bytes (the Spectrum: 27) |
| Bank 2 ($8000-$BFFF) | game code, the Einstein's keys, disc, front end and centre line code | about 140 bytes |
| Below $4000 | the Einstein's own code | about 300 bytes |
| Einstein buffers ($DB00-$EBFF) | names, slots, sprite data | about 460 bytes |
| The disc | `SPEEDRUN.COM` (48,640 bytes), `STAGES.DAT` (79,232: packs, pictures, overlays) | about 66K |

The disc has room for Einstein-only pictures; RAM is what's tight.

### Frame rate

The Einstein shows a frame every 4 TV frames (12.5 fps) when the work fits,
otherwise every 5 or 6. About 8 frames in 10 make it today. The frames that
miss are the ones with **big objects near the car**: every cell a
silhouette covers costs time to cut out and send. So:
- keep near objects' silhouettes compact;
- avoid very wide masters (a wide sign or building near the road costs far
  more than a tall, thin palm);
- check a busy stretch with `fliphist` (section 8) after changing scenery.

Colours cost nothing: palettes and colour changes don't affect speed.

## 8. Seeing your work

In MSYS2 (see `CLAUDE.md` for the setup and `local.mk` for the paths):

```
make einstein          # build/einstein/speedrun.dsk
make run-einstein      # open it in Albert; type SPEEDRUN at the 0: prompt
make test-einstein     # boots it and checks it (attract mode, a game, sound)
```

The test harness (`build/einstein/speedrun_check.exe`, built by
`make test-einstein`) takes screenshots and recordings without the
emulator's window. For example, 600 frames into the attract demo:

```
build/einstein/speedrun_check.exe <MOS ROM> build/einstein/speedrun.dsk build/einstein/speedrun.sym \
    boot SPEEDRUN frames 600 shot shot.ppm record 500 clip
```

`record` writes `clip.rgb` (256 × 192, 24-bit, 50 frames a second) and
`clip.wav`. `ffmpeg -f rawvideo -pix_fmt rgb24 -s 256x192 -framerate 50.08
-i clip.rgb -i clip.wav clip.mp4` makes a video. The MOS ROM path is
`EINSTEIN_ROM` in the `Makefile`.

**To see a particular stage:** the attract demo only drives stage 1.
1. Assemble with `-DAUTOPLAY=1 -DFIRST_STAGE=n` (the stage's index, counting
   from 0 along the pyramid's rows; 3 is the first alpine stage). The demo
   driver then plays the game from that stage.
2. Patch `STAGES.DAT` and make a disc, as `docs/port_einstein.md` section 7
   describes.
3. Boot it, press a key at about frame 300, and record. The tunnel on stage
   3 comes at about TV frame 1,250.

Afterwards, `touch src/main.asm` so the next `make` rebuilds the normal
game.

**Busy stretches:** the harness's `fliphist N` prints how many frames took
4, 5 or 6 TV frames over N frames, and the costliest routines of each slow
one. Compare before and after a scenery change.

## 9. Checklist before handing back

1. `make` and `make einstein`: everything fits (the builds fail with a
   message when it doesn't).
2. `make test` and `make test-einstein` pass.
3. The Spectrum build: `make build/speedrun.tap` and `cmp` with `release/`.
   It must be identical unless you changed shared art on purpose. If you
   did, regenerate the previews and the release as `docs/artwork.md`
   section 11 describes.
4. Look at all 15 stages on the Einstein: the sky, the horizon, both grass
   bands, both kerbs, the HUD, a tunnel (alpine), the fork at the end of a
   stage, and the title and goal screens.
5. Check a busy stretch with `fliphist`.
6. Commit the YAML, tools and previews with the change.
