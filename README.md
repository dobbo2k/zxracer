# ZX Racer

An original pseudo-3D arcade road racer for the **ZX Spectrum 128K**, inspired by
the late-80s sprite-scaling coast-road racers.

See **[PLAN.md](PLAN.md)** for the full technical design and milestone plan.

## Building

Requires [sjasmplus](https://github.com/z00m128/sjasmplus) (1.20+) on your `PATH`,
Python 3 with Pillow, and a C compiler (for the test emulator).

```sh
make          # -> build/zxracer.sna (128K snapshot)
make test     # Z80 core self-test + headless smoke run with screenshots in build/
make profile  # T-states per phase per game frame (border timing bars)
make run      # launches Fuse in 128K mode
```

Controls: **O/P** steer, **Q** accelerate, **A** brake (or a Kempston joystick).
The game starts in attract mode and hands over when you steer.

## Layout

```
src/          Z80 assembly source (main loop, interrupts/flip, road renderer, input, player)
tools/        gen_tables.py, profile.py, hotspots.py, zxsim/ (headless 128K emulator)
tests/        cputest.asm (Z80 core self-test), smoke.py (headless run + screenshot checks)
assets/       Source graphics, track descriptions, music
docs/         Technical notes
```

## Status

Playable prototype. Start it in Fuse (`make run`) or any 128K emulator with
`build/zxracer.sna`. Attract mode drives itself; press any key to start a game.

- **Road:** pseudo-3D road with red/white attribute kerbs (no colour clash),
  light/dark grass bands, centre line, and curves that build up in the distance.
- **Car:** original convertible sprite with steering frames, centrifugal force,
  off-road slowdown and braking.
- **Scenery:** palm trees and curve-warning signs along the track (XOR-drawn,
  pre-scaled, pre-shifted) and a mountain panorama that scrolls with the bends.
- **Game:** HUD with score, big countdown timer and speed; extra time each lap,
  game over, attract mode.
- **Traffic:** cars in two lanes. Running into one from behind slows you right
  down; driving into a palm off the road is a crash that stops you and spins the
  car. The attract-mode driver changes lane to avoid traffic.
- **Sound:** AY engine note that follows the speed, gravel noise off-road, tyre squeal.
- **Speed:** locked at 16.7 fps; sharp bends with traffic still drop some frames to
  12.5 fps (PLAN.md §3.6).
- **Next:** a performance pass, then more scenery and music. See PLAN.md §7.
