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
  db width in bytes, height, copies - 1 (0: one, 1: two), width in pixels
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
        dirl.append(f"        db {entry}_w, {entry}_h, {entry}_c, {entry}_p")
        dirl.append(f"        dw {entry}, {entry}_s")
    for k in sorted(set(indices)):
        n = copies(shifts[k])
        h = max(2, round(scn.SIZES[k] * factor))
        rows = halve(scn.scaled(master, h))
        wpx = len(rows[0])
        wb = size_bytes(wpx, n)
        lab = f"{label}_{k}"
        consts.append(f"{lab}_w EQU {wb}\n{lab}_h EQU {h}\n{lab}_c EQU {n - 1}\n{lab}_p EQU {wpx}\n"
                      f"{lab}_s EQU {wb * h}")
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


# The Spectrum's colours (index: BRIGHT x 8 + colour) as the placeholder
# car's pens (docs/port_cpc.md 5.5: 1 black, 3 the dark kerb's red, 14
# bright yellow, 15 bright white, 10 blue, 5 and 4 the grass's)
CAR_PENS = {0: 1, 1: 10, 2: 3, 3: 3, 4: 5, 5: 15, 6: 14, 7: 15}
CAR_W, CAR_H = 64, 32                       # (the Spectrum's: assets/gfx/car.png)


def line_runs(row):
    """A sprite's line as runs (src/cpc/sprites.asm CpcCar): the bytes to
    skip, then runs, each its length (bit 7 set: masked by pen 0, some of
    its pixels transparent; else every pixel drawn) and its bytes; 0 ends
    it. All transparent: 0, 0."""
    lit = [i for i, b in enumerate(row) if b]
    if not lit:
        return [0, 0]
    out = [lit[0]]
    i = lit[0]
    while i <= lit[-1]:
        masked = not opaque(row[i])
        j = i
        while j <= lit[-1] and (not opaque(row[j])) == masked and j - i < 127:
            j += 1
        out += [(j - i) | (0x80 if masked else 0)] + row[i:j]
        i = j
    return out + [0]


def opaque(b):
    """No pixel of the byte is pen 0."""
    left, right = pens(b)
    return left != 0 and right != 0


def car_frames(png="assets/gfx/car.png", split=24):
    """The Spider's 7 poses (the Spectrum's car.png, 64 x 32 each), Mode 0:
    16 bytes by 32 lines; outside its outline on each line transparent (pen
    0), black inside it black. Each pose a top part (SPLIT lines) and a
    bottom part, the same parts stored once. -> assembler lines."""
    from PIL import Image
    im = Image.open(png).convert("RGB")
    frames = im.width // CAR_W
    parts = {}                              # bytes -> label
    table, data = [], []

    def part(rows, name):
        key = bytes(b for r in rows for b in r)
        if key not in parts:
            parts[key] = name
            data.append(f"{name}:")
            data.extend("        db " + ", ".join(f"${b:02X}" for b in line_runs(r)) for r in rows)
        return parts[key]

    for k in range(frames):
        rows = []
        for y in range(CAR_H):
            pens = []
            for x in range(0, CAR_W, 2):
                rgb = [im.getpixel((k * CAR_W + x + d, y)) for d in (0, 1)]
                lit = [c for c in rgb if c != (0, 0, 0)]
                if not lit:
                    pens.append(None)          # black: inside or out (below)
                    continue
                r, g, b = lit[0]
                colour = (1 if b else 0) | (2 if r else 0) | (4 if g else 0)
                pens.append(CAR_PENS[colour])
            lit = [i for i, p in enumerate(pens) if p is not None]
            row = [0] * len(pens)
            if lit:
                for i in range(lit[0], lit[-1] + 1):
                    row[i] = pens[i] if pens[i] is not None else 1
            rows.append([byte(row[2 * i], row[2 * i + 1]) for i in range(len(row) // 2)])
        top = part(rows[:split], f"CpcCarTop{k}")
        bot = part(rows[split:], f"CpcCarBot{k}")
        table.append(f"        dw {top}, {bot}")
    return (["; Generated by tools/make_cpc.py - do not edit (a placeholder: the",
             "; Spectrum's poses, docs/port_cpc.md 5.6)",
             f"CARW_M0 EQU {CAR_W // 4}", f"CARH_M0 EQU {CAR_H}", f"CARTOP_M0 EQU {split}",
             "CpcCarFrames:                ; per pose: its top part, its bottom part"]
            + table + data)


# The HUD's and the front end's font for the CPC (docs/port_cpc.md 5.7):
# each glyph 3 Mode 0 pixels wide and 7 high (a fourth column the gap),
# drawn in the Spectrum's 8 x 8 cell with every pixel doubled across, so
# halving it gives the design exactly. ASCII 32-90; the rest blank.
FONT = {
    "0": "### #.# #.# #.# #.# #.# ###", "1": ".#. ##. .#. .#. .#. .#. ###",
    "2": "### ..# ..# ### #.. #.. ###", "3": "### ..# ..# .## ..# ..# ###",
    "4": "#.# #.# #.# ### ..# ..# ..#", "5": "### #.. #.. ### ..# ..# ###",
    "6": "### #.. #.. ### #.# #.# ###", "7": "### ..# ..# .#. .#. .#. .#.",
    "8": "### #.# #.# ### #.# #.# ###", "9": "### #.# #.# ### ..# ..# ###",
    "A": ".#. #.# #.# ### #.# #.# #.#", "B": "##. #.# #.# ##. #.# #.# ##.",
    "C": ".## #.. #.. #.. #.. #.. .##", "D": "##. #.# #.# #.# #.# #.# ##.",
    "E": "### #.. #.. ##. #.. #.. ###", "F": "### #.. #.. ##. #.. #.. #..",
    "G": ".## #.. #.. #.# #.# #.# .##", "H": "#.# #.# #.# ### #.# #.# #.#",
    "I": "### .#. .#. .#. .#. .#. ###", "J": "..# ..# ..# ..# ..# #.# .#.",
    "K": "#.# #.# ##. #.. ##. #.# #.#", "L": "#.. #.. #.. #.. #.. #.. ###",
    "M": "#.# ### ### #.# #.# #.# #.#", "N": "##. #.# #.# #.# #.# #.# #.#",
    "O": ".#. #.# #.# #.# #.# #.# .#.", "P": "##. #.# #.# ##. #.. #.. #..",
    "Q": ".#. #.# #.# #.# #.# ##. .##", "R": "##. #.# #.# ##. #.# #.# #.#",
    "S": ".## #.. #.. .#. ..# ..# ##.", "T": "### .#. .#. .#. .#. .#. .#.",
    "U": "#.# #.# #.# #.# #.# #.# ###", "V": "#.# #.# #.# #.# #.# #.# .#.",
    "W": "#.# #.# #.# #.# ### ### #.#", "X": "#.# #.# #.# .#. #.# #.# #.#",
    "Y": "#.# #.# #.# .#. .#. .#. .#.", "Z": "### ..# ..# .#. #.. #.. ###",
    ":": "... .#. .#. ... .#. .#. ...", "/": "..# ..# .#. .#. .#. #.. #..",
    "-": "... ... ... ### ... ... ...", ".": "... ... ... ... ... ... .#.",
    "!": ".#. .#. .#. .#. .#. ... .#.", "?": "##. ..# ..# .#. .#. ... .#.",
    ",": "... ... ... ... ... .#. #..", "<": "..# .#. .#. #.. .#. .#. ..#",
    ">": "#.. .#. .#. ..# .#. .#. #..", "+": "... .#. .#. ### .#. .#. ...",
    "'": ".#. .#. #.. ... ... ... ...", '"': "#.# #.# ... ... ... ... ...",
}


def font_asm():
    """build/cpc/font_data.asm: Font, as the Spectrum's (8 bytes a glyph)."""
    lines = ["; Generated by tools/make_cpc.py - do not edit (the CPC's font: 3 x 7,",
             "; each pixel doubled across)", "Font:      ; ASCII 32-90, 8 bytes each"]
    for code in range(32, 91):
        rows = FONT.get(chr(code), "... ... ... ... ... ... ...").split()
        data = [sum(0xC0 >> (2 * c) for c, p in enumerate(r) if p == "#") for r in rows] + [0]
        lines.append("        db " + ", ".join(f"${v:02X}" for v in data) + f"   ; {chr(code)!r}")
    return lines


def dash_header():
    """The HUD's top strip (stages.asm DashHeader: 8 lines of 32 bytes, as
    round_art.dash_header's) with the CPC's font: SCORE, TIME, SPEED, each
    Mode 0 pixel two of the Spectrum's, and the speed stripes."""
    from PIL import Image, ImageDraw
    im = Image.new("1", (256, 8))
    draw = ImageDraw.Draw(im)
    for x, word in ((8, "SCORE"), (112, "TIME"), (200, "SPEED")):
        for ch in word:
            for y, row in enumerate(FONT[ch].split()):
                for c, p in enumerate(row):
                    if p == "#":
                        draw.rectangle((x + 2 * c, y, x + 2 * c + 1, y), 1)
            x += 8
    for x in (0, 186):
        draw.line((x, 6, x + 4, 1), 1, width=2)
    return im.tobytes()
