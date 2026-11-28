#!/usr/bin/env python3
"""Boot the 48K tape through the ROM, then check assets and race routes."""
import argparse
from bisect import bisect_left
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import re
from struct import pack, pack_into, unpack_from
import subprocess
import sys

sys.path.insert(0, "tools")
from make_tap import symbols
from make_screens import ENDINGS, title_screen
from PIL import Image
import yaml


def read_ram(ram, address, size):
    """Translate a CPU address into zxsim's bank-ordered memory dump."""
    bank = (5, 2, 0)[(address - 0x4000) // 0x4000]
    offset = bank * 0x4000 + (address & 0x3FFF)
    return ram[offset:offset + size]


def cell_address(row, col, line):
    y = row * 8 + line
    return 0x4000 | ((y & 0xC0) << 5) | ((y & 7) << 8) | ((y & 0x38) << 2) | col


WATCH = re.compile(r"watch f=(\d+) T=(\d+) PC=\w+ AF=([0-9A-F]{2})")


class Check:
    def __init__(self, simulator, directory, rom):
        self.simulator, self.directory, self.rom = simulator, directory, rom
        self.s = symbols(directory / "speedrun.sym")
        self.snapshot = (directory / "speedrun.sna").read_bytes()
        self.themes = [st["theme"] for row in yaml.safe_load(Path("assets/stages.yaml").read_text())["rows"] for st in row]

    def run(self, args, label, *, frames, stop=None, stop_hit=1, watch=None, stack_usage=None):
        dump = self.directory / f"check_{label}.ram"
        command = [self.simulator, "-48", *args, "-n", str(frames), "-D", str(dump)]
        if stop:
            command += ["-H", f"{self.s[stop]}:{stop_hit}"]
        if watch:
            symbol, limit = watch
            command += ["-w", f"{self.s[symbol]}:{limit}"]
        if stack_usage is not None:
            command += ["-u", f"0xBF80:0xC000:{stack_usage}"]
        result = subprocess.run(command, capture_output=True, text=True, check=True)
        assert not result.stderr, result.stderr
        if stop:
            assert f"stopped at {self.s[stop]:04X}" in result.stdout, (label, result.stdout[-500:])
        events = [(int(frame), int(t), int(a, 16)) for frame, t, a in WATCH.findall(result.stdout)]
        ram = dump.read_bytes()
        dump.unlink()
        return ram, events

    def tape(self):
        args = ["--rom", self.rom, "--rom-tape", "325", "-T", str(self.directory / "speedrun48.tap"),
                "-k", "165:J", "-k", "176:none", "-k", "190:SS+P", "-k", "201:none",
                "-k", "215:SS+P", "-k", "226:none", "-k", "245:ENTER", "-k", "255:none"]
        ram, events = self.run(args, "tape", frames=12750, stop="MainLoop", watch=("start", 1))
        assert len(events) == 1
        self.check_archive(ram)
        self.assets(ram, 0)
        boot = events[0][0]
        print(f"48K ROM loaded BASIC and the entire tape at frame {boot} and entered the demo")
        restart = args + ["--eject", str(boot + 90),
                          "-k", f"{boot + 100}:Q", "-k", f"{boot + 107}:none",
                          "-k", f"{boot + 200}:H", "-k", f"{boot + 206}:none",
                          "-k", f"{boot + 258}:H", "-k", f"{boot + 265}:none"]
        for frame in range(boot + 3970, boot + 4500, 24):
            restart += ["-k", f"{frame}:Q", "-k", f"{frame + 8}:none"]
        ram, starts = self.run(restart, "restart", frames=boot + 4550,
                               stop="OvStartGame", stop_hit=2, watch=("OvStartGame", 2))
        assert len(starts) == 2 and starts[0][0] >= boot + 100 and starts[1][0] >= boot + 3970, starts
        self.check_archive(ram)
        assert read_ram(ram, self.s["GameState"], 1) == b"\0"
        print("Started a game, paused, reached time-up and started again with the tape disconnected")

    def frontend(self):
        snapshot = str(self.directory / "speedrun.sna")
        ram, _ = self.run([snapshot], "title_art", frames=100, stop="TitlePrompt")
        artwork = title_screen()
        for row in range(21):
            for line in range(8):
                address = cell_address(row, 0, line)
                assert read_ram(ram, address, 32) == artwork[address - 0x4000:address - 0x4000 + 32]
        assert read_ram(ram, 0x5800, 21 * 32) == artwork[6144:6816]
        _, edges = self.run([snapshot], "title_sound", frames=85, watch=("ToneUntil.edge", 3000))
        assert len(edges) > 100 and {a for _, _, a in edges} == {0, 16}
        assert len({t2 - t1 for (f1, t1, _), (f2, t2, _) in zip(edges, edges[1:]) if f1 == f2}) > 2
        keys = ("50:ENTER", "57:none", "80:5", "87:none", "100:6", "107:none",
                "120:2", "127:none", "140:4", "147:none",
                "160:W", "167:none", "180:S", "187:none", "200:J", "207:none",
                "220:K", "227:none", "240:M", "247:none",
                "270:ENTER", "277:none", "320:W", "327:none")
        args = [snapshot, *(argument for key in keys for argument in ("-k", key))]
        ram, edges = self.run(args, "options", frames=400, stop="OvStartGame",
                              watch=("ToneUntil.edge", 3000))
        assert read_ram(ram, self.s["SoundMode"], 1) == b"\1"
        assert read_ram(ram, self.s["Difficulty"], 1) == b"\2"
        assert read_ram(ram, self.s["KeyMap"], 10) == bytes((0xBF, 4, 0xBF, 8, 0xFD, 2, 0xFB, 2, 0x7F, 4))
        assert edges and all(frame < 57 for frame, _, _ in edges)
        _, edges = self.run(args + ["-k", "520:W", "-k", "675:none"], "engine",
                            frames=750, watch=("ToneUntil.edge", 16000))
        racing = [(f, t) for f, t, _ in edges if f > 530]
        assert racing and len({t2 - t1 for (f1, t1), (f2, t2) in zip(racing, racing[1:]) if f1 == f2}) > 2
        print("The title picture matches the 128K art. Options, custom keys, title music and engine output passed.")

    def beeper_effects(self):
        snapshot = str(self.directory / "speedrun.sna")
        cases = (("StartBeep", ("80:Q", "87:none"), 340, 4),
                 ("CrashStart", ("80:Q", "285:Q+P", "425:none"), 425, 1),
                 ("WarnBeep", ("80:Q", "87:none"), 3500, 7))
        for effect, keys, end, minimum in cases:
            args = [snapshot, *(argument for key in keys for argument in ("-k", key))]
            _, calls = self.run(args, effect, frames=end, watch=(effect, minimum + 2))
            assert len(calls) >= minimum, effect
            _, edges = self.run(args, f"{effect}_edges", frames=calls[-1][0] + 12,
                                watch=("ToneUntil.edge", 70000))
            after = [(frame, t, a) for frame, t, a in edges if calls[-1][0] < frame < calls[-1][0] + 9]
            assert len(after) >= 10 and {a for _, _, a in after} == {0, 16}, effect
            assert any(f1 == f2 and 800 < t2 - t1 < 4000
                       for (f1, t1, _), (f2, t2, _) in zip(after, after[1:])), effect
        print("Verified beeper pulses for the starting lights, a crash and the low timer.")

    def check_archive(self, ram):
        low, high = self.s["ArchiveStart"], self.s["ArchiveDataEnd"]
        assert read_ram(ram, low, high - low) == self.snapshot[low - 0x4000 + 27:high - 0x4000 + 27]

    def assets(self, ram, stage):
        def data(addr, size):
            return read_ram(ram, addr, size)

        track = (self.directory / f"track_{stage}.bin").read_bytes()
        art = (self.directory / f"art_{stage}.bin").read_bytes()
        assert data(self.s["Stage"], 1) == bytes((stage,))
        assert data(self.s["TRACK_CACHE"], len(track)) == track, f"track {stage}"
        assert data(self.s["THEME_CACHE"] + 6, 9) == art[:9], f"palette {stage}"
        assert data(self.s["PANO_CACHE"], 512) == art[9:], f"panorama {stage}"
        clouds = (self.directory / f"clouds_{self.themes[stage]}.bin").read_bytes()
        actual = b"".join(data(cell_address(row, 6, line), 20)
                          for row in range(6, 10) for line in range(8))
        assert actual == clouds, f"clouds {stage}"
        for theme, symbol in (("Shared", "SharedSprites"), (self.themes[stage], "ThemeSprites")):
            base = self.s[symbol]
            bitmaps = bytearray((self.directory / f"sprites_{theme}.bin").read_bytes())
            offset = 0
            while offset < len(bitmaps):
                end = offset + 45
                for i in range(offset, offset + 45, 5):
                    src = unpack_from("<H", bitmaps, i + 2)[0]
                    width, height = bitmaps[i] & 15, bitmaps[i + 1]
                    copies = 2 if bitmaps[i] & 64 else 1
                    end = max(end, src + width * height * copies)
                    pack_into("<H", bitmaps, i + 2, base + src)
                offset = end
            assert data(base, len(bitmaps)) == bitmaps, f"scenery {theme}"

    def variant(self, label, patches):
        snapshot = bytearray(self.snapshot)
        for address, value in patches:
            offset = 27 + address - 0x4000
            snapshot[offset:offset + len(value)] = value
        path = self.directory / f"check_{label}.sna"
        path.write_bytes(snapshot)
        return path

    def round(self, stage):
        path = self.variant(f"round{stage}", [(self.s["Restart"] + 1, bytes((stage,)))])
        ram, _ = self.run([str(path)], f"round{stage}", frames=80, stop="TitleScreen")
        self.check_archive(ram)
        self.assets(ram, stage)
        path.unlink()

    def scan_frames(self, snapshot, frames, keys, *options, first=0):
        command = [self.simulator, str(snapshot), "-48", "-q", "-n", str(frames), "-v", "-", *options]
        command += ["--capture-from", str(first)]
        for key in keys:
            command += ["-k", key]
        size = (320, 288)
        length = size[0] * size[1] * 3
        with subprocess.Popen(command, stdout=subprocess.PIPE) as proc:
            for _ in range(first, frames):
                yield Image.frombytes("RGB", size, proc.stdout.read(length))
            assert proc.wait() == 0

    def sprite_raster(self):
        # Hold a stationary view at a busy fork during the starting lights.
        # A sprite erased for part of the refresh changes the visible crop
        # even though the camera, sprites and road are stationary.
        s = self.s
        start = s["RestartState"] - 0x4000 + 27
        pattern = b"\x21\x00\x00\x22" + pack("<H", s["Pos"])
        operand = self.snapshot.index(pattern, start, start + 65) - 27 + 0x4001
        length = unpack_from("<H", (self.directory / "track_0.bin").read_bytes(), 4)[0]
        fork = self.variant("sprite_raster", [(operand, pack("<H", length - 2300))])
        views = {
            image.crop((32, 132, 288, 206)).tobytes()
            for frame, image in enumerate(self.scan_frames(fork, 205, ("60:Q", "66:none")))
            if frame >= 130
        }
        assert len(views) == 1, f"{len(views)} distinct views of the stationary fork"
        fork.unlink()
        sheet = Image.open("assets/gfx/car.png").convert("RGB")
        poses = {sheet.crop((x, 8, x + 64, 32)).tobytes() for x in range(0, sheet.width, 64)}
        keys = ("60:Q", "400:Q+P", "420:Q", "520:Q+O", "545:Q", "700:Q+P", "760:Q")
        tears = [
            frame
            for frame, image in enumerate(self.scan_frames(self.directory / "speedrun.sna", 1000, keys))
            if frame >= 120 and image.crop((128, 216, 192, 240)).tobytes() not in poses
        ]
        assert len(tears) <= 2, f"player car changed mid-refresh in {tears}"
        print(f"Stationary fork held all 75 refreshes. Player car intact in {880 - len(tears)}/880 refreshes.")

    def transient_pixels(self, snapshot, label, first, last, top, bottom, keys, *, palette_index=None):
        # Detect pixels present in neither finished scene as the live
        # display crosses an update.
        snapshots = self.directory / f"check_{label}.screens"
        capture = max(first - 8, 0)
        crop = (32, 48 + top, 288, 48 + bottom)
        frames = self.scan_frames(snapshot, last, keys,
                                  "--screens", f"{self.s['SwapRaceSprites']}:{snapshots}", first=capture)
        captured = [image.crop(crop).tobytes() for image in frames]
        palette = [level if ink & mask else 0
                   for level in (215, 255) for ink in range(8) for mask in (2, 4, 1)]
        commits, finished = [], []
        data = snapshots.read_bytes()
        snapshots.unlink()
        size = 4 + 256 * 192
        assert len(data) % size == 0
        palette_seen = False
        for start in range(0, len(data), size):
            commits.append(unpack_from("<I", data, start)[0])
            strip = data[start + 4 + top * 256:start + 4 + bottom * 256]
            if palette_index is not None and palette_index in strip:
                palette_seen = True
            image = Image.frombytes("P", (256, bottom - top), strip)
            image.putpalette(palette)
            finished.append(image.convert("RGB").tobytes())
        transient = 0
        assert commits[0] < first <= commits[-1] and commits[-1] >= last - 8
        assert palette_index is None or palette_seen, "expected feature absent from the completed frames"
        for frame in range(first, commits[-1]):
            after = bisect_left(commits, frame)
            before_rgb, after_rgb = finished[after - 1], finished[after]
            raster = captured[frame - capture]
            for offset in range(0, len(raster), 768):
                line = slice(offset, offset + 768)
                if raster[line] in (before_rgb[line], after_rgb[line]):
                    continue
                transient += sum(raster[i:i + 3] not in (before_rgb[i:i + 3], after_rgb[i:i + 3])
                                 for i in range(offset, offset + 768, 3))
        return transient

    def road_raster(self):
        keys = ("60:Q", "400:Q+P", "420:Q", "520:Q+O", "545:Q", "700:Q+P",
                "760:Q", "1080:O+Q", "1140:Q")
        transient = self.transient_pixels(self.directory / "speedrun.sna", "road",
                                          120, 1450, 96, 120, keys)
        assert transient < 4000, f"{transient} transient pixels in the top three road rows"
        print(f"Top three road rows: {transient} transient pixels during 1,450-refresh test.")

    def tunnel_raster(self):
        path = self.route_snapshot((0, 0, 0, 0), "tunnel_raster")
        try:
            # The Alpine entrance paints dark blue over the snowy road.
            # The palette assertion keeps the test from passing on an
            # empty approach if the auto driver's timing changes.
            transient = self.transient_pixels(path, "tunnel", 4500, 4900, 96, 160,
                                              ("80:Q", "86:none"), palette_index=1)
            assert transient < 12000, f"{transient} transient road pixels on the tunnel approach"
            print(f"Alpine tunnel approach: {transient} transient road pixels over 400 refreshes.")
        finally:
            path.unlink()

    def route_snapshot(self, choices, name):
        """Run the production demo driver with a scripted fork choice."""
        s = self.s
        pos = s["OvStartGame"] - 0x4000 + 27
        store = b"\x32" + pack("<H", s["DemoMode"])
        patch = self.snapshot.index(store, pos, pos + 20) - 27 + 0x4000
        program = s["CacheEnd"]
        autosteer = b"\x3C" + store + b"\x3D\xC9"  # inc a; ld (DemoMode),a; dec a; ret
        choose = program + len(autosteer)
        table = choose + 15
        script = (b"\xE5\x3A" + pack("<H", s["StageRow"]) + b"\x3D\x5F\x16\x00\x21"
                  + pack("<H", table) + b"\x19\x7E\xE1\xC9")
        assert len(script) == table - choose
        assert table + 4 <= 0xFFFE
        branch = s["DemoTarget.branch"]
        opcode = b"\x3A" + pack("<H", s["Stage"])
        pos = branch - 0x4000 + 27
        branch_patch = self.snapshot.index(opcode, pos, pos + 15) - 27 + 0x4000
        def call(dest):
            return b"\xCD" + pack("<H", dest)

        return self.variant(name, [(program, autosteer + script + bytes(choices)),
                                   (patch, call(program)), (branch_patch, call(choose))])

    def kerb_raster(self):
        # Reproduce the detached red character cell on the Country stage.
        first, last = 3500, 4124
        path = self.route_snapshot((0, 1, 1, 0), "kerb_raster")
        snapshots = path.with_suffix(".screens")
        frames = self.scan_frames(path, last, ("80:Q", "86:none"),
                                  "--screens", f"{self.s['SwapRaceSprites']}:{snapshots}", first=first - 8)
        red, black = b"\xff\0\0", b"\0\0\0"

        def detached_cells(rgb):
            for y in range(120, 184, 8):
                for x in range(128, 232, 8):
                    at = (y * 256 + x) * 3
                    rows = range(at, at + 8 * 768, 768)
                    if all(rgb[i:i + 27] == red * 8 + black for i in rows):
                        if any(rgb[j:j + 3] == red
                               for i in rows for j in range(i + 27, min(i + 99, i + (256 - x) * 3), 3)):
                            yield x, y

        matches = {}
        for frame, screen in enumerate(frames, first - 8):
            if frame >= first:
                cells = set(detached_cells(screen.crop((32, 48, 288, 240)).tobytes()))
                if cells:
                    matches[frame] = cells
        data = snapshots.read_bytes()
        snapshots.unlink()
        path.unlink()
        size = 4 + 256 * 192
        commits = [unpack_from("<I", data, n)[0] for n in range(0, len(data), size)]
        assert commits[0] <= first and commits[-1] >= last - 8
        palette = [level if ink & mask else 0
                   for level in (215, 255) for ink in range(8) for mask in (2, 4, 1)]
        for frame, raster_cells in matches.items():
            after = min(bisect_left(commits, frame), len(commits) - 1)
            complete_cells = set()
            for number in (after - 1, after):
                offset = number * size + 4
                image = Image.frombytes("P", (256, 192), data[offset:(number + 1) * size])
                image.putpalette(palette)
                complete_cells.update(detached_cells(image.convert("RGB").tobytes()))
            assert raster_cells <= complete_cells, (frame, raster_cells - complete_cells)
        print(f"Country stage: no detached red kerb cells in {last - first} sampled refreshes.")

    def route(self, choices):
        s = self.s
        name = "".join(map(str, choices))
        path = self.route_snapshot(choices, name)
        stack = path.with_suffix(".stack")
        ram, events = self.run([str(path), "-k", "80:Q", "-k", "86:none"], name, frames=22000,
                               stop="ResultsReady", watch=("RaceFrame", 10000), stack_usage=stack)
        used = stack.read_bytes()
        stack.unlink()
        peak = len(used) - next(i for i, access in enumerate(used) if access & 2)
        assert peak < 128, (name, peak)
        assert read_ram(ram, s["StageTimes"] + 8, 2) != b"\0\0", f"route {name} ran out of time"
        expected = [0]
        col = 0
        for row, choice in enumerate(choices, 1):
            col += choice
            expected.append(row * (row + 1) // 2 + col)
        assert read_ram(ram, s["Route"], 5) == bytes(expected), f"route {name}"
        for col, char in enumerate(ENDINGS[self.themes[expected[-1]]], 5):
            drawn = b"".join(read_ram(ram, cell_address(5, col, line), 1) for line in range(8))
            assert drawn == read_ram(ram, s["Font"] + (ord(char) - 32) * 8, 8)
        self.check_archive(ram)
        # The checkpoint gaps are isolated, with no gameplay updates between
        # them. Start-up and other shorter intervals are included.
        gaps = Counter(b[0] - a[0] for a, b in zip(events, events[1:]))
        assert sum(n for delay, n in gaps.items() if delay >= 9) == 4, (name, gaps)
        assert all(delay in (4, 5) or delay >= 9 for delay in gaps), (name, gaps)
        racing = sum(n for delay, n in gaps.items() if delay < 9)
        refreshes = sum(delay * n for delay, n in gaps.items() if delay < 9)
        assert gaps[5] * 150 <= racing, (name, gaps)
        print(f"Race pacing {name}: {racing * 50 / refreshes:.3f} fps, intervals {dict(sorted(gaps.items()))}, "
              f"stack {peak} bytes")
        path.unlink()
        return expected


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("simulator")
    parser.add_argument("directory", type=Path)
    parser.add_argument("--rom")
    args = parser.parse_args()
    check = Check(args.simulator, args.directory, args.rom)
    check.frontend()
    check.beeper_effects()
    if args.rom:
        check.tape()
    check.sprite_raster()
    check.road_raster()
    check.tunnel_raster()
    check.kerb_raster()
    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(check.round, range(15)))
        print("All 15 tracks, palettes, panoramas, clouds and scenery caches match the generated data")
        choices = ((0,0,0,0), (0,0,0,1), (0,0,1,0), (1,0,0,1),
                   (0,1,1,0), (1,1,0,1), (1,1,1,0), (1,1,1,1))
        routes = list(pool.map(check.route, choices))
    assert len({(a, b) for route in routes for a, b in zip(route, route[1:])}) == 20
    assert len({route[-1] for route in routes}) == 5
    print("Completed all 20 fork transitions and reached all five goals")
