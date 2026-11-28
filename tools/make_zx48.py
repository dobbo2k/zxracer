#!/usr/bin/env python3
"""Build Speed Run's resident 48K archive and standard ROM tape."""
import argparse
from collections import Counter
from pathlib import Path
from struct import iter_unpack, pack

import yaml

import make_scenery as scenery
import make_stages as stages
from make_tap import basic_line, header, symbols, tap_block, tape_seconds
from make_music import TUNES, note_index
import round_art
import zpack


def words(*values):
    return pack("<" + "H" * len(values), *values)


def track_data(address, segments, objects, length, tunnel):
    """The layout expected by the track, scenery and tunnel engine."""
    start, end = tunnel or (0, 0)
    segment_data = b"".join(pack("<Hbb", *segment) for segment in segments) + words(0)
    object_data = b"".join(pack("<HbB", z, x // 4, kind) for z, x, kind in objects)
    return (words(address + 10, address + 10 + len(segment_data), length, start, end)
            + segment_data + object_data + b"\x00\x00\x00\xFF")


def compact_track(raw, address, pairs):
    """Encode exact lengths, curve and hill changes, and object deltas."""
    objects = int.from_bytes(raw[2:4], "little") - address
    segments = list(iter_unpack("<Hbb", raw[10:objects - 2]))
    placements = list(iter_unpack("<HBB", raw[objects:-4]))
    result = bytearray(raw[:10] + bytes((len(segments), len(placements))))
    value = bits = 0

    def write(field, width):
        nonlocal value, bits
        assert 0 <= field < 1 << width
        value = (value << width) | field
        bits += width
        while bits >= 8:
            bits -= 8
            result.append((value >> bits) & 255)
        value &= (1 << bits) - 1

    previous_curve = previous_hill = 0
    for length, curve, hill in segments:
        long = length >= 4096
        write(long, 1)
        write(length, 14 if long else 12)
        write(curve != previous_curve, 1)
        if curve != previous_curve:
            write(curve & 63, 6)
        write(hill != previous_hill, 1)
        if hill != previous_hill:
            write(hill & 15, 4)
        previous_curve, previous_hill = curve, hill

    previous = 0
    for z, x, kind in placements:
        delta = z - previous
        write(delta >= 256, 1)
        if delta < 256:
            write(delta, 8)
        else:
            write(delta >= 1024, 1)
            write(delta, 10 if delta < 1024 else 13)
        index = pairs.get((x, kind), 128)
        if index < 32:
            write(0, 1)
            write(index, 5)
        elif index < 128:
            write(2, 2)
            write(index, 7)
        else:
            write(3, 2)
            write(KINDS.index(kind), 3)
            write(x, 8)
        previous = z
    if bits:
        write(0, 8 - bits)
    return bytes(result)


KINDS = (1, 2, 3, 4, 5, 8, 9, 10)
SPRITE_ENTRY = 5


def sprite(name, raw, expected, *, shifted_sizes, nearest=1):
    master, factor, shifts = scenery.TYPES[name]
    source = master()
    indices = [max(nearest, index) for index in scenery.size_indices(name)]
    variants = sorted(set(indices))
    raw.extend((len(variants), *(variants.index(k) for k in indices)))
    directory = len(expected)
    expected.extend(bytes(SPRITE_ENTRY * len(indices)))
    entries = []
    for k in variants:
        height = max(2, round(scenery.SIZES[k] * factor))
        image = scenery.scaled(source, height)
        width = (image.width + 7) // 8
        count = min(shifts[k], 2) if k in shifted_sizes else 1
        step = 8 // count
        stride = width + (count > 1)
        size = stride * height
        raw.extend((width, height, count))
        entries.append((stride, height, 8 - step, len(expected), size))
        rows = [
            sum(1 << (width * 8 - 1 - x) for x in range(image.width) if image.getpixel((x, y)))
            for y in range(height)
        ]
        rows = [row.to_bytes(width, "big") for row in rows]
        raw.extend(value for column in zip(*rows) for value in column)
        for shift in range(0, 8, step):
            for row in rows:
                bits = int.from_bytes(row, "big")
                expected.extend(((bits << (8 if count > 1 else 0)) >> shift).to_bytes(stride, "big"))
    for slot, index in enumerate(indices):
        width, height, mask, offset, size = entries[variants.index(index)]
        assert mask in (0, 4) and width < 16 and (not mask or size < 256)
        entry = directory + slot * SPRITE_ENTRY
        expected[entry:entry + SPRITE_ENTRY] = bytes((width | (mask << 4), height)) + words(offset) + bytes((size & 255,))


def db(data):
    return "\n".join("        db " + ", ".join(map(str, data[i:i + 24])) for i in range(0, len(data), 24))


def title_art():
    screen = stages.make_screens.title_screen()
    # Store the picture in vertical strips; the road edges compress better
    # than in ULA order. The three text rows are drawn by the front end.
    for top, end in ((0, 64), (64, 128), (128, 168)):
        bitmap = bytes(screen[(y & 7) * 256 + (y & 56) * 4 + (y & 192) * 32 + x]
                       for x in range(32) for y in range(top, end))
        yield bitmap + (screen[6144:6816] if end == 168 else b"")


def title_notes():
    tick, sections = TUNES["title"]
    # The lead line, with a short rotation through each broken chord.
    for _, _, _, _, bars in sections:
        for _, phrase in bars:
            for token in phrase.split():
                if token.startswith("!"):
                    continue
                note, duration = token.split(":")
                name, _, chord = note.lstrip("@/").partition(".")
                root = note_index(name)
                length = int(duration) * tick
                intervals = (0, 3 if chord.startswith("m") and chord != "maj7" else 4, 7)
                def pitch(interval):
                    hz = 440 * 2 ** ((root + interval + 35 - 69) / 12)
                    return round(3500000 / (2 * 57 * hz))
                if note.startswith("@"):
                    for offset in range(0, length, 2 * tick):
                        yield min(length - offset, 2 * tick), pitch(intervals[offset // (2 * tick) % 3])
                else:
                    yield length, pitch(0)


def generate(path, output):
    cfg = yaml.safe_load(path.read_text(encoding="utf-8"))
    output.mkdir(parents=True, exist_ok=True)
    address = stages.TRACK_CACHE
    rounds = [(row, col, st) for row, items in enumerate(cfg["rows"]) for col, st in enumerate(items)]
    assert len(cfg["rows"]) == 5 and len(rounds) == 15
    tracks, par_times = [], []
    for row, _, st in rounds:
        segments, objects, length, tunnel = stages.fitted_track(row, st["seed"], cfg["themes"][st["theme"]])
        tracks.append(track_data(address, segments, objects, length, tunnel))
        par_times.append(stages.par_time(segments, length))
    counts = Counter(
        tuple(raw[i + 2:i + 4])
        for raw in tracks
        for i in range(int.from_bytes(raw[2:4], "little") - address, len(raw) - 4, 4)
    )
    pairs = {pair: i for i, (pair, _) in enumerate(counts.most_common(128))}
    archive = []
    files = {}

    def stream(label, data):
        compressed = zpack.pack(data, output.parent)
        assert zpack.unpack(compressed) == data
        files[label] = len(compressed)
        archive.extend([label + ":", db(compressed)])

    groups = {"Shared": stages.SHARED_TYPES + ["sign_tunnel"]}
    groups.update({name: theme["types"] for name, theme in cfg["themes"].items()})
    sprite_info = []
    for name, objects in groups.items():
        raw, expected = bytearray(), bytearray()
        offsets = []
        for kind in objects:
            offsets.append(len(expected))
            shifts = (3,) if kind in ("sign_l", "sign_r") else ()
            sprite(kind, raw, expected, shifted_sizes=shifts, nearest=1 if name == "Shared" else 2)
        stream("Sprites_" + name, raw)
        (output / f"sprites_{name}.bin").write_bytes(expected)
        sprite_info.append((name, len(raw), len(expected)))
        groups[name] = offsets

    for index, data in enumerate(title_art()):
        stream(f"TitleArt{index}", data)
    archive.extend(["TitleTune48:", db([value for note in title_notes() for value in note] + [0])])

    table = ["NUM_ROWS EQU 5", "NUM_STAGES EQU 15", "StageTable:"]
    for i, ((row, col, config), raw, par) in enumerate(zip(rounds, tracks, par_times, strict=True)):
        theme = cfg["themes"][config["theme"]]
        style = theme["horizon"]["style"]
        palette = {**theme["palette"], **config.get("palette", {})}
        palette_bytes = bytes(palette[key] for key in stages.PALETTE_KEYS)
        panorama = round_art.panorama(style, config["seed"], config.get("vista")).tobytes()
        art = palette_bytes + panorama
        stream(f"Art_{i}", palette_bytes + bytes(panorama[y * 32 + x] for x in range(32) for y in range(16)))
        (output / f"art_{i}.bin").write_bytes(art)
        track = compact_track(raw, address, pairs)
        files[f"Track_{i}"] = len(track)
        archive.extend([f"Track_{i}:", db(track)])
        (output / f"track_{i}.bin").write_bytes(raw)
        region = config["theme"]
        left, right = (row + 1) * (row + 2) // 2 + col, (row + 1) * (row + 2) // 2 + col + 1
        if row == 4:
            left = right = 255
        table.extend([
            f"        dw Theme_{region}, Track_{i}, Art_{i}, RoundName_{region}, Clouds_{region}",
            f"        db {left}, {right}, {row + 1}",
            f"        dw {par}",
            "        db 0",
        ])
    for name, theme in cfg["themes"].items():
        archive.append(f'RoundName_{name}: db "{theme["name"]}", 0')
        # One carefully placed sky panel per region. The scrolling landmarks
        # and all nine palette bytes are still drawn from each round's art.
        representative = next(stage for row in cfg["rows"] for stage in row if stage["theme"] == name)
        clouds = round_art.sky(theme["horizon"]["style"], representative["seed"]).tobytes()
        stream(f"Clouds_{name}", clouds)
        kinds = ["traffic", "sign_r", "sign_l", "fork", *theme["types"][:2], "van", "truck",
                 *theme["types"][2:], "sign_tunnel"]
        inks = {**stages.OBJ_INKS, **theme.get("inks", {})}
        offsets = [f"ThemeSprites + {offset}" for offset in groups[name]]
        shared = [f"SharedSprites + {offset}" for offset in groups["Shared"]]
        directory = ["Scn_traffic", *shared[:3], *offsets[:2], "Scn_van", "Scn_truck",
                     *offsets[2:], shared[3]]
        table.extend([f"Theme_{name}: dw Sprites_{name}", db([inks.get(kind, 255) for kind in kinds]),
                      "        dw " + ", ".join(directory)])
        (output / f"clouds_{name}.bin").write_bytes(clouds)
    table.append("EndingNames: dw " + ", ".join(f'Ending_{st["theme"]}' for st in cfg["rows"][-1]))
    for st in cfg["rows"][-1]:
        name = st["theme"]
        archive.append(f'Ending_{name}: db "{stages.make_screens.ENDINGS[name]}", 0')
    table.extend(["ObjectKinds:", db(KINDS), "ObjectPairs:", db([byte for pair in pairs for byte in pair])])
    # Keep the original race dashboard.
    dash = round_art.dash_header()
    table.append(f"SHARED_SPRITES_SIZE EQU {sprite_info[0][2]}")
    table.append(f"SPRITE_SCRATCH_48 EQU {max(raw for _, raw, _ in sprite_info)}")
    table.append(f"THEME_SPRITES_SIZE EQU {max(size for name, _, size in sprite_info if name != 'Shared')}")
    resident = ["DashHeader:", db(dash)]
    for name in stages.RESIDENT_TYPES:
        shifts = {2: 2, 3: 2} if name == "traffic" else {}
        constants, _, data = scenery.emit_type(name, previews=False, shifts_by_size=shifts, trim_unshifted=True)
        resident += constants + [f"Scn_{name}:"]
        for index in scenery.size_indices(name):
            label = f"Scn_{name}_{index}"
            resident.extend([f"        db {label}_w | ({label}_m << 4), {label}_h",
                             f"        dw {label}",
                             f"        db {label}_s & 255"])
        resident += data
    resident.extend(f"TYPE_{kind.upper()} EQU {number}" for kind, number in stages.TYPE_IDS.items())
    resident.append(f"SCN_SIZES EQU {len(scenery.SIZES)}")
    for name, lines in (("zx48_table.asm", table), ("zx48_archive.asm", archive), ("zx48_resident.asm", resident)):
        (output / name).write_text("\n".join(lines) + "\n", encoding="ascii")
    print("Compressed bytes:", sum(files.values()),
          {key: sum(v for k, v in files.items() if k.startswith(key))
           for key in ("Track", "Sprites", "Art", "Clouds")})
    print("Sprite scratch and cache bytes:", sprite_info)


def tape(directory):
    sym = symbols(directory / "speedrun.sym")
    image = (directory / "speedrun.bin").read_bytes()
    resident = (directory / "resident.bin").read_bytes()
    entry = sym["TapeEntry"]
    program = (
        basic_line(10, ["BORDER", 0, ":", "PAPER", 0, ":", "INK", 7, ":", "CLEAR", entry - 1])
        + basic_line(20, ["LOAD", '""', "CODE"])
        + basic_line(30, ["LET", "e=", "USR", entry])
    )
    tap = (header(0, "SPEED RUN", len(program), 10, len(program)) + tap_block(255, program)
           + header(3, "SPEED 48K", len(image), entry, 32768) + tap_block(255, image)
           + tap_block(255, resident))
    (directory / "speedrun48.tap").write_bytes(tap)
    memory_map(directory, sym)
    print(f"48K tape: {len(tap)} bytes, {tape_seconds(tap):.1f} seconds at standard speed")


def memory_map(directory, sym):
    rows = [
        (0x4000, sym["SCN_DATA"], "Display, also decoder scratch between stages"),
        (sym["SCN_DATA"], sym["ScnEnd"], "Resident front end, renderer and graphics"),
        (sym["SharedSprites"], sym["SharedSpritesEnd"], "Expanded shared signs"),
        (sym["SharedSpritesEnd"], sym["TRACK_CACHE"], "Free contiguous space below the track"),
        (sym["TRACK_CACHE"], sym["TapeEntry"], "Active track cache"),
        (sym["TapeEntry"], sym["STACK_TOP"] - 128, "Engine, tables, IM2 and working variables"),
        (sym["STACK_TOP"] - 128, sym["STACK_TOP"], "Reserved stack"),
        (sym["ArchiveStart"], sym["ArchiveDataEnd"], "Immutable archive for all 15 rounds and title art"),
        (sym["ArchiveDataEnd"], sym["ArchiveEnd"], "Options and beeper code with working state"),
        (sym["ThemeSprites"], sym["ThemeSpritesEnd"], "Largest expanded regional sprite group"),
        (sym["ThemeSpritesEnd"], sym["PANO_CACHE"], "Panorama alignment"),
        (sym["PANO_CACHE"], sym["CacheEnd"], "Active scrolling panorama"),
        (sym["CacheEnd"], 0x10000, "Free contiguous space at top of RAM"),
    ]
    lines = ["Speed Run 48K peak RAM map", ""]
    lines.extend(f"{start:04X}-{end - 1:04X} {end - start:5}  {description}"
                 for start, end, description in rows if start < end)
    lines.extend([
        "",
        f"Scenery decode scratch: {sym['SPRITE_SCRATCH_48']} bytes inside the display bitmap, "
        "plus a 64-byte variant directory.",
        "Title decoding borrows the shared signs and track caches, which are rebuilt before racing.",
    ])
    (directory / "memory_map.txt").write_text("\n".join(lines) + "\n", encoding="ascii")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("gen", "tap"))
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    if args.mode == "gen":
        generate(Path("assets/stages.yaml"), args.directory)
    else:
        tape(args.directory)
