# ZX Racer

An original pseudo-3D arcade road racer for the **ZX Spectrum 128K**, inspired by
the late-80s sprite-scaling coast-road racers.

See **[PLAN.md](PLAN.md)** for the full technical design and milestone plan.

## Building

Requires [sjasmplus](https://github.com/z00m128/sjasmplus) (1.20+) on your `PATH`.

```sh
make        # -> build/zxracer.sna (128K snapshot)
make run    # launches Fuse in 128K mode
```

## Layout

```
src/     Z80 assembly source
tools/   Python asset and table generators
assets/  Source graphics, track descriptions, music
docs/    Technical notes
```

## Status

Milestone 0 (toolchain & skeleton).
