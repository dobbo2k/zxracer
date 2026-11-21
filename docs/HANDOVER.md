# Handover: from the cloud to a local machine

Speed Run, an original Outrun-style racer for the ZX Spectrum 128K, was
built so far in a **Claude Code cloud session**: a Linux container with no
access to the owner's computer. The owner now wants to work **locally**, in
`C:\ZX Spectrum\Speed Run`, so that sessions can use the emulators and tools
installed on that machine. This note is what a new session needs to carry
on.

## Where things stand

- **Repository:** `dobbo2k/zxracer`, branch `ccr-1843f024-sdqgs9`.
  Everything below is committed and pushed there.
- **The game is complete and playable:**
  - 15 stages in a 5-row branching pyramid, 5 themes;
  - traffic, crashes, the fork, hills, Alpine tunnels, a goal gantry;
  - stage times, extended play, 3 difficulty levels, high scores and
    stage records;
  - music for each theme, and an engine-sound option.
- **Release files are in `release/`:**
  - `speedrun.tap` (standard loader, about 6 minutes);
  - `speedrun.tzx` (turbo loader, about 3 minutes);
  - `README.txt`;
  - the cover, the cassette inlay (outside and inside) and the route-map
    leaflet.
- **Documentation:**
  - `README.md`: an overview of the game and how it is built;
  - `PLAN.md`: the design, with notes on every feature "as built", and the
    memory and performance budgets;
  - `docs/zxsim.md`: the test emulator's options;
  - `docs/port_cpc.md` and `docs/port_einstein.md`: port plans for the
    Amstrad CPC and the Tatung Einstein.

## How it was built in the cloud

| Tool | Version used | For |
|---|---|---|
| sjasmplus | 1.21.0 | assembling (`src/main.asm`, the loader, tests) |
| Python | 3.13 with Pillow 12, NumPy 2, PyYAML 6 | every generator in `tools/` (tables, stages, music, graphics, tape images) |
| GNU Make | 4.3 | the build (`Makefile`) |
| a C compiler | gcc 13 | `tools/zxsim` (the project's own emulator, below) |
| ffmpeg | 6.1 | videos (`tools/make_video.py`) |
| Node 22 with Playwright and Chromium | | rendering the cover and leaflet SVGs to PNG (`tools/make_cover.py`, `make_leaflet.py`) |

No real emulator was available. Instead the project has its own: **`zxsim`**
(`tools/zxsim/zxsim.c`, built by `make` into `build/zxsim`). It is a
headless Spectrum 128K with no ROM: it runs snapshots and `.tap` and `.tzx`
files with the project's own loader. It drives every test and gives
screenshots, key presses at given frames, memory watches and dumps, the AY
register log for audio, and video frames. `docs/zxsim.md` has its options.

**Main commands:**

```
make                      # build/zxracer.sna (the game) and its generated sources
make test                 # cputest, smoke, carcheck, stagecheck, tapecheck
make tap                  # build/speedrun.tap and build/speedrun.tzx
make release              # release/: tape files and the inlay
make video                # build/gameplay.mp4 (the autopilot plays, with sound)
make cover                # the cover art and the loading screen (needs Node and Playwright)
make leaflet              # the route-map leaflet
python3 tests/rendercheck.py save|check DIR   # pixel-exact rendering regression check
```

**Notes from the cloud work:**

- After a custom assemble with `-D` options (for example
  `-DFIRST_STAGE=6 -DAUTOPLAY=1`, used to record a given stage), run
  `touch src/main.asm` so `make` rebuilds the normal snapshots.
- `build/video.sna` is the autopilot build (it plays itself); the tests and
  videos use it.
- Memory is nearly full. Each region's free space is checked by `ASSERT`s:
  - bank 5: about 11 bytes free;
  - the main code area: 0 bytes;
  - the small gaps in the table pages (`src/holes.asm`).

  `PLAN.md` and the commit history explain what was moved where to make
  room.
- Commits end with two trailer lines: `Co-Authored-By:` and the session
  link.
- Some actions were refused in the cloud and were not worked around:
  - installing pip packages;
  - installing `spectrum-roms`;
  - pushing a git tag. Make the v1.0 release on GitHub's web page instead.

## Moving to the local machine

1. Clone into the chosen folder:
   ```
   git clone -b ccr-1843f024-sdqgs9 https://github.com/dobbo2k/zxracer.git "C:\ZX Spectrum\Speed Run"
   ```
2. On Windows, build under **WSL (Ubuntu)** or **MSYS2**. The Makefile
   and tools expect a Unix shell, `make`, `python3` and `cc`. Install the
   tools in the table above (sjasmplus can be built from source or taken
   from its releases). Then run `make` and `make test`: all five tests
   should pass.
3. Start Claude Code **in that folder** (the Claude desktop app, or
   `claude remote-control` there) so it can run local programs.

## What the local machine adds

- **Real emulators:** the game has only been tested in zxsim, which has no
  ROM and models the hardware only as far as the game needs. Check it on a
  full emulator, for example Fuse or ZEsarUX (Spectrum 128K, +2, +2A, +3):
  - load `release/speedrun.tzx` and `speedrun.tap` through the 128K ROM's
    tape loader;
  - check the 48K refusal message, the sound, the contended-memory timing
    and the frame rate against zxsim's.
- **An open report:** a tape loading problem was reported on a real
  machine, but which message and which model were never established. Use
  an emulator with real tape timing to look into it.
- **The port plans:** a CPC or Einstein emulator installed locally would
  serve the testing that `docs/port_cpc.md` and `docs/port_einstein.md`
  plan for (instead of, or alongside, extending zxsim).

Tell the new session which emulators are installed and where, so it can
run them from the build.
