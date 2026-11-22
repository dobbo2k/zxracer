#!/usr/bin/env python3
"""Tape: zxsim boots build/speedrun.tap as BASIC's LOAD "" CODE: RANDOMIZE USR
would and plays the rest of the tape into the EAR input. The loader's own
tape routine must load every block - unpacked exactly as in the snapshot -
and start the game (within 9 minutes) -
also with the tape 8% slow or fast and with random leftovers in memory -
and the game must then show its title screen (no timing bars: a release
build). On a 48K, and on a tape error, the loader must return to BASIC with
the code BASIC reports ("128K ONLY", "TAPE ERROR, BLOCK n"). The turbo .tzx
next to the .tap must load the same at 92-108% speed.
usage: tapecheck.py ZXSIM TAP RELEASE.sym OUTDIR
"""
import subprocess
import sys

from PIL import Image

zxsim, tap, sym, outdir = sys.argv[1:5]
start = next(int(l.split("0x")[1], 16) for l in open(sym) if l.startswith("start:"))
ok = True


def started(extra, limit, tapefile=tap):
    """frame the game started at, or None"""
    out = subprocess.run([zxsim, "-T", tapefile, "-n", str(limit), "-q", "-w", f"{start}:1"] + extra,
                         capture_output=True, text=True).stdout
    w = [l for l in out.splitlines() if l.startswith("watch")]
    return int(w[0].split("f=")[1].split()[0]) if w else None


LIMIT = 9 * 60 * 50
f0 = started([], LIMIT)
if f0 is None:
    print(f"FAIL: the game did not start within {LIMIT // 50} s of loading")
    sys.exit(1)
print(f"tapecheck: game started after {f0 // 50 // 60} min {f0 // 50 % 60} s of loading")
# what was loaded, byte for byte as in the snapshot (the decompressor)
sys.path.insert(0, "tools")
import make_tap                         # noqa: E402
banks, _ = make_tap.read_sna(sym.replace(".sym", ".sna"))
syms = make_tap.symbols(sym)
dump = f"{outdir}/tape_ram.bin"
subprocess.run([zxsim, "-T", tap, "-n", str(LIMIT), "-q", "-H", f"{start}", "-D", dump],
               capture_output=True, text=True)
ram = open(dump, "rb").read()
regions = [(b, 0, len(banks[b].rstrip(b"\0"))) for b in (0, 1, 3, 4, 6)]
regions += [(2, 0, make_tap.BANK2_END - 0x8000), (5, 0x1B00, syms["ScnEnd"] - 0x4000)]
bad = [f"bank {b}" for b, lo, hi in regions if ram[b * 16384 + lo:b * 16384 + hi] != banks[b][lo:hi]]
if bad:
    print("FAIL: loaded memory differs from the snapshot: " + ", ".join(bad))
    ok = False
else:
    print(f"tapecheck: memory as loaded matches the snapshot ({sum(hi - lo for _, lo, hi in regions)} bytes)")
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
art = Image.open("assets/gfx/screen_title.png").convert("RGB")
if im.crop((32, 48, 288, 216)).tobytes() != art.crop((0, 0, 256, 168)).tobytes():
    print("FAIL: tape boot did not display the Riviera title artwork")
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


# the turbo .tzx: starts sooner, loads the same, tolerates the same speed changes
tzx = tap[:-4] + ".tzx"
f1 = started([], LIMIT, tzx)
if f1 is None:
    print("FAIL: the .tzx did not start the game")
    ok = False
else:
    print(f"tapecheck: .tzx (turbo): game started after {f1 // 50 // 60} min {f1 // 50 % 60} s of loading")
    subprocess.run([zxsim, "-T", tzx, "-n", str(LIMIT), "-q", "-H", f"{start}", "-D", dump],
                   capture_output=True, text=True)
    ram = open(dump, "rb").read()
    if any(ram[b * 16384 + lo:b * 16384 + hi] != banks[b][lo:hi] for b, lo, hi in regions):
        print("FAIL: memory loaded from the .tzx differs from the snapshot")
        ok = False
    for x in ("92", "108"):
        if started(["-x", x], LIMIT, tzx) is None:
            print(f"FAIL: the .tzx did not load at {x}% speed")
            ok = False

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
