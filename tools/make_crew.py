#!/usr/bin/env python3
"""Draw the crew's crash close-ups: her (angry, shouting) and him (shades,
loud 80s shirt, sheepish), 48x48 pixels (6x6 cells) each, and convert them
to Spectrum cells (two colours per cell). Original procedural artwork.

Output (sjasmplus): CrewHer / CrewHim: 48 lines of 6 bytes, then 36
attribute bytes. Preview: assets/gfx/crew.png.
usage: make_crew.py out.asm
"""
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(__file__))
from make_screens import rgb, dist, COLOURS, BLACK, BLUE, RED, MAGENTA, GREEN, CYAN, YELLOW, WHITE  # noqa: E402

S = 48


def her():
    """Her: a big blonde 80s perm, cyan top; angry, shouting.
    Laid out on the 8x8 cell grid so each cell keeps to two colours: the
    eyes and brows in their own cell row (black on white skin), the nose
    between blushing cheeks below, the mouth in the row under that."""
    im = Image.new("RGB", (S, S), rgb(RED))
    d = ImageDraw.Draw(im)
    Y, Wt, K, C, R = rgb(YELLOW), rgb(WHITE), rgb(BLACK), rgb(CYAN), rgb(RED)
    # the perm: a mass of curls down to the shoulders, curl lines in red
    for x, y, r in ((24, 9, 13), (11, 12, 9), (37, 12, 9), (5, 22, 8), (43, 22, 8),
                    (4, 34, 8), (44, 34, 8), (6, 44, 6), (42, 44, 6), (16, 3, 7), (32, 3, 7)):
        d.ellipse([x - r, y - r, x + r, y + r], fill=Y)
    for x, y, r, a0, a1 in ((14, 6, 5, 200, 340), (26, 4, 5, 190, 350), (36, 7, 5, 200, 330),
                            (6, 18, 4, 100, 300), (42, 18, 4, 240, 80), (4, 30, 4, 90, 300),
                            (44, 30, 4, 240, 90), (5, 40, 3, 60, 300), (43, 40, 3, 240, 120)):
        d.arc([x - r, y - r, x + r, y + r], a0, a1, fill=R)
    # cyan top on the shoulders, the neck
    d.rounded_rectangle([8, 41, 39, 52], radius=4, fill=C)
    d.rectangle([18, 36, 29, 44], fill=Wt)
    d.polygon([(18, 41), (24, 47), (29, 41)], fill=Wt)          # the neckline
    # the face: cells 1-4 across; full width through the eyes and cheeks,
    # then tapering to the chin
    d.ellipse([9, 9, 38, 30], fill=Wt)
    d.rectangle([8, 16, 39, 31], fill=Wt)
    d.polygon([(8, 31), (39, 31), (36, 36), (30, 40), (17, 40), (11, 36)], fill=Wt)
    d.polygon([(10, 13), (16, 9), (24, 8), (32, 9), (38, 13), (38, 15), (31, 13),
               (24, 15), (17, 13), (10, 15)], fill=Y)                     # fringe
    # brows: drawn down towards the nose in a frown
    d.line([(10, 16), (15, 16), (20, 17)], K)
    d.line([(10, 17), (15, 17)], K)
    d.line([(37, 16), (32, 16), (27, 17)], K)
    d.line([(37, 17), (32, 17)], K)
    # eyes: almond, a thick upper lid with lashes at the outer corner, a dark
    # iris with a highlight, a fine lower lid (all within cell row 2)
    for cx, out in ((16, -1), (31, 1)):
        d.line([(cx - 5, 20), (cx - 4, 19), (cx + 3, 19), (cx + 4, 20)], K)   # upper lid
        d.line([(cx + (4 if out > 0 else -5), 19), (cx + (6 if out > 0 else -7), 17)], K)  # lashes
        d.rectangle([cx - 2, 20, cx + 1, 22], fill=K)                 # iris
        d.point((cx - 1, 20), Wt)                                     # highlight
        d.point([(cx - 4, 22), (cx + 3, 22)], K)                      # lower lid
        d.line([(cx - 3, 23), (cx + 2, 23)], K)
    # nose, between blushing cheeks
    d.line([(24, 24), (23, 28)], K)
    d.point([(22, 29), (25, 29)], K)
    d.line([(23, 30), (24, 30)], K)
    for x0 in (10, 33):
        for k in range(3):
            d.point([(x0 + 2 * k, 27), (x0 + 1 + 2 * k, 28)], R)
    # the shouting mouth: red lips, teeth top and bottom
    d.ellipse([18, 32, 29, 39], fill=R)
    d.rectangle([20, 33, 27, 33], fill=Wt)
    d.rectangle([21, 38, 26, 38], fill=Wt)
    # anger marks
    for x, y in ((44, 2), (40, 5)):
        d.line([(x, y), (x + 3, y)], Wt)
        d.line([(x + 1, y - 1), (x + 1, y + 2)], Wt)
    return im


def him():
    im = Image.new("RGB", (S, S), rgb(BLUE))
    d = ImageDraw.Draw(im)
    Y, Wt, K, C, M = rgb(YELLOW), rgb(WHITE), rgb(BLACK), rgb(CYAN), rgb(MAGENTA)
    # loud 80s shirt: magenta with cyan zigzags, open collar
    d.rounded_rectangle([1, 39, 46, 54], radius=7, fill=M)
    for x0 in range(-4, 48, 8):
        d.line([(x0, 47), (x0 + 4, 43), (x0 + 8, 47)], C, width=2)
    d.polygon([(18, 39), (24, 47), (30, 39)], fill=Y)     # neck in the open collar
    d.rectangle([20, 34, 27, 40], fill=Y)
    # big hair, then the face
    d.ellipse([9, 3, 38, 26], fill=K)
    d.polygon([(12, 8), (18, 0), (30, 0), (38, 6), (24, 4)], fill=K)   # quiff
    d.rectangle([10, 12, 15, 27], fill=K)                 # sideburns
    d.rectangle([32, 12, 37, 27], fill=K)
    d.ellipse([13, 9, 34, 37], fill=Y)
    # sunglasses
    d.rectangle([13, 18, 34, 19], fill=K)
    d.rounded_rectangle([14, 18, 22, 25], radius=2, fill=K)
    d.rounded_rectangle([25, 18, 33, 25], radius=2, fill=K)
    d.line([(16, 20), (18, 20)], Y)                       # glint
    # sheepish grin
    d.line([(19, 31), (21, 30), (23, 31), (25, 30), (27, 31), (29, 30)], K)
    d.line([(23, 26), (24, 28)], K)
    # a bead of sweat
    d.ellipse([39, 12, 42, 17], fill=C)
    d.point((40, 11), C)
    return im


def cells(im):
    """-> (48 lines x 6 bytes, 36 attributes); two colours per cell."""
    px = im.load()
    lines = [[0] * 6 for _ in range(S)]
    attrs = []
    for cy in range(S // 8):
        for cx in range(S // 8):
            counts = {}
            for y in range(8):
                for x in range(8):
                    p = px[cx * 8 + x, cy * 8 + y]
                    counts[p] = counts.get(p, 0) + 1
            order = sorted(counts, key=lambda p: -counts[p])
            paper = order[0]
            ink = order[1] if len(order) > 1 else order[0]
            if ink == (0, 0, 0) and paper != (0, 0, 0):   # black ink reads better
                pass
            bright = any(COLOURS[p][1] for p in (paper, ink) if p != (0, 0, 0))
            attrs.append((0x40 if bright else 0) | (COLOURS[paper][0] << 3) | COLOURS[ink][0])
            for y in range(8):
                b = 0
                for x in range(8):
                    p = px[cx * 8 + x, cy * 8 + y]
                    if p == ink or (p != paper and dist(p, ink) < dist(p, paper)):
                        b |= 0x80 >> x
                lines[cy * 8 + y][cx] = b
    return lines, attrs


def render(lines, attrs):
    im = Image.new("RGB", (S, S))
    for y in range(S):
        for cx in range(6):
            a = attrs[(y // 8) * 6 + cx]
            for x in range(8):
                on = lines[y][cx] & (0x80 >> x)
                c = a & 7 if on else (a >> 3) & 7
                im.putpixel((cx * 8 + x, y), rgb(c, bool(a & 0x40)))
    return im


def main(out):
    asm = ["; Generated by tools/make_crew.py - do not edit"]
    sheet = Image.new("RGB", (S * 2 + 8, S), (0, 0, 0))
    for k, (label, fn) in enumerate((("CrewHer", her), ("CrewHim", him))):
        lines, attrs = cells(fn())
        asm.append(f"{label}:")
        for ln in lines:
            asm.append("        db " + ", ".join(f"${b:02X}" for b in ln))
        for r in range(6):
            asm.append("        db " + ", ".join(f"${a:02X}" for a in attrs[r * 6:r * 6 + 6]))
        sheet.paste(render(lines, attrs), (k * (S + 8), 0))
    sheet.save(os.path.join("assets", "gfx", "crew.png"))
    open(out, "w").write("\n".join(asm) + "\n")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "build/crew_data.asm")
