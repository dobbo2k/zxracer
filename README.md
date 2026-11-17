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

## Layout

```
src/          Z80 assembly source (main loop, interrupts/flip, road renderer, input, player)
tools/        gen_tables.py, profile.py, hotspots.py, zxsim/ (headless 128K emulator)
tests/        cputest.asm (Z80 core self-test), smoke.py (headless run + screenshot checks)
assets/       Source graphics, track descriptions, music
docs/         Technical notes
```

## Status

- **M0 (toolchain) done:** build, CI, and `zxsim`, our own cycle-counting headless
  128K emulator for tests and profiling.
- **M1 (road) working:** pseudo-3D road with red/white attribute kerbs, light/dark
  grass bands, centre line, double buffering with tear-free flips in the interrupt.
  Runs at 24 fps on straights and 17.7 fps under hard steering. Optimisation (M1b)
  is next; see PLAN.md §3.6.
