#!/usr/bin/env python3
"""The Einstein build in Albert's core (tests/einstein/speedrun_check.exe):
the disc boots to the game's main loop, the attract demo drives at a
reasonable frame rate, a key starts a game, the clock runs and the music
plays, and no VRAM access ever comes too fast (the chip would lose it).

usage: einstein_check.py <speedrun_check.exe> <mos.rom> <speedrun.dsk> <speedrun.sym> <out dir>
"""
import os
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np

MIN_FPS = 7.0           # game frames a second, attract mode (the Spectrum: 16.7)


def run(harness, rom, dsk, sym, *commands):
    out = subprocess.run([harness, rom, dsk, sym, *commands], capture_output=True, text=True)
    if out.returncode:
        sys.exit(f"einstein_check: the harness failed: {out.stderr.strip()}")
    values = {}
    for line in out.stdout.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            values.setdefault(k, []).append(v)
    return values


def check_artwork(harness, rom, dsk, sym, outdir):
    # Compare the actual VDP against the generated artwork. Revisit the coast
    # after the other fourteen stages to exercise the overlay sharing sky RAM.
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
    import einstein_art
    import yaml
    cfg = yaml.safe_load((Path(__file__).resolve().parents[1] / "assets/stages.yaml").read_text())
    stages = [stage for row in cfg["rows"] for stage in row]
    route = [*range(len(stages)), 0]
    commands = ["boot", "SPEEDRUN"]
    for stage in route:
        commands += ["stage", str(stage), "frames", "80", "vram", "1B00", "57",
                     "vram", "3800", "416", "vram", "0300", "256",
                     "vram", "0C00", "512", "vram", "2C00", "512",
                     "shot", str(Path(outdir) / f"round_{stage:02}.ppm")]
    values = run(harness, rom, dsk, sym, *commands, "stats")
    horizons = values["vram_2C00"]
    if len(set(horizons)) != 15 or horizons[0] != horizons[-1]:
        sys.exit("einstein_check: scrolling horizon colour planes did not survive stage loading")
    for stage, shown, tiles, inks in zip(route, values["vram_0300"], values["vram_0C00"], horizons):
        spec = stages[stage]
        scene = einstein_art.landscape(spec, cfg["themes"][spec["theme"]])
        pixels, _ = einstein_art.planes(scene.crop((0, 24, 256, 32)))
        panorama, colours = einstein_art.planes(scene.crop((0, 80, 256, 96)))
        if panorama != bytes.fromhex(tiles):
            sys.exit(f"einstein_check: native panorama patterns differ on stage {stage}")
        if colours != bytes.fromhex(inks):
            sys.exit(f"einstein_check: native panorama colours differ on stage {stage}")
        if pixels != bytes.fromhex(shown):
            sys.exit(f"einstein_check: native sky pixels differ on stage {stage}")
    # The tail lamps are sprites 0 and 1, or 12 and 13 after the centre
    # line's twelve in a build with them (-DEIN_DASH).
    dash = any(line.startswith("EinDashRow:") for line in Path(sym).read_text().splitlines())
    first = 48 if dash else 0
    for table, tiles in zip(values["vram_1B00"], values["vram_3800"]):
        attrs, patterns = bytes.fromhex(table), bytes.fromhex(tiles)
        if attrs[first:first + 9] != bytes((177,100,48,8,177,143,48,8,208)):
            sys.exit("einstein_check: tail lamp sprites missing")
        for n in range(0, first, 4):
            y, x, tile, _ = attrs[n:n+4]
            for line in range(8):
                if not 160 <= y + 1 + line < 192:
                    continue
                for dx in range(16):
                    byte = patterns[tile*8 + line + (dx//8)*16]
                    if 96 <= x+dx < 160 and byte & (128 >> (dx%8)):
                        sys.exit("einstein_check: lane marker visible through the Spider")
    if values["fast_vram_accesses"] != ["0"]:
        sys.exit("einstein_check: stage artwork exceeded the VDP access rate")
    print("einstein_check: verified the native sky and scrolling horizon across 15 stages")


def main(harness, rom, dsk, sym, outdir):
    wav = os.path.join(outdir, "einstein_check")
    v = run(harness, rom, dsk, sym, "boot", "SPEEDRUN",
            "frames", "100", "peek16", "GameFrames", "frames", "500", "peek16", "GameFrames",
            "peek8", "GameState", "shot", os.path.join(outdir, "einstein_attract.ppm"),
            "hold", "UP", "frames", "20", "release", "frames", "300",
            "hold", "UP", "frames", "200", "peek8", "Speed", "frames", "200", "peek8", "Speed",
            "frames", "200", "peek8", "GameState", "peek8", "Time", "peek8", "Speed",
            "record", "150", wav, "shot", os.path.join(outdir, "einstein_game.ppm"), "stats")
    failures = []
    if v.get("main_loop") != ["1"]:
        sys.exit("einstein_check: the game's main loop was not reached")
    frames = [int(x) for x in v["GameFrames"]]
    fps = (frames[1] - frames[0]) / 10.0
    print(f"einstein_check: booted in {v['boot_seconds'][0]} s; attract mode {fps:.1f} game frames a second")
    if fps < MIN_FPS:
        failures.append(f"attract mode at {fps:.1f} fps (at least {MIN_FPS})")
    state = [int(x) for x in v["GameState"]]
    if state != [0, 1]:
        failures.append(f"game states {state}: attract (0), then playing (1) after a key")
    # (the speed at three moments: accelerating blind, the car may have just
    # hit something at any one of them)
    time, speed = int(v["Time"][0]), max(int(x) for x in v["Speed"])
    print(f"einstein_check: in the game, time {time:02X}, top speed {speed}")
    if not (0 < time < 0x68 and speed > 0):
        failures.append("the clock did not run or the car did not move")
    with wave.open(wav + ".wav") as w:
        pcm = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(float)
    rms = float(np.sqrt((pcm ** 2).mean())) if len(pcm) else 0.0
    print(f"einstein_check: sound level {rms:.0f}")
    if rms < 500:
        failures.append("no sound")
    fast = int(v["fast_vram_accesses"][0])
    if fast:
        failures.append(f"{fast} VRAM accesses too fast")
    for f in ("einstein_check.rgb",):
        p = os.path.join(outdir, f)
        if os.path.exists(p):
            os.remove(p)
    if failures:
        sys.exit("einstein_check: FAILED: " + "; ".join(failures))
    check_artwork(harness, rom, dsk, sym, outdir)
    print("einstein_check: passed")


if __name__ == "__main__":
    main(*sys.argv[1:6])
