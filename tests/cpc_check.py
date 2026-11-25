#!/usr/bin/env python3
"""make test-cpc: the Amstrad CPC build in MAME (docs/port_cpc.md section 7).

    python tests/cpc_check.py DISK SYMBOLS OUTDIR

- the disc boots (RUN"SPEED") to the title, and the attract demo runs;
- SPACE starts a game: GameState playing, the clock running;
- the AY log: the engine at its 1 MHz period, the tune playing, and the
  mixer never with bit 6 set (the PPI's port A must stay an input: the
  keyboard);
- every stage loads (the demo on each, CStageReq), a screenshot of each in
  OUTDIR/stage_NN.png;
- the Spectrum's tape is still the release's (build/speedrun.tap, if built).
"""
import filecmp
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import cpc_harness as h  # noqa: E402

ENGINE_IDLE = (1400 * 564 + 500) // 1000      # src/sound.asm at 1 MHz
NUM_STAGES = 15


def fail(text):
    sys.exit(f"cpc_check: {text}")


def main(disk, sym, outdir):
    disk, sym, outdir = Path(disk), Path(sym), Path(outdir)
    folder = outdir / "check"
    # ---- boot, the title, the demo; a game; the AY
    r = h.run("ay on", *h.boot(), "frames 300", "peek8 gs0 GameState", "peek8 dm0 DemoMode",
              "shot title", "untilw GameFrames 200 6000", "peek16 gf0 GameFrames", "shot demo",
              "hold SPACE", "frames 10", "release", "frames 400", "peek8 gs1 GameState",
              "peek8 dm1 DemoMode", "peek16 gf1 GameFrames", "hold Q", "frames 150", "release",
              "peek8 speed Speed", "shot game", "ay log",
              disk=disk, sym=sym, folder=folder, timeout=1200)
    if int(r["gf0"]) < 200:
        fail(f"the attract demo did not run (GameFrames {r['gf0']})")
    if r["gs1"] != "1" or r["dm1"] != "0":
        fail(f"SPACE did not start a game (GameState {r['gs1']}, DemoMode {r['dm1']})")
    if int(r["speed"]) == 0:
        fail("Q did not move the car")
    writes = [tuple(map(int, w.split("."))) for w in r["log"].split(",") if w]
    regs = {}
    for _frame, reg, value in writes:
        regs.setdefault(reg, []).append(value)
    if any(v & 0x40 for v in regs.get(7, [])):
        fail("the AY's mixer turned port A to an output")
    periods = set(zip(regs.get(0, []), regs.get(1, [])))
    if not any(abs((lo | hi << 8) - ENGINE_IDLE) < 40 for lo, hi in periods):
        fail(f"no engine note near period {ENGINE_IDLE}")
    if len(regs.get(10, [])) < 20 and len(regs.get(9, [])) < 20:
        fail("the tune's channels were not written")
    for name in ("title", "demo", "game"):
        shutil.copy(folder / f"{name}.png", outdir / f"cpc_{name}.png")
    # ---- every stage (a boot each five: the demo goes back to the title in time)
    for first in range(0, NUM_STAGES - 1, 5):
        group = range(first, min(first + 5, NUM_STAGES - 1))
        cmds = list(h.boot()) + ["untilw GameFrames 20 6000"]
        for st in group:
            cmds += [f"poke8 CStageReq {st + 1}", "frames 200", f"peek8 s{st} Stage",
                     f"peek16 g{st} GameFrames", "frames 60", f"peek16 h{st} GameFrames",
                     f"shot stage_{st:02}"]
        r = h.run(*cmds, disk=disk, sym=sym, folder=folder, timeout=1200)
        for st in group:
            if r[f"s{st}"] != str(st):
                fail(f"stage {st} did not load (Stage {r[f's{st}']})")
            if int(r[f"h{st}"]) <= int(r[f"g{st}"]):
                fail(f"stage {st}: the game stopped")
            shutil.copy(folder / f"stage_{st:02}.png", outdir / f"stage_{st:02}.png")
    # ---- the Spectrum's tape
    tap, release = ROOT / "build" / "speedrun.tap", ROOT / "release" / "speedrun.tap"
    if tap.exists() and not filecmp.cmp(tap, release, shallow=False):
        fail("build/speedrun.tap differs from release/")
    print(f"cpc_check: passed (the demo, a game, the AY, {NUM_STAGES - 1} stages)")


if __name__ == "__main__":
    main(*sys.argv[1:4])
