#!/usr/bin/env python3
"""Smoke test: run the game headless, take screenshots and sanity-check them.

Fails if the game stops flipping frames, runs into ROM, or the screenshots
lose the expected road / kerb / grass / sky colours.
usage: smoke.py ZXSIM SNA OUTDIR
"""
import subprocess, sys
from PIL import Image

zxsim, sna, outdir = sys.argv[1:4]
T = 760                     # the title (8 s) and the high-score table (6 s) end at ~720
L = 230                     # the starting lights hold the car this long
shots = {T + 149: "attract_1", T + 299: "attract_2",
         T + L + 369: "straight", T + L + 439: "steer_right", T + L + 509: "steer_left"}
# title, attract mode (demo driver) until T + 300, then a game: accelerate, steer
# symbols, to read game variables at the end of the run
syms = {}
for line in open(sna.replace(".sna", ".sym")):
    if ": EQU 0x" in line:
        name, val = line.split(": EQU ")
        syms[name.strip()] = int(val, 16)
keys = ["-k", f"{T + 300}:Q", "-k", f"{T + L + 370}:Q+P", "-k", f"{T + L + 390}:Q",
        "-k", f"{T + L + 440}:Q+O", "-k", f"{T + L + 460}:Q"]
cmd = [zxsim, sna, "-n", str(T + L + 510), "-a", "-d", f"{syms['Pos']}:2", "-s", f"100:{outdir}/title.ppm",
       "-s", f"560:{outdir}/hiscores.ppm"] + keys
for f, name in shots.items():
    cmd += ["-s", f"{f}:{outdir}/{name}.ppm"]
res = subprocess.run(cmd, capture_output=True, text=True)
print(res.stdout.strip())
ok = res.returncode == 0
if "entered ROM" in res.stderr:
    print("FAIL: execution entered ROM:", res.stderr.strip())
    ok = False
# frame rate over the demo and the game only (the title shows no flips)
flips = int(res.stdout.split("flips=")[1].split()[0])
pre = subprocess.run([zxsim, sna, "-n", str(T)], capture_output=True, text=True).stdout
fps = round((flips - int(pre.split("flips=")[1].split()[0])) * 50 / (L + 510), 2)
print(f"fps after the title: {fps}")
ay = [int(v, 16) for v in res.stdout.split("ay ")[1].split()[:14]]
dump = res.stdout.split("ay ")[1].splitlines()[1].split()
pos = int(dump[0], 16) | (int(dump[1], 16) << 8)
if pos < 1000:                      # (from a standing start)
    print(f"FAIL: the car only travelled {pos} units in the 210 frames since the lights went green")
    ok = False
melody = ay[4] | (ay[5] << 8)            # with music on there is no engine note
if not (melody and not ay[7] & 4 and not ay[7] & 2):
    print(f"FAIL: music not playing in the game (melody period {melody}, mixer {ay[7]:02X})")
    ok = False
if fps < 12:
    print(f"FAIL: frame rate {fps} below 12")
    ok = False

EXPECT = {"road": (0, 0, 0), "sunlit sand": (255, 255, 0), "sand in shade": (215, 215, 0),
          "red kerb": (255, 0, 0), "white kerb": (255, 255, 255)}
for f, name in shots.items():
    im = Image.open(f"{outdir}/{name}.ppm").convert("RGB")
    im.save(f"{outdir}/{name}.png")
    play = im.crop((32, 48, 288, 240))
    colours = {c for _, c in play.crop((0, 96, 256, 160)).getcolors(1 << 16)}
    missing = [k for k, v in EXPECT.items() if v not in colours]
    sky = play.crop((48, 48, 208, 80))
    if {c for _, c in sky.getcolors()} != {(0, 255, 255), (255, 255, 255)}:
        missing.append("coastal sky and clouds")
    if missing:
        print(f"FAIL: {name}: missing {', '.join(missing)}")
        ok = False
title = Image.open(f"{outdir}/title.ppm").convert("RGB").crop((32, 48, 288, 240))
title.save(f"{outdir}/title.png")
art = Image.open("assets/gfx/screen_title.png").convert("RGB")
if title.crop((0, 0, 256, 168)).tobytes() != art.crop((0, 0, 256, 168)).tobytes():
    print("FAIL: title artwork differs from the packed picture")
    ok = False
table = Image.open(f"{outdir}/hiscores.ppm").convert("RGB").crop((32, 48, 288, 240))
table.save(f"{outdir}/hiscores.png")
tcol = {c for _, c in table.getcolors(1 << 16)}
for name, v in {"white": (255, 255, 255), "cyan": (0, 255, 255), "blue": (0, 0, 255)}.items():
    if v not in tcol:
        print(f"FAIL: high-score table: missing {name}")
        ok = False
print("smoke: " + ("passed" if ok else "FAILED"))
sys.exit(0 if ok else 1)
