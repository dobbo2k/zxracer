#!/usr/bin/env python3
"""Summarise a zxsim -p profile by routine using the sjasmplus .sym file.

usage: hotspots.py profile.txt build/zxracer.sym [frames]
"""
import sys
from collections import defaultdict

prof = [(int(a, 16), int(t)) for a, t in (l.split() for l in open(sys.argv[1]))]
syms = []
for line in open(sys.argv[2]):
    if ": EQU 0x" in line:
        name, val = line.split(": EQU ")
        v = int(val, 16)
        if 0x8000 <= v < 0xC000:
            syms.append((v, name.strip()))
syms.sort()
frames = int(sys.argv[3]) if len(sys.argv) > 3 else 1


def owner(addr, local):
    best = None
    for v, n in syms:
        if v > addr:
            break
        if local or "." not in n:
            best = n
    return best or f"{addr:04X}"


for local in (False, True):
    tot = defaultdict(int)
    for a, t in prof:
        tot[owner(a, local)] += t
    total = sum(tot.values())
    print(("labels" if local else "routines") + f" (T per frame over {frames} frames):")
    for n, t in sorted(tot.items(), key=lambda kv: -kv[1])[:25 if local else 15]:
        print(f"  {n:32s} {t // frames:8d}  {100 * t / total:5.1f}%")
    print()
