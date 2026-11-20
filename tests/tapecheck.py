#!/usr/bin/env python3
"""Tape: zxsim boots build/speedrun.tap as BASIC's LOAD "" CODE: RANDOMIZE USR
would and plays the rest of the tape into the EAR input. The loader's own
tape routine must load every block and start the game (within 9 minutes) -
also with the tape 8% slow or fast and with random leftovers in memory -
and the game must then show its title screen (no timing bars: a release
build). On a 48K, and on a tape error, the loader must return to BASIC with
the code BASIC reports ("128K ONLY", "TAPE ERROR, BLOCK n").
usage: tapecheck.py ZXSIM TAP RELEASE.sym OUTDIR
"""
import subprocess
import sys

from PIL import Image

zxsim, tap, sym, outdir = sys.argv[1:5]
start = next(int(l.split("0x")[1], 16) for l in open(sym) if l.startswith("start:"))
ok = True


def started(extra, limit):
    """frame the game started at, or None"""
    out = subprocess.run([zxsim, "-T", tap, "-n", str(limit), "-q", "-w", f"{start}:1"] + extra,
                         capture_output=True, text=True).stdout
    w = [l for l in out.splitlines() if l.startswith("watch")]
    return int(w[0].split("f=")[1].split()[0]) if w else None


LIMIT = 9 * 60 * 50
f0 = started([], LIMIT)
if f0 is None:
    print(f"FAIL: the game did not start within {LIMIT // 50} s of loading")
    sys.exit(1)
print(f"tapecheck: game started after {f0 // 50 // 60} min {f0 // 50 % 60} s of loading")
for extra, what in ((["-x", "92"], "the tape 8% slow"), (["-x", "108"], "the tape 8% fast"),
                    (["-R", "7"], "random leftovers in memory")):
    if started(extra, LIMIT + LIMIT // 10) is None:
        print(f"FAIL: the game did not start with {what}")
        ok = False
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


# failures go back to BASIC (the return address zxsim pushed: 0) with a code
def returns(tapefile, extra, limit):
    out = subprocess.run([zxsim, "-T", tapefile, "-n", str(limit), "-q", "-w", "0:1"] + extra,
                         capture_output=True, text=True).stdout
    w = [l for l in out.splitlines() if l.startswith("watch")]
    return int(w[0].split("BC=")[1].split()[0], 16) if w else None


r = returns(tap, ["-48"], 500)
print(f"tapecheck: on a 48K the loader returns {r}")
if r != 1:
    print("FAIL: on a 48K the loader should return 1 (BASIC: 128K ONLY)")
    ok = False
raw = bytearray(open(tap, "rb").read())
i, n = 0, 0
while i < len(raw):                     # corrupt the 2nd block after the loader
    ln = raw[i] | raw[i + 1] << 8
    if n == 5:
        raw[i + 2 + 100] ^= 0x10
    i += 2 + ln
    n += 1
bad = f"{outdir}/corrupt.tap"
open(bad, "wb").write(raw)
r = returns(bad, [], LIMIT)
print(f"tapecheck: with a tape error in block 2 the loader returns {r}")
if r != 12:
    print("FAIL: a tape error in block 2 should return 12 (BASIC: TAPE ERROR, BLOCK 2)")
    ok = False
print("tapecheck: " + ("passed" if ok else "FAILED"))
sys.exit(0 if ok else 1)
