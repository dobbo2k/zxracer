#!/usr/bin/env python3
"""Draw scenery masters and build pre-scaled, pre-shifted sprite data.

Each object type is drawn procedurally as a large silhouette master (white on
black), saved as assets/gfx/<type>.png for reference/editing, then scaled to
the size ladder and pre-shifted. Sprites are ORed onto a zero background, so
no masks are stored.

Output (sjasmplus): per type a directory of SIZES entries, 8 bytes each:
  db width_bytes (incl. shift padding), height, shift_mask, 0
  dw data pointer (shift 0), dw bytes per shift
shift_mask selects which pixel shifts exist: x & shift_mask picks the copy
(7 = 8 copies, 6 = 4 copies at 2 - px steps, 4 = 2 copies at 4 - px steps).
usage: make_scenery.py out.asm
"""
import math
import random
import sys
from PIL import Image, ImageDraw

SIZES = [64, 48, 36, 27, 20, 15, 11, 8, 6]       # heights in pixels
SHIFTS = [2, 2, 4, 4, 4, 8, 8, 8, 8]             # copies per size


def master(width, height):
    image = Image.new("L", (width, height))
    return image, ImageDraw.Draw(image)


def palm():
    m, d = master(43, 52)
    d.polygon([(14, 51), (18, 38), (20, 26), (20, 15), (23, 13), (24, 22), (23, 36), (21, 49), (25, 51)], 255)
    for y, x in [(23, 21), (28, 21), (34, 20), (40, 19), (45, 17)]:
        d.line((x, y, x + 2, y - 1), 0)
    fronds=[[(21, 15), (13, 8), (4, 8), (0, 12), (8, 10), (14, 11)],
            [(22, 15), (15, 4), (8, 1), (6, 1), (12, 5), (15, 10)],
            [(22, 15), (20, 7), (21, 0), (23, 2), (24, 7), (23, 12)],
            [(22, 15), (29, 4), (35, 3), (39, 5), (33, 5), (28, 10)],
            [(22, 15), (32, 9), (38, 10), (42, 15), (35, 12), (29, 13)],
            [(21, 15), (32, 15), (38, 19), (40, 25), (35, 20), (28, 18)],
            [(21, 15), (15, 14), (9, 17), (4, 23), (3, 27), (9, 21), (15, 18)],
            [(21, 15), (18, 18), (14, 25), (15, 29), (17, 23), (20, 19)],
            [(21, 15), (27, 17), (30, 22), (30, 28), (28, 24), (24, 19)]]
    for f in fronds:
        d.polygon(f, 255)
    for x, y, side in [(4, 11, -1), (8, 10, -1), (12, 11, -1), (11, 5, -1), (15, 8, -1),
                       (29, 9, 1), (33, 6, 1), (34, 12, 1), (37, 13, 1), (33, 19, 1), (9, 20, -1)]:
        d.line((x, y, x + side, y + 3), 255)
    for x, y in [(18, 14), (21, 13), (24, 15)]:
        d.point((x, y), 0)
    d.line((12, 51, 27, 51), 255)
    return m.resize((192, 256), Image.Resampling.NEAREST)


def car():
    m, d = master(40, 20)
    d.polygon([(1, 12), (5, 9), (9, 3), (12, 2), (28, 2), (33, 9), (38, 10), (39, 15),
               (37, 17), (3, 17), (0, 15)], 255)
    d.polygon([(7, 9), (11, 4), (26, 4), (31, 9)], 0)
    d.line((14, 5, 12, 8), 255)
    d.line((26, 5, 29, 8), 255)
    for x in [3, 29]:
        d.rectangle((x, 11, x + 7, 13), 0)
        d.line((x + 1, 12, x + 4, 12), 255)
    d.line((4, 15, 35, 15), 0)
    d.rectangle((17, 12, 22, 14), 0)
    d.rectangle((4, 17, 10, 19), 255)
    d.rectangle((30, 17, 36, 19), 255)
    return m.resize((256, 128), Image.Resampling.NEAREST)


def truck():
    im, d = master(39, 34)
    d.rectangle((1, 0, 37, 25), 255)
    d.rectangle((3, 2, 35, 22), 0)
    for x in (4, 20):
        d.rectangle((x, 3, x + 14, 21), 255)
        for y in (6, 9, 12):
            d.line((x + 2, y, x + 12, y), 0)
        d.rectangle((x + 5, 15, x + 6, 20), 0)
    d.rectangle((0, 26, 38, 29), 255)
    for x in (3, 28):
        d.rectangle((x, 27, x + 6, 28), 0)
        d.rectangle((x, 30, x + 7, 33), 255)
        d.line((x + 3, 30, x + 3, 33), 0)
    d.line((16, 27, 22, 27), 0)
    return im


def van():
    im, d = master(34, 25)
    d.polygon([(1, 21), (1, 9), (4, 3), (7, 1), (27, 1), (31, 4), (32, 10), (32, 21)], 255)
    d.polygon([(5, 10), (6, 4), (15, 4), (15, 10)], 0)
    d.polygon([(18, 4), (27, 4), (29, 10), (18, 10)], 0)
    d.line((16, 4, 16, 18), 0)
    d.line((4, 13, 13, 13), 0)
    d.line((19, 13, 29, 13), 0)
    for x in (3, 28):
        d.rectangle((x, 15, x + 2, 18), 0)
        d.rectangle((x, 21, x + 3, 24), 255)
    d.rectangle((13, 16, 20, 18), 0)
    d.line((4, 20, 29, 20), 0)
    return im


def sign(direction):
    """Master curve sign: a board on a post with an arrow cut out of it,
    160 x 160. direction +1 points right, -1 left."""
    def draw():
        W, H = 160, 160
        im = Image.new("L", (W, H), 0)
        d = ImageDraw.Draw(im)
        d.rectangle([70, 70, 90, 159], fill=255)                    # post
        d.rounded_rectangle([4, 4, 156, 92], radius=10, fill=255)    # board
        d.line((20, 83, 139, 83), 0, 5)
        pts = [(40, 28), (96, 28), (96, 12), (136, 48), (96, 84), (96, 68), (40, 68)]
        if direction < 0:
            pts = [(W - x, y) for x, y in pts]
        d.polygon(pts, fill=0)                                     # arrow (hole)
        return im
    return draw


def sign_tunnel():
    """Tunnel warning: a board on a post with a tunnel mouth cut out of it -
    an arch over the road - 160 x 160."""
    W, H = 160, 160
    im = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(im)
    d.rectangle([70, 70, 90, 159], fill=255)                        # post
    d.rounded_rectangle([4, 4, 156, 96], radius=10, fill=255)        # board
    d.pieslice([34, 18, 126, 110], 180, 360, fill=0)                 # the arch ...
    d.rectangle([34, 63, 126, 84], fill=0)                           # ... and its sides
    d.polygon([(72, 84), (88, 84), (98, 64), (62, 64)], fill=255)    # the road going in
    d.arc((23, 10, 137, 122), 180, 360, 0, 6)
    d.line((18, 90, 142, 90), 0, 4)
    return im


def fork():
    """Fork marker: a wide board with arrows both ways on two posts, 192 x 128."""
    W, H = 192, 128
    im = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(im)
    d.rectangle([40, 70, 56, 127], fill=255)
    d.rectangle([136, 70, 152, 127], fill=255)
    d.rounded_rectangle([2, 2, 190, 84], radius=10, fill=255)
    d.polygon([(14, 43), (54, 12), (54, 30), (88, 30), (88, 56), (54, 56), (54, 74)], fill=0)
    d.polygon([(178, 43), (138, 12), (138, 30), (104, 30), (104, 56), (138, 56), (138, 74)], fill=0)
    d.line((16, 80, 176, 80), 0, 4)
    d.line((47, 93, 47, 113), 0, 5)
    d.line((142, 93, 142, 113), 0, 5)
    return im


def bush():
    """Low bush: a cluster of round clumps, 192 x 112."""
    im = Image.new("L", (192, 112), 0)
    d = ImageDraw.Draw(im)
    for x, y, r in [(50, 70, 40), (100, 52, 48), (148, 72, 40), (96, 84, 36)]:
        d.ellipse([x - r, y - r, x + r, min(111, y + r)], fill=255)
    for x, y in [(70, 40), (120, 30), (40, 66), (160, 60)]:        # leafy gaps
        d.ellipse([x - 6, y - 6, x + 6, y + 6], fill=0)
    for x, y in ((16, 84), (55, 56), (96, 38), (135, 65)):
        d.polygon([(x, y), (x + 10, y - 18), (x + 28, y - 19), (x + 13, y - 12)], 0)
    d.line([(13, 101), (44, 95), (74, 103), (101, 95)], 0, 5)
    return im


def cactus():
    """Saguaro cactus with two arms, 160 x 256."""
    im = Image.new("L", (160, 256), 0)
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([62, 10, 98, 255], radius=18, fill=255)       # trunk
    d.rounded_rectangle([14, 96, 44, 176], radius=15, fill=255)       # left arm
    d.rectangle([14, 150, 70, 178], fill=255)
    d.rounded_rectangle([116, 60, 146, 150], radius=15, fill=255)     # right arm
    d.rectangle([90, 124, 146, 152], fill=255)
    for x in (72, 80, 88):                                             # ribs
        d.line([(x, 30), (x, 250)], fill=0, width=2)
    d.polygon([(24, 255), (46, 230), (60, 246), (54, 219), (71, 243), (82, 255)], 255)
    d.line([(25, 109), (25, 150), (40, 161), (61, 161)], 0, 6)
    d.line([(129, 70), (129, 131), (117, 144)], 0, 6)
    d.line([(73, 24), (73, 100), (77, 112)], 0, 5)
    return im


def rock():
    """Boulder, 192 x 112."""
    im = Image.new("L", (192, 112), 0)
    d = ImageDraw.Draw(im)
    d.polygon([(6, 111), (20, 50), (60, 18), (118, 8), (162, 34), (186, 80), (190, 111)], fill=255)
    d.line([(70, 30), (96, 70), (90, 111)], fill=0, width=5)          # crack
    d.line([(140, 40), (128, 80)], fill=0, width=4)
    d.polygon([(15, 85), (58, 29), (87, 27), (63, 44), (46, 71)], 0)
    d.line([(108, 25), (149, 48), (156, 66)], 0, 7)
    d.line([(18, 101), (61, 91), (77, 94)], 0, 5)
    return im


def pine():
    m, d = master(27, 42)
    d.rectangle((12, 16, 15, 41), 255)
    for x, y, width, height in [(13, 0, 5, 12), (13, 6, 8, 12), (12, 11, 10, 14),
                             (14, 17, 11, 14), (13, 23, 13, 12)]:
        d.polygon([(x, y), (x + width//2, y + height//2), (x + width//2 - 1, y + height//2),
                   (x + width, y + height - 2), (x + 3, y + height - 3), (x + 4, y + height),
                   (x - width//2, y + height - 2), (x - width, y + height - 1)], 255)
        d.line((x - 1, y + 4, x - width//2, y + height - 4), 0)
    d.line((4, 40, 24, 41), 255)
    return m.resize((160, 256), Image.Resampling.NEAREST)


def tree():
    """Round-crowned tree, 192 x 224."""
    im = Image.new("L", (192, 224), 0)
    d = ImageDraw.Draw(im)
    d.polygon([(84, 223), (88, 120), (104, 120), (108, 223)], fill=255)   # trunk
    for x, y, r in [(96, 70, 62), (54, 96, 40), (138, 96, 40), (96, 112, 44)]:
        d.ellipse([x - r, y - r, x + r, y + r], fill=255)
    for x, y in [(70, 50), (124, 62), (100, 96), (60, 110)]:
        d.ellipse([x - 7, y - 7, x + 7, y + 7], fill=0)
    d.polygon([(90, 175), (56, 127), (65, 126), (95, 150), (127, 119), (134, 119), (101, 167)], 255)
    for x, y in ((30, 91), (54, 64), (79, 45), (104, 67), (138, 83), (84, 109)):
        d.arc((x, y, x + 37, y + 24), 195, 334, 0, 6)
    d.polygon([(74, 223), (93, 204), (109, 216), (120, 223)], 255)
    return im


def lamp():
    m, d = master(29, 48)
    d.polygon([(7, 47), (9, 28), (10, 11), (12, 6), (20, 4), (22, 6), (14, 8), (13, 27), (13, 47)], 255)
    d.polygon([(16, 4), (21, 1), (27, 1), (28, 3), (23, 6), (18, 6)], 255)
    d.line((21, 4, 25, 3), 0)
    d.line((8, 43, 12, 43), 0)
    d.rectangle((6, 46, 15, 47), 255)
    return m.resize((128, 256), Image.Resampling.NEAREST)


def tower():
    m, d = master(24, 45)
    d.polygon([(5, 42), (9, 13), (16, 13), (20, 42)], 255)
    d.rectangle((6, 10, 18, 12), 255)
    d.rectangle((8, 5, 16, 10), 255)
    d.rectangle((10, 6, 14, 9), 0)
    d.line((12, 5, 12, 10), 255)
    d.polygon([(6, 5), (12, 1), (18, 5)], 255)
    d.point((12, 0), 255)
    d.polygon([(9, 19), (16, 16), (16, 20), (8, 24)], 0)
    d.polygon([(8, 30), (17, 26), (18, 30), (7, 35)], 0)
    d.rectangle((11, 36, 13, 41), 0)
    d.rectangle((3, 42, 22, 44), 255)
    return m.resize((192, 256), Image.Resampling.NEAREST)


def parasol():
    """Beach parasol: a striped canopy on a pole, 192 x 160."""
    im = Image.new("L", (192, 160), 0)
    d = ImageDraw.Draw(im)
    d.pieslice([4, 6, 188, 110], 180, 360, fill=255)                   # canopy
    for k in (1, 3, 5):                                                # stripes
        a0, a1 = 180 + k * 30, 180 + k * 30 + 30
        d.pieslice([24, 22, 168, 94], a0, a1, fill=0)
    d.rectangle([90, 50, 102, 159], fill=255)                          # pole
    d.ellipse([88, 0, 104, 14], fill=255)
    d.line([(6, 58), (21, 65), (37, 56), (52, 64), (68, 55), (84, 63), (101, 54), (119, 62), (139, 54), (158, 62), (183, 55)], 255, 7)
    d.line([(99, 120), (152, 100), (137, 132), (103, 141)], 255, 7)
    d.line((104, 141, 95, 159), 255, 6)
    d.line((132, 133, 145, 159), 255, 6)
    return im


def windpump():
    """Windpump: a wheel of vanes on a lattice tower, 176 x 256."""
    im = Image.new("L", (176, 256), 0)
    d = ImageDraw.Draw(im)
    d.line([(40, 255), (82, 80)], fill=255, width=12)                  # legs
    d.line([(136, 255), (94, 80)], fill=255, width=12)
    for y in (120, 170, 220):                                          # cross bars
        w = (y - 80) * 0.24
        d.line([(88 - 6 - w, y), (88 + 6 + w, y)], fill=255, width=8)
    d.line([(60, 220), (110, 120)], fill=255, width=6)
    d.ellipse([28, 4, 148, 124], fill=255)                             # the wheel
    d.ellipse([74, 50, 102, 78], fill=0)
    for k in range(12):                                                # gaps between vanes
        a = math.radians(k * 30 + 15)
        d.line([(88 + 18 * math.cos(a), 64 + 18 * math.sin(a)),
                (88 + 60 * math.cos(a), 64 + 60 * math.sin(a))], fill=0, width=5)
    d.ellipse([82, 58, 94, 70], fill=255)
    d.polygon([(130, 56), (174, 40), (174, 88), (130, 72)], fill=255)  # tail vane
    d.line([(47, 233), (116, 176), (66, 176), (106, 127)], 0, 5)
    d.ellipse((75, 51, 101, 77), 255)
    d.ellipse((82, 58, 94, 70), 0)
    d.polygon([(121, 67), (153, 43), (174, 43), (164, 79)], 255)
    return im


def tumbleweed():
    """Tumbleweed: a tangled ball of twigs, 128 x 112."""
    im = Image.new("L", (128, 112), 0)
    d = ImageDraw.Draw(im)
    d.ellipse([4, 4, 124, 110], fill=255)
    rnd = random.Random(5)
    for _ in range(14):                                                # gaps in the tangle
        x, y = rnd.randint(24, 104), rnd.randint(22, 92)
        a = rnd.random() * math.pi
        d.line([(x - 18 * math.cos(a), y - 18 * math.sin(a)),
                (x + 18 * math.cos(a), y + 18 * math.sin(a))], fill=0, width=5)
    for x, y in ((10, 91), (23, 37), (62, 15), (85, 25), (108, 74)):
        d.line([(59, 81), (x, y), (x - 5, y - 9)], 255, 5)
    d.line([(38, 99), (52, 73), (69, 63), (96, 33)], 0, 6)
    return im


def chalet():
    """Alpine chalet: a broad steep roof over a timber house, 256 x 224."""
    im = Image.new("L", (256, 224), 0)
    d = ImageDraw.Draw(im)
    d.rectangle([36, 100, 220, 223], fill=255)                         # house
    d.polygon([(0, 120), (128, 4), (256, 120), (232, 120), (128, 30), (24, 120)], fill=255)
    d.polygon([(24, 120), (128, 30), (232, 120)], fill=255)            # gable
    d.rectangle([20, 150, 236, 160], fill=255)                         # balcony
    for x in range(30, 232, 18):
        d.rectangle([x, 160, x + 6, 182], fill=0)
    d.rectangle([60, 116, 96, 144], fill=0)                            # windows
    d.rectangle([160, 116, 196, 144], fill=0)
    d.rectangle([112, 70, 144, 100], fill=0)
    d.rectangle([110, 182, 146, 223], fill=0)                          # door
    d.polygon([(155, 56), (155, 14), (174, 14), (174, 75)], 255)
    d.line([(29, 111), (128, 21), (222, 111)], 0, 7)
    for x in (65, 174):
        d.line((x, 116, x, 144), 255, 6)
    for y in (190, 208):
        d.line((42, y, 90, y), 0, 5)
        d.line((150, y, 212, y), 0, 5)
    return im


def snowman():
    """Snowman with a hat, coal eyes and stick arms, 160 x 192."""
    im = Image.new("L", (160, 192), 0)
    d = ImageDraw.Draw(im)
    d.ellipse([28, 104, 132, 191], fill=255)                           # body
    d.ellipse([44, 56, 116, 120], fill=255)                            # chest
    d.ellipse([54, 22, 106, 72], fill=255)                             # head
    d.rectangle([56, 16, 104, 24], fill=255)                           # hat
    d.rectangle([66, 0, 94, 18], fill=255)
    d.rectangle([60, 18, 100, 22], fill=0)                             # its band
    d.rectangle([68, 38, 76, 46], fill=0)                              # eyes
    d.rectangle([86, 38, 94, 46], fill=0)
    for y in (74, 92, 132, 156):                                       # buttons
        d.ellipse([74, y, 86, y + 12], fill=0)
    d.line([(48, 84), (6, 52)], fill=255, width=7)                     # arms
    d.line([(112, 84), (154, 52)], fill=255, width=7)
    d.polygon([(47, 69), (103, 70), (110, 80), (69, 82), (51, 77)], 0)
    d.polygon([(97, 77), (118, 84), (127, 111), (110, 103)], 255)
    d.polygon([(81, 52), (106, 56), (80, 60)], 0)
    return im


def windmill():
    """Windmill: a tapering tower with a cap and four sails, 224 x 256."""
    im = Image.new("L", (224, 256), 0)
    d = ImageDraw.Draw(im)
    d.polygon([(70, 255), (154, 255), (136, 90), (88, 90)], fill=255)  # tower
    d.pieslice([82, 66, 142, 114], 180, 360, fill=255)                 # cap
    d.rectangle([98, 200, 126, 255], fill=0)                           # door
    d.ellipse([104, 130, 120, 146], fill=0)                            # window
    cx, cy = 112, 86
    for k in range(4):                                                 # sails
        a = math.radians(45 + 90 * k)
        ux, uy = math.cos(a), math.sin(a)
        px, py = -uy, ux
        p0 = (cx + 10 * ux, cy + 10 * uy)
        p1 = (cx + 108 * ux, cy + 108 * uy)
        d.polygon([(p0[0], p0[1]), (p1[0], p1[1]),
                   (p1[0] + 22 * px, p1[1] + 22 * py), (p0[0] + 22 * px, p0[1] + 22 * py)], fill=255)
        for t in (40, 64, 88):                                         # lattice
            q = (cx + t * ux, cy + t * uy)
            d.line([(q[0] + 4 * px, q[1] + 4 * py), (q[0] + 18 * px, q[1] + 18 * py)], fill=0, width=4)
    d.ellipse([cx - 9, cy - 9, cx + 9, cy + 9], fill=255)
    for y in (161, 179, 195):
        d.line((95, y, 115, y - 4), 0, 5)
    d.rectangle((123, 199, 135, 213), 0)
    d.ellipse((104, 78, 120, 94), 0)
    return im


def haybales():
    """Two round hay bales, end on, 224 x 112."""
    im = Image.new("L", (224, 112), 0)
    d = ImageDraw.Draw(im)
    for cx, cy, r in ((60, 60, 52), (160, 62, 50)):
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
        for rr in (r - 14, r - 28, r - 40):                            # the rolled spiral
            if rr > 4:
                d.arc([cx - rr, cy - rr, cx + rr, cy + rr], 20, 330, fill=0, width=4)
    for cx in (60, 160):
        d.arc((cx - 34, 29, cx + 29, 91), 30, 282, 0, 6)
        d.line((cx - 28, 94, cx - 7, 99), 0, 4)
    return im


def billboard():
    """Roadside billboard: a big board with a sunset on two legs, 256 x 192."""
    im = Image.new("L", (256, 192), 0)
    d = ImageDraw.Draw(im)
    d.rectangle([56, 120, 72, 191], fill=255)                          # legs
    d.rectangle([184, 120, 200, 191], fill=255)
    d.rectangle([0, 0, 255, 124], fill=255)                            # the board
    d.rectangle([10, 10, 245, 114], fill=0)
    d.pieslice([78, 30, 178, 130], 180, 360, fill=255)                 # a sun setting
    for y in (54, 66, 76):                                             # its stripes
        d.rectangle([70, y, 186, y + 4], fill=0)
    d.rectangle([10, 82, 245, 114], fill=255)                          # the sea
    for x in range(20, 240, 40):                                       # waves
        d.arc([x, 88, x + 30, 104], 200, 340, fill=0, width=4)
    d.line((10, 10, 245, 10), 0, 6)
    d.line((15, 121, 240, 121), 0, 5)
    return im


# name: (draw function, height relative to a palm at the same distance,
#        pre-shifted copies per size)
SHIFTS_SMALL = [2, 2, 2, 2, 4, 4, 4, 8, 8]     # for signs: less memory, coarser steps
SHIFTS_TRAFFIC = [2, 2, 2, 2, 2, 4, 4, 4, 4]   # traffic (resident): memory is short
SHIFTS_VAN = [1, 1, 2, 2, 2, 4, 4, 4, 4]
SHIFTS_SCENERY = [2, 2, 2, 2, 2, 4, 4, 4, 4]   # theme cache: room for four types
TYPES = {
    "palm": (palm, 1.0, SHIFTS_SCENERY),
    "traffic": (car, 0.45, SHIFTS_TRAFFIC),
    "van": (van, 0.62, SHIFTS_VAN),
    "truck": (truck, 0.8, SHIFTS_TRAFFIC),
    "sign_r": (sign(1), 0.5, SHIFTS_SCENERY),
    "sign_l": (sign(-1), 0.5, SHIFTS_SCENERY),
    "fork": (fork, 0.6, SHIFTS_SCENERY),
    "sign_tunnel": (sign_tunnel, 0.5, SHIFTS_SCENERY),
    "bush": (bush, 0.35, SHIFTS_SCENERY),
    "cactus": (cactus, 0.85, SHIFTS_SCENERY),
    "rock": (rock, 0.35, SHIFTS_SCENERY),
    "pine": (pine, 1.0, SHIFTS_SCENERY),
    "tree": (tree, 0.95, SHIFTS_SCENERY),
    "lamp": (lamp, 1.0, SHIFTS_SCENERY),
    "tower": (tower, 0.85, SHIFTS_SCENERY),
    "parasol": (parasol, 0.45, SHIFTS_SCENERY),
    "windpump": (windpump, 1.0, SHIFTS_SCENERY),
    "tumbleweed": (tumbleweed, 0.3, SHIFTS_SCENERY),
    "chalet": (chalet, 0.8, SHIFTS_SCENERY),
    "snowman": (snowman, 0.45, SHIFTS_SCENERY),
    "windmill": (windmill, 0.9, SHIFTS_SCENERY),
    "haybales": (haybales, 0.35, SHIFTS_SCENERY),
    "billboard": (billboard, 0.75, SHIFTS_SCENERY),
    "citypalm": (palm, 0.8, SHIFTS_SCENERY),         # (a smaller palm for the boulevard)
}


def scaled(master, h):
    w = max(1, round(master.width * h / master.height))
    small = master.resize((w, h), Image.BOX)
    return small.point(lambda v: 255 if v >= 80 else 0)


def size_indices(name):
    # Tall roadside silhouettes should read from a distance. Remap their
    # directory entries at build time, keeping the nearest size at 48 px.
    tall = {"palm", "citypalm", "tower", "pine", "tree", "windmill", "lamp",
            "chalet", "cactus", "windpump", "billboard"}
    lift = 2 if name in tall else 0
    return [max(1, k - lift) for k in range(len(SIZES))]


def emit_type(name, label=None, *, master=None, previews=True):
    """Sprite directory and data for one type.

    Returns (consts, directory, data) lists of assembler lines. The
    directory is SIZES entries of 8 bytes; the never-drawn largest size
    aliases size 1."""
    fn, factor, shifts = TYPES[name]
    label = label or f"Scn_{name}"
    master = fn() if master is None else master
    if previews:
        master.save(f"assets/gfx/{name}.png")
    consts, dirl, data = [], [f"{label}:"], []
    indices = size_indices(name)
    for k in indices:
        entry = f"{label}_{k}"
        dirl.append(f"        db {entry}_w, {entry}_h, {entry}_m, 0")
        dirl.append(f"        dw {entry}, {entry}_s")
    for k in sorted(set(indices)):
        nshift = shifts[k]
        h = max(2, round(SIZES[k] * factor))
        img = scaled(master, h)
        wb = (img.width + 7) // 8 + 1        # one byte of shift padding
        step = 8 // nshift
        mask = {1: 0, 2: 4, 4: 6, 8: 7}[nshift]
        lab = f"{label}_{k}"
        consts.append(f"{lab}_w EQU {wb}\n{lab}_h EQU {h}\n{lab}_m EQU {mask}\n{lab}_s EQU {wb * h}")
        data.append(f"{lab}:")
        for s_ in range(0, 8, step):
            for y in range(h):
                bits = 0
                for x in range(img.width):
                    if img.getpixel((x, y)):
                        bits |= 1 << (wb * 8 - 1 - x - s_)
                row = [(bits >> (8 * (wb - 1 - b))) & 0xFF for b in range(wb)]
                data.append("        db " + ", ".join(f"${v:02X}" for v in row))
    return consts, dirl, data


def type_bytes(name, master=None):
    """Bytes of sprite data emit_type produces (for memory planning)."""
    fn, factor, shifts = TYPES[name]
    master = fn() if master is None else master
    tot = 0
    for k in set(size_indices(name)):
        nshift = shifts[k]
        h = max(2, round(SIZES[k] * factor))
        wb = (scaled(master, h).width + 7) // 8 + 1
        tot += wb * h * nshift
    return tot + 8 * len(SIZES)


def main(out):
    lines = ["; Generated by tools/make_scenery.py - do not edit"]
    data = []
    consts = []
    for name, (fn, factor) in TYPES.items():
        master = fn()
        master.save(f"assets/gfx/{name}.png")
        lines.append(f"Scn_{name}:")
        for k, (h0, nshift) in enumerate(zip(SIZES, SHIFTS)):
            if k == 0:
                # the largest size is never drawn (too costly): alias size 1
                lines.append(f"        db Scn_{name}_1_w, Scn_{name}_1_h, Scn_{name}_1_m, 0")
                lines.append(f"        dw Scn_{name}_1, Scn_{name}_1_s")
                continue
            h = max(2, round(h0 * factor))
            img = scaled(master, h)
            wb = (img.width + 7) // 8 + 1        # one byte of shift padding
            step = 8 // nshift
            mask = {1: 0, 2: 4, 4: 6, 8: 7}[nshift]
            label = f"Scn_{name}_{k}"
            lines.append(f"        db {wb}, {h}, {mask}, 0")
            lines.append(f"        dw {label}, {wb * h}")
            consts.append(f"{label}_w EQU {wb}\n{label}_h EQU {h}\n{label}_m EQU {mask}\n{label}_s EQU {wb * h}")
            data.append(f"{label}:")
            for s in range(0, 8, step):
                for y in range(h):
                    bits = 0
                    for x in range(img.width):
                        if img.getpixel((x, y)):
                            bits |= 1 << (wb * 8 - 1 - x - s)
                    row = [(bits >> (8 * (wb - 1 - b))) & 0xFF for b in range(wb)]
                    data.append("        db " + ", ".join(f"${v:02X}" for v in row))
    lines.append("TypeDir:")
    for k, name in enumerate(TYPES):
        lines.append(f"        dw Scn_{name}")
        lines.append(f"TYPE_{name.upper()} EQU {k}")
    lines.append(f"SCN_SIZES EQU {len(SIZES)}")
    lines.append("SizeHeights:")
    lines.append("        db " + ", ".join(str(h) for h in SIZES))
    open(out, "w").write("\n".join(consts + lines + ["ScnData:"] + data) + "\n")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "build/scenery_data.asm")
