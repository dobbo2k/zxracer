# ZX Racer

An original pseudo-3D arcade road racer for the **ZX Spectrum 128K**, inspired by
the late-80s sprite-scaling coast-road racers.

See **[PLAN.md](PLAN.md)** for the full technical design and milestone plan.

## Building

Requires [sjasmplus](https://github.com/z00m128/sjasmplus) (1.20+) on your `PATH`,
Python 3 with Pillow, and a C compiler (for the test emulator).

```sh
make          # -> build/zxracer.sna (128K snapshot, with border timing bars)
make tap      # -> build/zxracer.tap: the tape release (no timing bars)
make test     # Z80 core self-test, headless runs with screenshots in build/, tape load
make profile  # T-states per phase per game frame (border timing bars)
make run      # launches Fuse in 128K mode
make video    # build/gameplay.mp4: 48 s of autopilot gameplay with synthesised AY sound
```

**Loading the tape:** on a 128K / +2 / +2A / +3 choose *Tape Loader* (or type
`LOAD ""`) and play `build/zxracer.tap`. A BASIC loader loads a small machine-code
loader, which reads the rest with its own tape routine (standard blocks at the
normal speed, no ROM calls): the loading screen, then the game's memory banks,
compressed - about 6½ minutes. Emulators' instant "flash load" only speeds up the
first two blocks; use the emulator's fast-forward / turbo tape option for the rest.
On a 48K Spectrum it stops with "128K ONLY"; if a block fails to load it says
"TAPE ERROR, BLOCK n". `build/release.sna` is the same game as
a snapshot.

Controls: **O/P** steer, **Q** accelerate, **A** brake, **SPACE** change gear
(LOW / HIGH), or a Kempston joystick (fire changes gear).
The game opens on the title screen, then alternates it with a self-driving
demo; any of the game keys starts a game.

## Layout

```
src/          Z80 assembly source (main loop, interrupts/flip, road renderer, input, player)
tools/        gen_tables.py, profile.py, hotspots.py, zxsim/ (headless 128K emulator)
tests/        cputest.asm (Z80 core self-test), smoke.py (headless run + screenshot checks)
assets/       stages.yaml (themes, palettes, the stage pyramid), generated artwork
docs/         Technical notes
```

## Status

Playable prototype. Start it in Fuse (`make run`) or any 128K emulator with
`build/zxracer.sna`. Attract mode drives itself; press any key to start a game.

- **Road:** pseudo-3D road with red/white attribute kerbs (no colour clash),
  light/dark grass bands, centre line, curves that build up in the distance,
  and hills: climbs, dips and crests the road (and the cars and scenery on it)
  disappears behind.
- **Car:** original convertible sprite with steering frames, braking and
  off-road slowdown. Its crew: him (mullet, shades, loud striped 80s shirt)
  at the wheel and her (big blonde hair) beside him. After a crash, close-ups
  of the two of them appear while the car spins: she tells him off ("< NICE
  ONE, GENIUS!"), he answers back ("IT JUMPED OUT! >"). Handling has sideways momentum: bends push the car
  outwards, steering builds up and the car carries its drift out of a bend.
  Past the tyres' grip limit (sharp bend × high speed) it slides wide, steers
  half as well and scrubs speed off: brake or ease off for the sharp bends of the
  later stages. You can see it: on a fast bend the car yaws into it, and near the
  grip limit it swings further round with light smoke from both rear tyres.
- **Gears:** two, like an arcade shifter. LOW pulls hard but tops out at 182 km/h;
  HIGH reaches 280 km/h but bogs down from a standstill. Start in LOW, change up
  around 180; the engine note drops as you do, and the HUD shows the gear.
- **Scenery:** palm trees and curve-warning signs along the track (XOR-drawn,
  pre-scaled, pre-shifted) and a mountain panorama that scrolls with the bends.
- **Stages:** 15 stages in a 5-row pyramid across 5 themes (Sunny Coast, Desert
  Highway, Alpine Pass, Green Valley, Sunset Boulevard), each with its own scenery,
  mountain backdrop and colours. At the end of a stage the road really forks:
  it widens, a median opens and two branches pull apart, and the branch you
  drive down picks the next stage (left or right in the next row). Checkpoints
  add time; the last row ends at the GOAL.
- **Game:** HUD with score, stage, big countdown timer and speed; game over,
  attract mode.
- **Title and goal screens:** a title screen (logo, sunset, high score) between
  demo runs, and five goal scenes, one for each route's last stage, that count
  the time left into the score as a bonus (1000 points a second). All artwork is
  drawn by `tools/make_screens.py` (previews in `assets/gfx/screen_*.png`).
- **Traffic:** cars in two lanes. Running into one from behind slows you right
  down; driving into a palm off the road is a crash that stops you and spins the
  car. The attract-mode driver changes lane to avoid traffic.
- **Sound:** AY engine note that follows the speed, gravel noise off-road, tyre squeal.
- **Speed:** locked at 16.7 fps; sharp bends with traffic still drop some frames to
  12.5 fps (PLAN.md §3.6).
- **Next:** a performance pass, then more scenery and music. See PLAN.md §7.
