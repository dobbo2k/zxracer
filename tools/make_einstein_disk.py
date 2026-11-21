#!/usr/bin/env python3
# Copied unchanged (apart from this line) from the More Burgers! project,
# tools/make_einstein_disk.py, where it is proven against Albert and real XtalDOS.
"""Build a verified bootable CP/M disc for the Tatung Einstein.

    python3 tools/make_einstein_disk.py -o OUTPUT.dsk -s SYSTEM131.CPM FILE [FILE...]
    python3 tools/make_einstein_disk.py --interleave 1 ...  raw image

Produces a single-sided Einstein disc: 40 tracks, 10 sectors of 512 bytes,
Xtal DOS in the two reserved tracks and a CP/M 2.2 filesystem in the rest.
Every file is then read back out through the directory and compared with the
original, so a disc that this script calls good is one the BDOS can read.

**The sectors are interleaved.**  Written in id order 0..9, a program reading
two consecutive sectors misses the second by the time it has asked for it, and
waits a whole revolution -- 200 ms at 300 rpm -- for it to come round again.
Laying them 0,5,1,6,2,7,3,8,4,9 gives the machine a tenth of a revolution of
thinking time between one sector and the next, which is what a 2:1 interleave
is for.  This is the layout the commercial Oh Mummy disc uses.

Interleave can only be expressed in a container that records the physical
order of the sectors, so the output is an Extended CPC DSK rather than a plain
sector image.  `--interleave 1` falls back to a raw image.

The disc parameters are the ones the machine itself uses -- the DPB Xtal DOS
1.31 installs, at BIOS131.ZSM:167-170:

    SPT 40 records/track   BSH 4 (2048-byte blocks)   BLM 15   EXM 0
    DSM 94 (95 blocks)     DRM 63 (64 entries)        AL0 80h (block 0 = dir)
    CKS 16                 OFF 2 reserved tracks

Two details are worth stating because getting either wrong yields a disc that
looks plausible and reads as garbage:

  * **Allocation numbers are 16-bit**, little-endian, eight to a directory
    entry.  Stock CP/M 2.2 would use one byte each here, because DSM is 94 and
    the rule is "16-bit only when DSM exceeds 255" -- but Xtal DOS does not
    follow that rule, and the machine settles the argument: with 8-bit numbers
    its own DIR reports exactly half the space each file occupies and loading
    a .COM fails outright.  Eight 2048-byte blocks is 16K, which is one
    logical extent, which is what EXM 0 asks for.

  * **There is no sector skew.**  Xtal DOS's BIOS jump table stops at BWRIT
    (BIOS131.ZSM:14-28) and has no SECTRAN, so logical records map straight
    through, four to each 512-byte sector.
"""

import os
import sys

SECTOR = 512
SECTORS_PER_TRACK = 10
TRACKS = 40
TRACK_BYTES = SECTOR * SECTORS_PER_TRACK       # 5120
DISC_BYTES = TRACK_BYTES * TRACKS              # 204800

SPT = 40                                       # 128-byte records per track
BLS = 2048
DSM = 94                                       # highest block number
DRM = 63                                       # highest directory entry
OFF = 2                                        # reserved tracks
FILLER = 0xE5

RECS_PER_BLOCK = BLS // 128                    # 16
RECS_PER_EXTENT = 128                          # EXM 0: one 16K extent per entry
BLOCKS_PER_EXTENT = RECS_PER_EXTENT // RECS_PER_BLOCK   # 8, stored as words
DIR_ENTRIES = DRM + 1
DIR_BLOCKS = 1                                 # AL0 = 80h
FIRST_DATA_BLOCK = DIR_BLOCKS


def record_offset(record):
    """Byte offset in the image of logical record `record` of the data area."""
    track = OFF + record // SPT
    within = record % SPT
    return track * TRACK_BYTES + (within // 4) * SECTOR + (within % 4) * 128


def block_record(block, n):
    return block * RECS_PER_BLOCK + n


def interleave_order(n, k):
    """Physical order of sector ids for an n-sector track at interleave k."""
    order = [None] * n
    pos = 0
    for sec in range(n):
        while order[pos] is not None:
            pos = (pos + 1) % n
        order[pos] = sec
        pos = (pos + k) % n
    return order


def write_edsk(disc, tracks, sectors, interleave):
    """Wrap a linear sector image as an Extended CPC DSK.

    The Track Information Block records each sector's id in the order the
    sectors physically appear, and the data follows in that same order, so the
    interleave lives in the file rather than in a driver.
    """
    order = interleave_order(sectors, interleave)
    track_bytes = 256 + sectors * SECTOR          # info block + data

    out = bytearray()
    out += b'EXTENDED CPC DSK File\r\nDisk-Info\r\n'   # 34 bytes
    out += b'MBURG mkdisc  '                             # 14-byte creator
    out += bytes([tracks, 1, 0, 0])                      # tracks, sides, unused
    sizes = bytes([track_bytes // 256]) * tracks         # track size table
    out += sizes
    out += bytes(256 - len(out))                         # pad the DIB to 256

    for t in range(tracks):
        tib = bytearray(256)
        tib[0:13] = b'Track-Info\r\n\x00'
        tib[16] = t          # track number
        tib[17] = 0          # side
        tib[20] = 2          # sector size code: 2 = 512 bytes
        tib[21] = sectors
        tib[22] = 0x4E       # GAP#3
        tib[23] = 0xE5       # filler
        for i, sec_id in enumerate(order):
            e = 24 + i * 8
            tib[e + 0] = t                  # C
            tib[e + 1] = 0                  # H
            tib[e + 2] = sec_id             # R
            tib[e + 3] = 2                  # N
            tib[e + 4] = 0                  # ST1
            tib[e + 5] = 0                  # ST2
            tib[e + 6] = SECTOR & 0xFF      # actual length
            tib[e + 7] = SECTOR >> 8
        out += tib
        for sec_id in order:
            off = t * TRACK_BYTES + sec_id * SECTOR
            out += disc[off:off + SECTOR]

    return bytes(out)


def cpm_name(path):
    base = os.path.basename(path).upper()
    stem, _, ext = base.partition('.')
    if not stem:
        raise ValueError("%s has no name" % path)
    return stem[:8].ljust(8), ext[:3].ljust(3)


def build(sources, system):
    disc = bytearray([FILLER]) * DISC_BYTES

    if system is not None:
        reserved = OFF * TRACK_BYTES
        if len(system) > reserved:
            raise ValueError("system image is %d bytes; %d fit in the reserved "
                             "tracks" % (len(system), reserved))
        disc[0:len(system)] = system
    else:
        disc[0:OFF * TRACK_BYTES] = bytes(OFF * TRACK_BYTES)

    directory = bytearray([FILLER]) * (DIR_ENTRIES * 32)
    next_entry = 0
    next_block = FIRST_DATA_BLOCK
    placed = []

    for path in sources:
        data = open(path, 'rb').read()
        stem, ext = cpm_name(path)
        records = (len(data) + 127) // 128
        if records == 0:
            records = 0

        # Pad to a whole number of records; CP/M has no byte-granular length.
        padded = data + bytes((-len(data)) % 128)

        rec = 0
        extent = 0
        while rec < records or (records == 0 and extent == 0):
            if next_entry > DRM:
                raise ValueError("directory full at %s" % path)
            n_recs = min(RECS_PER_EXTENT, records - rec)
            blocks = []
            r = rec
            while r < rec + n_recs:
                if next_block > DSM:
                    raise ValueError("disc full at %s" % path)
                b = next_block
                next_block += 1
                blocks.append(b)
                for k in range(RECS_PER_BLOCK):
                    if r + k >= rec + n_recs:
                        break
                    off = record_offset(block_record(b, k))
                    src = (r + k) * 128
                    disc[off:off + 128] = padded[src:src + 128]
                r += RECS_PER_BLOCK

            e = bytearray(32)
            e[0] = 0                                    # user 0
            e[1:9] = stem.encode('ascii')
            e[9:12] = ext.encode('ascii')
            e[12] = extent & 0x1F                       # EX
            e[13] = 0                                   # S1
            e[14] = (extent >> 5) & 0x3F                # S2
            e[15] = n_recs                              # RC
            for i, b in enumerate(blocks[:BLOCKS_PER_EXTENT]):
                e[16 + i * 2] = b & 0xFF                # 16-bit allocation,
                e[17 + i * 2] = (b >> 8) & 0xFF         # little-endian
            directory[next_entry * 32:(next_entry + 1) * 32] = e
            next_entry += 1

            rec += n_recs
            extent += 1
            if records == 0:
                break

        placed.append((stem.strip() + ('.' + ext.strip() if ext.strip() else ''),
                       path, len(data), records))

    # The directory lives in block 0.
    for n in range(RECS_PER_BLOCK):
        off = record_offset(block_record(0, n))
        disc[off:off + 128] = directory[n * 128:(n + 1) * 128]

    return disc, placed, next_entry, next_block


# ---------------------------------------------------------------- verification

def read_directory(disc):
    out = []
    for i in range(DIR_ENTRIES):
        off = record_offset(block_record(0, i // 4)) + (i % 4) * 32
        e = disc[off:off + 32]
        if e[0] == 0xE5:
            continue
        stem = e[1:9].decode('ascii', 'replace').rstrip()
        ext = bytes(b & 0x7F for b in e[9:12]).decode('ascii', 'replace').rstrip()
        name = stem + ('.' + ext if ext else '')
        extent = (e[12] & 0x1F) | ((e[14] & 0x3F) << 5)
        blocks = [e[16 + i * 2] | (e[17 + i * 2] << 8) for i in range(BLOCKS_PER_EXTENT)]
        out.append((name, extent, e[15], blocks))
    return out


def extract(disc, name):
    parts = {}
    for entry_name, extent, rc, blocks in read_directory(disc):
        if entry_name != name:
            continue
        data = bytearray()
        for r in range(rc):
            b = blocks[r // RECS_PER_BLOCK]
            off = record_offset(block_record(b, r % RECS_PER_BLOCK))
            data += disc[off:off + 128]
        parts[extent] = bytes(data)
    if not parts:
        return None
    return b''.join(parts[k] for k in sorted(parts))


def main(argv):
    out = None
    system_path = None
    interleave = 2
    sources = []
    i = 1
    while i < len(argv):
        a = argv[i]
        if a == '-o':
            i += 1
            out = argv[i]
        elif a == '-s':
            i += 1
            system_path = argv[i]
        elif a == '--interleave':
            i += 1
            interleave = int(argv[i])
        elif a in ('-h', '--help'):
            print(__doc__)
            return 0
        else:
            sources.append(a)
        i += 1

    if not out or not sources:
        print(__doc__)
        return 2

    system = open(system_path, 'rb').read() if system_path else None
    disc, placed, entries, next_block = build(sources, system)

    failures = 0
    for name, path, size, records in placed:
        got = extract(disc, name)
        if got is None:
            print("MISSING   %-14s" % name)
            failures += 1
        elif got[:size] != open(path, 'rb').read():
            print("CORRUPT   %-14s" % name)
            failures += 1
        else:
            print("verified  %-14s %7d bytes  %3d records" % (name, size, records))

    if failures:
        print("\n%d file(s) did not read back" % failures)
        return 1

    if interleave > 1:
        image = write_edsk(disc, TRACKS, SECTORS_PER_TRACK, interleave)
        order = interleave_order(SECTORS_PER_TRACK, interleave)
        layout = "Extended DSK, %d:1 interleave, sectors laid %s" % (
            interleave, ",".join(str(x) for x in order))
    else:
        image = bytes(disc)
        layout = "raw sector image, no interleave"
    open(out, 'wb').write(image)

    used = next_block
    free = (DSM + 1) - used
    print()
    if system:
        print("boot      %s, %d bytes in tracks 0-%d"
              % (os.path.basename(system_path), len(system), OFF - 1))
    print("directory %d of %d entries" % (entries, DIR_ENTRIES))
    print("space     %d of %d blocks used, %dK free" % (used, DSM + 1, free * BLS // 1024))
    print("layout    %s" % layout)
    print("\nwrote %s (%d bytes)" % (out, len(image)))
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
