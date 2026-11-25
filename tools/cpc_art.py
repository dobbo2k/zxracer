#!/usr/bin/env python3
"""The Amstrad CPC build's graphics in Mode 0 (docs/port_cpc.md 5.6).

A Mode 0 byte is two pixels of 16 pens, each pixel as wide as two of the
Spectrum's: the screen is 128 x 192, the Spectrum's 256 x 192 halved
across. A pixel's pen bits are interleaved: the left pixel's bits 0-3 in
the byte's bits 7, 3, 5, 1, the right pixel's in 6, 2, 4, 0.

Sprites (scenery, traffic) keep the Spectrum's sizes (tools/make_scenery.py
SIZES and its types' factors: the projection and the clipping depend on
them) and are drawn masked by pen 0 (src/cpc/sprites.asm): pen 0 is
transparent. A type's directory is SIZES entries of 8 bytes, as the
Spectrum's:
  db width in bytes, height, copies - 1 (0: one, 1: two), 0
  dw the data (copy 0), dw bytes a copy
One copy steps 4 Spectrum pixels (a byte, as the Spectrum's near sizes);
two step 2 (a Mode 0 pixel), the second drawn a pixel to the right.

Until the CPC's own art is drawn (phase A), the placeholders are the
Spectrum's silhouettes in one pen (PLACEHOLDER_PEN).
"""
import make_scenery as scn

LEFT_BITS = (7, 3, 5, 1)            # a pen's bit 0-3 in a byte's left pixel
RIGHT_BITS = (6, 2, 4, 0)
PLACEHOLDER_PEN = 1                 # black (src/cpc pens: docs/port_cpc.md 5.5)


def byte(left, right):
    """The Mode 0 byte of two pens."""
    b = 0
    for i in range(4):
        if left >> i & 1:
            b |= 1 << LEFT_BITS[i]
        if right >> i & 1:
            b |= 1 << RIGHT_BITS[i]
    return b


def pens(b):
    """A Mode 0 byte's (left, right) pens."""
    left = sum(1 << i for i in range(4) if b >> LEFT_BITS[i] & 1)
    right = sum(1 << i for i in range(4) if b >> RIGHT_BITS[i] & 1)
    return left, right


def copies(spectrum_shifts):
    """The CPC's copies for a size the Spectrum shifts this many ways."""
    return 1 if spectrum_shifts <= 2 else 2


def halve(img):
    """A 1-bit Spectrum-scale image -> rows of Mode 0 pixels (True: set),
    each pixel set if either of its two Spectrum pixels is."""
    w = (img.width + 1) // 2
    rows = []
    for y in range(img.height):
        rows.append([bool(img.getpixel((2 * x, y))) or
                     (2 * x + 1 < img.width and bool(img.getpixel((2 * x + 1, y))))
                     for x in range(w)])
    return rows


def size_bytes(width_px, ncopies):
    """Bytes a line: the width, and a pixel more for the shifted copy."""
    return (width_px + ncopies) // 2 if ncopies == 2 else (width_px + 1) // 2


def emit_type(name, label=None, *, master=None, previews=True, pen=PLACEHOLDER_PEN):
    """A type's directory and data, as make_scenery.emit_type's, in Mode 0:
    -> (consts, directory, data) lists of assembler lines."""
    fn, factor, shifts = scn.TYPES[name]
    label = label or f"Scn_{name}"
    master = fn() if master is None else master
    consts, dirl, data = [], [f"{label}:"], []
    indices = scn.size_indices(name)
    for k in indices:
        entry = f"{label}_{k}"
        dirl.append(f"        db {entry}_w, {entry}_h, {entry}_c, 0")
        dirl.append(f"        dw {entry}, {entry}_s")
    for k in sorted(set(indices)):
        n = copies(shifts[k])
        h = max(2, round(scn.SIZES[k] * factor))
        rows = halve(scn.scaled(master, h))
        wpx = len(rows[0])
        wb = size_bytes(wpx, n)
        lab = f"{label}_{k}"
        consts.append(f"{lab}_w EQU {wb}\n{lab}_h EQU {h}\n{lab}_c EQU {n - 1}\n{lab}_s EQU {wb * h}")
        data.append(f"{lab}:")
        for shift in range(n):
            for row in rows:
                line = [0] * (2 * wb)
                for x, on in enumerate(row):
                    if on:
                        line[x + shift] = pen
                out = [byte(line[2 * i], line[2 * i + 1]) for i in range(wb)]
                data.append("        db " + ", ".join(f"${v:02X}" for v in out))
    return consts, dirl, data


def type_bytes(name, master=None):
    """Bytes emit_type gives a type (for the theme cache's size check)."""
    fn, factor, shifts = scn.TYPES[name]
    master = fn() if master is None else master
    total = 0
    for k in set(scn.size_indices(name)):
        n = copies(shifts[k])
        h = max(2, round(scn.SIZES[k] * factor))
        wpx = (scn.scaled(master, h).width + 1) // 2
        total += size_bytes(wpx, n) * h * n
    return total + 8 * len(scn.SIZES)
