#!/usr/bin/env python3
"""The player's car is redrawn only when something touched its block, so
check that every displayed frame shows an intact car: the car's three
fully owned cell rows must equal one of the frames in assets/gfx/car.png
(the steering frames with their tyres' tread at any of its three rows).
usage: carcheck.py ZXSIM SNA OUTDIR
"""
import os
import subprocess
import sys
from PIL import Image

zxsim, sna, outdir = sys.argv[1:4]
d = os.path.join(outdir, "carcheck")
os.makedirs(d, exist_ok=True)
# (the frames before 120 are the title screen, its jingle and the stage load)
# (Q at frame 60 leaves the title screen and starts a game)
frames = [f for f in range(120, 860, 4)]
cmd = [zxsim, sna, "-n", "861", "-q", "-k", "60:Q", "-k", "400:Q+P", "-k", "420:Q",
       "-k", "520:Q+O", "-k", "545:Q", "-k", "700:Q+P", "-k", "760:Q"]
for f in frames:
    cmd += ["-s", f"{f}:{d}/f{f}.ppm"]
subprocess.run(cmd, check=True)
sheet = Image.open("assets/gfx/car.png").convert("RGB")
frames_car = [sheet.crop((64 * k, 0, 64 * k + 64, 32)) for k in range(sheet.width // 64)]


def rolled(car, phase):
    """The car with its tyres' tread at PHASE, as src/tyres.asm draws it: in
    pixel rows 26-31, the outer bytes (x 0-15, 48-63) of row 26 + r are the
    tread row (27) where r = phase (mod 3), else a plain row (28)."""
    out = car.copy()
    px, orig = out.load(), car.load()
    for r in range(6):
        src = 27 if (r - phase) % 3 == 0 else 28
        for x in list(range(16)) + list(range(48, 64)):
            px[x, 26 + r] = orig[x, src]
    return out


variants = list(frames_car)
for k in range(3):                     # the steering frames' tyres roll
    variants += [rolled(frames_car[k], p) for p in range(3)]
refs = [v.crop((0, 8, 64, 32)).tobytes() for v in variants]
bad = [f for f in frames
       if Image.open(f"{d}/f{f}.ppm").convert("RGB").crop((128, 216, 192, 240)).tobytes() not in refs]
print(f"carcheck: {len(frames) - len(bad)}/{len(frames)} frames show an intact car")
if bad:
    print("damaged at frames", bad[:10])
sys.exit(1 if bad else 0)
