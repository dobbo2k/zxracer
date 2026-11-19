#!/usr/bin/env python3
"""Stages: attract mode must drive through the forks into later rows, and
an autopilot game (AUTOPLAY build) must reach the goal and return to attract
mode on stage 1.
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
    s = syms(symfile)
    vals = {}
    for n in names:
        r = subprocess.run([zxsim, snap, "-n", str(frames), "-q", "-d", f"{s[n]}:1"] + extra,
                           capture_output=True, text=True, check=True)
        if "entered ROM" in r.stderr:
            sys.exit(f"FAIL: {snap} crashed: {r.stderr.strip()}")
        vals[n] = int(r.stdout.split()[0], 16)
    return vals


ok = True
v = run(sna, sna.replace(".sna", ".sym"), 9000, [], ["StageRow"])
print(f"attract mode after 9000 frames: row {v['StageRow']}")
if v["StageRow"] < 4:
    print("FAIL: attract mode did not get through the forks")
    ok = False
keys = ["-k", "250:Q", "-k", "256:none"]
v = run(video, video.replace(".sna", ".sym"), 10000, keys, ["GameState", "StageRow", "Time"])
print(f"autopilot game after 10000 frames: state {v['GameState']} row {v['StageRow']} time {v['Time']:02X}")
if not (v["GameState"] == 2 and v["StageRow"] == 5 and v["Time"] > 0):
    print("FAIL: the autopilot did not reach the goal in time")
    ok = False
v = run(video, video.replace(".sna", ".sym"), 11000, keys, ["GameState", "StageRow"])
if not (v["GameState"] == 0 and v["StageRow"] == 1):
    print(f"FAIL: no return to attract mode on stage 1 after the goal ({v})")
    ok = False
print("stagecheck: " + ("passed" if ok else "FAILED"))
sys.exit(0 if ok else 1)
