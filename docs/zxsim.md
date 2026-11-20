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
  -a              print the AY registers at exit
  -v FILE         write every frame as raw RGB24 320x288 (video capture)
  -y FILE         write the 14 AY registers at the end of every frame
  -q              no summary line
  -T file.tap     tape boot instead of a snapshot (see below)
```

**Tape boot (`-T`).** zxsim has no ROM, so it does what the tape's BASIC loader
would: it loads the first CODE block to its address and calls it with the 48K BASIC
ROM's paging (bank 0 at `$C000`, `$7FFD` = `$10`). From then on a call to the ROM's
LD-BYTES (`$0556`) is served from the next tape block - flag, length and checksum
checked, carry set on success, interrupts re-enabled as the ROM does - and takes as
long as the block would take to play (pilot, sync, 855 / 1710 T pulses per bit, a
second's gap between blocks). `tests/tapecheck.py` uses it to load
`build/zxracer.tap` end to end.

The summary line reports `flips` (writes to `$7FFD` that change the displayed
screen), so `fps = flips × 50 / frames`.

`tools/profile.py` turns the border log into T-states per phase; `tools/hotspots.py
profile.txt build/zxracer.sym N` groups a `-p` profile by routine and local label.

`tools/make_video.py` pipes `-v` into ffmpeg and synthesises the `-y` register
log (square-wave tones, LFSR noise, AY volume table) into the soundtrack;
`make video` uses it on an `AUTOPLAY=1, PROFILE=0` build in which the
attract-mode driver also plays the game.
