#!/usr/bin/env python3
"""An Amstrad CPC disk in AMSDOS's DATA format, as an Extended CPC DSK
(docs/port_cpc.md 5.11). From the Wonder Boy port's tools/cpc/make_dsk.py,
as it is but for the disc's name.

The DATA format: one side, 40 tracks of 9 sectors of 512 bytes, the sectors
numbered &C1-&C9 and laid on each track 2:1 interleaved (C1 C6 C2 C7 C3 C8 C4
C9 C5, as AMSDOS formats them). CP/M 2.2's filing system with no reserved
tracks: 1K blocks, blocks 0 and 1 (track 0's first four sectors) the
directory of 64 entries, 180 blocks in all; a block's sectors are the next
two in (track, sector number) order. A binary file starts with AMSDOS's
128-byte header (its type, load and run addresses, length and checksum), so
RUN"NAME" loads and runs it.

Every file is laid in consecutive blocks, so the game's own reader
(src/cpc/fdc.asm) can read one by its first sector and length: the
layout returned gives each file's first logical sector (track x 9 + sector
- &C1) and its length on disk. The disk is read back through its directory
and checked before it is written.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass
from pathlib import Path

SECTOR = 512
SECTORS = 9
TRACKS = 40
FIRST_ID = 0xC1
INTERLEAVE = (0, 5, 1, 6, 2, 7, 3, 8, 4)        # the sectors' numbers (- &C1) in track order
BLOCK = 1024
DIRECTORY_BLOCKS = 2
ENTRIES = 64
BLOCKS = TRACKS * SECTORS * SECTOR // BLOCK     # 180
RECORD = 128
EXTENT_RECORDS = 128                            # 16K an extent (8-bit block numbers, 16 a entry)


@dataclass
class DiskFile:
    name: str                   # "DISC.BIN"
    data: bytes
    load: int | None = None     # a binary file: AMSDOS's header with these
    run: int | None = None


def amsdos_header(name: str, length: int, load: int, run: int) -> bytes:
    """AMSDOS's 128-byte header of a binary file (type 2)."""
    base, _, ext = name.upper().partition(".")
    header = bytearray(RECORD)
    header[1:9] = base.ljust(8).encode("ascii")[:8]
    header[9:12] = ext.ljust(3).encode("ascii")[:3]
    header[18] = 2
    header[21:23] = load.to_bytes(2, "little")
    header[24:26] = length.to_bytes(2, "little")
    header[26:28] = run.to_bytes(2, "little")
    header[64:67] = length.to_bytes(3, "little")
    header[67:69] = (sum(header[:67]) & 0xFFFF).to_bytes(2, "little")
    return bytes(header)


def logical_sector(track: int, sector: int) -> int:
    return track * SECTORS + sector


def place(sector_index: int) -> tuple[int, int]:
    """A logical sector -> (track, sector number &C1-&C9)."""
    return sector_index // SECTORS, FIRST_ID + sector_index % SECTORS


def build(files: list[DiskFile]) -> tuple[bytes, dict[str, tuple[int, int]]]:
    """-> the Extended DSK, and per file (first logical sector of its
    contents past any header, its bytes on disk)."""
    image = bytearray(b"\xE5" * (TRACKS * SECTORS * SECTOR))
    directory = bytearray(b"\xE5" * (DIRECTORY_BLOCKS * BLOCK))
    layout: dict[str, tuple[int, int]] = {}
    next_block = DIRECTORY_BLOCKS
    entry = 0
    for file in files:
        body = file.data
        if file.load is not None:
            body = amsdos_header(file.name, len(file.data), file.load, file.run or file.load) + file.data
        blocks = -(-len(body) // BLOCK)
        if next_block + blocks > BLOCKS:
            raise ValueError(f"{file.name}: the disk is full ({next_block + blocks} blocks of {BLOCKS})")
        start = next_block * BLOCK
        image[start:start + len(body)] = body
        header_bytes = RECORD if file.load is not None else 0
        layout[file.name] = ((start + header_bytes) // SECTOR, len(file.data)) if header_bytes == 0 else \
            (start // SECTOR, len(body))
        base, _, ext = file.name.upper().partition(".")
        records = -(-len(body) // RECORD)
        for extent in range(max(1, -(-records // EXTENT_RECORDS))):
            if entry >= ENTRIES:
                raise ValueError("the directory is full")
            record = bytearray(32)
            record[0] = 0
            record[1:9] = base.ljust(8).encode("ascii")[:8]
            record[9:12] = ext.ljust(3).encode("ascii")[:3]
            record[12] = extent
            record[15] = min(EXTENT_RECORDS, records - extent * EXTENT_RECORDS)
            first = next_block + extent * 16
            count = min(16, blocks - extent * 16)
            record[16:16 + count] = bytes(range(first, first + count))
            directory[entry * 32:entry * 32 + 32] = record
            entry += 1
        next_block += blocks
    image[:len(directory)] = directory
    check(bytes(image), files)
    return extended_dsk(bytes(image)), layout


def check(image: bytes, files: list[DiskFile]) -> None:
    """Every file read back through the directory as AMSDOS would."""
    found: dict[str, list[tuple[int, bytes]]] = {}
    for k in range(ENTRIES):
        record = image[k * 32:k * 32 + 32]
        if record[0] == 0xE5:
            continue
        name = record[1:9].decode().rstrip() + "." + record[9:12].decode().rstrip()
        blocks = [b for b in record[16:32] if b]
        data = b"".join(image[b * BLOCK:(b + 1) * BLOCK] for b in blocks)[:record[15] * RECORD]
        found.setdefault(name, []).append((record[12], data))
    for file in files:
        data = b"".join(d for _e, d in sorted(found[file.name.upper()]))
        if file.load is not None:
            header = data[:RECORD]
            if header[67] | header[68] << 8 != sum(header[:67]) & 0xFFFF:
                raise ValueError(f"{file.name}: header checksum")
            data = data[RECORD:]
        if data[:len(file.data)] != file.data:
            raise ValueError(f"{file.name}: read back differs")


def extended_dsk(image: bytes) -> bytes:
    """The image as an Extended CPC DSK: each track its sectors in the
    interleaved order, their ids, 512 bytes each."""
    track_bytes = 256 + SECTORS * SECTOR
    out = bytearray(256)
    out[0:34] = b"EXTENDED CPC DSK File\r\nDisk-Info\r\n"
    out[34:48] = b"Speed Run 6128"
    out[48] = TRACKS
    out[49] = 1
    for t in range(TRACKS):
        out[52 + t] = track_bytes >> 8
    for t in range(TRACKS):
        info = bytearray(256)
        info[0:12] = b"Track-Info\r\n"
        info[16] = t
        info[17] = 0
        info[20] = 2                # 512 bytes
        info[21] = SECTORS
        info[22] = 0x4E            # gap 3
        info[23] = 0xE5            # filler
        data = bytearray()
        for k, s in enumerate(INTERLEAVE):
            info[24 + 8 * k:32 + 8 * k] = bytes([t, 0, FIRST_ID + s, 2, 0, 0]) + struct.pack("<H", SECTOR)
            start = logical_sector(t, s) * SECTOR
            data += image[start:start + SECTOR]
        out += info + data
    return bytes(out)


def write(path: Path, files: list[DiskFile]) -> dict[str, tuple[int, int]]:
    dsk, layout = build(files)
    path.write_bytes(dsk)
    return layout
