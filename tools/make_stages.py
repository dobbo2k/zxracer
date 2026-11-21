#!/usr/bin/env python3
"""Build the stage data for Speed Run from assets/stages.yaml.

Outputs (sjasmplus include files):
  build/resident_data.asm  sprites every stage needs (traffic), bank 5
  build/packs.asm          theme packs and track packs, stored in the free
                           banks (0, 1, 3, 4, 6) and assembled to run in the
                           caches they are copied to at a stage start
  build/stages.asm         stage table (where each stage's packs are, forks)

Theme pack (runs at THEME_CACHE in bank 7): header, type directory, name,
panorama, the curve/fork signs and the theme's four scenery types.
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
import make_screens                         # noqa: E402
import round_art
import make_music                           # noqa: E402

THEME_CACHE = 0xDB00                # bank 7, after screen buffer B
THEME_CACHE_SIZE = 0x10000 - THEME_CACHE
TRACK_CACHE = 0x8000 - 608          # bank 5, after the resident data and code
FRONTEND_RESERVE = 4352             # room kept in a pack bank for the front-end overlay
THEME_TOP = 120                    # the cache's last bytes stay free (src/main.asm: CmdListB)
PAR_V = 17                         # par times: depth units per 50 Hz frame on a straight
PAR_K = 1600                       # ... and sqrt(PAR_K / |curve|) on a curve
STAGEOV_RESERVE = 2304              # ... and for the between-stages overlay (run at $4000)
TRACK_CACHE_SIZE = 0x8000 - TRACK_CACHE
PACK_BANKS = [0, 1, 3, 4, 6]
BANK_SIZE = 0x4000
PANO_H = 16
SHARED_TYPES = ["sign_r", "sign_l", "fork"]          # in every theme pack
TYPE_IDS = {"traffic": 0, "sign_r": 1, "sign_l": 2, "fork": 3,   # theme types: 4, 5, 8, 9
            "van": 6, "truck": 7, "sign_tunnel": 10}         # (10: themes with tunnels only)
LANDMARK_SHARE = 0.18               # of the big roadside scenery: the theme's landmark
SMALL2_SHARE = 0.4                  # of the small scenery: the theme's second small type
RESIDENT_TYPES = ["traffic", "van", "truck"]          # in bank 5
MAP_PAPER = {"coast": 5, "desert": 6, "alpine": 7, "country": 4, "sunset": 3}   # route map boxes
END_STRAIGHT = SPLIT_LEN            # the road forks along the final straight
MAX_X = 127 * 4                     # object x is stored / 4 in a signed byte
MAX_STAGE_LEN = 60000
TUNNEL_FROM = 5000                  # tunnels: not before this far into a stage
TUNNEL_MIN, TUNNEL_MAX = 3500, 6000


PALETTE_KEYS = ("sky", "pano", "hud", "time", "grass_l", "grass_d", "kerb_l", "kerb_d", "road")
PANO_CACHE = (0x10000 - THEME_TOP - 1024) & ~31


def stage_art(theme, stage):
    """A stage's palette, scrolling panorama and protected sky panel."""
    palette = {**theme["palette"], **stage.get("palette", {})}
    assert {palette["kerb_l"], palette["kerb_d"]}.isdisjoint(
        {palette["grass_l"], palette["grass_d"], palette["road"]}), stage
    style = theme["horizon"]["style"]
    seed = stage["seed"]
    horizon = round_art.panorama(style, seed, stage.get("vista"))
    clouds = round_art.sky(style, seed)
    # Keep the two shifted copies out of the pack. Only the unshifted copy
    # travels on tape. The stage overlay computes the other once at load.
    return bytes(palette[key] for key in PALETTE_KEYS) + make_screens.lz(
        horizon.tobytes() + clouds.tobytes())


# ---------------------------------------------------------------- tracks
def tunnel_for(row, seed, theme, stage_len):
    """A tunnel (start, end) for themes with them, or None: clear of the
    stage's start and of its end (the fork, or the run-in to the goal)."""
    if not theme.get("tunnels"):
        return None
    r = random.Random(seed * 131 + row * 7 + 1)      # (its own: the track stays as it was)
    length = r.randint(TUNNEL_MIN, TUNNEL_MAX)
    last = stage_len - SPLIT_LEN - 3000 - length if row < 4 else stage_len - 6000 - length
    start = r.randint(TUNNEL_FROM, max(TUNNEL_FROM, last))
    return start, start + length


def make_track(row, seed, theme):
    """Segments (length, curve, hill), objects (z, x, type id) and the tunnel
    (start, end, or None) for a stage."""
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
    hills = hill_profile(rnd, stage_len, theme.get("hills", 0))

    objs = []
    big, small, landmark, small2 = theme["types"]
    tid = {big: 4, small: 5, landmark: 8, small2: 9}
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
                if rnd.random() < LANDMARK_SHARE:            # now and then a landmark
                    side_obj(z + rnd.randint(0, 200), side, rnd.randint(270, 320), tid[landmark])
                else:
                    side_obj(z + rnd.randint(0, 200), side, rnd.randint(240, 300), tid[big])
        z += rnd.randint(900, 1300)
    z = 2800
    while z < end:                                   # small scenery
        t = tid[small2] if rnd.random() < SMALL2_SHARE else tid[small]
        side_obj(z, rnd.choice([-1, 1]), rnd.randint(200, 320), t)
        z += rnd.randint(500, 900)
    zc = 0
    for length, curve in segs:                       # curve warning signs (before hills are merged)
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
    tunnel = tunnel_for(row, seed, theme, stage_len)
    if tunnel:                                       # nothing at the roadside in the tunnel
        objs = [o for o in objs if not tunnel[0] - 600 <= o[0] <= tunnel[1] + 200]
        ts = tunnel[0]                               # warning signs before it
        objs += [(ts - 1700, 250, TYPE_IDS["sign_tunnel"]), (ts - 1700, -250, TYPE_IDS["sign_tunnel"]),
                 (ts - 1000, 250, TYPE_IDS["sign_tunnel"])]
    # no scenery right on the road edge near curve signs etc.: keep sorted, unique z
    # A pair of landmarks outside the racing surface frames the starting grid.
    # Keep the course's established obstacle positions and random sequence.
    objs.extend([(320, -260, tid[big]), (380, 256, tid[landmark])])
    objs.sort()
    return merge_hills(segs, hills), objs, stage_len, tunnel


def hill_profile(rnd, stage_len, amp):
    """Hills as (start, end, value): a climb then a crest, a dip, or a long
    climb. Positive values lift the road ahead, negative ones drop it away;
    each event's values sum to zero, so the road ends up level again. The
    start and the run-in to the checkpoint (and fork) stay flat."""
    out = []
    if amp <= 0:
        return out
    z = 4000 + rnd.randint(0, 2000)
    end = stage_len - SPLIT_LEN - 1500
    while True:
        length = rnd.randint(1300, 2300)
        h = rnd.randint(max(2, amp // 2), amp)
        r = rnd.random()
        if r < 0.45:
            seq = [(length, h), (length, -h)]                 # over a hill
        elif r < 0.8:
            seq = [(length, -h), (length, h)]                 # through a dip
        else:
            seq = [(length, h), (rnd.randint(800, 1600), 0), (length, -h)]   # long climb
        if z + sum(l for l, _ in seq) > end:
            return out
        for l, v in seq:
            if v:
                out.append((z, z + l, v))
            z += l
        z += rnd.randint(1500, 4500)


def merge_hills(segs, hills):
    """Split the curve segments where hills start and end: (length, curve, hill)."""
    cuts, z = set(), 0
    for length, _ in segs:
        z += length
        cuts.add(z)
    for a, b, _ in hills:
        cuts.update((a, b))
    starts, z = [], 0
    for length, curve in segs:
        starts.append((z, z + length, curve))
        z += length
    out, prev = [], 0
    for c in sorted(cuts):
        mid = (prev + c) / 2
        curve = next(cv for a, b, cv in starts if a <= mid < b)
        hill = next((v for a, b, v in hills if a <= mid < b), 0)
        if out and out[-1][1:] == (curve, hill):
            out[-1] = (out[-1][0] + c - prev, curve, hill)
        else:
            out.append((c - prev, curve, hill))
        prev = c
    return out


def par_time(segs, stage_len):
    """A stage's par time (50 Hz frames): beating it is extended play. Each
    segment at PAR_V depth units a frame, or slower on a curve (curve c:
    sqrt(PAR_K / |c|)) - about how the autopilot drives."""
    t = 0.0
    for seg in segs:
        length, curve = seg[0], seg[1]
        v = PAR_V if curve == 0 else min(PAR_V, math.sqrt(PAR_K / abs(curve)))
        t += length / v
    return round(t)


def track_pack(name, segs, objs, stage_len, tunnel=None):
    ts, te = tunnel or (0, 0)
    out = [f"        MODULE {name}",
           f"        dw Track, Objects, {stage_len}, {ts}, {te}",     # (tunnel: start, end; 0: none)
           "Track:"]
    for length, curve, hill in segs:
        out.append(f"        dw {length}")
        out.append(f"        db {curve & 0xFF}, {hill & 0xFF}")
    out += ["        dw 0", "Objects:"]
    for z, x, t in objs:
        out.append(f"        dw {z}")
        out.append(f"        db {(x // 4) & 0xFF}, {t}")
    out += ["        dw 0", "        db 0, $FF", "        ENDMODULE"]
    size = 10 + 4 * len(segs) + 2 + 4 * len(objs) + 4
    return out, size


def theme_pack(name, theme):
    pal = theme["palette"]
    # DrawForkRow finds the kerb cells it drew by their attributes
    assert {pal["kerb_l"], pal["kerb_d"]}.isdisjoint(
        {pal["grass_l"], pal["grass_d"], pal["road"]}), name
    types = SHARED_TYPES + theme["types"] + (["sign_tunnel"] if theme.get("tunnels") else [])
    out = [f"        MODULE {name}",
           "        dw TypeDir, @PANO_CACHE, Name",
           "        db " + ", ".join(str(pal[k]) for k in
                                    ("sky", "pano", "hud", "time", "grass_l", "grass_d",
                                     "kerb_l", "kerb_d", "road")),
           "        dw Tune                ; (+15: the theme's tune)",
           "TypeDir:",
           "        dw @Scn_traffic"]
    assert len(theme["types"]) == 4, "a theme has four scenery types (ids 4, 5, 8, 9)"
    out += [f"        dw Scn_{t}" for t in types[:5]]
    out += ["        dw @Scn_van, @Scn_truck"]
    out += [f"        dw Scn_{t}" for t in types[5:]]
    out += [f'Name:   db "{theme["name"]}", 0']
    out += make_music.tune_asm(name[6:], "Tune")
    im = round_art.panorama(**theme["horizon"])
    im.convert("L").point(lambda v: 0 if v else 255).save(f"assets/gfx/horizon_{name[6:]}.png")
    size = 6 + 9 + 2 + make_music.tune_bytes(name[6:]) + 2 * (len(types) + 3) + len(theme["name"]) + 1
    for t in types:
        consts, dirl, data = scn.emit_type(t)
        out += consts + dirl + data
        size += scn.type_bytes(t)
    out.append("        ENDMODULE")
    if size > PANO_CACHE - THEME_CACHE:
        raise SystemExit(f"theme {name}: {size} bytes, the cache holds {PANO_CACHE - THEME_CACHE}")
    return out, size


# ---------------------------------------------------------------- main
def main(src="assets/stages.yaml", outdir="build"):
    cfg = yaml.safe_load(open(src))
    themes = cfg["themes"]

    # resident sprites (bank 5)
    res = ["; Generated by tools/make_stages.py - do not edit"]
    for t in RESIDENT_TYPES:
        consts, dirl, data = scn.emit_type(t)
        res += consts + dirl + data
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
    art_sizes = {}
    for r, row in enumerate(cfg["rows"]):
        for k, st in enumerate(row):
            label = f"track_{len(stages)}"
            art = f"art_{len(stages)}"
            data = stage_art(themes[st["theme"]], st)
            assert len(data) <= 0x800, "stage art exceeds the overlay input buffer"
            art_sizes[art] = len(data)
            asm = ["        db " + ", ".join(map(str, data[i:i + 32])) for i in range(0, len(data), 32)]
            packs.append((art, asm, len(data), None))
            segs, objs, stage_len, tunnel = make_track(r, st["seed"], themes[st["theme"]])
            lines, size = track_pack(label, segs, objs, stage_len, tunnel)
            while size > TRACK_CACHE_SIZE:          # too long: a little less small scenery
                small = [i for i, o in enumerate(objs) if o[2] in (5, 9)]
                if not small:
                    small = [i for i, (z, _, kind) in enumerate(objs) if kind == 4 and 1000 < z < stage_len - SPLIT_LEN]
                if not small:
                    break
                drop = set(small[::2][:(size - TRACK_CACHE_SIZE + 3) // 4])
                objs = [o for i, o in enumerate(objs) if i not in drop]
                lines, size = track_pack(label, segs, objs, stage_len, tunnel)
            if size > TRACK_CACHE_SIZE:
                raise SystemExit(f"{label}: {size} bytes, the cache holds {TRACK_CACHE_SIZE}")
            packs.append((label, lines, size, TRACK_CACHE))
            stages.append({"row": r, "col": k, "theme": theme_label[st["theme"]], "track": label, "art": art,
                           "par": par_time(segs, stage_len)})

    # title and goal screens: compressed pictures stored with the packs
    shots = make_screens.build(make_screens.ending_themes(cfg))
    for name, (raw, packed) in shots.items():
        lines = ["        db " + ", ".join(str(b) for b in packed[i:i + 32])
                 for i in range(0, len(packed), 32)]
        packs.append((f"scr_{name}", lines, len(packed), None))

    # the front-end overlay (src/frontend.asm), copied over the theme cache
    packs.append(("frontend", ['        INCLUDE "../src/frontend.asm"'], FRONTEND_RESERVE, THEME_CACHE))
    packs.append(("stageov", ['        INCLUDE "../src/stageov.asm"'], STAGEOV_RESERVE, 0x4000))

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
           f"PANO_CACHE EQU ${PANO_CACHE:04X}", f"THEME_CACHE EQU ${THEME_CACHE:04X}", f"TRACK_CACHE EQU ${TRACK_CACHE:04X}",
           "        SLOT 3"]
    for b in PACK_BANKS:
        out += [f"        PAGE {b}", "        ORG $C000"]
        for label, lines, size, cache in packs:
            if where[label] != b:
                continue
            if cache is None:                    # a picture: unpacked from here
                out += [f"Pack_{label}:"] + lines
                continue
            out += [f"Pack_{label}:", f"        DISP ${cache:04X}"] + lines + \
                   ["        ENT", f"Pack_{label}_end:",
                    f"        ASSERT Pack_{label}_end - Pack_{label} <= ${size if label in ('frontend', 'stageov') else 0x10000 - cache:04X}"]
        out.append(f"        ASSERT $ <= $10000")
    out += ["        PAGE 7"]
    open(os.path.join(outdir, "packs.asm"), "w").write("\n".join(out) + "\n")

    # stage table (16 bytes per stage): theme bank, src, length; track bank,
    # src, length; left, right, row; par time; padding
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
        tab.append(f"        db {left}, {right}, {r + 1}")
        tab.append(f"        dw {st['par']}")                          # par time, 50 Hz frames
        tab.append(f"        db 0")                                    # 16 bytes
    tab.append("RoundArtTable:")
    for st in stages:
        art = st["art"]
        tab += [f"        db {where[art]}", f"        dw Pack_{art}, {art_sizes[art]}"]
    tab.append("DashHeader:")
    header = round_art.dash_header()
    for y in range(8):
        tab.append("        db " + ", ".join(map(str, header[y * 32:(y + 1) * 32])))
    tab += ["FrontEndPack:", f"        db {where['frontend']}",
            "        dw Pack_frontend, Pack_frontend_end - Pack_frontend"]
    open(os.path.join(outdir, "stages.asm"), "w").write("\n".join(tab) + "\n")
    # resident: where the between-stages overlay is
    res = ["; Generated by tools/make_stages.py - do not edit",
           "StageOvPack:", f"        db {where['stageov']}",
           "        dw Pack_stageov, Pack_stageov_end - Pack_stageov"]
    open(os.path.join(outdir, "stageov_pack.asm"), "w").write("\n".join(res) + "\n")
    for b in PACK_BANKS:
        print(f"bank {b}: {fill[b]} bytes of packs and pictures")

    # where the pictures are, and the endings (resident)
    last = [st for st in stages if st["row"] == len(rows) - 1]
    sd = ["; Generated by tools/make_stages.py - do not edit",
          f"HISCORE_ROW EQU {make_screens.HISCORE_AT[0]}",
          f"HISCORE_COL EQU {make_screens.HISCORE_AT[1]}",
          f"PRESS_ROW EQU {make_screens.PRESS_ROW}"]
    for k, v in make_screens.GOAL_TEXT.items():
        sd.append(f"GOAL_{k.upper()}_ROW EQU {v}")
    sd += ["ScrTitle:   db " + str(where["scr_title"]), "        dw Pack_scr_title",
           "GoalTable:                  ; per last-row stage: bank, picture, ending line"]
    for k, st in enumerate(last):
        tname = st["theme"][6:]
        sd.append(f"        db {where['scr_goal_' + tname]}")
        sd.append(f"        dw Pack_scr_goal_{tname}, Ending{k}")
    for k, st in enumerate(last):
        line = "YOU REACHED " + make_screens.ENDINGS[st["theme"][6:]]
        assert len(line) <= 32, line
        sd.append(f'Ending{k}:   db {(32 - len(line)) // 2}, "{line}", 0')
    # the route map: per stage its place in the pyramid and theme; per theme
    # its box colour (paper) and name
    tnames = list(themes)
    sd += [f"NUM_THEMES EQU {len(tnames)}", "MapStages:                  ; per stage: row, column, theme"]
    for st in stages:
        sd.append(f"        db {st['row']}, {st['col']}, {tnames.index(st['theme'][6:])}")
    sd.append("MapThemes:                  ; per theme: box attribute, name")
    for t in tnames:
        sd.append(f"        db ${0x40 | MAP_PAPER[t] << 3:02X}")
        sd.append(f"        dw MapName_{t}")
    for t in tnames:
        sd.append(f'MapName_{t}: db "{themes[t]["name"]}", 0')
    open(os.path.join(outdir, "screens_data.asm"), "w").write("\n".join(sd) + "\n")




if __name__ == "__main__":
    main(*sys.argv[1:3])
