#!/usr/bin/env python3
"""The player's car is redrawn only when something touched its block, so
check that every displayed frame shows an intact car: the car's three
fully owned cell rows must equal one of the frames in assets/gfx/car.png.
usage: carcheck.py ZXSIM SNA OUTDIR
"""
import os
import subprocess
import sys
from PIL import Image

zxsim, sna, outdir = sys.argv[1:4]
d = os.path.join(outdir, "carcheck")
os.makedirs(d, exist_ok=True)
# (frames just after a stage load are skipped: both screens are cleared and
# refilled over a couple of game frames - the stage transition)
frames = [f for f in range(60, 860, 4) if not 300 <= f < 330]
cmd = [zxsim, sna, "-n", "861", "-q", "-k", "300:Q", "-k", "400:Q+P", "-k", "420:Q",
       "-k", "520:Q+O", "-k", "545:Q", "-k", "700:Q+P", "-k", "760:Q"]
for f in frames:
    cmd += ["-s", f"{f}:{d}/f{f}.ppm"]
subprocess.run(cmd, check=True)
sheet = Image.open("assets/gfx/car.png").convert("RGB")
refs = [sheet.crop((64 * k, 8, 64 * k + 64, 32)).tobytes() for k in range(3)]
bad = [f for f in frames
       if Image.open(f"{d}/f{f}.ppm").convert("RGB").crop((128, 216, 192, 240)).tobytes() not in refs]
print(f"carcheck: {len(frames) - len(bad)}/{len(frames)} frames show an intact car")
if bad:
    print("damaged at frames", bad[:10])
sys.exit(1 if bad else 0)
