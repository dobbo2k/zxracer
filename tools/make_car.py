#!/usr/bin/env python3
"""Draw the seven-frame Riviera Spider sprite sheet (assets/gfx/car.png).

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
Y = (255, 255, 0)
W = (255, 255, 255)
C = (0, 255, 255)


def car(lean, smoke=None):
    """Riviera Spider. The cockpit leads the tail through a corner."""
    mask = Image.new("L", (64, 32))
    d = ImageDraw.Draw(mask)
    # Low, curved open spider. Twin headrests, split engine grille and four round lamps.
    d.line([(7, 9), (12, 2), (16, 1), (47, 1), (52, 3), (56, 9)], 255)
    d.line((16, 1, 25, 1), 0)
    d.line((28, 1, 36, 1), 0)
    for x, y, w in [(19, 3, 7), (38, 2, 9)]:
        d.ellipse((x, y, x + w, y + 7), 255)
        d.line((x + 2, y + 2, x + 4, y + 1), 0)
    d.line([(46, 4), (49, 6), (47, 7)], 255)
    d.polygon([(0, 13), (3, 10), (10, 9), (15, 11), (24, 10), (29, 11), (36, 11),
               (41, 10), (48, 10), (53, 9), (60, 10), (63, 14), (62, 23),
               (58, 26), (6, 26), (1, 23)], 255)
    d.polygon([(14, 11), (25, 10), (39, 10), (50, 11), (54, 15), (9, 15)], 0)
    for y, x1, x2 in [(11, 18, 46), (13, 15, 48), (15, 11, 52)]:
        d.line((x1, y, x2, y), 255)
        d.point((32, y), 0)
    d.line((2, 14, 8, 13), 0)
    d.line((55, 13, 61, 14), 0)
    d.rounded_rectangle((2, 16, 61, 22), radius=2, fill=0)
    for x in (4, 11, 47, 54):
        d.ellipse((x, 17, x + 5, 21), 255)
        d.point((x + 2, 19), 0)
    d.rectangle((26, 18, 37, 21), 255)
    for x in (28, 30, 33, 35):
        d.line((x, 19, x, 20), 0)
    for x in [20, 22, 40, 42]:
        d.line((x, 18, x - 1, 21), 255)
    d.line((6, 24, 57, 24), 0)
    d.rectangle((0, 26, 63, 31), 0)
    for x in (4, 51):
        d.line((x, 26, x, 31), 255)
        d.line((x + 8, 26, x + 8, 31), 255)
        for offset in (2, 5):
            d.line((x + offset, 27, x + offset + 1, 27), 255)
    for x in (18, 42):
        d.rectangle((x, 26, x + 4, 28), 255)
        d.line((x + 1, 27, x + 3, 27), 0)

    inks = ((C, C, W, W, Y, Y, Y, C), (R,) * 8,
            (R, R, R, W, W, R, R, R), (R, R, W, W, W, W, R, R))
    swing = (7 if smoke is not None else 4) * lean
    im = Image.new("RGB", mask.size, K)
    for y in range(32):
        shift = round(swing * (1 - y / 21)) if y < 24 else -lean
        for x in range(64):
            dest = x + shift
            if 0 <= dest < 64 and mask.getpixel((x, y)):
                im.putpixel((dest, y), inks[y // 8][dest // 8])
    if smoke is not None:
        tyre_smoke(im, ImageDraw.Draw(im), lean, smoke)
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
