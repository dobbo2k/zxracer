#!/usr/bin/env python3
"""Build the stage data for ZX Racer from assets/stages.yaml.

Outputs (sjasmplus include files):
  build/resident_data.asm  sprites every stage needs (traffic), bank 5
  build/packs.asm          theme packs and track packs, stored in the free
                           banks (0, 1, 3, 4, 6) and assembled to run in the
                           caches they are copied to at a stage start
  build/stages.asm         stage table (where each stage's packs are, forks)

Theme pack (runs at THEME_CACHE in bank 7): header, type directory, name,
panorama, the curve/fork signs and the theme's two scenery types.
Track pack (runs at TRACK_CACHE in bank 5): header, segments, objects.
usage: make_stages.py [stages.yaml] [build dir]
"""
import math
import os
import random
import sys

import yaml
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
import make_scenery as scn          # noqa: E402
from gen_tables import SPLIT_LEN, fork_dx   # noqa: E402

THEME_CACHE = 0xDB00                # bank 7, after screen buffer B
THEME_CACHE_SIZE = 0x10000 - THEME_CACHE
TRACK_CACHE = 0x6800                # bank 5, after the resident data
TRACK_CACHE_SIZE = 0x8000 - TRACK_CACHE
PACK_BANKS = [0, 1, 3, 4, 6]
BANK_SIZE = 0x4000
PANO_W, PANO_H = 256, 16
SHARED_TYPES = ["sign_r", "sign_l", "fork"]          # in every theme pack
TYPE_IDS = {"traffic": 0, "sign_r": 1, "sign_l": 2, "fork": 3}   # theme types: 4, 5
END_STRAIGHT = SPLIT_LEN            # the road forks along the final straight
MAX_X = 127 * 4                     # object x is stored / 4 in a signed byte
MAX_STAGE_LEN = 60000


# ---------------------------------------------------------------- horizon
def ridge(rnd, top, bottom, octaves):
    phases = [(rnd.random() * 2 * math.pi, k) for k in octaves]
    raw = [sum(math.sin(2 * math.pi * k * x / PANO_W + ph) / k ** 0.8 for ph, k in phases)
           for x in range(PANO_W)]
    lo, hi = min(raw), max(raw)
    return [top + (v - lo) / (hi - lo) * (bottom - top) for v in raw]


def panorama(style, seed):
    """256 x 16 tiling backdrop; 1 = ink."""
    rnd = random.Random(seed)
    tops = [PANO_H] * PANO_W
    holes = set()
    if style == "mountains":
        far = ridge(rnd, 1, 13, [1, 2, 3, 5, 8, 13])
        near = ridge(rnd, 9, 14, [2, 4, 7, 11, 17])
        tops = [min(a, b) for a, b in zip(far, near)]
    elif style == "hills":
        tops = ridge(rnd, 5, 13, [1, 2, 3, 5])
    elif style == "mesas":
        tops = [14] * PANO_W
        x = 0
        while x < PANO_W:
            w = rnd.randint(18, 40)
            h = rnd.choice([3, 5, 7, 9])
            for k in range(w):
                slope = min(k, w - 1 - k)
                t = h + max(0, 3 - slope) * 2
                xx = (x + k) % PANO_W
                tops[xx] = min(tops[xx], t)
            x += w + rnd.randint(4, 24)
    elif style == "peaks":
        tops = [12] * PANO_W
        for _ in range(9):
            cx, h = rnd.randrange(PANO_W), rnd.randint(1, 8)
            for d in range(-24, 25):
                xx = (cx + d) % PANO_W
                tops[xx] = min(tops[xx], h + abs(d) * 0.55)
        for x in range(PANO_W):                      # snow caps: dithered tops
            t = int(tops[x])
            if t < 6:
                for y in range(t, t + 3):
                    if (x + y) % 2:
                        holes.add((x, y))
    elif style == "skyline":
        tops = [15] * PANO_W
        x = 0
        while x < PANO_W:
            w, h = rnd.randint(6, 18), rnd.randint(2, 12)
            for k in range(w):
                tops[(x + k) % PANO_W] = h
            for wy in range(h + 2, PANO_H - 1, 3):  # lit windows: holes
                for wx in range(x + 2, x + w - 1, 3):
                    if rnd.random() < 0.5:
                        holes.add((wx % PANO_W, wy))
            x += w
    else:
        raise SystemExit(f"unknown horizon style {style}")
    im = Image.new("1", (PANO_W, PANO_H), 0)
    for x in range(PANO_W):
        for y in range(max(0, int(tops[x])), PANO_H):
            if (x, y) not in holes:
                im.putpixel((x, y), 1)
    return im


def panorama_lines(im):
    out = ["Panorama:"]
    for s in range(4):
        for y in range(PANO_H):
            row = []
            for b in range(32):
                v = 0
                for x in range(8):
                    if im.getpixel(((b * 8 + x + 2 * s) % PANO_W, y)):
                        v |= 0x80 >> x
                row.append(v)
            out.append("        db " + ", ".join(f"${v:02X}" for v in row))
    return out


# ---------------------------------------------------------------- tracks
def make_track(row, seed, theme):
    """Segments (length, curve) and objects (z, x, type id) for a stage."""
    rnd = random.Random(seed * 7919 + row)
    maxc = 8 + 2 * row
    target = 26000 + 2000 * row
    segs = [(3000, 0)]
    z = 3000
    while z < target:
        r = rnd.random()
        if r < 0.3:
            length = rnd.randint(1500, 3500)
            segs.append((length, 0))
        elif r < 0.5:                                # S-bend
            c = rnd.randint(max(4, maxc // 2), maxc) * rnd.choice([-1, 1])
            for cc in (c, -c):
                length = rnd.randint(1800, 3000)
                segs.append((length, cc))
                z += length
            continue
        else:
            c = rnd.randint(max(3, maxc // 3), maxc) * rnd.choice([-1, 1])
            length = rnd.randint(2000, 4500)
            segs.append((length, c))
        z += segs[-1][0]
    segs.append((END_STRAIGHT, 0))
    stage_len = sum(length for length, _ in segs)
    assert stage_len <= MAX_STAGE_LEN, stage_len

    objs = []
    big, small = theme["types"]
    tid = {big: 4, small: 5}
    fork = row < 4                                   # the last row ends at the goal
    zs = stage_len - SPLIT_LEN                       # where the road splits

    def side_obj(z, side, x, t):
        # past the split, roadside objects move out with the branches
        if fork:
            x += fork_dx(z - zs)
        if x <= MAX_X:
            objs.append((z, side * round(x), t))

    end = stage_len - 300 if fork else stage_len - 4500
    z = 2500
    while z < end:                                   # big scenery, both sides
        for side in (-1, 1):
            if rnd.random() < 0.7:
                side_obj(z + rnd.randint(0, 200), side, rnd.randint(240, 300), tid[big])
        z += rnd.randint(900, 1300)
    z = 2800
    while z < end:                                   # small scenery
        side_obj(z, rnd.choice([-1, 1]), rnd.randint(200, 320), tid[small])
        z += rnd.randint(500, 900)
    zc = 0
    for length, curve in segs:                       # curve warning signs
        if abs(curve) >= 10:
            kind = TYPE_IDS["sign_r" if curve > 0 else "sign_l"]
            x = -240 if curve > 0 else 240
            for back in (1500, 1000, 500):
                if zc - back > 0:
                    objs.append((zc - back, x, kind))
        zc += length
    if fork:
        for back in (1300, 500):                     # fork boards before the split
            for side in (-1, 1):
                objs.append((zs - back, side * 250, TYPE_IDS["fork"]))
        objs.append((zs + 3600, 0, TYPE_IDS["fork"]))   # in the median once it opens
        for d in (4200, 4700):
            objs.append((zs + d, 0, tid[big]))
    # no scenery right on the road edge near curve signs etc.: keep sorted, unique z
    objs.sort()
    return segs, objs, stage_len


def track_pack(name, segs, objs, stage_len):
    out = [f"        MODULE {name}",
           "        dw Track, Objects, " + str(stage_len),
           "Track:"]
    for length, curve in segs:
        out.append(f"        dw {length}")
        out.append(f"        db {curve & 0xFF}, 0")
    out += ["        dw 0", "Objects:"]
    for z, x, t in objs:
        out.append(f"        dw {z}")
        out.append(f"        db {(x // 4) & 0xFF}, {t}")
    out += ["        dw 0", "        db 0, $FF", "        ENDMODULE"]
    size = 6 + 4 * len(segs) + 2 + 4 * len(objs) + 4
    return out, size


def theme_pack(name, theme):
    pal = theme["palette"]
    # DrawForkRow finds the kerb cells it drew by their attributes
    assert {pal["kerb_l"], pal["kerb_d"]}.isdisjoint(
        {pal["grass_l"], pal["grass_d"], pal["road"]}), name
    types = SHARED_TYPES + theme["types"]
    out = [f"        MODULE {name}",
           "        dw TypeDir, Panorama, Name",
           "        db " + ", ".join(str(pal[k]) for k in
                                    ("sky", "pano", "hud", "time", "grass_l", "grass_d",
                                     "kerb_l", "kerb_d", "road")),
           "TypeDir:",
           "        dw @Scn_traffic"]
    out += [f"        dw Scn_{t}" for t in types]
    out += [f'Name:   db "{theme["name"]}", 0']
    im = panorama(**theme["horizon"])
    im.convert("L").point(lambda v: 0 if v else 255).save(f"assets/gfx/horizon_{name[6:]}.png")
    out += panorama_lines(im)
    size = 6 + 9 + 2 * (len(types) + 1) + len(theme["name"]) + 1 + 4 * PANO_H * 32
    for t in types:
        consts, dirl, data = scn.emit_type(t)
        out += consts + dirl + data
        size += scn.type_bytes(t)
    out.append("        ENDMODULE")
    if size > THEME_CACHE_SIZE:
        raise SystemExit(f"theme {name}: {size} bytes, the cache holds {THEME_CACHE_SIZE}")
    return out, size


# ---------------------------------------------------------------- main
def main(src="assets/stages.yaml", outdir="build"):
    cfg = yaml.safe_load(open(src))
    themes = cfg["themes"]

    # resident sprites (bank 5)
    consts, dirl, data = scn.emit_type("traffic")
    res = ["; Generated by tools/make_stages.py - do not edit"] + consts + dirl + data
    for t, k in TYPE_IDS.items():
        res.append(f"TYPE_{t.upper()} EQU {k}")
    res.append(f"SCN_SIZES EQU {len(scn.SIZES)}")
    open(os.path.join(outdir, "resident_data.asm"), "w").write("\n".join(res) + "\n")

    # packs
    packs = []                                       # (label, lines, size)
    theme_label = {}
    for tname, theme in themes.items():
        label = f"theme_{tname}"
        lines, size = theme_pack(label, theme)
        packs.append((label, lines, size, THEME_CACHE))
        theme_label[tname] = label
    stages = []
    for r, row in enumerate(cfg["rows"]):
        for k, st in enumerate(row):
            label = f"track_{len(stages)}"
            segs, objs, stage_len = make_track(r, st["seed"], themes[st["theme"]])
            lines, size = track_pack(label, segs, objs, stage_len)
            if size > TRACK_CACHE_SIZE:
                raise SystemExit(f"{label}: {size} bytes, the cache holds {TRACK_CACHE_SIZE}")
            packs.append((label, lines, size, TRACK_CACHE))
            stages.append({"row": r, "col": k, "theme": theme_label[st["theme"]], "track": label})

    # first-fit into the free banks
    fill = {b: 0 for b in PACK_BANKS}
    where = {}
    for label, lines, size, _ in sorted(packs, key=lambda p: -p[2]):
        for b in PACK_BANKS:
            if fill[b] + size <= BANK_SIZE - 16:
                where[label] = b
                fill[b] += size + 4
                break
        else:
            raise SystemExit("stage packs do not fit in the free banks")
    out = ["; Generated by tools/make_stages.py - do not edit",
           f"THEME_CACHE EQU ${THEME_CACHE:04X}", f"TRACK_CACHE EQU ${TRACK_CACHE:04X}",
           "        SLOT 3"]
    for b in PACK_BANKS:
        out += [f"        PAGE {b}", "        ORG $C000"]
        for label, lines, size, cache in packs:
            if where[label] != b:
                continue
            out += [f"Pack_{label}:", f"        DISP ${cache:04X}"] + lines + \
                   ["        ENT", f"Pack_{label}_end:",
                    f"        ASSERT Pack_{label}_end - Pack_{label} <= ${0x10000 - cache:04X}"]
        out.append(f"        ASSERT $ <= $10000")
    out += ["        PAGE 7"]
    open(os.path.join(outdir, "packs.asm"), "w").write("\n".join(out) + "\n")

    # stage table (16 bytes per stage): theme bank, src, length; track bank,
    # src, length; left, right, row, padding
    rows = cfg["rows"]
    idx = {}
    for i, st in enumerate(stages):
        idx[(st["row"], st["col"])] = i
    tab = ["; Generated by tools/make_stages.py - do not edit",
           f"NUM_STAGES EQU {len(stages)}", f"NUM_ROWS EQU {len(rows)}",
           f"PANO_H EQU {PANO_H}", "STAGE_SIZE EQU 16", "StageTable:"]
    for st in stages:
        r, k = st["row"], st["col"]
        left = idx.get((r + 1, k), 0xFF)
        right = idx.get((r + 1, k + 1), 0xFF)
        th, tr = st["theme"], st["track"]
        tab.append(f"        db {where[th]}")
        tab.append(f"        dw Pack_{th}, Pack_{th}_end - Pack_{th}")
        tab.append(f"        db {where[tr]}")
        tab.append(f"        dw Pack_{tr}, Pack_{tr}_end - Pack_{tr}")
        tab.append(f"        db {left}, {right}, {r + 1}, 0, 0, 0")   # 16 bytes
    open(os.path.join(outdir, "stages.asm"), "w").write("\n".join(tab) + "\n")
    for b in PACK_BANKS:
        print(f"bank {b}: {fill[b]} bytes of packs")


if __name__ == "__main__":
    main(*sys.argv[1:3])
