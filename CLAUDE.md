# Speed Run: working on the local Windows machine

The game, its design and the build are described in `README.md`, `PLAN.md`
and `docs/HANDOVER.md` (the move from the cloud). This file covers the local
setup.

## Toolchain: MSYS2 (UCRT64)

Everything builds in MSYS2 at `C:\msys64`, UCRT64 environment:

| Tool | Where |
|---|---|
| make 4.4 | `/usr/bin/make` (MSYS2 package `make`) |
| gcc (cc) | `/ucrt64/bin` (`mingw-w64-ucrt-x86_64-gcc`) |
| Python 3.12 + Pillow, NumPy, PyYAML | `/ucrt64/bin/python3` (`mingw-w64-ucrt-x86_64-python-*`) |
| ffmpeg | `/ucrt64/bin` (`mingw-w64-ucrt-x86_64-ffmpeg`) |
| sjasmplus 1.21.0 | `C:\msys64\usr\local\bin\sjasmplus.exe` (the official Windows release) |

Not set up: Node with Playwright and Chromium (`make cover`, `make leaflet`).
Node is installed on Windows but is not on MSYS2's PATH, and Playwright is
not installed. The generated cover, loading screen and spine are committed,
so the other targets don't need it.

Running make:

- **From Claude Code's Bash tool (Git Bash):**
  `MSYSTEM=UCRT64 /c/msys64/usr/bin/bash.exe -lc 'cd "/c/ZX Spectrum/Speed Run" && make test'`
  (the explicit `cd` is needed: the login shell does not keep Git Bash's
  directory).
- **From PowerShell or cmd:** `.\make test` (PowerShell) or `make test`
  (cmd), using the `make.cmd` wrapper in the project root.
- **By hand:** the "MSYS2 UCRT64" terminal, then `cd "/c/ZX Spectrum/Speed Run"`.

`make` and `make test` (all five tests) pass. The local build of
`build/speedrun.tap` and `.tzx` is byte-identical to `release/`.

Windows notes:

- zxsim builds as `build/zxsim.exe`. The Makefile adds the `.exe` when
  `uname -s` contains `_NT`, and calls it as `./build/zxsim.exe`. Claude
  Code's PowerShell sets `NoDefaultCurrentDirectoryInExePath=1`, so a bare
  `build/zxsim.exe` would not launch from Python.
- This clone has `core.autocrlf=false` (repo-local config), so files keep
  their LF endings and the build matches the cloud's. Keep it that way.

## Emulators on this machine

| Emulator | Path | Machines |
|---|---|---|
| Fuse 1.6.0 | `C:\Program Files (x86)\Fuse\fuse.exe` | 48K, 128K, +2, +2A, +3 (ROMs included) |
| ZEsarUX 13.0 | `C:\Emulators\ZEsarUX_windows-13.0\zesarux.exe` (12.1 also in `C:\Emulators`) | all Spectrum models, CPC (no Einstein) |
| EightyOne | `C:\Emulators\EightyOne\EightyOne.exe` | ZX81 family, also Spectrum |
| WinAPE (CPC) | `C:\ZX Spectrum\Wonderboy\build\winape\WinApe.exe` | Amstrad CPC |
| MAME 0.288 | `C:\ZX Spectrum\Wonderboy\tools\vendor\mame0288\mame.exe` | CPC and Einstein drivers, but its `roms` folder is empty |

The Fuse and ZEsarUX paths are set in `local.mk` (ignored by git and read
by the Makefile):

```
make run                         # build/zxracer.sna in Fuse
make run-tape                    # build/speedrun.tzx through the 128K ROM loader, in Fuse
make run-tape TAPE=build/speedrun.tap MACHINE=plus2a
make run-tape FUSE_OPTS="--no-accelerate-loader --no-fastload --no-traps"   # real loading speed
make run-realtape                # ZEsarUX, the tape played as audio (real tape timing)
make run-realtape ZX_MACHINE=P341
```

Fuse machine names are `48`, `128`, `plus2`, `plus2a` and `plus3`. ZEsarUX's
are `48k`, `128k`, `P2`, `P2A41` and `P341` (`zesarux --help` lists all).

Screenshots of an emulator window: start it with `Start-Process -PassThru`,
wait, then capture `MainWindowHandle` with user32 `PrintWindow` (flag 2) in
PowerShell. `CopyFromScreen` gives a blank image when the window is covered.
Both Fuse and ZEsarUX (SDL) capture this way.

## Conventions

- Commits end with the `Co-Authored-By:` and session-link trailer lines.
- After a custom assemble with `-D` options, `touch src/main.asm` so make
  rebuilds the normal snapshots.
