#!/usr/bin/env python3
"""Tape: zxsim boots build/zxracer.tap as BASIC's LOAD "" CODE: RANDOMIZE USR
would, serving the ROM's LD-BYTES from the tape with real tape timing. The
loader must load every block and start the game (within 7 minutes), which
must then show its title screen (no timing bars: a release build).
usage: tapecheck.py ZXSIM TAP RELEASE.sym OUTDIR
"""
import subprocess
import sys

from PIL import Image

zxsim, tap, sym, outdir = sys.argv[1:5]
start = next(int(l.split("0x")[1], 16) for l in open(sym) if l.startswith("start:"))
LIMIT = 7 * 60 * 50
out = subprocess.run([zxsim, "-T", tap, "-n", str(LIMIT), "-q", "-w", f"{start}:1"],
                     capture_output=True, text=True).stdout
w = [l for l in out.splitlines() if l.startswith("watch")]
ok = True
if not w:
    print(f"FAIL: the game did not start within {LIMIT // 50} s of loading")
    sys.exit(1)
f0 = int(w[0].split("f=")[1].split()[0])
print(f"tapecheck: game started after {f0 // 50 // 60} min {f0 // 50 % 60} s of loading")
shot = f"{outdir}/tape_title.ppm"
r = subprocess.run([zxsim, "-T", tap, "-n", str(f0 + 300), "-q", "-s", f"{f0 + 250}:{shot}"],
                   capture_output=True, text=True)
if "entered ROM" in r.stderr:
    print("FAIL:", r.stderr.strip())
    ok = False
im = Image.open(shot).convert("RGB")
im.save(f"{outdir}/tape_title.png")
colours = {c for _, c in im.crop((32, 48, 288, 240)).getcolors(1 << 16)}
for name, v in {"sun": (255, 255, 0), "sunset": (255, 0, 255), "car red": (255, 0, 0)}.items():
    if v not in colours:
        print(f"FAIL: no title screen after loading (missing {name})")
        ok = False
if im.getpixel((4, 4)) != (0, 0, 0):
    print("FAIL: the border is not black (timing bars in the release build?)")
    ok = False
print("tapecheck: " + ("passed" if ok else "FAILED"))
sys.exit(0 if ok else 1)
