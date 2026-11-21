# Porting Speed Run to the Tatung Einstein

A plan, not a commitment: what carries over, what has to be rebuilt, and in
what order. The Einstein is less documented than the Spectrum or the CPC:
facts marked *(verify)* need checking against the Einstein's technical
manual (or a working machine or emulator) before the work that depends on
them starts.

## 1. Target

- **Machine:** Tatung Einstein TC-01: 64K RAM, a TMS9129 video chip with
  its own 16K, an AY sound chip, a built-in 3" disc drive.
- **Media:** a disc image only (the Einstein has no tape port).
- **Frame rate:** 25 fps where possible, 16.7 fps at worst, as on the
  Spectrum. The video chip makes this harder: see §5.

## 2. The two machines side by side

| | Spectrum 128 (now) | Tatung Einstein |
|---|---|---|
| CPU | Z80 3.55 MHz | Z80 4 MHz |
| Screen | 256×192 in main memory, colour per 8×8 cell | 256×192 in the video chip's own 16K (Graphics II), colour per **8×1** pixels; reached only through I/O ports |
| Colours | fixed 15 | fixed 15 (TMS9129 palette), no palette changes |
| Sprites | none (all software) | 32 hardware sprites, one colour each, 16×16 (or 32×32 magnified), at most **4 on a line** |
| Double buffering | two screens, port $7FFD | the name table's base can be switched; the pattern and colour tables cannot (§5) |
| Memory | 128K, banked | 64K, no banking, but the screen is not in it |
| Sound | AY at 1.7734 MHz | AY at about 2 MHz *(verify)* |
| Interrupt | 50 Hz, IM 2 | Z80 CTC timers (IM 2); the video chip's frame interrupt may not reach the CPU *(verify)* |
| Storage | tape (turbo loader) | 3" disc, Xtal DOS |

## 3. What carries over unchanged

As for the CPC (docs/port_cpc.md §3):
- the game logic and the road's shape pass;
- scenery projection, tunnels, traffic and the fork;
- the music sequencer and every tune;
- the stage data, its tools and zpack.

## 4. Step 0: the platform layer

The same split as in the CPC plan (docs/port_cpc.md §4), with
`PLATFORM=EINSTEIN`: screen, road output, sprites, HUD, sound out, input,
interrupt, paging and loading behind one interface. The Spectrum build stays
byte-identical, checked by the existing tests.

## 5. Graphics: the name table does the work

The video chip's own memory is reached one byte at a time through a port.
During the visible part of the frame it accepts a byte only every 8 µs or
so (about 32 T-states), and much faster in the vertical blank. So the
Spectrum's approach, writing bitmap and attributes directly, would be
limited to about 2,000 bytes a frame in total. The port has to write as
little as possible. Graphics II mode gives the tool for that:

- **Graphics II** is a 32×24 grid of cells. Each cell shows one of 256
  patterns (8×8 pixels), with a foreground/background colour for each of
  its 8 lines. There are 256 patterns for each third of the screen.
- **Shared solid cells:** most of the road area is solid colour: light
  grass, dark grass, road, tunnel wall, sky, and both colours of kerb. Each
  is one pattern, defined once. A cell becomes "dark grass" by writing
  **one name-table byte**, not 16 bytes of pattern and colour. This is the
  Spectrum's attribute trick, done with the name table instead.
- **Edge cells:** only cells that a road edge, kerb boundary or the centre
  line passes through need their own pattern. Each gets a dynamic pattern
  slot: 8 pattern bytes, then 8 colour bytes, with the kerb colours exact to
  the line (better than the Spectrum's whole-cell kerb colour). That is
  roughly 2 edges × 12 rows × 1-2 cells, plus the centre line: about 50
  cells, 800 bytes a frame, and fewer when the shape does not change.
- **Bands:** the grass and kerb bands stay per character row as on the
  Spectrum (`RowAttrs` becomes "choose the row's solid patterns").
- **Double buffering:** two name tables, flipped by the name-table base
  register at the frame's end, so the picture never tears. Dynamic pattern
  slots are split in two sets, one per buffer, so the buffer on show is
  never changed. Each third has 256 patterns: about 20 shared solids, then
  two sets of about 110 slots.
- **Writes in cell order:** a pattern's 8 bytes are 8 *lines* of one cell,
  so drawing works cell by cell (build the 8 lines, then send them in one
  run), not line by line as on the Spectrum.

VRAM budget (16K): patterns 6K, colours 6K, two name tables 1.5K, sprite
patterns 2K (64 patterns of 16×16), sprite attributes 128 bytes. That fits,
just.

### Backdrop and sky

- The mountain band is two rows of cells. Its scrolling uses pre-shifted
  pattern sets: 4 shifts of a 32-cell band is 128 patterns. Scrolling then
  means rewriting 64 name bytes, not 512 bitmap bytes. The upper third's
  patterns are otherwise unused, so there is room.
- The sky is solid cells; tunnel ceilings and portals are name changes.

### Sprites

Use the hardware where it helps, and software for the rest:

- **Traffic cars:** hardware sprites, two each (body colour and black
  details), from pre-scaled sizes in the sprite pattern table. A traffic car
  uploads 32-64 bytes when it changes size. Five cars at most, two
  sprites each, is 10 of the 32.
- **The player's car:** it sits low and nearly still on the screen, so it
  is mostly static cells with their own patterns (uploaded once per
  steering pose), with up to 4 hardware sprites on top for extra colours.
  The 4-a-line limit is spent there, so traffic sprites must not share the
  car's lines: traffic near the car falls back to software cells, or
  overlaps for only a frame or two.
- **Scenery** (trees, signs, houses, the goal's gantry): software, drawn
  into dynamic cells like the road's edges. They gain colour per 8×1 line,
  where the Spectrum has one per cell.
- `make_scenery.py` and `make_car.py` emit cell-organised data (8 vertical
  bytes a cell), plus sprite patterns for the traffic.

### HUD and text

The HUD rows are cells with the font as patterns: a digit or letter is one
name byte, so the HUD is nearly free. The big timer digits become 2×2 cell
glyphs.

## 6. Sound

The same AY chip, so the music needs only:

- **the clock** *(verify: about 2 MHz)*: set `AY_CLOCK` in
  `make_music.py`, and scale the drum periods and engine pitch from it;
- **`AyWrite`:** the Einstein's AY register and data ports *(verify the
  addresses)*;
- **timing:** music at 50 Hz from a CTC timer interrupt, or from the
  video chip's frame interrupt if it is wired *(verify)*.

## 7. Input

- The keyboard matrix is read partly through the AY's I/O port *(verify
  which port selects the row and which reads the keys)*.
- The joystick ports are analogue *(verify)*: read them through the ADC and
  threshold them into the same left/right/up/down/fire bits that
  `ReadInput` produces now.

## 8. Memory

The Einstein has 64K and no banks. That is less memory than the Spectrum,
but the screen does not live in it, which frees the 13.8K the Spectrum
spends on two screens.

| Range | Use |
|---|---|
| $0000-$00FF | interrupt vectors (the ROM paged out after loading) |
| $0100-$7FFF | code and tables (about 30K on the Spectrum today) |
| $8000-$A7FF | the theme cache (9.4K) and the track cache |
| $A800-$FFFF | packed stage data, or a disc buffer (§9) |

The Spectrum keeps about 76K of stage, theme and front-end packs in its
banks. They will not all fit raw in 22K. Two ways, decided by measuring:

1. **Keep them compressed in memory:** zpack the theme and track packs
   (expect about half size, so 35-40K) and unpack one at each checkpoint, as
   the tape does now. If the packed set fits in about 22K, the game never
   touches the disc after loading.
2. **Load from disc at each checkpoint:** read the next stage's theme and
   track pack (about 10K) at the stage change: a second or two from a 3"
   disc. The stage change shows "Loading..." over the frozen frame. This is
   simpler and always fits.

Start with option 2; move to 1 if the packed sizes allow.

## 9. Loading

A disc image with a boot program for Xtal DOS. It loads the code and the
front end, pages the ROM out, and takes over the machine (interrupts, CTC,
video chip). The packs are separate files on the same disc (option 2
above). Build it with a `make_dsk.py` beside `make_tap.py`.

## 10. Tools and tests

- **Emulator:** an Einstein mode for `tools/zxsim` (or a headless emulator
  with scripting). It needs the TMS9129 Graphics II mode and sprites, VRAM
  port timing (to catch writes that come too fast), the AY, the CTC, the
  keyboard and a disc trap. That is about 1,500 lines of C. Port timing is
  the important part: on real hardware, writes that arrive faster than the
  chip accepts are simply lost.
- **Tests:** smoke, carcheck, stagecheck and a rendercheck from Graphics II
  screenshots, all for `PLATFORM=EINSTEIN`, plus a test that counts VRAM
  writes per frame and fails over budget.

## 11. Phases

| Phase | Work | Size |
|---|---|---|
| 0 | the platform layer (shared with the CPC port) | M |
| 1 | Einstein emulation in zxsim, with VRAM timing checks | L |
| 2 | boot from disc, memory map, CTC interrupt, video chip set-up, input | M |
| 3 | the road in Graphics II: solid cells, edge cells, two name tables | L |
| 4 | the backdrop's pre-shifted patterns, the HUD from font cells | M |
| 5 | traffic as hardware sprites, the car, software scenery cells | L |
| 6 | sound (clock and ports), front end screens, options | M |
| 7 | stage changes from disc (or packed memory), tunnels and gantries | M |
| 8 | the disc image and packaging, speed tuning, playtesting | M |

## 12. Risks and open questions

- **VRAM bandwidth** is the hard limit. Every frame's writes must fit about
  2,000 slow bytes plus the faster vertical blank. Busy frames (sharp bends,
  hills, the fork) may drop to 12.5 fps unless the edge cells are clever
  (for example, reuse an identical edge pattern instead of uploading a new
  one).
- **The 4-sprites-a-line limit:** traffic beside the player's car may
  flicker or vanish. Rotating sprite priorities each frame (the usual
  TMS9918 trick) turns vanishing into flicker.
- **Fixed colours:** 15 fixed TMS colours. The themes need re-picking (the
  TMS palette has good greens and blues, but no orange: the sunset theme
  needs care).
- **Hardware details** *(verify)*: the AY's clock and ports; the keyboard
  scan; the analogue joysticks; whether the video chip's frame interrupt
  reaches the Z80; how Xtal DOS hands over the machine; the 3" disc's read
  speed for option 2.
- **Few users and emulators:** testing on real hardware will need a
  helper with an Einstein. A scriptable emulator matters even more here
  than for the CPC.
