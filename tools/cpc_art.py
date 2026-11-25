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
    colour = isinstance(master, tuple)              # the CPC's own: ("cpc", image)
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
        if colour:
            rows = shrink(master[1], h)
        else:
            rows = [[pen if on else 0 for on in r] for r in halve(scn.scaled(master, h))]
        wpx = len(rows[0])
        wb = size_bytes(wpx, n)
        lab = f"{label}_{k}"
        consts.append(f"{lab}_w EQU {wb}\n{lab}_h EQU {h}\n{lab}_c EQU {n - 1}\n{lab}_p EQU {wpx}\n"
                      f"{lab}_s EQU {wb * h}")
        data.append(f"{lab}:")
        for shift in range(n):
            for row in rows:
                line = [0] * (2 * wb)
                for x, p in enumerate(row):
                    line[x + shift] = p
                out = [byte(line[2 * i], line[2 * i + 1]) for i in range(wb)]
                data.append("        db " + ", ".join(f"${v:02X}" for v in out))
    return consts, dirl, data


def type_bytes(name, master=None):
    """Bytes emit_type gives a type (for the theme cache's size check)."""
    fn, factor, shifts = scn.TYPES[name]
    colour = isinstance(master, tuple)
    master = fn() if master is None else master
    total = 0
    for k in set(scn.size_indices(name)):
        n = copies(shifts[k])
        h = max(2, round(scn.SIZES[k] * factor))
        if colour:
            wpx = len(shrink(master[1], h)[0])
        else:
            wpx = (scn.scaled(master, h).width + 1) // 2
        total += size_bytes(wpx, n) * h * n
    return total + 8 * len(scn.SIZES)


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


def car_frames(spider, split=24):
    """The Spider's 7 poses (tools/cpc_illustration.py spider: 32 Mode 0
    pixels by 32 lines, the Spectrum's car block), as runs of bytes a line
    (line_runs). Each pose a top part (SPLIT lines) and a bottom part, the
    same parts stored once. -> assembler lines."""
    parts = {}                              # bytes -> label
    table, data = [], []

    def part(rows, name):
        key = bytes(b for r in rows for b in r)
        if key not in parts:
            parts[key] = name
            data.append(f"{name}:")
            data.extend("        db " + ", ".join(f"${b:02X}" for b in line_runs(r)) for r in rows)
        return parts[key]

    for k in range(7):
        px = spider(k).load()
        rows = [[byte(*[0 if px[2 * i + j, y] == 255 else px[2 * i + j, y] for j in (0, 1)])
                 for i in range(CAR_W // 4)] for y in range(CAR_H)]
        top = part(rows[:split], f"CpcCarTop{k}")
        bot = part(rows[split:], f"CpcCarBot{k}")
        table.append(f"        dw {top}, {bot}")
    return (["; Generated by tools/make_cpc.py - do not edit (the Spider's poses:",
             "; tools/cpc_illustration.py spider)",
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


SPEC_HW = (0x14, 0x04, 0x1C, 0x18, 0x16, 0x06, 0x1E, 0x00,      # the Spectrum's colours as
           0x14, 0x15, 0x0C, 0x0D, 0x12, 0x13, 0x0A, 0x0B)      # the Gate Array's (src/cpc)


def spectrum_screen(scr):
    """A Spectrum screen (6912 bytes) as a CPC screen's 16K block: Mode 0,
    pen k the Spectrum's colour k (BRIGHT x 8 + colour), each pair of
    Spectrum pixels a Mode 0 pixel (ink if either is); line y at
    (y & 7) x $800 + (y / 8) x 64. Its 17 inks (the pens' and the border's
    hardware colours) in the first 2K's unshown part, at $600."""
    out = bytearray(0x4000)
    for y in range(192):
        line = ((y & 0xC0) << 5) | ((y & 7) << 8) | ((y & 0x38) << 2)
        for cx in range(32):
            attr = scr[6144 + (y >> 3) * 32 + cx]
            bright = 8 if attr & 0x40 else 0
            ink, paper = (attr & 7) + bright, ((attr >> 3) & 7) + bright
            bits = scr[line + cx]
            px = [ink if bits & (0xC0 >> (2 * k)) else paper for k in range(4)]
            at = (y & 7) * 0x800 + (y >> 3) * 64 + cx * 2
            out[at] = byte(px[0], px[1])
            out[at + 1] = byte(px[2], px[3])
    out[0x600:0x611] = bytes(SPEC_HW) + bytes([0x14])
    return bytes(out)


def put_text(block, x, row, text, pen):
    """CPC font text into a screen block (spectrum_screen's): Mode 0 pixel
    x, character row ROW (its 8 lines), each glyph 4 pixels wide."""
    for ch in text:
        for y, r in enumerate(FONT.get(ch, "... ... ... ... ... ... ...").split()):
            for c, p in enumerate(r + "."):
                px = x + c
                at = (y & 7) * 0x800 + row * 64 + px // 2
                left, right = pens(block[at])
                if p == "#":
                    left, right = (pen, right) if px % 2 == 0 else (left, pen)
                block[at] = byte(left, right)
        x += 4


def loading_screen():
    """The loading screen until the CPC's own (phase A): the Spectrum's title
    in its colours, its last three rows saying what it is for."""
    import make_screens
    block = bytearray(spectrum_screen(make_screens.title_screen(loading=True)))
    for row in range(21, 24):
        for y in range(8):
            at = y * 0x800 + row * 64
            block[at:at + 64] = bytes(64)
    put_text(block, 16, 21, "FOR THE AMSTRAD CPC 6128", 13)
    put_text(block, 50, 23, "LOADING", 14)
    return bytes(block)


def shrink(master, h):
    """A CPC master (tools/cpc_illustration.py: pens, 255 transparent) at
    height H, its width in proportion -> rows of pens (0: transparent). Each
    pixel from its block of the master: transparent if most of it is, else
    the pen most of the rest is."""
    from collections import Counter
    W, H = master.size
    w = max(1, round(W * h / H))
    px = master.load()
    rows = []
    for ty in range(h):
        y0, y1 = ty * H // h, max(ty * H // h + 1, (ty + 1) * H // h)
        row = []
        for tx in range(w):
            x0, x1 = tx * W // w, max(tx * W // w + 1, (tx + 1) * W // w)
            seen = Counter(px[x, y] for y in range(y0, y1) for x in range(x0, x1))
            clear = seen.pop(255, 0)
            if not seen or clear > sum(seen.values()):
                row.append(0)
            else:
                row.append(seen.most_common(1)[0][0])
        rows.append(row)
    return rows
