#!/usr/bin/env python3
"""Build the tape image build/speedrun.tap from the release snapshot
(build/release.sna: no timing bars).

Blocks:
  1. BASIC "SPEED RUN" (autostart line 10):
       10 BORDER 0: PAPER 0: INK 7: CLEAR 32767
       20 LOAD "" CODE
       30 LET e=USR 48640
       40 IF e=1 THEN PRINT "128K ONLY"
       50 IF e>1 THEN PRINT "TAPE ERROR, BLOCK ";e-10
     (the loader only returns on a 48K, or on a tape error)
  2. CODE "loader" at $BE00 (src/loader.asm)
  3. headerless standard data blocks, read by the loader's own tape routine
     (no ROM calls, interrupts off):
     compressed (tools/zpack.py): the loading screen (assets/gfx/loading.scr,
     the cover art as a Spectrum screen; to $4000), the pack
     banks 0, 1, 3, 4, 6 (unpacked to $C000), bank 2 ($8000-$BDBF: code,
     tables, chains) and the resident part of bank 5 ($5B00 up to ScnEnd),
     which replaces BASIC - then the game starts.

usage: make_tap.py build/release.sna build/release.sym build/speedrun.tap
"""
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
import make_screens                 # noqa: E402
import zpack                        # noqa: E402

LOADER_ORG = 0xBE00
LOADING_SCREEN = os.path.join(os.path.dirname(__file__), "..", "assets", "gfx", "loading.scr")
BANK2_END = 0xBDC0                  # after ISR_JP; the IM2 table and stack are built at run time


def read_sna(path):
    """128K .sna -> list of 8 banks (16 KB each)."""
    d = open(path, "rb").read()
    assert len(d) > 49179 + 4, "not a 128K snapshot"
    m48 = d[27:27 + 49152]
    p7ffd = d[27 + 49152 + 2]
    cur = p7ffd & 7
    banks = [None] * 8
    banks[5], banks[2], banks[cur] = m48[:16384], m48[16384:32768], m48[32768:]
    off = 27 + 49152 + 4
    for b in range(8):
        if banks[b] is None:
            banks[b] = d[off:off + 16384]
            off += 16384
    return banks, (d[27 + 49152] | d[27 + 49153] << 8)


def symbols(path):
    out = {}
    for line in open(path):
        if ": EQU 0x" in line:
            n, v = line.split(": EQU ")
            out[n.strip()] = int(v, 16)
    return out


# ---------------------------------------------------------------- BASIC
TOKENS = {"BORDER": 0xE7, "PAPER": 0xDA, "INK": 0xD9, "CLEAR": 0xFD, "LOAD": 0xEF,
          "CODE": 0xAF, "USR": 0xC0, "PRINT": 0xF5, "LET": 0xF1, "IF": 0xFA,
          "THEN": 0xCB}


def number(n):
    """Digits as typed, then the hidden 5-byte small-integer form."""
    return str(n).encode() + bytes([0x0E, 0, 0, n & 0xFF, n >> 8, 0])


def basic_line(num, parts):
    body = bytearray()
    for p in parts:
        if isinstance(p, int):
            body += number(p)
        elif p in TOKENS:
            body.append(TOKENS[p])
        else:
            body += p.encode()
    body.append(0x0D)
    return bytes([num >> 8, num & 0xFF, len(body) & 0xFF, len(body) >> 8]) + body


def basic_program():
    return (basic_line(10, ["BORDER", 0, ":", "PAPER", 0, ":", "INK", 7, ":", "CLEAR", 32767]) +
            basic_line(20, ["LOAD", '""', "CODE"]) +
            basic_line(30, ["LET", "e=", "USR", LOADER_ORG]) +
            basic_line(40, ["IF", "e=", 1, "THEN", "PRINT", '"128K ONLY"']) +
            basic_line(50, ["IF", "e>", 1, "THEN", "PRINT", '"TAPE ERROR, BLOCK ";e-', 10]))


# ---------------------------------------------------------------- TAP
def tap_block(flag, data):
    body = bytes([flag]) + data
    x = 0
    for b in body:
        x ^= b
    body += bytes([x])
    return bytes([len(body) & 0xFF, len(body) >> 8]) + body


def header(kind, name, length, p1, p2):
    return tap_block(0, bytes([kind]) + name.ljust(10).encode()[:10] +
                     bytes([length & 0xFF, length >> 8, p1 & 0xFF, p1 >> 8, p2 & 0xFF, p2 >> 8]))


def tape_seconds(tape):
    """Playing time at the ROM's speed: pilot, sync, 855 / 1710 T pulses per
    0 / 1 bit, a second's gap after each block."""
    t, i = 0, 0
    while i < len(tape):
        n = tape[i] | tape[i + 1] << 8
        body = tape[i + 2:i + 2 + n]
        i += 2 + n
        t += (8063 if body[0] < 128 else 3223) * 2168 + 667 + 735 + 3500000
        t += sum(2 * (1710 if b >> k & 1 else 855) for b in body for k in range(8))
    return t / 3.5e6


# ---------------------------------------------------------------- TZX
TURBO_ZERO, TURBO_ONE = 420, 840    # data bit pulses (the ROM's: 855, 1710)
TURBO_PILOT_N = 1600                # pilot pulses per turbo block (ROM: 3223)
TURBO_PAUSE = 500                   # ms after each (time to unpack it)


def tzx_text(text):
    return bytes([0x30, len(text)]) + text.encode()


def tzx_standard(body, pause_ms):
    return bytes([0x10, pause_ms & 0xFF, pause_ms >> 8, len(body) & 0xFF, len(body) >> 8]) + body


def tzx_turbo(body):
    h = [2168, 667, 735, TURBO_ZERO, TURBO_ONE, TURBO_PILOT_N]
    out = bytearray([0x11])
    for v in h:
        out += bytes([v & 0xFF, v >> 8])
    out += bytes([8, TURBO_PAUSE & 0xFF, TURBO_PAUSE >> 8,
                  len(body) & 0xFF, len(body) >> 8 & 0xFF, len(body) >> 16])
    return bytes(out) + body


def tzx_seconds(tzx):
    """Playing time of the blocks this script writes."""
    t, p = 0, 10
    while p < len(tzx):
        i = tzx[p]
        if i == 0x30:
            p += 2 + tzx[p + 1]
            continue
        if i == 0x10:
            pause = tzx[p + 1] | tzx[p + 2] << 8
            n = tzx[p + 3] | tzx[p + 4] << 8
            body = tzx[p + 5:p + 5 + n]
            pilot, pn, s1, s2, z, o = 2168, 8063 if body[0] < 128 else 3223, 667, 735, 855, 1710
            p += 5 + n
        else:
            v = [tzx[p + 1 + 2 * k] | tzx[p + 2 + 2 * k] << 8 for k in range(6)]
            pilot, s1, s2, z, o, pn = v
            pause = tzx[p + 14] | tzx[p + 15] << 8
            n = tzx[p + 16] | tzx[p + 17] << 8 | tzx[p + 18] << 16
            body = tzx[p + 19:p + 19 + n]
            p += 19 + n
        t += pn * pilot + s1 + s2 + pause * 3500
        t += sum(2 * (o if b >> k & 1 else z) for b in body for k in range(8))
    return t / 3.5e6


def main(sna, sym, out):
    banks, _ = read_sna(sna)
    s = symbols(sym)
    # (port while loading, load address, port while unpacking, unpack to, data);
    # unpack port $FF: stored as it is
    build = os.path.dirname(out)
    screen = open(LOADING_SCREEN, "rb").read()            # (tools/make_loading.py, from the cover art)
    assert len(screen) == 6912
    blocks = [(0x10, 0x8000, 0x10, 0x4000, zpack.pack(screen, build))]
    for b in (0, 1, 3, 4, 6):
        data = banks[b].rstrip(b"\0")
        if data:
            blocks.append((0x10, 0x8000, 0x10 | b, 0xC000, zpack.pack(data, build)))
    blocks.append((0x17, 0xC000, 0x17, 0x8000, zpack.pack(banks[2][:BANK2_END - 0x8000], build)))
    blocks.append((0x17, 0xC000, 0x17, 0x5B00,
                   zpack.pack(banks[5][0x1B00:s["ScnEnd"] - 0x4000], build)))
    for port, addr, _, _, data in blocks:
        assert addr != 0x8000 or len(data) <= BANK2_END - 0x8000

    after = sum(len(d) for *_, d in blocks[1:])       # the progress bar: 32 cells
    tick_n = -(-after // (32 * 256))
    tab = ["; Generated by tools/make_tap.py - do not edit",
           f"GAME_START EQU ${s['start']:04X}", f"TICK_N EQU {tick_n}", "Blocks:"]
    for port, addr, uport, uaddr, data in blocks:
        tab.append(f"        db ${port:02X}")
        tab.append(f"        dw {len(data)}, ${addr:04X}")
        tab.append(f"        db ${uport:02X}")
        tab.append(f"        dw ${uaddr:04X}")
    tab.append("        db $FF")
    open(os.path.join(build, "loader_table.asm"), "w").write("\n".join(tab) + "\n")
    def loader_bin(turbo):
        name = "loader_turbo" if turbo else "loader"
        src = os.path.join(build, name + "_main.asm")
        binf = os.path.join(build, name + ".bin")
        open(src, "w").write('        DEVICE ZXSPECTRUM48\n        INCLUDE "loader.asm"\n'
                             f'        SAVEBIN "{binf}", Loader, LoaderEnd - Loader\n')
        subprocess.run(["sjasmplus", "--nologo", "--msg=war", f"-I{build}", "-Isrc", src]
                       + (["-DTURBO=1"] if turbo else []), check=True)
        return open(binf, "rb").read()

    prog = basic_program()
    total = sum(len(d) for *_, d in blocks)
    # the .tap: every block at the ROM's speed
    loader = loader_bin(False)
    tape = header(0, "SPEED RUN", len(prog), 10, len(prog)) + tap_block(0xFF, prog)
    tape += header(3, "loader", len(loader), LOADER_ORG, 32768) + tap_block(0xFF, loader)
    for *_, data in blocks:
        tape += tap_block(0xFF, bytes(data))
    open(out, "wb").write(tape)
    secs = tape_seconds(tape)
    print(f"{out}: {len(tape)} bytes, {len(blocks)} data blocks ({total} bytes), "
          f"about {int(secs) // 60} min {int(secs) % 60} s to load")
    # the .tzx: BASIC and the turbo loader at the ROM's speed, the rest turbo
    loader = loader_bin(True)
    tzx = bytearray(b"ZXTape!\x1a\x01\x14")
    tzx += tzx_text("SPEED RUN - turbo loading")
    for blk in (header(0, "SPEED RUN", len(prog), 10, len(prog)), tap_block(0xFF, prog),
                header(3, "loader", len(loader), LOADER_ORG, 32768), tap_block(0xFF, loader)):
        tzx += tzx_standard(blk[2:], 1000)
    for *_, data in blocks:
        tzx += tzx_turbo(tap_block(0xFF, bytes(data))[2:])
    tzx_out = os.path.splitext(out)[0] + ".tzx"
    open(tzx_out, "wb").write(tzx)
    secs = tzx_seconds(tzx)
    print(f"{tzx_out}: {len(tzx)} bytes, turbo, about {int(secs) // 60} min {int(secs) % 60} s to load")


if __name__ == "__main__":
    main(*sys.argv[1:4])
