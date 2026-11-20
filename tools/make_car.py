#!/usr/bin/env python3
"""Draw the initial player car sprite sheet (assets/gfx/car.png).

An original rear view of a red convertible with its crew (him: mullet,
shades, loud striped shirt; her: big blonde hair), 64x32 pixels per frame,
frames side by side: straight, left, right. Spectrum colours only, at most
two per 8x8 cell (see tools/png2zx.py). The top cell row is the open
cockpit: only its ink colours are used, over whatever lies under the car.
"""
import sys
from PIL import Image, ImageDraw

K = (0, 0, 0)
R = (255, 0, 0)
r = (215, 0, 0)
Y = (255, 255, 0)
W = (255, 255, 255)
C = (0, 255, 255)


def car(lean, smoke=None):
    """lean: -1 left, 0 straight, +1 right; smoke: None, or 0 / 1 for the two
    puffs of tyre smoke. Returns a 64x32 image."""
    im = Image.new("RGB", (64, 32), K)
    d = ImageDraw.Draw(im)
    swing = 5 if smoke is not None else 3              # drifting: swung further round
    t = swing * lean       # interior shifts most with the lean
    m = (swing - 1) * lean  # rear deck
    b = -lean * (2 if smoke is not None else 1)        # tyres move the other way
    # --- row 0 (y 0-7): the open cockpit. Paper is whatever lies under the
    # car; each cell's ink colour comes from here: white for him and the
    # windscreen pillars, yellow for her
    d.line([(7, 0), (4, 7)], W)                        # windscreen pillars
    d.line([(56, 0), (59, 7)], W)
    mx = 19 + t                                        # him: mullet, shades
    d.ellipse([mx - 4, 0, mx + 4, 7], fill=W)          # head
    d.rectangle([mx - 3, 4, mx + 3, 7], fill=W)        # mullet down the neck
    d.point([(mx - 5, 3), (mx + 5, 3), (mx - 5, 4), (mx + 5, 4)], W)   # ears
    d.point([(mx - 4, 3), (mx + 4, 3)], K)             # sunglasses' arms
    wx = 44 + t                                        # her: big blown hair
    d.ellipse([wx - 6, 0, wx + 5, 7], fill=Y)
    d.polygon([(wx + 4, 1), (wx + 8, 2), (wx + 6, 3), (wx + 8, 5), (wx + 4, 6)], fill=Y)
    d.point([(wx - 3, 2), (wx, 1), (wx + 2, 3)], K)    # strands
    for y in range(8):                                 # (not into the pillar's cell)
        for x in range(56, 64):
            if im.getpixel((x, y)) == Y:
                im.putpixel((x, y), K)
    # --- row 1 (y 8-15): rear deck (red) with their shoulders above it:
    # his loud striped shirt (cyan), her hair over her shoulders (yellow)
    d.rounded_rectangle([0 + m, 8, 63 + m, 17], radius=4, fill=R)
    d.point([(3 + m, 9), (60 + m, 9)], K)              # rounded corners
    d.rounded_rectangle([mx - 8, 8, mx + 8, 11], radius=1, fill=C)
    for x in range(mx - 7, mx + 8, 3):                 # stripes
        d.line([(x, 8), (x + 1, 11)], R)
    d.rectangle([mx - 2, 8, mx + 2, 8], fill=C)        # collar
    d.rounded_rectangle([wx - 7, 8, wx + 6, 10], radius=1, fill=Y)
    d.line([(wx - 6, 11), (wx + 5, 11)], Y)
    # --- row 2 (y 16-23): lamps (yellow cells), body (red), plate (white)
    d.rectangle([0, 16, 15, 23], K)
    d.rectangle([48, 16, 63, 23], K)
    for x0 in (1, 49):
        d.rectangle([x0, 17, x0 + 13, 22], Y)
        for y in (18, 20):
            d.line([(x0 + 1, y), (x0 + 12, y)], K)     # slatted lamp clusters
    d.rectangle([16, 16, 23, 23], R)
    d.rectangle([40, 16, 47, 23], R)
    d.rectangle([24, 16, 39, 23], K)
    d.rectangle([25, 17, 38, 22], W)                   # number plate
    for x in (27, 30, 33, 36):                         # plate characters
        d.line([(x, 18), (x, 21)], K)
        d.point((x + 1, 18), K)
    # --- row 3 (y 24-31): bumper, tyres outlined in red, shadow
    d.rectangle([1, 24, 62, 25], R)
    for x0 in (3 + b, 47 + b):
        d.rectangle([x0, 26, x0 + 13, 31], K)
        d.line([(x0, 26), (x0, 31)], R)                # tyre sidewalls
        d.line([(x0 + 13, 26), (x0 + 13, 31)], R)
        for x in range(x0 + 2, x0 + 12, 3):            # tread
            d.line([(x, 27), (x + 1, 27)], R)
    for x in (22, 39):                                 # exhaust tips
        d.rectangle([x, 26, x + 2, 27], R)
    if smoke is not None:
        tyre_smoke(im, d, lean, smoke)
    return im


def tyre_smoke(im, d, lean, phase):
    """Light white smoke from both rear tyres (drifting at the limit).
    It takes over the tyre cells of the bottom row: their red turns white,
    the smoke is white, the tyres stay black."""
    rnd = [(2, 30, 3), (9, 31, 3), (14, 28, 2), (5, 26, 2), (12, 25, 1)] if phase == 0 else \
          [(4, 31, 3), (11, 29, 3), (1, 27, 2), (15, 31, 2), (7, 25, 1)]
    specks = [(0, 25), (6, 24), (13, 27), (3, 28)] if phase == 0 else \
             [(2, 24), (9, 26), (15, 25), (5, 29)]
    puffs = Image.new("L", im.size, 0)
    pd = ImageDraw.Draw(puffs)
    for side, x0 in ((-1, 0), (1, 48)):              # the same, light, from both tyres
        for x, y, r in rnd:
            if side > 0:
                x = 15 - x
            r = max(1, r - 1)
            pd.ellipse([x0 + x - r, y - r, x0 + x + r, y + r], fill=255)
        for x, y in specks:
            pd.point((x0 + (15 - x if side > 0 else x), y), 255)
    pd.rectangle([0, 0, 63, 23], fill=0)               # (bottom row only)
    im.paste(Image.new("RGB", im.size, W), (0, 0), puffs)
    for cx in (0, 1, 6, 7):                            # the smoky cells: no red there:
        for y in range(24, 32):                        # bumper black, tyre outline white
            for x in range(cx * 8, cx * 8 + 8):
                if im.getpixel((x, y)) == R:
                    im.putpixel((x, y), K if y < 26 else W)
    for y in range(24, 32):                            # (smoke stays in those cells)
        for x in range(16, 48):
            if im.getpixel((x, y)) == W:
                im.putpixel((x, y), K)


FRAMES = [(0, None), (-1, None), (1, None),          # straight, left, right
          (-1, 0), (-1, 1), (1, 0), (1, 1)]             # drifting left / right, smoke puffs


def main(path):
    sheet = Image.new("RGB", (64 * len(FRAMES), 32), K)
    for k, (lean, smoke) in enumerate(FRAMES):
        sheet.paste(car(lean, smoke), (64 * k, 0))
    sheet.save(path)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "assets/gfx/car.png")
