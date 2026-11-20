#!/usr/bin/env python3
"""Stages: attract mode must drive through the forks into later rows, and
an autopilot game (AUTOPLAY build) must reach the goal and return to attract
mode on stage 1 (after the end-of-game screens and the title). The autopilot takes
the left branch on even stages and the right one on odd stages, so it must
arrive on stage 0 -> 1 -> 4 -> 7 -> 12.
usage: stagecheck.py ZXSIM NORMAL.sna VIDEO.sna
"""
import subprocess
import sys

zxsim, sna, video = sys.argv[1:4]


def syms(path):
    out = {}
    for line in open(path):
        if ": EQU 0x" in line:
            name, val = line.split(": EQU ")
            out[name.strip()] = int(val, 16)
    return out


def run(snap, symfile, frames, extra, names):
    """One run: dump the memory spanning the named (byte) variables."""
    s = syms(symfile)
    lo = min(s[n] for n in names)
    hi = max(s[n] for n in names) + 1
    r = subprocess.run([zxsim, snap, "-n", str(frames), "-q", "-d", f"{lo}:{hi - lo}"] + extra,
                       capture_output=True, text=True, check=True)
    if "entered ROM" in r.stderr:
        sys.exit(f"FAIL: {snap} crashed: {r.stderr.strip()}")
    mem = [int(x, 16) for x in r.stdout.split()]
    return {n: mem[s[n] - lo] for n in names}


ok = True
v = run(sna, sna.replace(".sna", ".sym"), 12000, [], ["StageRow"])   # (with title / table breaks)
print(f"attract mode after 12000 frames: row {v['StageRow']}")
if v["StageRow"] < 4:
    print("FAIL: attract mode did not get through the forks")
    ok = False
keys = ["-k", "250:Q", "-k", "256:none"]
goal = None
for frames in range(8000, 16001, 100):     # (the goal screen lasts 200 frames)
    v = run(video, video.replace(".sna", ".sym"), frames, keys, ["GameState", "StageRow", "Stage", "Time"])
    if v["GameState"] == 2:
        goal = frames, v
        break
if goal:
    frames, v = goal
    print(f"autopilot game: goal by frame {frames}, stage {v['Stage']} (row {v['StageRow']}), "
          f"time left {v['Time']:02X}")
if not (goal and v["StageRow"] == 5 and v["Stage"] == 12 and v["Time"] > 0):
    print(f"FAIL: the autopilot did not reach the goal in time by the expected branches")
    ok = False
if goal:                                   # stage times: rows 1-4 recorded at the checkpoints
    s = syms(video.replace(".sna", ".sym"))
    r = subprocess.run([zxsim, video, "-n", str(goal[0]), "-q", "-d", f"{s['StageTimes']}:8"] + keys,
                       capture_output=True, text=True, check=True)
    b = [int(x, 16) for x in r.stdout.split()]
    times = [b[i] + 256 * b[i + 1] for i in range(0, 8, 2)]
    print("stage times (s): " + " ".join(f"{t / 50:.2f}" for t in times))
    if not all(1000 < t < 5000 for t in times):
        print("FAIL: the stage times were not recorded")
        ok = False
v = run(video, video.replace(".sna", ".sym"), (goal[0] if goal else 16000) + 4500, keys,   # (goal, route, initials, table, title, table)
        ["GameState", "StageRow"])
if not (v["GameState"] == 0 and v["StageRow"] == 1):
    print(f"FAIL: no return to attract mode on stage 1 after the goal ({v})")
    ok = False
print("stagecheck: " + ("passed" if ok else "FAILED"))
sys.exit(0 if ok else 1)
