# Plan: traffic and scenery drawn the Einstein's own way

A plan, not yet built (24 November 2026). It follows the road-projection work in
`docs/port_einstein.md` section 6, which took the fixed-step benchmark from 1,292 to
1,279 TV frames (locked at 4) and normal play from 11.78 to 11.96 fps. What is left
between that and a steady 12.5 fps is mostly traffic and scenery.

## 1. Where the time goes now

Measured on the fixed-step benchmark (300 game frames of the attract demo,
`-DFIXED_ELAPSED=1`), with a throwaway build whose `DrawSprites` makes no commands:

| Build | Locked at 4 | Unlocked |
|---|---|---|
| as now | 1,279 | 1,176 (3.92 TV frames a game frame) |
| no traffic or scenery | 1,200 (every frame at 4) | 908 (3.03) |

So objects cost about 0.89 TV frames, some 71K T, a game frame on average. Without
them every frame makes 4; with them, in normal play, 16% of frames take 5 to 7. The
frames that take 6 or 7 are the ones with 50 to 75 object cells (big objects near the
car, or many far ones over the panorama: `EinPanoCell` alone reaches 20K T there).

The average, by stage (`profile`, per game frame):

| Stage | Routines | K T |
|---|---|---|
| projection (shared, stays) | `DrawSprites`, `DrawTraffic`, `DrawObject`, `MulS8U8` | 8 |
| XOR into screen B | `RunCommand` and the XOR chain | 9 |
| covered cells marked | `EinSprCells` | 2.4 |
| cells read back from screen B | `EinSprMask` | 9.4 |
| a road cell's colours | `EinSprCell`, `EinMaterialCell`, `EinCellGround` | 6 |
| a panorama cell | `EinPanoCell`, `EinPanoCompose` | 4 |
| rows composed, slots committed, sent | `EinRoadCompose`, `EinComposeStart`, `EinCommitSlot`, `EinAllocSlot`, `EinSendRun`, the OUTI chain | the rest, about 25-35 |

Every object cell costs about 2.2K T from end to end: read back (about 530 T), its
colours, a slot (compare, copy, note) and 16 bytes sent (8 pattern, 8 colour). Of the
21 cells read back a game frame on average, 7 are empty.

## 2. Two ways

### A. Cells without screen B (software)

Draw each command's silhouette straight into per-cell buffers instead of XORing it into
screen B and reading the cells back.

- **Rows 10-23.** `RunCommand` keeps XORing into screen B above row 10 only (its
  `.clipY`, as for the erase), so the sky's mirroring, `EinErase` and the tunnel's
  ceiling rows are unchanged. For rows 10-23 an Einstein routine walks each command's
  source: for each covered cell, its 8 lines (the cell's lines are the source's lines
  `8r - ytop ...`, a byte column apart by the command's stride), ORed into a cell buffer.
- **Cell buffers.** A pool of 8-byte buffers (the cells covered this frame, at most
  about 80) and a byte per cell of rows 10-23 (`12 x 32 + 64` = 448 bytes, or a smaller
  index per masked cell) giving its buffer. Two objects in one cell share a buffer
  (OR, where the Spectrum XORs: the same wherever silhouettes don't overlap, which
  needs checking against the pictures; if not, XOR).
- **The compositors** (`EinSprCell`, `EinPanoCell`) take the buffer in place of
  `EinSprMask`'s copy in `EPat`; an empty buffer is known while it is filled, so empty
  cells are skipped outright.
- **Gain.** The read-back (9.4K) and the empty cells' work (about 3.7K) go; the gather
  costs about what the XOR into rows 10-23 did. About 10-13K T a game frame on
  average, 25K or so in the busiest frames.
- **Look.** None: the pictures must be identical to today's (see 4).
- **Memory.** About 640 bytes of pool and 448 of index (or less with a compact index)
  in the Einstein's buffers above the overlay or in screen A's free tail (324 bytes
  there now, 128 after `EObjectLower`): tight, and to be found before starting.

### B. Hardware sprites for the objects that cost most

The TMS9918 has 32 sprites (16 x 16, or 32 x 32 magnified, for all of them at once),
one colour each, transparent elsewhere, and shows at most four on a scanline (a fifth
and later are not shown). The normal build uses sprites 0-1 (the tail lamps' red
highlights, on the car's rows); 2-31 are free, and so are most of the 2K of sprite
patterns at $3800.

An object drawn as sprites needs no cells: no read-back, no colours worked out, no
slots, no 16 bytes a cell sent; only 4 bytes of attributes a sprite a frame, and its
patterns when its size changes (32 bytes a 16 x 16 pattern). That is most of the
2.2K T a cell, for every cell the object covers.

- **Which objects.** Each game frame, the commands are taken nearest first and given
  sprites while the budget allows: four a scanline (two on the car's rows, with the
  lamps), 30 in all, and never an object that overlaps the car's cells (it would show
  over the car, whose cells are names, not sprites) or lies beyond a tunnel's mouth or
  the gantry while they are drawn (the portal hides objects by painting over cells; it
  can't hide sprites). The rest go the present way. Far objects are one sprite each
  and could be sprites too: they are what makes `EinPanoCell` expensive.
- **Patterns.** One image per object size (a sprite's x is exact, so no pre-shifts):
  traffic's 3 types x 8 sizes resident in VRAM, scenery's per theme uploaded at the
  display reset (4 types x 8 sizes, and signs). Sizes in 16 x 16 pieces: about 20
  patterns a vehicle type, so the traffic alone would take nearly all 64. Scenery would
  need patterns uploaded as objects change size, through a small cache.
- **Colour.** One colour a sprite. The present look gives an object 3 inks, by thirds
  of its height (`EObjectInks`); stacked 16-line sprites could take two or three of
  them, at 16-line steps. Silhouette pixels would be exact over kerbs and verges (no
  two-colour cell to choose between), which is a gain.
- **Magnified or not.** Unmagnified, a near vehicle (up to 56 x 22 pixels) is 4
  sprites wide: one object fills a scanline's budget, and two side by side don't fit.
  Magnified, it is 2 wide at double-size pixels, and the lamps' sprites would have to
  be redrawn at half resolution. A choice for the eye, in the emulator.
- **Gain.** For the objects it takes, nearly all their cost: in the busiest frames
  50K T and more. On average perhaps 30-50K T a game frame (a rough guess, for the
  prototype to measure), depending on how many objects the budget lets through.
- **Risks.** The look changes (one colour per 16 lines, or double pixels); a scanline
  that overflows shows nothing of a fifth sprite, so the budget must be exact; the VRAM
  writes must still fit the vertical blank; and two drawing paths for objects.

## 3. Recommendation and steps

A first, because it changes nothing on the screen, can be checked pixel for pixel, and
takes the read-back's cost from every object cell; then B as a prototype, for traffic
only, to see how it looks and what it gains before deciding.

1. **Measure.** Per-stage timing in the slow frames (`fliphist`'s lists), the object
   cells per frame, and how often two silhouettes overlap in a cell (decides OR or XOR
   in A). Find the memory for A's buffers.
2. **A: cells without screen B**, rows 10-23 (`IFDEF EINSTEIN`; the Spectrum's build
   byte for byte the same). Done when the fixed-step pictures are identical and the
   benchmark has improved.
3. **B prototype:** the nearest vehicle as unmagnified sprites, one colour per 16
   lines, with the scanline budget and the fallback. Screenshots and the benchmark,
   and a magnified variant to compare. Decide on B from those.
4. **B in full** if chosen: all traffic within the budget, then far scenery, then near
   scenery with its patterns' cache.

Expected: A alone takes normal play from about 11.96 to about 12.1-12.2 fps; with B,
most frames should make 4 TV frames, a nearly steady 12.5.

## 4. Checking

- **Pictures.** `-DFIXED_ELAPSED=1` pictures at every 10th game frame, 25 to 315, of
  the attract demo, compared with today's build (`docs/einstein_code.md` section 16).
  For A they must be identical. For B they differ where objects are sprites (the
  harness's `shot` must then include the sprite layer, to be checked).
- **Benchmark.** 300 fixed-step game frames, locked at 4 and unlocked (`wait16`), and
  normal play (`fliphist 1300`).
- **Tests.** `make test-einstein`; `make test` and the Spectrum's snapshots byte for byte
  the same as before (`cmp`).
- **Places.** A tunnel's way in (`-DFIRST_STAGE=3 -DSTART_POS=6977`), the goal's gantry
  (`-DFIRST_STAGE=12`), a fork, and crashes into scenery and traffic.
