#!/usr/bin/env python3
"""Profile ZX Racer using the PROFILE border bars logged by zxsim.

Each phase of the main loop sets a border colour; this script turns the
border-change log into average T-states per phase per game frame.
"""
import subprocess, sys
from collections import defaultdict

PHASES = {1: "logic", 2: "road", 3: "sprites", 4: "hud", 0: "wait/flip"}
FRAME_T = 70908


def main():
    zxsim, sna = sys.argv[1], sys.argv[2]
    frames = int(sys.argv[3]) if len(sys.argv) > 3 else 300
    keys = sys.argv[4:] or ["-k", "0:Q", "-k", "100:Q+P", "-k", "200:Q+O"]
    out = subprocess.run([zxsim, sna, "-n", str(frames), "-b", "40"] + keys,
                         capture_output=True, text=True, check=True).stdout
    events = []
    for line in out.splitlines():
        if line.startswith("border"):
            f = dict(kv.split("=") for kv in line.split()[1:])
            events.append((int(f["frame"]) * FRAME_T + int(f["T"]), int(f["colour"])))
        elif line.startswith("frames="):
            summary = line
    totals = defaultdict(int)
    loops = 0
    for (t0, c), (t1, _) in zip(events, events[1:]):
        totals[c] += t1 - t0
        if c == 1:
            loops += 1
    loops = max(loops - 1, 1)
    print(summary)
    print(f"{loops} game frames profiled; average T-states per game frame:")
    busy = 0
    for c, total in sorted(totals.items(), key=lambda kv: -kv[1]):
        avg = total // loops
        if c != 0:
            busy += avg
        print(f"  {PHASES.get(c, f'colour {c}'):10s} {avg:8d}")
    print(f"  {'busy':10s} {busy:8d}  (25 fps budget 141816, 16.7 fps budget 212724)")


if __name__ == "__main__":
    main()
