# Speed Run artwork on the Tatung Einstein

The Einstein disk uses native TMS9129 artwork throughout the race, title and five finish postcards. The Riviera Spider study in `docs/art-prototypes/einstein/` is the visual reference. The running game uses a different pattern layout so the road, scenery and traffic can move.

[Sunny Coast gameplay capture](einstein/sunny-coast-gameplay.png) · [All fifteen stages in Albert](einstein/route-gallery.png)

## The race screen

| Pixel rows | What the game draws | How it fits |
|---|---|---|
| 0–23 | Aqua instrument labels on black, score, stage, gold timer, speed and gear | The labels are generated once. The game updates the changing digits, low-time flash and gear text. |
| 24–79 | Layered clouds, sun and distant landscape | Each of the 224 cells has eight independent pattern and colour bytes. A moving object, message, starting lamp or tunnel wall can cover a cell. Cleared cells recover the original artwork. |
| 80–95 | Foreground panorama with boats, fields, rock formations or buildings | The 64 patterns scroll in eight-pixel steps. Cells under scenery get a separate composited pattern and colour plane. |
| 96–191 | Road, kerbs, terrain, signs, traffic and scenery | The road renderer uses sloping edges on near diagonals and reusable patterns on shallow edges. Two bottom-third patterns texture the verges. Moving objects use projected masks with upper, middle and lower inks for their shape and region. |
| 160–191 | The 64 × 32 open Spider | Seven poses cover straight driving, steering and two smoke frames per side. The road or verge shows through transparent runs. Two red sprite overlays pick out the four rear lamps. |

The display is 256 × 192. Graphics II allows any two of the fifteen opaque colours in each horizontal run of eight pixels. The art builder chooses those inks independently on each scanline. Interrupt-driven uploads still use the port’s vertical-blank budget and paced-write path. The twelve lane-marker sprites and two lamp sprites stay within the four-sprites-per-scanline limit.

## Editing a route

The fifteen routes and five regions are defined in `assets/stages.yaml`. The stage seed selects its native lighting and the arrangement of scenery. The optional `vista` names its near landmark. For example, the Alpine Pass branches feature a bridge, cable cars and a lodge, and the three Sunny Coast branches lead past the harbour, beacon and liner.

- **Landscape and lighting.** Edit `landscape()` and the `LIGHT` table in `tools/einstein_art.py`. An optional seven-entry `einstein_light` on a stage overrides the zenith, lower sky, sunlight, distant ridge, accent, near ridge and ground colours in that order. Each value is a TMS palette index from 1 to 15.
- **Road and kerbs.** The theme and stage `palette` entries supply their colours. An `einstein_palette` entry overrides the corresponding Spectrum attribute byte on this port. The native verge tile uses the resulting paper colour.
- **Vehicles and roadside objects.** The Spider, coastal buildings, clouds, palms and rival coupe are drawn in `tools/einstein_illustration.py`. The native sprite masters, steering poses, transparent runs and object inks are built in `tools/einstein_art.py`. Region packs retain the projected sizes and shift tables the game uses for collisions and rendering.
- **Title and finishes.** The postcard builder draws the scene above a writable panel. Score, time bonus, ending text and the blinking title prompt are still printed by the game. Text menus, route-map symbols and the font use the shared interface artwork.

| Index | Colour | Index | Colour | Index | Colour |
|---|---|---|---|---|---|
| 1 | Black | 6 | Dark red | 11 | Light yellow |
| 2 | Medium green | 7 | Cyan | 12 | Dark green |
| 3 | Light green | 8 | Medium red | 13 | Magenta |
| 4 | Dark blue | 9 | Light red | 14 | Grey |
| 5 | Light blue | 10 | Dark yellow | 15 | White |

## Storage and rendering

`tools/make_einstein.py` writes the Einstein assets to `build/einstein`. A route pack begins with nine palette bytes, followed by four LZ streams holding sky pixels, sky colours, panorama pixels and colours, and the object inks and verge tiles. Packs are read from `STAGES.DAT` at stage changes. The stage loader shares screen A with the landscape cache and reloads its overlay on its next entry. The live race needs no artwork reads from disk between stages.

Middle-third patterns 128–191 hold the panorama and 192–255 hold cells covered by an object. In the bottom third, 192–219 are kerb patterns, 220–221 are verge textures and 224–255 hold the car. Sprite patterns 0–47 hold the lane markers and pattern 48 supplies both pairs of tail lamps. The title and endings use a full bitmap layout while the front end is active.

## Building and checking

From PowerShell in the repository, run `.\make.cmd einstein` to build `build/einstein/speedrun.dsk`. Boot the disk in Albert or on the Einstein and enter `SPEEDRUN` at the XtalDOS prompt.

Run `.\make.cmd test-einstein` for the emulator checks. These exercise boot, driving, the clock, audio, VDP timing and every route’s native sky and panorama. The harness writes a captured frame for each route to `build/einstein/round_00.ppm` through `round_14.ppm`. To see a stage in motion, pass the harness its normal ROM, disk and symbol arguments followed by `boot SPEEDRUN stage 3 frames 500 shot alpine.ppm`. Stage indices are zero-based in route-pyramid order. `fliphist 500` measures the frame intervals.

The Spectrum asset workflow and release are described in `docs/artwork.md`. Emulator setup and disk format are in `docs/port_einstein.md`.
