"""Scrolling landscapes drawn at the CPC's displayed resolution (128 x 16)."""
import math
import random

from PIL import Image, ImageDraw

from cpc_illustration import (BLACK, GROUND_D, GROUND_L, HUD, PANO_INK, PANO_PAPER,
                              RED, S1, S2, S3, S4, S5, SKY, WHITE, YELLOW)


def landscape(style, seed, vista=None):
    im = Image.new("L", (128, 16), SKY)
    d = ImageDraw.Draw(im)
    rng = random.Random(seed)
    phase = rng.random() * math.tau

    def ridge(base, amplitude, colour, frequency):
        for x in range(128):
            a = x * math.tau / 128
            y = round(base + amplitude * (.65 * math.sin(frequency * a + phase)
                                          + .35 * math.sin(3 * a - phase)))
            d.line((x, y, x, 15), colour)

    if style == "harbour":
        ridge(8, 4, PANO_PAPER, 2)
        ridge(10, 3, PANO_INK, 3)
        d.rectangle((0, 12, 127, 15), S5)
        for x in (8, 29, 86, 113):
            d.polygon([(x, 10), (x + 3, 2), (x + 3, 10)], WHITE)
            d.line((x, 11, x + 6, 11), S4)
        for _ in range(16):
            x, y = rng.randrange(128), rng.randrange(13, 16)
            d.line((x, y, x + 2, y), PANO_PAPER)
        if vista == "liner":
            d.polygon([(42, 10), (69, 10), (65, 14), (45, 14)], HUD)
            d.rectangle((46, 7, 63, 9), WHITE)
            for x in (49, 55):
                d.rectangle((x, 4, x + 2, 6), RED)
        elif vista == "beacon":
            d.polygon([(51, 12), (53, 3), (55, 3), (57, 12)], WHITE)
            d.rectangle((52, 6, 55, 7), RED)
            d.rectangle((52, 2, 55, 3), S4)
    elif style == "peaks":
        ridge(7, 5, PANO_PAPER, 3)
        for x in range(-12, 132, 17):
            h = rng.randint(1, 6)
            d.polygon([(x - 9, 15), (x + 3, h), (x + 19, 15)], S1)
            d.polygon([(x + 3, h), (x + 7, h + 4), (x + 5, h + 3),
                       (x + 3, h + 5), (x + 2, h + 3), (x - 2, h + 5)], WHITE)
            d.polygon([(x + 4, h + 4), (x + 17, 15), (x + 9, 15)], S2)
        ridge(14, 2, S3, 4)
        if vista == "gondola":
            d.line((28, 1, 60, 6, 84, 1), BLACK)
            for x, y in ((38, 3), (69, 4)):
                d.rectangle((x, y + 2, x + 4, y + 5), RED)
        elif vista == "lodge":
            d.rectangle((39, 10, 51, 15), S5)
            d.polygon([(37, 10), (45, 4), (53, 10)], WHITE)
            for x in (41, 46):
                d.point((x, 12), YELLOW)
    elif style == "mesas":
        ridge(9, 4, S5, 2)
        for x in range(-8, 128, 25):
            y = rng.randint(2, 8)
            w = 3 if vista == "needles" else rng.randint(7, 13)
            d.polygon([(x, 14), (x+4, y+3), (x+5, y), (x+w+4, y),
                       (x+w+5, y+5), (x+w+10, 14)], S4)
            d.polygon([(x, 14), (x+5, y), (x+7, y), (x+5, 10)], S3)
            d.line((x+5, y, x+w+3, y), GROUND_L)
        ridge(14, 1, GROUND_D, 3)
        if vista == "arch":
            d.arc((45, 3, 62, 22), 180, 360, S4, width=3)
        elif vista == "ruins":
            for x, y in ((46, 7), (52, 8), (58, 5)):
                d.rectangle((x, y, x+2, 14), S3)
            d.line((45, 6, 54, 6), S4, 2)
    elif style == "hills":
        ridge(6, 4, PANO_PAPER, 2)
        ridge(10, 4, S1, 3)
        ridge(13, 3, GROUND_D, 2)
        for x in (8, 20, 78, 101):
            d.rectangle((x, 10, x+5, 13), WHITE)
            d.polygon([(x-1, 10), (x+2, 6), (x+6, 10)], S3)
        if vista == "mill":
            d.polygon([(48, 13), (50, 5), (52, 5), (54, 13)], WHITE)
            d.line((47, 1, 55, 9), S3)
            d.line((55, 1, 47, 9), S3)
        elif vista == "manor":
            d.rectangle((40, 7, 55, 13), S3)
            d.line((40, 6, 55, 6), HUD)
            for x in range(42, 55, 3):
                d.point((x, 9), YELLOW)
    else:
        for x in range(0, 128, 4):
            y = rng.randrange(2, 12)
            d.rectangle((x, y, x+2, 15), PANO_INK)
            for wy in range(y+2, 14, 3):
                d.point((x+1, wy), rng.choice((YELLOW, S5)))
        d.line((0, 15, 127, 15), S5)
        if vista == "wheel":
            d.ellipse((42, 1, 55, 14), outline=YELLOW)
            d.line((44, 3, 53, 12), RED)
            d.line((53, 3, 44, 12), RED)
            d.line((48, 1, 48, 14), YELLOW)
    if vista == "bridge":
        for x in (35, 62):
            d.rectangle((x, 2, x+1, 15), HUD)
            d.line((x-12, 11, x, 2, x+13, 11), WHITE)
        d.line((20, 12, 78, 12), S4)
    return im


def cloud_mask(style, seed):
    """Cloud banks or a slatted sunset disc inside the protected 80 x 32 area."""
    im = Image.new("1", (80, 32))
    d = ImageDraw.Draw(im)
    rng = random.Random(seed)
    if style == "skyline":
        x = rng.randrange(13, 48)
        d.ellipse((x, 0, x+15, 29), 1)
        for y in (16, 20, 24, 25, 28):
            d.line((x, y, x+15, y), 0)
    else:
        for start in (0, 40):
            x, y = start + rng.randrange(4), rng.randrange(10, 17)
            for dx, dy, w, h in ((0, 1, 12, 4), (6, -3, 13, 8), (12, -8, 12, 13), (19, -3, 10, 8), (24, 1, 10, 4)):
                if style == "mesas":
                    dy, h = dy//2, max(2, h//2)
                d.ellipse((x+dx, y+dy, x+dx+w, y+dy+h), 1)
            d.line((x+7, y+3, x+14, y+3), 0)
            d.line((x+15, y+8, x+27, y+8), 1)
    return im
