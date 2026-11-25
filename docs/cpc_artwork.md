# The Amstrad CPC's artwork

The CPC port draws its own art (`docs/port_cpc.md` 5.6, decided 24 November
2026): for Mode 0's pixels, twice as wide as tall, and the CPC's 27 colours,
16 pens at a time. The Spectrum's and the Einstein's pictures only say what
each thing is.

## Where it comes from

| File | What |
|---|---|
| `tools/cpc_illustration.py` | The masters, drawn in code: indexed images in Mode 0 pixels, each value a pen (255 transparent), at twice the largest size shown. The themes' palettes (`THEMES`), each stage's lighting (`stage_colours`) |
| `tools/cpc_landscape.py` | Scrolling 128 × 16 landscapes for every route and the fixed cloud or sunset mask. The title and goal postcards reuse the same art. |
| `tools/cpc_art.py` | The masters made the game's bytes: scaled to the Spectrum's ladder of sizes (`shrink`: each pixel the pen most of its block is), one copy or two a pixel apart (`emit_type`); the Spider's poses compiled, a line of straight code each (`car_code`); the font (`FONT`), the HUD's top strip (`dash_header`), the loading screen (`loading_screen`) |
| `tools/make_cpc.py` | Hands the masters to `make_stages` (each theme its own, the traffic resident); the stage's pens appended to its art pack |

The sizes stay `make_scenery.py`'s (the projection and the clipping depend
on them); a master's width follows from its height.

## Pens

| Pen | Every stage | Use |
|---|---|---|
| 0 | grey | the road. In a sprite, transparent: no sprite uses it |
| 1 | black | outlines, tyres, the dark kerb in a tunnel |
| 2 | bright white | the light kerb, the centre line, text |
| 3 | bright red | the dark kerb, the Spider |
| 4, 5 | the theme's | the ground, light and dark bands |
| 6 | the stage's | the sky |
| 7, 8 | the stage's | the panorama: its ink, its paper |
| 9, 10 | the theme's | scenery (a tunnel's walls, light and dark, on alpine stages) |
| 11 | the theme's | dark accents on buildings, bridges and signs |
| 12 | bright yellow | the timer, lamps, a tunnel's arch, the Spider's lamps |
| 13, 14, 15 | the theme's | scenery |

The Spider and traffic share dark red body shading and reflect the stage's haze colour in their glass. The HUD, the messages and the sky's cells (still converted from
the Spectrum's shadow) find each Spectrum colour's pen by its colour
(`src/cpc/reset.asm CpcPalette`, `CSpecPB`).

A stage's 16 pens and its border travel in its art pack: unpacked at
`ART_BITMAP + 1024 + 640`, after the panorama and the clouds, where
`CpcPalette` reads them at the display reset.

## Done so far (25 November 2026)

- **The coast:** palm, bush, lifeguard tower, parasol; its palette (sand in
  pastel and bright yellow, a grey road, a bright cyan sky). Approved by
  the owner (25 November 2026).
- **The other four themes:** the desert's saguaro, rocks, windpump and
  tumbleweed (orange and yellow sand); the alpine pass's fir, rocks in
  blue-grey, chalet and snowman (ice-blue ground, the tunnels' walls in
  bright blue and blue); the valley's oak, bush, windmill and hay bales
  (greens); the boulevard's street lamp, bush, hoarding and palms (purple
  and mauve ground). Each stage keeps its own sky, panorama, ground and
  HUD colours (its Spectrum palette's, over its theme's CPC palette).
- **Every theme:** the bend signs, the fork's and the tunnel's boards; the
  traffic (a yellow hatchback, a white van, a lorry); the Spider's seven
  poses.
- **The pictures** (`tools/cpc_pictures.py`): the title (the logo on its
  fascia, the coast, the Spider), the five goal postcards (each region
  under the GOAL! gantry) and the loading screen, in Mode 0 from the
  masters. Each is a screen's 16K block, its inks at $600 and its text
  panel's Spectrum cells in the other 2Ks' unshown parts: the front end
  prints and blinks its text there as before (`src/cpc/front.asm
  GfxPicture`); the title's labels in the CPC's font.
- **Arcade redraw:** each stage now loads a packed 1,024-byte Mode 0
  panorama straight into the scrolling cache. Sailboats and a liner,
  mesas and a rock arch, alpine cable cars, valley villages and a lit
  waterfront use multiple pens on one scanline. The static sky uses a
  CPC-drawn cloud mask or striped sun through the existing shadow cells.
  Native sky colours map to the same ink above and inside the panorama.
- The seven Spider poses now show an open two-seat cockpit, louvred engine
  cover, paired rear lamps and twin exhausts. Traffic has reflective glass
  or delivery graphics, and the roadside masters include feathered palm
  fronds, a laddered lookout, faceted rock and a neon boulevard poster.
