#!/usr/bin/env python3
"""Run the Amstrad CPC port headless in MAME cpc6128 (tools/mame/cpc_harness.lua,
from the Wonder Boy port's).

    from cpc_harness import run, boot
    values = run(*boot(), "frames 500", "peek16 frames GameFrames", "shot title")

Commands as the Lua runner's; a symbol name may stand for an address
(build/cpc/speedrun.sym). "shot NAME" saves the screen as FOLDER/NAME.png.
The disc (build/cpc/speedrun.dsk) is in drive A; boot() types RUN"SPEED"
at the BASIC prompt and waits for the game's first frame. Returns the
results as a dict. MAME and its ROM set: CPC_MAME and CPC_ROMS (local.mk),
or the environment.

Wonder Boy's traps hold: one MAME at a time, MAME's -state hangs (load
states from Lua), wait on a game state rather than a frame count.
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "build" / "cpc" / "run"
DISK = ROOT / "build" / "cpc" / "speedrun.dsk"
SYMBOLS = ROOT / "build" / "cpc" / "speedrun.sym"
KEYS_OF = {" ": "SPACE", "\n": "ENTER", '"': "SHIFT,2", ",": ",", ".": "."}


def local_mk() -> dict[str, str]:
    out = {}
    path = ROOT / "local.mk"
    if path.exists():
        for line in path.read_text().splitlines():
            m = re.match(r"^(\w+)\s*:?=\s*(.+)$", line)
            if m:
                out[m.group(1)] = m.group(2).strip()
    return out


def msys_path(p: str) -> Path:
    m = re.match(r"^/([a-zA-Z])/(.*)$", p)
    return Path(f"{m.group(1)}:/{m.group(2)}") if m else Path(p)


_mk = local_mk()
MAME = msys_path(os.environ.get("CPC_MAME", _mk.get("CPC_MAME", "mame")))
ROMS = msys_path(os.environ.get("CPC_ROMS", _mk.get("CPC_ROMS", "roms")))


def symbols(path: Path = SYMBOLS) -> dict[str, int]:
    """sjasmplus's --sym file: NAME: EQU 0x0000ABCD"""
    out = {}
    for line in path.read_text().splitlines():
        m = re.match(r"^([\w.]+):\s+EQU\s+0x([0-9A-Fa-f]+)", line)
        if m:
            out[m.group(1)] = int(m.group(2), 16)
    return out


def typing(text: str) -> list[str]:
    """Commands that type text on the CPC's keyboard, a key at a time."""
    out = []
    for ch in text:
        out += [f"hold {KEYS_OF.get(ch, ch.upper())}", "frames 3", "release", "frames 3"]
    return out


def boot(frames: int = 2000) -> list[str]:
    """To BASIC's prompt, RUN"SPEED", and on till the game counts its frames."""
    return ["frames 120", *typing('RUN"SPEED"\n'), f"until FrameCount 5 {frames}"]


def translate(commands, syms: dict[str, int]) -> tuple[list[str], list[str]]:
    """The commands with symbol names made addresses; the screenshots' names."""
    def addr(text: str) -> int:
        base, _, off = text.partition("+")
        v = syms[base] if base in syms else int(base, 0)
        return v + (int(off, 0) if off else 0)

    shots, lines = [], []
    for command in commands:
        words = command.split()
        op = words[0]
        if op in ("peek8", "peek16"):           # peek8 NAME [ADDRESS]
            words = [op, words[1], str(addr(words[2] if len(words) > 2 else words[1]))]
        elif op == "peekn":                     # peekn NAME ADDRESS COUNT
            words = [op, words[1], str(addr(words[2])), words[3]]
        elif op in ("until", "untilw"):         # until ADDRESS VALUE MAXFRAMES
            words = [op, str(addr(words[1])), str(int(words[2], 0)), words[3]]
        elif op in ("poke8", "poke16"):
            words = [op, str(addr(words[1])), str(int(words[2], 0))]
        elif op == "watch":
            words = [op, str(addr(words[1]))]
        elif op == "shot":
            shots.append(words[1])
            words = ["shot"]
        lines.append(" ".join(words))
    return lines, shots


def run(*commands: str, disk: Path = DISK, timeout: int = 600, debug: bool = False,
        folder: Path = RUN, wav: Path | None = None, sym: Path = SYMBOLS) -> dict[str, str]:
    """debug: MAME's debugger on (for "debug" commands: traces); folder: the
    run's own (commands, results, screenshots, MAME states)."""
    syms = symbols(sym)
    folder.mkdir(parents=True, exist_ok=True)
    snaps = folder / "snaps"
    shutil.rmtree(snaps, ignore_errors=True)
    states = folder / "states"
    (states / "cpc6128").mkdir(parents=True, exist_ok=True)
    lines, shots = translate(commands, syms)
    (folder / "commands.txt").write_text("\n".join(lines) + "\n", encoding="ascii")
    (folder / "results.txt").unlink(missing_ok=True)
    subprocess.run([str(MAME), "cpc6128", "-rompath", str(ROMS), "-flop1", str(disk.resolve()),
                    "-state_directory", str(states), "-cfg_directory", str(folder / "cfg"),
                    "-autoboot_script", str(ROOT / "tools" / "mame" / "cpc_harness.lua"),
                    "-snapshot_directory", str(snaps), "-video", "none",
                    "-sound", "none" if not wav else "auto",
                    *(["-wavwrite", str(wav)] if wav else []),
                    *(["-debug", "-debugger", "none"] if debug else []),
                    "-nothrottle", "-skip_gameinfo"], cwd=ROOT, check=True, capture_output=True,
                   timeout=timeout, env={**os.environ, "CPC_RUN": str(folder)})
    taken = sorted(snaps.rglob("*.png"))
    for name, path in zip(shots, taken):
        shutil.move(str(path), folder / f"{name}.png")
    text = (folder / "results.txt").read_text()
    return dict(line.split("=", 1) for line in text.splitlines() if "=" in line)


if __name__ == "__main__":
    for key, value in run(*sys.argv[1:]).items():
        print(f"{key}={value}")
