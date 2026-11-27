# The Einstein port's code

A guide to the Tatung Einstein port's own code: what each part does, where it lives,
the data it shares, and the rules it relies on. The plan, history and speed measurements
are in [port_einstein.md](port_einstein.md); the artwork and its tools in
[einstein_artwork.md](einstein_artwork.md).

## 1. How the port is put together

The Einstein assembles the same `src/main.asm` as the Spectrum, with `-DEINSTEIN`. The
game runs at its Spectrum addresses ($4000-$BFFF) in the Einstein's flat 64K: its logic,
the road's projection (pass 1, the hills), the traffic and scenery projection, the HUD and
messages, the music and the front end are the Spectrum's own code. `IFDEF EINSTEIN` blocks
in the shared files swap out what touches the hardware, and `src/einstein/` holds the rest.

The shared code still draws much of the picture into the Spectrum's **screen B** ($C000,
plain RAM here, never shown): the HUD, the message line, the starting lamps, and the
traffic and scenery silhouettes. The Einstein layer turns that, and the road it builds
itself, into the TMS9129's Graphics II tables: names, patterns, colours and sprites. It
builds each frame in RAM and sends it to VRAM from the interrupt, in the vertical blank.

The Spectrum build must stay byte-identical to `release/`: Einstein-only code goes in
`src/einstein/` or under `IFDEF EINSTEIN`, and after any change to a shared file,
`make build/speedrun.tap` and `cmp` it with `release/speedrun.tap`.

## 2. The files

| File | Area | What it does |
|---|---|---|
| `platform.asm` | below $4000 | Ports, VRAM addresses, the pattern and slot layout, the buffer map; the COM file's entry (`jp EinBoot`); includes the files below that run from the platform area |
| `boot.asm` | below $4000 | `EinBoot` (start-up), `EinCtcInit` and `EinIsr` (the frame tick from the CTC), `EinCoarse` (AY pitches for 2 MHz) |
| `vdp.asm` | below $4000 | VDP registers and set-up, `VdpAddr`, paced `VdpWrite` and `VdpFill`, Spectrum colour to TMS colour (`SpecTms`, `AttrPaper`, `AttrInk`) |
| `roadgfx.asm` | below $4000 | The road: `EinDraw` and every way a row is drawn, colour sets, slots and their commits |
| `flip.asm` | below $4000 | `WaitFlip`, `RequestFlip`, `EinUpload` (the frame into VRAM), the blank's budget, `EinResetDisplay` |
| `sky.asm` | below $4000 | Rows 0-9: cells noted and mirrored from screen B, the native sky, FLASH; `EinCarSync`; the panorama's scroll |
| `sprites.asm` | below $4000 | Traffic and scenery: `EinErase`, `EinSprCells`, compositing over the panorama and the road; `EinCarNames` |
| `portal.asm` | below $4000 | Tunnels' mouths and the goal's gantry, from screen B's attributes |
| `screen.asm` | bank 2 | `FillA`, the one routine of the Spectrum's `screen.asm` the shared code still needs |
| `keys.asm` | bank 2 | The keyboard (answering the Spectrum's port reads), `EinReadInput`, the analogue joystick |
| `disc.asm` | bank 2 | `EinRead`: records of `STAGES.DAT` through XtalDOS's BDOS |
| `front.asm` | bank 2 | The front end's full-screen bitmap mode |
| `dash.asm` | bank 2 | The tail-lamp sprites; with `-DEIN_DASH` the centre line's sprites |
| `slope.asm` | bank 2 | `EinSlopeRow`: a sloped near-road row in one pass (only with `-DEIN_SLOPE=n`) |
| `objcolour.asm` | bank 2 | `EinCellGround`: the ground colour under an object in a two-colour road cell |
| `kerbrow.asm` | bank 2 | `EinKerbRow`: a road row with both kerb edges exact (the default); `EKGe` |
| `kerbcell.asm` | below $4000 | `EinKerbCell`, `EinKerbRight`, `EinKerbMerged`: its cells; `EinSendCols` |
| `kerbmac.asm` | (macros) | `KLOAD`, `KPUT`, `KLEFT`, `KRIGHT`; `KPAIRS`, `KSTEP` (4-line or 2-line steps) |
| `static.asm` | bank 2 ($B900) | `EinStaticInit`: the ready-made kerb edges, at a display reset |
| `reset.asm` | bank 2 (after the OUTI chain) | `EinMirrorAll`, `EinPanoUpload`: more of the display reset |
| `ground.asm` | bank 5 | The two verge textures: `EinGroundInit`, `EinGroundName`, `EinGroundPaper` |
| `car.asm` | bank 2 | The native Spider's pose selection, ground colours and pending pattern runs |

"Bank 2" and "bank 5" are the Spectrum's names for those address ranges ($8000-$BFFF and
$5B00-$7FFF); on the Einstein all RAM is alike. The generated `build/einstein/spider.asm`
(the car's poses) and `einstein_objects.asm` (the objects' sizes and silhouettes) are
included in bank 5 too.

## 3. Memory

| Address | What |
|---|---|
| $0100 | `jp EinBoot` |
| $0120 `THEME_CACHE` | The theme pack; the front end's code (`frontend.bin`) is loaded here while the front end runs |
| $21A0 `PANO_CACHE` | The panorama's 512 pixel bytes followed by 512 colour bytes. Both planes hold two rows of 32 tiles, eight consecutive bytes per tile. |
| $25A0 `EIN_CODE` | The platform code (`platform.asm`'s includes), up to $4000 |
| $4000-$47FF | The between-stages overlay (`stageov.asm`), resident until a display reset unpacks the sky over it: `ESkyPixels` ($4000, 7 x 256), `EObjectUpper` ($4700) |
| $4800 `BaseNames` | Rows 10-23's names as the panorama and the road draw them (448 bytes); the art pack is read here first |
| $4A00 `ESkyAttr` | Sky rows 3-9's attributes as last seen (portals) |
| $4AE0 ... | `EMaskP`, `EMaskPOld`, `EMaskN`, `EMaskU`: 96 bytes each (24 rows x 4) |
| $4D00 `EPanoInkBuf` | Colours of panorama cells under silhouettes (64 x 8) |
| $4F00 `ESkyInks` | The native sky's colour bytes (7 rows x 256), then `EObjectInks` ($5600), `EGroundPatterns`, `EGroundPapers` |
| $5680 `EPanoSpr` | Pixels of panorama cells under silhouettes (64 x 8), then `EPanoList`, `ERowSig`, `ERowFk` |
| $5B00 | Bank 5's part: resident data and code (see above), then `TRACK_CACHE` |
| $8000 | Bank 2: `start`, the main loop, the shared code, then `keys`, `disc`, `front`, `car`, `dash`, `slope` |
| $A300 `TABLES` | The road's lookup tables (`tables.asm`) |
| $B900 | `static.asm`, the OUTI chain ($B9C0, `OutiEnd` = $BA00), `reset.asm`, `respawn.asm`, `lights.asm` |
| $BAD8 | The XOR chain (`XorEnd` = $BB00), the hill tables, `FillBlock`, `jp Isr` at $BDBD, the IM2 table at $BE00, BSS, the stack (to $C000) |
| $C000-$DAFF | Screen B: the shared code's drawing (bitmap $C000, attributes $D800) |
| $DB00 `EIN_BUF` | `NameBuf` (768), `SlotShadow` (220 x 11; `-DEIN_BLOCKS`: 196 x 9), `DirtyList` (220), `EDirtyRowN` (12), `EMirrorBits` (40), the Spectrum's command list B (`EIN_CMDLISTB`), the centre line's state (`EDashX` ... `EDashAttr`, with `-DEIN_DASH` only), `ECarCol`, `EObjectLower` ($EA00) |
| $EC00 | XtalDOS, kept for reading the disc |

Screen A ($4000-$5AFF) is the overlay's and the Einstein's buffers' during play: the game
code must never write it there (`Ceiling`, `TimeWarn` and `LampDraw` skip it on the
Einstein). The front end draws over all of screen A, so everything in it is made afresh
by the next display reset. Setting `CarShownB` to $FF there requests a full car upload.

Space is very tight. In the normal build, 270 bytes are free before the bank 2 tables,
364 below $4000, 128 at the end of the buffers at $DB00, 52 before the bank 5 track cache
and 324 at the end of screen A. With `-DEIN_BLOCKS`, 1,104 in bank 2 and 76 below $4000.
`-DEIN_BLOCKS -DEIN_DASH -DEIN_SLOPE=4` (the look before the speed cut) no longer fits
bank 2, and `-DEIN_DASH` without `-DEIN_BLOCKS` doesn't fit the buffers.

## 4. VRAM

| Address | What |
|---|---|
| $0000 `VRAM_PAT` | Patterns: three thirds of 256 x 8 bytes |
| $1800 `VRAM_NAMES` | Names, 32 x 24 |
| $1B00 `VRAM_SPRATTR` | Sprite attributes |
| $2000 `VRAM_COL` | Colours: a byte (ink, paper) for each pattern line |
| $3800 `VRAM_SPRPAT` | Sprite patterns |

The patterns, per third:

| Third | Patterns |
|---|---|
| top (rows 0-7) | one a cell, in order: the HUD and the sky, mirrored |
| middle (rows 8-15) | 0-15 solid colours; 16-35 slots (rows 12-15, `SLOTS_T1` = 5 each); 36-63 the ready-made kerb edges (`KERB_T1`); 64-127 rows 8-9 mirrored (`SKY_PAT_T1`); 128-191 the panorama (`PANO_PAT`); 192-255 panorama cells under silhouettes (`PANO_SPR`) |
| bottom (rows 16-23) | 0-15 solid colours; 16-191 slots (rows 16-23, `SLOTS_T2` = 22 each); 192-219 the ready-made kerb edges (`KERB_T2`); 220-221 the verge textures (`GROUND_PAT`); 224-255 the car (`CAR_PAT`) |

A solid cell's name is its TMS colour: pattern k (k < 16) is blank with colour k behind it.
A **slot** is a pattern made each frame (8 pixel bytes and one colour byte for all 8
lines), handed out per row. The ready-made kerb edges are 7 left edges (road from pixel
1-7) and 7 right (road to pixel 0-6) in the light kerb and the dark.

Sprites are 16x16. Sprites 0-1 are the four tail lamps' red highlights, pattern 48. A $D0
follows them. With `-DEIN_DASH`, sprites 0-11 are the centre line, one a road row, their
patterns at 4k, and the lamps are sprites 12-13.

During the front end the screen is a plain bitmap instead: each third's 256 patterns are
its 256 cells in order.

## 5. A frame

### The main loop (`src/main.asm`)

| Step | Does |
|---|---|
| `CheckPause`, `EinReadInput`, `UpdatePlayer` | The game's logic (shared); the keys looked up directly in the rows read this TV frame |
| `RoadPrepare` | Pass 1 (shared): the road's edges, centre line, bands and depth per screen line |
| `WaitFlip` | Waits until the last frame has gone into VRAM: its buffers are free |
| `EinErase`, `DrawSprites` | Last frame's silhouettes out of screen B, this frame's projected and XORed in (shared) |
| `EinCarPrep` | The Spider's pose for this frame |
| `DrawPortal` | A tunnel's mouth or the gantry painted into screen B's attributes (shared) |
| `EinSprCells`, `EinPortal` | The cells the silhouettes and the portal cover |
| `EinHorizon` | The panorama's names for its scroll |
| `EinDraw` | The road's rows, composited with silhouettes and portals, into names and slots |
| `EinCarGroundSync` | The car's cells whose ground changed, coloured again |
| `DrawHud`, `EinFlash` | The HUD into screen B (shared), its cells noted; the timer's FLASH |
| `RequestFlip` | The frame is ready: `FlipPending` |

Everything before `WaitFlip` runs while the previous frame is still being sent.

### The interrupt (`boot.asm` `EinIsr`)

The VDP's frame interrupt is not wired to the Z80. CTC channel 2 interrupts every 1 ms
(timer, /16, 250) and the handler reads the VDP's status. When the frame flag is set (at
the start of the vertical blank), it counts a TV frame (`FrameCount`). If a frame is
pending, it calls `EinUpload` when the frame is due: frames go on a grid of
`EIN_MIN_FRAMES` (4) TV frames (`EGrid`, the tick the last was due at), and a late one
puts the grid's next ticks no more than `EIN_DEBT` (4) TV frames behind; while it is
behind, frames go 3 TV frames apart (`EIN_MIN_GAP`), one TV frame made up each.
`LastFlip` stays the TV frame the last was sent in (the stage's jingle waits for it). Then it plays the sound (`SoundTick`). After seeing a frame it sets
the CTC to a 16 ms wait (/256, 250) and goes back to 1 ms polls after that, so the flag is
seen at most 1 ms late. A frame seen at the very first poll after the wait may be late by
an unknown time (`EFirstPoll`): its upload is all paced. A frame that begins while the
interrupt is still busy is counted at its end, with its sound (the `.over` loop;
`EinMirror` checks too, through `EinLateFrame`).

A game frame takes 4 TV frames here, or 3 while one late is made up. `Elapsed` goes up to 8 (`player.asm`) so the
clock and the car keep real time.

### Sending a frame (`flip.asm` `EinUpload`)

In order: the centre line's changed sprites (`EinDashSend`, with `-DEIN_DASH`), the panorama cells under
silhouettes (`EinPanoSend`), then rows 10 to 23: each row's changed slots, then its names
if it was drawn again (`ERowDrawn`: 1 from `BaseNames`, 2 from `NameBuf`). A row's slots go
before its names, so a row never shows new names over old patterns. Then the car's
changed cells (`EinCarSync`) and the sky's noted cells (`EinMirror`).

**The raster.** An upload averages about 56K T, against a 30.8K T blank, so it often runs
on into the picture (in the attract demo about 40% finish after the raster has reached row
10). If the raster reaches a row between its slots and its names, that TV frame shows its
old names over its new slots: tiles from the wrong cells (or the car between its new
patterns and its colours). So before each road row's writes, and the car's
(`EinRowHold`, `EinCarHold`, `rowhold.asm`), while the upload is timed (the CTC's 16 ms
wait, started as the frame was seen), the raster's place is worked out from the CTC
(`EinElapsed`, a count each 256 T, its reloads counted): a row whose writes could meet it
waits till it has gone past. The row then shows its old frame, whole, for that TV frame.
Rows written before the raster got there and rows written after it still show different
frames in that one TV frame (a torn picture: about 3.5% of TV frames in the attract
demo). Only an upload that starts behind the raster at row 10, or fits before it gets
there, could avoid that. The frame rate is unchanged (694 game frames in 6,000 TV frames
either way).

Albert draws each line as the raster finishes it and shows the frame when line 191 is
done (`Machine::presented`, since 25 November 2026), as a television does. Before, it
drew all of VRAM at its own moments, which caught uploads halfway: about one picture in
six torn in the attract demo.

## 6. Writing VRAM

With the picture on, VRAM accesses must be at least 32 T apart or the chip loses them.
Albert counts every access that comes too fast, and the tests fail on any. In the vertical
blank (30,830 T) any speed is safe.

- `VdpAddr` sets a write address. `VdpWrite` (32 T a byte) and `VdpFill` are always paced.
- `EinWrite` and `EinFill` ask `EinSpend` first. If there's time, they go at full speed:
  `EinWrite` through the unrolled OUTI chain (16 T a byte, entered at `OutiEnd - 2n`,
  32 at a time). Otherwise they fall back to the paced routines.
- `EinSpend` reads `EBudget`. 0 means every write is paced (set for the front end). Any
  value other than 0 or 1 means any speed (the display reset, with the display off).
  1 means timed: the CTC's 16 ms wait started when the frame was seen, counting down from
  250 every 256 T. A write of B bytes goes fast only while the count is at least
  `BLANK_END + 1 + B/8`; the first write that fails sets `EBudget` to 0 for the rest of
  the upload, since the count runs on and restarts at 250.
- `EinSlotRuns` scans each road row's dirty slots once for pixels and once for colours.
  `EinSendRun` sets one VRAM address per contiguous run and streams the tiles in increasing
  address order. Its fast and paced loops step through the strided RAM records. Mixed colour
  tiles use `EinSendCols` at 34–35 T per byte. Colour runs of 16 or more tiles use paced
  writes because their worst-case cost exceeds the range of the eight-bit budget argument.

## 7. The road

### What pass 1 leaves

The shared pass 1 fills per screen line, at line-pair resolution (each even line copies
the odd line below it):

- `DEPage`: the first road pixel (D) in the low half, the last (E) at +$80.
- `LXPage` (`LaneX`): the centre line's x.
- `SrcLine`: the depth line shown on the line (hills), which gives the kerb widths
  (`RoadRW`) and the centre line's width (`LaneW`).
- `Band`: bit 6 dark, bit 7 a tunnel's.
- `CXLo`/`CXHi`: the road's centre per depth line, for the objects.
- `RowFork` and `DE2Page`: a fork's second branch.

`RoadPrepare` sets `EinShape` when it runs pass 1 (the shape may have changed).

### Which rows are drawn again (`EinDraw`)

For each of the 12 road rows:

- **Bands:** the bands of its lines 0 and 4 are compared with `ERowBands`. Only those two
  matter: line 4 gives the row's colours, lines 0 and 4 its dashes.
- **Shape:** if the bands are unchanged and `EinShape` is set, `EinRowSame` compares the
  row's 20-byte signature (`ERowSig`: D, E, the centre line and the depth line for its 4
  pairs and its last line).
- **Forced:** `ERowFk` forces a fork row, and the row after it, to be redrawn.
  `EinForce` redraws every row (a display reset, going in or out of a tunnel).

A row to be drawn goes to `EinRow`. Then, if a silhouette or a portal covers it now or
did last frame (`EMaskU`), it is composited (`EinRoadCompose`). Last comes `EinDashFinish`
(centre line, with `-DEIN_DASH`).

### The ways to draw a row

0. **Exact kerbs** (`EinKerbRow`, `kerbrow.asm`; the default, every row of the open
   road, from `EinRowFast`): the line groups' edges and kerb widths (lines 0 and 4; with
   `-DEIN_KERB2` all 4 line pairs) give each group L, D, E, R (kerb [L, D) and (E, R]);
   the left run's cells [`ERA`, `ERB`) and the right run's [`ERC`, `ERD`) are made a
   group at a time through `EKGe` (a cell's pixels from v on, indexed by v - x0), each
   group's byte on its lines, over grass or over road. A cell all kerb, road or grass is
   a solid name; else a slot with kerb over grass, kerb over road and the mask of the
   lines over road (`EComM`, `EComC2` for `EinCommitSlot`). Where the runs share a cell (a
   narrow road), `EinKerbMerged` makes [`ERA`, `ERD`) with both. A row with no road is
   grass; one with a group without road, or a run over 119 pixels wide, goes the exact,
   generic way (3). With `-DEIN_BLOCKS` this way is left out, and 1 and 2 are as below.
1. **Ready-made** (`EinRowFast`, `-DEIN_BLOCKS` only): most rows. In one pass:
   - the row's ranges `ERA`-`ERD` (grass, kerb, road, kerb, grass, as the Spectrum's
     `DrawRoadRow`);
   - its colour set;
   - its names, each kerb edge upright in the row at the mean of its top and bottom
     lines, from the ready-made patterns (`EFastK`).

   Not for:
   - a tunnel's row or a fork's;
   - a row whose two edges fall in one cell;
   - with `-DEIN_SLOPE=n`, in rows 16-23, an edge whose top and bottom lines are more
     than n pixels apart (without it every other row is ready-made).
2. **Sloped** (`EinSlopeRow`, `slope.asm`, with `-DEIN_BLOCKS -DEIN_SLOPE=n` only): the near rows refused for their slope. It does
   what the exact way does, in one pass, with each kerb cell made straight from the pairs'
   edge pixels. That needs each kerb run to be crossed by its own edge alone: every pair
   with road, every E right of the left run, every D left of the right run. Otherwise it
   sets `ESloped` and the row goes the generic way, its ranges already made.
3. **Exact, generic** (`EinRowBase`): a tunnel's row, a fork's (`EinForkCells`: both
   branches), the rows the exact kerbs can't draw, one-cell rows and the sloped fallback
   (`-DEIN_BLOCKS`). In order:
   - `EinRowRanges` and `EinStaticRanges`, unless `ESloped` says they're made already;
   - `EinRowNames` (the fills);
   - a tunnel's lamps;
   - `EinLineEdges` (each pair's D and E cell and mask);
   - `EinKerbCells` over the two kerb runs (each cell's pairs by `EinCellMasks`' rule,
     then none, all or some road);
   - `EinDashRow` (with `-DEIN_DASH`).

   `EinCellMasks` and `EinKerbName` remain for forks.

Each way ends at `EinRowBase.slotsUsed`. That records the row's free slots for its
silhouettes (`ERowLo`, `ERowHi`, bit 7 of `ERowHi` the direction) and, for rows 20-23,
writes the car's names over the road's (`EinCarNames`).

### Colours

`EinColourSets` makes four sets a frame in `ERowSets` (open or tunnel, light or dark),
7 bytes each:

- `EAG`, `EAK`: grass and kerb attributes;
- `ECG`, `ECK`, `ECR`: grass, kerb and road colours;
- `EKC`: a kerb cell's colour byte (road over kerb);
- `ELC`: a centre-line cell's.

A row's set comes from the band of its middle line (`ERBand`). `EinRowColours` copies it
into `EAG` ... `ELC`, and with the exact kerbs works out `EKCG` and `EKCR` (kerb over
grass, kerb over road) too, only when the set is not the one there already
(`ERowSetNow`, reset by `EinColourSets`). In rows 16-23 the open road's grass becomes the
verge textures (`EinGroundName`). `EinGroundPaper` maps those back to a paper colour.

### Slots

- **`SlotShadow`:** holds what VRAM holds for every slot (9 bytes each).
- **`EinRowSlots`:** points `ESlotPtr` and `ESlotName0` at the row's slots, from
  `ERowSlotTab`.
- **`EinSlotRange`:** sets the free range `ESlotN`-`ESlotTop` and the direction
  (`EDown`). A light-band row takes its road slots from the bottom up, a dark-band row
  from the top down, and its silhouettes continue on from them. A kerb slot therefore
  keeps its light or dark colour as bands pass, and only its pixels are resent.
- **`EinCommitSlot`:** uses `EinAllocSlot` to take the next slot. It compares `EPat` and the colour
  with the shadow, copies what differs, and notes the slot. Four-line kerbs use
  `EinCommitKerb`, which compares both compact bytes against all eight shadow lines and
  expands them on a pixel mismatch. Both paths share colour comparison and dirty flags.
- **`DirtyList`:** one byte a changed slot (bits 0-4 the slot in its row, bit 6 pixels,
  bit 7 colour), in row order, counted per row in `EDirtyRowN`.
- **`EinSlotBase`:** finds a row's shadow and VRAM bases once for the upload.

## 8. Traffic and scenery

**Projection (shared).** `DrawSprites`, `DrawTraffic` and `DrawObject` project the objects
and record draw commands in command list B (`CmdListB` = `EIN_CMDLISTB`, at most 14).
A command is 8 bytes: y top, column, bytes a line, source skip, source address, height,
and on the Einstein the object's type. `RunCommand` XORs pre-scaled, pre-shifted
silhouettes into screen B. On the Einstein it skips the Spectrum's car-block check, and
`.clipY` limits it to the lines above that y: 192 normally, 80 (row 10) while erasing.

**Erasing (`EinErase`).** Last frame's commands are XORed out of screen B above row 10
only. Below, screen B holds nothing but silhouettes, and `EinSprMask` clears each cell as
it reads it. So **every covered cell in rows 10-23 must be read every frame**, including
the car's cells and a tunnel's ceiling rows: `EinSprCell` and `EinPanoCell` do so.

**Covered cells (`EinSprCells`).**

- **Masks:** `EMaskN` holds this frame's covered cells, and `EMaskU` those plus last
  frame's. `MASK_ROW` is 4 bytes a row; bit k of byte j is column 8j + k.
- **Row bits:** `ENRows` and `EURows` hold a bit for each row that has any, so only those
  rows are copied, cleared and mirrored.
- **Inks:** for rows 4-23, each covered cell's ink goes into `EObjectUpper` or
  `EObjectLower` (`EinMaterialCell`). It comes from the object's type and the third of
  its height the row is in (`EObjectInks`: 3 a type). The list is walked last command
  first, so a cell two objects share takes the first's ink, as on the Spectrum
  (traffic, then the nearest scenery; the far palm's ink had been on the near one's
  crown).
- **Sky rows:** covered cells in rows 0-9 are noted for mirroring.

**Compositing.** A row with silhouettes is copied from `BaseNames` to `NameBuf`
(`EinComposeStart`), and each covered cell is made:

- **Rows 10-11** (`EinPanoCompose`, `EinPanoCell`): the panorama's pixels, except on lines
  with silhouette pixels. Those take the silhouette's pixels and the object's ink over the
  panorama's paper, or a shade of that ink if they're the same (`EinShadeE`). The result goes into a pattern of
  its own (`PANO_SPR` + index). `EinPanoSend` groups adjacent tile indices and sends
  each run's pixels and colours through `EinWrite`. A run contains up to eight tiles,
  so each transfer is at most 64 bytes and gets its own vertical-blank timing check.
- **Rows 12-23** (`EinRoadCompose`, `EinSprCell`): the road's name under the cell decides.
  - A solid cell becomes the silhouette in the object's ink over the cell's paper.
  - A cell of two colours (a ready-made kerb edge, a slot) becomes the silhouette in the
    object's ink over the colour most of its pixels show (`EinCellGround`,
    `objcolour.asm`), so objects keep their colours across kerbs.
  - Where the ink is the ground's colour it takes a shade of the same hue (`EinShadeE`,
    `EShade`: the coast's palms on its dark green band were drawn black, and flicked
    between green and black as the bands passed).

  Each result takes one of the row's slots. When the row has none left (rows 12-15
  have 11: a big palm's crown over the far road's kerbs used them up, and its cells
  were left out, the road showing through), `EinBorrowPano` takes one of the
  panorama's covered-cell patterns (`PANO_SPR` on, the same third) that no
  silhouette covers this frame or covered the last, and sends it with them
  (`EPanoList`). The car's cells are skipped (its names go over).

## 9. The sky, the HUD and the panorama

**Rows 0-9 are mirrored from screen B.** Shared code that writes a cell there notes it:

- `DrawHud`, through `EinMarkCell`;
- `PrintBig`, through `EinMarkBig`;
- the starting lamps, through `EinLampCells`;
- `EinFlash`, `EinSprCells` and `EinPortal`.

Each note sets a bit in `EMirrorBits`, so a cell is sent once however often it's noted.
`EinMirror` (in the interrupt) sends every noted cell. `EinSendCell` sends one cell's
8 pixel bytes and its colours:

- **Row 0:** fixed colours for the labels.
- **Rows 3-9:** with the sky's own attribute, outside a tunnel and away from an active
  message, `EinSkyCell` composites screen B's moving ink over the native sky
  (`ESkyPixels`, `ESkyInks`): an object's lines in its own ink (rows 4-9, from
  `EObjectUpper`; row 3 black), or a shade of it over a sky of the same colour. Each
  uncovered line gets the art's own pixels and colours back.
- **Everything else** (rows 1-2, a tunnel, a lamp, the message): the cell's attribute
  ink over paper, with FLASH swapped when `EFlashOn` says so.

**The panorama** (rows 10-11) is sent once a stage (`EinPanoUpload`) and scrolls by its
names alone, in 8-pixel steps (`EinHorizon`, `EinHorizonNow`, from `HorizonX`). That is
one column every dozen game frames or so. In a tunnel the panorama rows become its
ceiling (`EinCeiling`).

**Portals** (`portal.asm`). The shared `DrawPortal`, `Ceiling` and `Gate` paint screen
B's attributes. `EinPortal` mirrors the sky cells whose attribute changed (against
`ESkyAttr`). In rows 10-19, a cell whose attribute isn't its row's own is the portal's:
it is noted in `EMaskP`, and `EinPortalCells` makes it a solid cell of the portal's paper
and puts the attribute back. Rows covered now or last frame (`EMaskPOld`) are added to
`EMaskU` and composited again.

## 10. The centre line (`dash.asm`)

Only with `-DEIN_DASH`: the normal build has no centre line (cut for speed, about 24K T a
game frame: docs/port_einstein.md section 6), and `dash.asm` holds only `EinTailLamps`.

One sprite per road row. Its pixels are exact at any x and use no slot.

- **Making a row's sprite** (`EinDashRow`, `EinDashRedo`): takes the dashes of line
  pairs 0 and 2, each for 4 lines, light bands only, inside the road's cells
  [`ERB`, `ERC` - 1), as the Spectrum does. They come from `LaneX` and the width from
  `LaneW`, through the `LaneM1`/`LaneM2` masks.
- **Hiding:** pixels over a cell that a silhouette, the portal or (rows 20-23) the car
  covers are taken out. Those cells come from the two mask bytes under the sprite's 16
  pixels (`EMaskN` and `EMaskP`, reached from `EMaskPOld` at -96 and +96).
- **Sending:** `EDashOut` holds what VRAM shows, so only a changed sprite is copied into
  `EDashQ` (its 24 sent bytes) and flagged. `EDashAttr` holds the attributes.
- **Rows not drawn again:** `EinDashFinish` remakes those whose cover changed.
- **The tail lamps:** `EinTailLamps` sets up the two highlight sprites at a display reset.

Sixteen-line sprites mean two centre-line sprites share each scanline. With the lamps
that is the limit of four a line.

## 11. The car (`car.asm`; `EinCarNames` in `sprites.asm`, `EinCarSync` in `sky.asm`)

The Spider's 32 cells are the bottom third's patterns 224-255, at rows 20-23, columns
12-19.

- **Poses** come from `build/einstein/spider.asm` (`EinCarFrames`: seven poses, each a
  top and a base). `EinCarPrep` selects the resident art and looks up the old and new
  poses in `EinCarTransitions`. The entry supplies four colour-change masks and a list
  of contiguous pattern runs. The first pose after a display reset uploads all 32 cells.
- **Transparent lines:** a line whose paper is 0 is transparent. It takes the paper of the
  ground under its cell.
- **Ground:** as each car row is drawn, `EinCarNames` notes that ground (`ECarGround`) and
  marks a cell in `ECarDirty` if its ground changed and the pose has transparent lines there.
- **Colouring:** `EinCarGroundSync` makes those cells' colours in `ECarCol` (8-aligned)
  and marks them to be sent (`ECarSend`).
- **Sending:** `EinCarSync` reads the pattern runs directly from the resident pose and
  uploads contiguous runs of marked colours from `ECarCol`. A left smoke-puff change
  sends 16 pattern bytes and a right one sends 24.
- **Rolling tyres** (`eintyres.asm`, as the Spectrum's `src/tyres.asm`): the rear tyres
  are the bottom row's cells 0-1 and 6-7 (patterns 248, 249, 254, 255), their tread on
  line 3. Each TV frame the interrupt moves the tread on by the speed (`EinTyreTick`: a
  row each 21 depth units, three positions); when it has moved, `EinTyreDraw` writes the
  four cells' lines 2-6 (the shown pose's tread line or plain line 4, two tread lines
  three apart, colours with the ground's paper where the art has none). `EinUpload` also
  draws them after `EinCarSync` (under the car's raster hold), since that may have sent
  the cells again, and notes the pose now shown (`ETyrePose`). Not in the front end, a
  display reset or the smoke poses. `EinTyreTick` is at the platform code's end, the
  drawing at the theme cache's last 192 bytes (`EIN_TAIL`: `tools/make_einstein.py`
  keeps theme packs below it; the alpine pack, the fullest, ends 14 bytes short), the
  data in the ZPage table page's hole. About 3-4K T in a TV frame when the tread moves;
  the frame rate is unchanged (694 game frames in 6,000 TV frames).

## 12. The display reset

`EinResetDisplay` (`flip.asm`) ends every stage load: the overlay's `OvResetDisplay`
tail-calls it, once screen B has been made afresh. With interrupts off and the display
off, it does the following in order.

1. Unpacks the stage's art: the pack was read into `BaseNames` and is copied to `NameBuf`
   first. The art goes into `ESkyPixels` (over the overlay, so `EOvClobbered` is set),
   `ESkyInks`, `PANO_CACHE`, `EObjectInks`, the verge patterns and their papers.
2. Clears VRAM.
3. Sets up the solid cells.
4. Loads the verge textures (`EinGroundInit`) and the ready-made kerb edges
   (`EinStaticInit`).
5. Sets up the tail-lamp sprites (and with `-DEIN_DASH` the centre line's).
6. Sends every sky cell (`EinMirrorAll`) and the panorama's patterns (`EinPanoUpload`).
7. Writes every name, with the car's names in rows 20-23.
8. Clears the masks and their row bits, the portal state (`EinPortalReset`) and
   `SlotShadow`. Sets `CarShownB` to $FF so the next frame reloads the pose, and sets
   `EinShape` and `EinForce` so every row is drawn.

## 13. Input, sound, the disc and the front end

**Keys** (`keys.asm`).

- **Scanning:** the Einstein's matrix is read through the AY's I/O ports, a row selected on
  register 14 and read on register 15, with interrupts off between the two.
  `EinKeyScan` reads all 8 rows once a TV frame into `EKeyRows`.
- **Spectrum port reads:** `EinSpecIn` answers the Spectrum's port $FE reads (the
  `KEY_IN` macro: the front end, the pause key, the generic `ReadInput`) from those rows.
  Each Spectrum key maps to where the same key sits on the Einstein (`SpecKeys`).
- **The game's keys:** `EinReadInput` looks up the game's five keys (`KeyMap`) directly.
- **The joystick:** `EinJoy` reads the analogue joystick through the ADC0844 and the fire
  button.

**Sound.** The AY runs at 2 MHz, so every tone and noise period is scaled by
`AYN`/`AYD` = 1128/1000 (`defs.asm`). The computed ones use `EinCoarse`, and the
tune's notes come from `build/einstein/music_notes.asm`. The AY's ports are in
`sound.asm`.

**The disc** (`disc.asm`).

- **Reading:** `EinRead` reads whole records of `STAGES.DAT` straight into place, the last
  part of one through `ERecBuf`. It does this for the stage packs (`CopyFromBank`,
  `CopyToCache`), the overlay, the front end's code and the pictures.
- **Mode switching:** for each read the machine goes back to MOS's interrupt set-up
  (`EinMosMode`: I = $FB, CTC channels 2 and 3 as MOS has them), because the BDOS needs
  them to time the disc. Afterwards it returns (`EinGameMode`).
- **Caching:** a theme or track already in its cache is not read again (`ELastTheme`,
  `ELastTrack`).

**The front end** (`front.asm`). The Spectrum's title, high scores, options, goal and
game-over screens run unchanged and draw into screen A.

- **Showing a screen:** `EinFrontOn` shows screen A as a bitmap.
- **Frame waits:** each of the front end's frame waits (`EinHalt`) compares 96 cells with
  the copy in screen B's memory and sends those that differ (`EinFrontSync`, paced).
- **The interrupt:** meanwhile it counts frames on the CTC alone.
- **Pictures:** `EinPicture` reads a picture into $C000 and unpacks its pattern and colour
  planes.
- **Overlay:** `EOvClobbered` makes `StageOv` (`stage.asm`) read the overlay back from the
  disc before it is next run.

## 14. The shared files' Einstein blocks

| File | On the Einstein |
|---|---|
| `main.asm` | The 64K device; the platform code; its own main loop; the bank-2 includes; no panorama or kerb chains (their place holds `static.asm`, the OUTI chain and `reset.asm`); the overlay and the front end assembled as their own files; `SAVEBIN` of the COM file |
| `defs.asm` | No border profiling; `AYN`/`AYD`; `FRAME_WAIT` is `EinHalt`; `KEY_IN` is `EinSpecIn` |
| `interrupt.asm` | `InitInterrupts` is `EinCtcInit`; `Isr` is `EinIsr` |
| `scenery.asm` | `DrawObject` records the type; `RunCommand` without the car check, clipped by `.clipY` |
| `road.asm` | No pass 2 (`DrawRoad`, `DrawRoadRow`); `RoadPrepare` sets `EinShape`; pass 1 without the centre line (`EIN_NOLANE`, `src/defs.asm`), the road's centre in BC', its slow path `Span`'s |
| `hills.asm` | The hill mapping's loop with `ProjClip + j` in HL' and the free pairs in C'; `HillStore` and the ground without the centre line, the depth line in C' |
| `track.asm` | `ApplyCurve`: `<< (zone - 2)` from zone 2 on |
| `horizon.asm`, `fork.asm`, `tyres.asm`, `car.asm` | Their drawing left out (`IFNDEF EINSTEIN`) |
| `tunnelaside.asm` | In bank 2 (on the Spectrum in bank 5, beside `tunnel.asm`): no room in bank 5 here |
| `hud.asm`, `extend.asm`, `lampdraw.asm` | The cells they write noted to be sent; screen B only |
| `tunnelb2.asm`, `holes.asm` | Screen B only (screen A's memory is the Einstein's); `EinCoarse` for the crash's thud |
| `input.asm` | The joystick from `EinJoy` |
| `sound.asm` | The AY's ports; the engine's pitch for 2 MHz |
| `player.asm` | `Elapsed` up to 8 |
| `pause.asm` | PAUSED drawn into screen B and sent with a flip |
| `stage.asm`, `stageov.asm`, `pics.asm` | Packs, the overlay and pictures from `STAGES.DAT`; the overlay reloaded when clobbered; `EinResetDisplay` at the end of a display reset |
| `frontend.asm` | `EinScreensEnter`, `EinFrontOn`; the joystick's options text |

## 15. Building

`make einstein` builds `build/einstein/speedrun.dsk` in three steps around the assembly.

1. **`gen`:** `tools/make_einstein.py gen` writes:
   - the caches' addresses (`packs.asm`);
   - every stage pack's source (`stagepacks.asm`);
   - the art (`art_*.bin`, through `einstein_art.py` and `einstein_illustration.py`);
   - the objects and the Spider (`einstein_objects.asm`, `spider.asm`);
   - the tune's notes.
2. **`dat`:** after the packs are assembled, `dat` writes `stages_raw.dat` (every pack and
   picture, each from a 128-byte record of its own, with room for the front end and the
   overlay), `stages.asm` (the stage table: each pack's first record and length) and
   `screens_data.asm`.
3. **`patch`:** after the game is assembled (`-DEINSTEIN=1`, `build/einstein` last on the
   include path, because sjasmplus 1.21 searches the last `-I` first), `patch` puts
   `frontend.bin` and `stageov.bin` into `STAGES.DAT`. `tools/make_einstein_disk.py` then
   writes the disc: XtalDOS 1.31's system tracks, `SPEEDRUN.COM` and `STAGES.DAT`.

These need the einstein repository (`EINSTEIN_REPO` in `local.mk`).

Assembly options (`-D`):

| Option | Does |
|---|---|
| `FIXED_ELAPSED=1` | Every update counts 3 TV frames: the same game at any speed (the benchmark) |
| `EIN_MIN_FRAMES=3` | The 12.5 fps lock off, to measure the work alone |
| `EIN_DEBT=n` | The TV frames late a frame may be made up by (4; 0: never, every frame at least 4 apart) |
| `EIN_BLOCKS` | The block kerbs: ready-made edges, the outer edge on a cell's edge (12.45 fps in the attract demo, against 11.7) |
| `EIN_KERB2` | The exact kerbs in 2-line steps, not 4 (11.1 fps; no longer fits: bank 2 overflows) |
| `EIN_SLOPE=n` | With `EIN_BLOCKS`: the near rows' kerbs drawn exactly where they slope more than n pixels (4: the look before the speed cut) |
| `EIN_DASH` | With `EIN_BLOCKS`: the centre line's sprites (none by default) |
| `EIN_KERB`, `EIN_KERB4` | (set by `platform.asm` unless `EIN_BLOCKS`; `EIN_KERB4` unless `EIN_KERB2`): the exact kerbs, in 4-line steps; slots of 11 bytes, 11 a row in rows 12-15, the ready-made rows' code left out |
| `AUTOPLAY=1` | The demo driver plays the game (tunnels, forks, later stages) |
| `FIRST_STAGE=n`, `START_POS=units` | Start on another stage, or further along it |

After a build with options, `touch src/main.asm` so `make` builds the normal one again.

## 16. Testing and measuring

`make test-einstein` builds the harness if needed (`tests/einstein/build_harness.cmd`,
Visual Studio's C++ tools, Albert's `ein_core.lib`) and runs `tests/einstein_check.py`. It
checks that:

- the game boots;
- the attract demo runs at a reasonable rate (at least 7 fps);
- a key starts a game, and the clock, the car and the sound work;
- no VRAM access comes too fast;
- every stage's native sky and panorama are right in VRAM.

The harness (`build/einstein/speedrun_check.exe <rom> <dsk> <sym> commands...`, listed in
its header) runs commands after booting the disc:

- `profile N` and `profilel N` give each routine's T-states over N TV frames;
- `fliphist N` gives the TV frames between frames sent;
- `fastpc N` shows where VRAM writes came too fast;
- `linehist SYM N` counts how often an address is reached;
- `linereg SYM N` counts, at each time an address is reached, register C and the raster
  line (`EinUpload.row+4`: each road row's first write);
- `wait16 GameFrames N` with `shot` takes a picture at a given game frame;
- `rshot FILE` and `rrecord N PREFIX` take the picture as the raster drew it (what a
  television shows: `Machine::presented`), where `shot` and `record` draw VRAM as it is.
  Where a frame's `rrecord` and `record` differ, VRAM was written while the raster drew it.

**The benchmark.** Assemble with `-DFIXED_ELAPSED=1` (and `-DEIN_MIN_FRAMES=3` for the
work alone). Boot, `wait16 GameFrames 20`, then `wait16 GameFrames 320`: it prints the TV
frames that 300 game frames took. Figures are in [port_einstein.md](port_einstein.md)
section 6.

**Checking a change pixel for pixel.** With `-DFIXED_ELAPSED=1` the game is the same at any
speed. So take pictures at the same game frames (for instance every tenth, from 25 to 315)
from the change and from a reference build, and compare them. For tunnels and forks, use
`-DAUTOPLAY=1` with `-DFIRST_STAGE=3 -DSTART_POS=10200` (the first alpine tunnel) or
`-DSTART_POS=26500` (stage 1's fork). A difference that lasts one frame only can be timing
(a tunnel's sky changes over several TV frames), not drawing.

## 17. Rules and pitfalls

- **The Spectrum build stays byte-identical.** Check it after touching a shared file.
- **Never write screen A during play.** It holds the overlay and the Einstein's buffers.
  Anything kept there must be remade by the display reset.
- **Every covered cell in rows 10-23 is read each frame** (`EinSprMask` clears it). A path
  that skips one leaves its pixels in screen B, where a later silhouette would XOR over
  them.
- **VRAM:** with the picture on, keep accesses 32 T apart. In the interrupt, write through
  `EinWrite`, `EinFill` or `EinSendRun`, which follow `EBudget`. Keep interrupts off only
  briefly: a late frame interrupt leaves less of the blank.
- **Registers:**
  - The interrupt saves AF, BC, DE, HL, IX and IY but not the alternate set, so the main
    code may use `exx` but the interrupt must not.
  - `FillA` uses AF'.
  - `ldi` decrements BC.
- **Alignments the code relies on** (asserted):
  - `EPat` (64-aligned);
  - `ELines` and `ELines2` (no page crossed);
  - `ESlD`/`ESlE` (one page);
  - `EObjectUpper`, `EObjectLower` (page-aligned);
  - `ECarCol` (8-aligned);
  - `OutiEnd` and `XorEnd` (page-aligned);
  - `EMaskN` (one page) and `EMaskU` (page-aligned);
  - `EBitTab` (one page);
  - `RMask` and `LMaskIncl` (one page).
- **Self-modifying code:**
  - immediates patched at run time: `RunCommand.clipY`, `EinSlopeRow`'s run constants,
    `EinWrite`'s chain entry;
  - an IX displacement reaching across buffers: `EinDashRedo`'s Â±96 from `EMaskPOld`.

  Keep the patched instructions' layout when editing them.
- **Space:** check the assertions' areas (section 3) before adding code. Code that runs
  only at a display reset can go in the bank-2 room at $B900. Data rebuilt at every reset
  can go in screen A's free tail.
