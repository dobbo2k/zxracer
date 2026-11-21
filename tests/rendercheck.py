#!/usr/bin/env python3
"""Rendering regression check for speed work: a FIXED_ELAPSED autopilot
build (every update counts 3 TV frames, nothing drawn depends on timing)
plays identically however fast the code is, so after the same number of
game loops both screens and the road and state tables must be
byte-identical to a
reference made from the code before the change.

usage: rendercheck.py save DIR      (build and keep the reference)
       rendercheck.py check DIR     (build and compare with it)
"""
import os
import subprocess
import sys

LOOPS = [300, 600, 900, 1200, 1500, 1800]
KEYS = ["-k", "250:Q", "-k", "256:none"]
ZXSIM = "./build/zxsim.exe" if os.name == "nt" else "build/zxsim"
REGIONS = {"screen A": (5, 0, 6912), "screen B": (7, 0, 6912)}


def table_ranges(sym):
    """The lookup / state tables' own bytes (label .. label_end): the
    table pages' holes hold code and data that move with the code."""
    syms = {l.split(":")[0]: int(l.split("0x")[1], 16) for l in open(sym) if ": EQU 0x" in l}
    return {n: (2, a - 0x8000, syms[n + "_end"] - a) for n, a in syms.items()
            if n + "_end" in syms and 0xA300 <= a < 0xB900}


def build(outdir):
    sna, sym = os.path.join(outdir, "fixed.sna"), os.path.join(outdir, "fixed.sym")
    subprocess.run(["sjasmplus", "--nologo", "--msg=war", "--fullpath", "-Ibuild", f"--sym={sym}",
                    "-DPROFILE=0", "-DAUTOPLAY=1", "-DFIXED_ELAPSED=1", "src/main.asm"], check=True)
    os.replace("build/video.sna", sna)
    os.utime("src/main.asm")             # (make rebuilds build/video.sna)
    return sna, sym


def dumps(sna, sym, outdir, tag):
    addr = next(int(l.split("0x")[1], 16) for l in open(sym) if l.startswith("RequestFlip:"))
    out = {}
    for n in LOOPS:
        f = os.path.join(outdir, f"{tag}{n}.ram")
        subprocess.run([ZXSIM, sna, "-n", "60000", "-q", "-H", f"{addr}:{n}", "-D", f] + KEYS,
                       check=True, capture_output=True)
        out[n] = open(f, "rb").read()
    return out


def main(mode, d):
    os.makedirs(d, exist_ok=True)
    sna, sym = build(d)
    if mode == "save":
        dumps(sna, sym, d, "ref")
        print(f"rendercheck: reference saved ({len(LOOPS)} points)")
        return 0
    new = dumps(sna, sym, d, "new")
    regions = dict(REGIONS, **table_ranges(sym))
    bad = 0
    for n in LOOPS:
        ref = open(os.path.join(d, f"ref{n}.ram"), "rb").read()
        for name, (bank, off, ln) in regions.items():
            a = ref[bank * 16384 + off:bank * 16384 + off + ln]
            b = new[n][bank * 16384 + off:bank * 16384 + off + ln]
            if a != b:
                diff = sum(x != y for x, y in zip(a, b))
                first = next(i for i in range(ln) if a[i] != b[i])
                print(f"rendercheck: loop {n}: {name} differs in {diff} bytes (first at +{first:04X})")
                bad += 1
    print("rendercheck: " + ("identical" if not bad else "DIFFERENT"))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
