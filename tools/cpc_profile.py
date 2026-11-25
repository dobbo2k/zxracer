#!/usr/bin/env python3
"""Profile the CPC port in MAME: where the time goes (from the Wonder Boy
port's tools/cpc_profile.py).

    python tools/cpc_profile.py [--frames N] [--after G] [--disk D --sym S]

Boots the disc, runs the attract demo to game frame G (GameFrames), then
traces N TV frames with MAME's debugger, each instruction with the CPU's
cycle count, and sums the time spent under each code label (the nearest at
or below the PC, from the build's symbols). The CPC's Z80 runs at 4 MHz,
its instructions stretched to whole microseconds: times are in
microseconds, 19,968 a TV frame.
"""
from __future__ import annotations

import argparse
import bisect
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import cpc_harness  # noqa: E402

FRAME_US = 19968
LINE = re.compile(r"^([0-9A-F]+) ([0-9A-F]{4}):")


def profile(frames: int, after: int, disk: Path, sym: Path, folder: Path) -> Counter:
    symbols = cpc_harness.symbols(sym)
    labels = sorted((a, n) for n, a in symbols.items()
                    if "." not in n and any(c.islower() for c in n) and a < 0xC000)
    addresses = [a for a, _ in labels]
    trace = folder / "trace.txt"
    trace.unlink(missing_ok=True)
    cpc_harness.run(*cpc_harness.boot(), f"untilw GameFrames {after} 8000",
                    f'debug trace {trace.as_posix()},maincpu,noloop,{{tracelog "%X ",totalcycles}}',
                    f"frames {frames}", "debug traceoff maincpu",
                    disk=disk, sym=sym, folder=folder, debug=True, timeout=3600)
    spent: Counter = Counter()
    previous = None
    with trace.open(errors="ignore") as lines:
        for line in lines:
            m = LINE.match(line)
            if not m:
                continue
            cycles, pc = int(m.group(1), 16), int(m.group(2), 16)
            if previous:
                spent[previous[1]] += cycles - previous[0]
            k = bisect.bisect_right(addresses, pc) - 1
            previous = (cycles, labels[k][1] if k >= 0 else "(low)")
    return Counter({n: t / 4 / frames for n, t in spent.items()})


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--frames", type=int, default=20)
    ap.add_argument("--after", type=int, default=60)
    ap.add_argument("--disk", type=Path, default=cpc_harness.DISK)
    ap.add_argument("--sym", type=Path, default=cpc_harness.SYMBOLS)
    ap.add_argument("--top", type=int, default=40)
    args = ap.parse_args()
    folder = ROOT / "build" / "cpc" / "profile"
    spent = profile(args.frames, args.after, args.disk, args.sym, folder)
    total = sum(spent.values())
    for name, us in spent.most_common(args.top):
        print(f"{name:28} {us:8.0f} us a TV frame {100 * us / total:5.1f}%")
    print(f"{'(all)':28} {total:8.0f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
