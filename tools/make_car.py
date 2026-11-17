#!/usr/bin/env python3
"""Draw the initial player car sprite sheet (assets/gfx/car.png).

An original rear view of a red convertible, 64x32 pixels per frame, frames
side by side: straight, left, right. Spectrum colours only, one ink colour
per 8x8 cell on black paper (see tools/png2zx.py). Edit the PNG freely
afterwards; this script only bootstraps it.
"""
import sys
from PIL import Image, ImageDraw

K = (0, 0, 0)
R = (255, 0, 0)
r = (215, 0, 0)
Y = (255, 255, 0)
W = (255, 255, 255)
C = (0, 255, 255)


def car(lean):
    """lean: -1 left, 0 straight, +1 right. Returns a 64x32 image."""
    im = Image.new("RGB", (64, 32), K)
    d = ImageDraw.Draw(im)
    t = 3 * lean           # interior shifts most with the lean
    m = 2 * lean           # rear deck
    b = -lean              # tyres move the other way (we see the outer side)
    # --- row 0 (y 0-7): windscreen frame behind, headrests, heads (white)
    d.line([(9 + t, 0), (54 + t, 0)], W)               # windscreen top
    d.line([(9 + t, 0), (6 + t, 7)], W)
    d.line([(54 + t, 0), (57 + t, 7)], W)
    for cx in (20 + t, 43 + t):
        d.rounded_rectangle([cx - 7, 4, cx + 7, 7], radius=1, fill=W)   # headrest
        d.ellipse([cx - 4, 0, cx + 4, 7], fill=K)                       # outline gap
        d.ellipse([cx - 3, 0, cx + 3, 6], fill=W)                       # head
        d.line([(cx - 1, 1), (cx + 1, 1)], K)                           # hair line
    # --- row 1 (y 8-15): rear deck (red)
    d.rounded_rectangle([0 + m, 8, 63 + m, 17], radius=4, fill=R)
    d.line([(12 + m, 10), (51 + m, 10)], K)            # boot lid shut line
    d.line([(12 + m, 10), (9 + m, 15)], K)
    d.line([(51 + m, 10), (54 + m, 15)], K)
    d.point([(3 + m, 9), (60 + m, 9)], K)              # rounded corners
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
    return im


def main(path):
    sheet = Image.new("RGB", (64 * 3, 32), K)
    for k, lean in enumerate((0, -1, 1)):
        sheet.paste(car(lean), (64 * k, 0))
    sheet.save(path)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "assets/gfx/car.png")
