#!/usr/bin/env python3
"""The Amstrad CPC build's generated files and its disc (docs/port_cpc.md).

The CPC assembles the same src/main.asm with -DCPC and build/cpc last on
the include path, so these files stand in for their Spectrum namesakes in
build/. The packs don't fit the 6128's spare banks (phase 0's measure:
docs/port_cpc.md 5.11), so as on the Einstein they are read from the disc
when they are needed: SPEED.DAT holds each packed (tools/zpack.py) from a
sector of its own, and the game reads and unpacks it (src/cpc/disc.asm).

  make_cpc.py gen [stages.yaml] [out dir]
    packs.asm         THEME_CACHE, PANO_CACHE, TRACK_CACHE for the CPC's map
    cpc_objects.asm   the resident objects (traffic, vans, trucks) in Mode 0
    cpc_car.asm       the Spider in Mode 0
    font_data.asm     the font, 3 pixels wide, each pixel doubled across
    stagepacks.asm    every theme and track pack, each assembled where it
                      runs, to theme_*.bin and track_*.bin (sjasmplus);
                      art_*.bin every stage's art
    music_notes.asm   the tone periods for the CPC's 1 MHz AY

  make_cpc.py dat [stages.yaml] [out dir]
    speed_raw.dat     the packs and the pictures packed, each from a sector
                      of its own; room for the overlay and the front end
    stages.asm        the stage table in the Spectrum's layout, its pack
                      entries (first sector on the disc, packed bytes)
                      where the Spectrum has (bank, address, length)
    stageov_pack.asm  StageOvPack: the overlay's
    screens_data.asm  the pictures' (sectors, first sector), the endings
    reserve.txt       where the overlay and the front end go

  make_cpc.py patch [stages.yaml] [out dir]
    SPEED.DAT         speed_raw.dat with stageov.bin and frontend.bin
                      (assembled with the game) packed into their room, and
                      the game's image (base0.bin, base2.bin) packed after
    loader_defs.asm   where the image is, for the loader (src/cpc/loader.asm)

  make_cpc.py dsk [stages.yaml] [out dir]
    speedrun.dsk      SPEED.DAT, then SPEED.BIN (the loader: RUN"SPEED")
"""
import os
import sys

import yaml
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cpc_art                              # noqa: E402
import cpc_illustration                     # noqa: E402
import make_music                           # noqa: E402
import make_stages                          # noqa: E402
import zpack                                # noqa: E402
from cpc import make_dsk                    # noqa: E402

AY_CLOCK = 1000000                          # the CPC's AY: 1 MHz
TRACK_CACHE = make_stages.TRACK_CACHE - 0x4000      # bank 5's part's end, $4000 lower
SCN_DATA = 0x1500                           # its start (src/defs.asm: after the CPC's code)
SECTOR = 512
DAT_SECTOR = 4                              # SPEED.DAT first on the disc, after the directory
LOADER_AT = 0x1000                          # SPEED.BIN (src/cpc/loader.asm: it moves to $C000)
RESERVE = {"stageov": make_stages.STAGEOV_RESERVE, "frontend": make_stages.FRONTEND_RESERVE}


def db_bytes(lines):
    out = []
    for line in lines:
        text = line.strip()
        assert text.startswith("db "), text
        out += [int(v, 0) if not v.strip().startswith("$") else int(v.strip()[1:], 16)
                for v in text[3:].split(",")]
    return bytes(out)


def cpc_sprites():
    """make_stages' sprite emission, in Mode 0 (tools/cpc_art.py); its
    stage art with the stage's pens after the panorama and the clouds
    (src/cpc/reset.asm CpcPalette)."""
    make_stages.scn.emit_type = cpc_art.emit_type
    make_stages.scn.type_bytes = cpc_art.type_bytes
    make_stages.stage_art = stage_art


def stage_art(theme, stage):
    """make_stages.stage_art's, the stage's 17 pens appended to what is
    packed (unpacked at ART_BITMAP + 512 + 640: CpcPalette)."""
    palette = {**theme["palette"], **stage.get("palette", {})}
    style = theme["horizon"]["style"]
    seed = stage["seed"]
    horizon = make_stages.round_art.panorama(style, seed, stage.get("vista"))
    clouds = make_stages.round_art.sky(style, seed)
    assert len(horizon.tobytes()) == 512 and len(clouds.tobytes()) == 640
    pens = cpc_illustration.stage_pens(stage["theme"], palette)
    return bytes(palette[key] for key in make_stages.PALETTE_KEYS) + make_stages.make_screens.lz(
        horizon.tobytes() + clouds.tobytes() + pens)




def sectors(n):
    return (n + SECTOR - 1) // SECTOR


def packed(data):
    return zpack.pack(data, cache_dir="build")


def theme_masters():
    """make_stages.theme_pack given each theme's own masters."""
    plain = make_stages.theme_pack

    def theme_pack(name, theme, masters=None):
        return plain(name, theme, cpc_illustration.cpc_masters(name[6:]))
    make_stages.theme_pack = theme_pack


def gen(cfg, outdir):
    cpc_sprites()
    theme_masters()
    masters = cpc_illustration.cpc_masters(None)    # (the resident traffic's)
    packs, stages, art_sizes = make_stages.stage_packs(cfg, masters)
    head = ["; Generated by tools/make_cpc.py - do not edit",
            f"PANO_CACHE EQU ${make_stages.PANO_CACHE:04X}",
            f"THEME_CACHE EQU ${make_stages.THEME_CACHE:04X}",
            f"TRACK_CACHE EQU ${TRACK_CACHE:04X}"]
    open(os.path.join(outdir, "packs.asm"), "w").write("\n".join(head) + "\n")
    open(os.path.join(outdir, "cpc_objects.asm"), "w").write(make_stages.resident_data(masters))
    open(os.path.join(outdir, "cpc_car.asm"), "w").write(
        "\n".join(cpc_art.car_frames(spider=cpc_illustration.spider)) + "\n")
    open(os.path.join(outdir, "font_data.asm"), "w").write("\n".join(cpc_art.font_asm()) + "\n")
    out = head + ["; the resident sprites the theme packs name (src/main.asm: at SCN_DATA)",
                  f"        ORG ${SCN_DATA:04X}", '        INCLUDE "cpc_objects.asm"']
    for label, lines, size, cache in packs:
        if label.startswith("art_"):
            open(os.path.join(outdir, label + ".bin"), "wb").write(db_bytes(lines))
            continue
        top = "PANO_CACHE" if label.startswith("theme_") else "$4000"
        if label.startswith("track_"):
            cache = TRACK_CACHE
        out += [f'        OUTPUT "{outdir}/{label}.bin"', f"        ORG ${cache:04X}"] + lines + \
               [f"        ASSERT $ <= {top}", "        OUTEND"]
    open(os.path.join(outdir, "stagepacks.asm"), "w").write("\n".join(out) + "\n")

    make_music.AY_CLOCK = AY_CLOCK
    p = make_music.periods()
    notes = ["; Generated by tools/make_cpc.py - do not edit (the AY at 1 MHz)"]
    for i in range(0, len(p), 8):
        notes.append("        dw " + ", ".join(str(v) for v in p[i:i + 8]))
    open(os.path.join(outdir, "music_notes.asm"), "w").write("\n".join(notes) + "\n")


def dat(cfg, outdir):
    cpc_sprites()
    theme_masters()
    packs, stages, art_sizes = make_stages.stage_packs(cfg, cpc_illustration.cpc_masters(None))
    data = bytearray()
    where = {}                              # label -> (first sector, packed bytes)

    def put(label, blob):
        p = packed(blob)
        where[label] = (DAT_SECTOR + len(data) // SECTOR, len(p))
        data.extend(p + bytes(sectors(len(p)) * SECTOR - len(p)))

    for label, _, _, _ in packs:
        put(label, open(os.path.join(outdir, label + ".bin"), "rb").read())
    screens = make_stages.make_screens
    shots = screens.build(screens.ending_themes(cfg), preview_dir=outdir)
    for name, (raw, _lz) in shots.items():         # (the Spectrum's, in the shadow: phase A)
        put("scr_" + name, raw)
    room = {}
    for name, size in RESERVE.items():
        room[name] = (DAT_SECTOR + len(data) // SECTOR, sectors(size))
        data.extend(bytes(sectors(size) * SECTOR))
    open(os.path.join(outdir, "speed_raw.dat"), "wb").write(data)
    open(os.path.join(outdir, "reserve.txt"), "w").write(
        "".join(f"{k} {v[0]} {v[1]}\n" for k, v in room.items()))

    rows = cfg["rows"]
    idx = {(st["row"], st["col"]): i for i, st in enumerate(stages)}
    tab = ["; Generated by tools/make_cpc.py - do not edit",
           f"NUM_STAGES EQU {len(stages)}", f"NUM_ROWS EQU {len(rows)}",
           f"PANO_H EQU {make_stages.PANO_H}", "STAGE_SIZE EQU 16",
           "StageTable:                 ; (theme and track: first sector on the disc, packed bytes)"]
    for st in stages:
        r, k = st["row"], st["col"]
        left = idx.get((r + 1, k), 0xFF)
        right = idx.get((r + 1, k + 1), 0xFF)
        th, tr = where[st["theme"]], where[st["track"]]
        tab += ["        db 0", f"        dw {th[0]}, {th[1]}", "        db 0", f"        dw {tr[0]}, {tr[1]}",
                f"        db {left}, {right}, {r + 1}", f"        dw {st['par']}", "        db 0"]
    tab.append("RoundArtTable:")
    for st in stages:
        a = where[st["art"]]
        tab += ["        db 0", f"        dw {a[0]}, {a[1]}"]
    tab.append("DashHeader:")
    header = cpc_art.dash_header()
    for y in range(8):
        tab.append("        db " + ", ".join(map(str, header[y * 32:(y + 1) * 32])))
    tab += ["FrontEndPack:   db 0", f"        dw {room['frontend'][0]}, {room['frontend'][1] * SECTOR}"]
    open(os.path.join(outdir, "stages.asm"), "w").write("\n".join(tab) + "\n")
    open(os.path.join(outdir, "stageov_pack.asm"), "w").write("\n".join([
        "; Generated by tools/make_cpc.py - do not edit",
        "StageOvPack:                ; (first sector on the disc, bytes to read)",
        "        db 0", f"        dw {room['stageov'][0]}, {room['stageov'][1] * SECTOR}"]) + "\n")
    sd = make_stages.screens_data(cfg, stages, lambda n: (str(sectors(where[n][1])), str(where[n][0])))
    sd[0] = "; Generated by tools/make_cpc.py - do not edit (pictures: sectors, first sector)"
    open(os.path.join(outdir, "screens_data.asm"), "w").write("\n".join(sd) + "\n")
    print(f"SPEED.DAT packs: {len(data)} bytes, {len(data) // SECTOR} sectors, {len(packs)} packs")


def patch(cfg, outdir):
    data = bytearray(open(os.path.join(outdir, "speed_raw.dat"), "rb").read())
    for line in open(os.path.join(outdir, "reserve.txt")):
        name, first, count = line.split()
        blob = packed(open(os.path.join(outdir, name + ".bin"), "rb").read())
        if len(blob) > int(count) * SECTOR:
            raise SystemExit(f"{name}.bin packed: {len(blob)} bytes, its room {int(count) * SECTOR}")
        at = (int(first) - DAT_SECTOR) * SECTOR
        data[at:at + len(blob)] = blob
    defs = ["; Generated by tools/make_cpc.py - do not edit (the game's image in SPEED.DAT)"]
    # the loading screen (until the CPC's own, phase A: the Spectrum's)
    blob = packed(cpc_art.loading_screen())
    if len(blob) > 0x3000:
        raise SystemExit(f"the loading screen packed: {len(blob)} bytes, more than base 0's room")
    defs += [f"LOADING_SECTOR EQU {DAT_SECTOR + len(data) // SECTOR}",
             f"LOADING_SECTORS EQU {sectors(len(blob))}"]
    data.extend(blob + bytes(sectors(len(blob)) * SECTOR - len(blob)))
    for name in ("base0", "base2"):
        blob = packed(open(os.path.join(outdir, name + ".bin"), "rb").read())
        if len(blob) > 0x4000:
            raise SystemExit(f"{name}.bin packed: {len(blob)} bytes, more than a bank")
        defs += [f"IMAGE_{name.upper()}_SECTOR EQU {DAT_SECTOR + len(data) // SECTOR}",
                 f"IMAGE_{name.upper()}_SECTORS EQU {sectors(len(blob))}"]
        data.extend(blob + bytes(sectors(len(blob)) * SECTOR - len(blob)))
    open(os.path.join(outdir, "SPEED.DAT"), "wb").write(data)
    open(os.path.join(outdir, "loader_defs.asm"), "w").write("\n".join(defs) + "\n")
    print(f"SPEED.DAT: {len(data)} bytes, {len(data) // SECTOR} sectors")


def dsk(cfg, outdir):
    files = [make_dsk.DiskFile("SPEED.DAT", open(os.path.join(outdir, "SPEED.DAT"), "rb").read()),
             make_dsk.DiskFile("SPEED.BIN", open(os.path.join(outdir, "speed.bin"), "rb").read(),
                               load=LOADER_AT, run=LOADER_AT)]
    target = Path(os.environ.get("CPC_DSK") or Path(outdir) / "speedrun.dsk")
    layout = make_dsk.write(target, files)
    assert layout["SPEED.DAT"][0] == DAT_SECTOR, layout
    used = sum(sectors(len(f.data) + (128 if f.load is not None else 0)) for f in files)
    print(f"{target.name}: {used} of {make_dsk.TRACKS * make_dsk.SECTORS - 4} sectors used")


def main(step, src="assets/stages.yaml", outdir="build/cpc"):
    os.makedirs(outdir, exist_ok=True)
    cfg = yaml.safe_load(open(src)) if step in ("gen", "dat") else None
    {"gen": gen, "dat": dat, "patch": patch, "dsk": dsk}[step](cfg, outdir)


if __name__ == "__main__":
    main(*sys.argv[1:4])
