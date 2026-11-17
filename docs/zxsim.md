# zxsim — headless 128K emulator for testing and profiling

`tools/zxsim/zxsim.c` is a small, dependency-free ZX Spectrum 128K emulator written
for this project. It is not a playable emulator. It exists so that every change can
be checked automatically: screenshots, frame rate, and exact cycle counts.

- Z80 core (documented instructions plus IXH/IXL/IYH/IYL and SLL), checked by
  `tests/cputest.asm`.
- 128K paging via `$7FFD`, shadow screen (bank 7), approximate memory contention
  using 128K timings (70,908 T per frame, 228 T per line).
- IM1/IM2 interrupts at the start of each frame. No ROM is loaded (the game never
  uses it), and execution entering `$0000-$3FFF` is reported as an error.
- Screen and border are captured line by line, so tearing and border timing bars
  show up in screenshots exactly as on hardware.

```
zxsim game.sna [options]
  -n N            run N frames (default 50)
  -s F:file.ppm   screenshot at the end of frame F (repeatable)
  -k F:KEYS       from frame F hold KEYS, e.g. Q+P, none (repeatable)
  -j F:BITS       from frame F set Kempston bits (1 R, 2 L, 4 D, 8 U, 16 F)
  -b F            log every border write (frame, T, colour) from frame F
  -p F:file       from frame F accumulate T-states per PC into file
  -w ADDR[:N]     print registers the first N times PC reaches ADDR
  -d ADDR:LEN     hex-dump memory at exit
  -q              no summary line
```

The summary line reports `flips` (writes to `$7FFD` that change the displayed
screen), so `fps = flips × 50 / frames`.

`tools/profile.py` turns the border log into T-states per phase; `tools/hotspots.py
profile.txt build/zxracer.sym N` groups a `-p` profile by routine and local label.
