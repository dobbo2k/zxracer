#!/usr/bin/env python3
"""Smoke test: run the game headless, take screenshots and sanity-check them.

Fails if the game stops flipping frames, runs into ROM, or the screenshots
lose the expected road / kerb / grass / sky colours.
usage: smoke.py ZXSIM SNA OUTDIR
"""
import subprocess, sys
from PIL import Image

zxsim, sna, outdir = sys.argv[1:4]
shots = {199: "attract_1", 349: "attract_2",
         419: "straight", 489: "steer_right", 559: "steer_left"}
# attract mode (demo driver) until frame 350, then a game: accelerate, steer
cmd = [zxsim, sna, "-n", "560", "-k", "350:Q", "-k", "420:Q+P", "-k", "490:Q+O"]
for f, name in shots.items():
    cmd += ["-s", f"{f}:{outdir}/{name}.ppm"]
res = subprocess.run(cmd, capture_output=True, text=True)
print(res.stdout.strip())
ok = res.returncode == 0
if "entered ROM" in res.stderr:
    print("FAIL: execution entered ROM:", res.stderr.strip())
    ok = False
fps = float(res.stdout.split("fps=")[1].split()[0])
if fps < 12:
    print(f"FAIL: frame rate {fps} below 12")
    ok = False

EXPECT = {"sky": (0, 255, 255), "grass": (0, 255, 0), "road": (0, 0, 0),
          "kerb / car red": (255, 0, 0), "kerb white": (255, 255, 255),
          "car lamps": (255, 255, 0)}
for f, name in shots.items():
    im = Image.open(f"{outdir}/{name}.ppm").convert("RGB")
    im.save(f"{outdir}/{name}.png")
    play = im.crop((32, 48, 288, 240))
    colours = {c for _, c in play.getcolors(1 << 16)}
    missing = [k for k, v in EXPECT.items() if v not in colours]
    if missing:
        print(f"FAIL: {name}: missing {', '.join(missing)}")
        ok = False
print("smoke: " + ("passed" if ok else "FAILED"))
sys.exit(0 if ok else 1)
