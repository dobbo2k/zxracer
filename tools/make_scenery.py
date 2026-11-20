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
(7 = 8 copies, 6 = 4 copies at 2-px steps, 4 = 2 copies at 4-px steps).
usage: make_scenery.py out.asm
"""
import math
import random
import sys
from PIL import Image, ImageDraw

SIZES = [64, 48, 36, 27, 20, 15, 11, 8, 6]       # heights in pixels
SHIFTS = [2, 2, 4, 4, 4, 8, 8, 8, 8]             # copies per size


def palm():
    """Master palm tree, 192 x 256 (scaled 1/4 to 48 x 64)."""
    W, H = 192, 256
    im = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(im)
    # trunk: a gentle S-curve, tapering from 22 px at the foot to 10 at the top
    top = (104, 70)
    pts = []
    for k in range(41):
        t = k / 40
        x = 92 + 18 * math.sin(t * 2.4) + 10 * t
        y = H - 1 - t * (H - 1 - top[1])
        pts.append((x, y, 11 - 6 * t))
    for (x0, y0, r0), (x1, y1, r1) in zip(pts, pts[1:]):
        d.polygon([(x0 - r0, y0), (x0 + r0, y0), (x1 + r1, y1), (x1 - r1, y1)], 255)
    for k in range(4, 40, 4):                       # bark rings
        x, y, r = pts[k]
        d.line([(x - r, y), (x + r, y)], 0, 2)
    cx, cy = pts[-1][0], pts[-1][1]
    # fronds: drooping arcs, thick near the crown, thin at the tips
    for ang, length, droop in [(-170, 92, 60), (-140, 80, 50), (-110, 60, 30),
                               (-70, 60, 30), (-40, 82, 52), (-10, 92, 62),
                               (-90, 40, 10), (160, 70, 70), (20, 70, 70)]:
        a = math.radians(ang)
        prev = (cx, cy)
        for k in range(1, 21):
            t = k / 20
            x = cx + math.cos(a) * length * t
            y = cy + math.sin(a) * length * t + droop * t * t
            wdt = max(5, int(22 * (1 - t)))
            d.line([prev, (x, y)], 255, wdt)
            # leaflets
            if k % 2 == 0 and t > 0.2:
                d.line([(x, y), (x + 6 * math.cos(a + 1.2), y + 10)], 255, 5)
                d.line([(x, y), (x + 6 * math.cos(a - 1.2), y + 10)], 255, 5)
            prev = (x, y)
    d.ellipse([cx - 14, cy - 10, cx + 14, cy + 12], 255)   # crown / coconuts
    return im


def car():
    """Master traffic car (rear view of a small hatchback), 256 x 128.

    Drawn as a white body with black holes (windows, lamps, gaps): on the
    road the XOR sprite shows white with the details in the road's black.
    """
    W, H = 256, 128
    im = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([40, 4, 216, 64], radius=24, fill=255)      # cabin
    d.rounded_rectangle([12, 52, 244, 108], radius=14, fill=255)    # body
    d.rounded_rectangle([60, 14, 196, 52], radius=12, fill=0)       # rear window
    d.rectangle([24, 66, 64, 80], fill=0)                           # lamps
    d.rectangle([192, 66, 232, 80], fill=0)
    d.rectangle([100, 76, 156, 96], fill=0)                         # number plate
    d.rectangle([20, 104, 64, 127], fill=255)                       # tyres
    d.rectangle([192, 104, 236, 127], fill=255)
    return im


def truck():
    """Master truck (rear view of a box lorry), 256 x 210: a tall box with
    two doors, lamps, a bumper and twin tyres."""
    W, H = 256, 210
    im = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([4, 0, 252, 168], radius=8, fill=255)       # the box
    d.rectangle([121, 14, 135, 168], fill=0)                        # door seam
    d.rectangle([12, 8, 244, 16], fill=0)                           # top rail
    d.rectangle([4, 84, 252, 100], fill=0)                          # a stripe round the box
    for x in (40, 216):                                             # hinges
        for y in (36, 132):
            d.rectangle([x - 18, y, x + 18, y + 10], fill=0)
    d.rectangle([96, 112, 108, 150], fill=0)                        # handles
    d.rectangle([148, 112, 160, 150], fill=0)
    d.rectangle([0, 172, 256, 190], fill=255)                       # bumper
    d.rectangle([14, 176, 52, 186], fill=0)                         # lamps
    d.rectangle([204, 176, 242, 186], fill=0)
    d.rectangle([104, 174, 152, 188], fill=0)                       # plate
    d.rectangle([10, 192, 84, 209], fill=255)                       # twin tyres
    d.rectangle([172, 192, 246, 209], fill=255)
    d.rectangle([46, 192, 48, 209], fill=0)
    d.rectangle([208, 192, 210, 209], fill=0)
    return im


def van():
    """Master van (rear view), 256 x 160: a high roof, two rear windows on
    split doors, lamps down the sides."""
    W, H = 256, 160
    im = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([16, 0, 240, 136], radius=30, fill=255)     # body
    d.rounded_rectangle([34, 16, 122, 60], radius=8, fill=0)        # windows
    d.rounded_rectangle([134, 16, 222, 60], radius=8, fill=0)
    d.rectangle([126, 16, 130, 128], fill=0)                        # door seam
    d.rectangle([20, 70, 32, 108], fill=0)                          # lamps
    d.rectangle([224, 70, 236, 108], fill=0)
    d.rectangle([100, 98, 156, 114], fill=0)                        # plate
    d.rectangle([8, 124, 248, 140], fill=255)                       # bumper
    d.rectangle([24, 142, 72, 159], fill=255)                       # tyres
    d.rectangle([184, 142, 232, 159], fill=255)
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
        pts = [(40, 28), (96, 28), (96, 12), (136, 48), (96, 84), (96, 68), (40, 68)]
        if direction < 0:
            pts = [(W - x, y) for x, y in pts]
        d.polygon(pts, fill=0)                                     # arrow (hole)
        return im
    return draw


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
    return im


def bush():
    """Low bush: a cluster of round clumps, 192 x 112."""
    im = Image.new("L", (192, 112), 0)
    d = ImageDraw.Draw(im)
    for x, y, r in [(50, 70, 40), (100, 52, 48), (148, 72, 40), (96, 84, 36)]:
        d.ellipse([x - r, y - r, x + r, min(111, y + r)], fill=255)
    for x, y in [(70, 40), (120, 30), (40, 66), (160, 60)]:        # leafy gaps
        d.ellipse([x - 6, y - 6, x + 6, y + 6], fill=0)
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
    return im


def rock():
    """Boulder, 192 x 112."""
    im = Image.new("L", (192, 112), 0)
    d = ImageDraw.Draw(im)
    d.polygon([(6, 111), (20, 50), (60, 18), (118, 8), (162, 34), (186, 80), (190, 111)], fill=255)
    d.line([(70, 30), (96, 70), (90, 111)], fill=0, width=5)          # crack
    d.line([(140, 40), (128, 80)], fill=0, width=4)
    return im


def pine():
    """Pine tree: stacked triangles on a short trunk, 160 x 256."""
    im = Image.new("L", (160, 256), 0)
    d = ImageDraw.Draw(im)
    d.rectangle([70, 200, 90, 255], fill=255)
    for top, base, half in [(4, 80, 40), (40, 140, 58), (90, 210, 78)]:
        d.polygon([(80, top), (80 - half, base), (80 + half, base)], fill=255)
    for y in (82, 142):                                                # layer gaps
        d.line([(40, y), (120, y)], fill=0, width=3)
    return im


def tree():
    """Round-crowned tree, 192 x 224."""
    im = Image.new("L", (192, 224), 0)
    d = ImageDraw.Draw(im)
    d.polygon([(84, 223), (88, 120), (104, 120), (108, 223)], fill=255)   # trunk
    for x, y, r in [(96, 70, 62), (54, 96, 40), (138, 96, 40), (96, 112, 44)]:
        d.ellipse([x - r, y - r, x + r, y + r], fill=255)
    for x, y in [(70, 50), (124, 62), (100, 96), (60, 110)]:
        d.ellipse([x - 7, y - 7, x + 7, y + 7], fill=0)
    return im


def lamp():
    """Street lamp: a tall post with an arm and a lamp head, 128 x 256."""
    im = Image.new("L", (128, 256), 0)
    d = ImageDraw.Draw(im)
    d.rectangle([56, 30, 66, 255], fill=255)
    d.rectangle([44, 236, 78, 255], fill=255)                         # base
    d.rectangle([56, 22, 110, 32], fill=255)                          # arm
    d.rounded_rectangle([92, 22, 124, 44], radius=6, fill=255)        # lamp head
    return im


def tower():
    """Lifeguard tower: a hut on stilts with a sloping roof, 192 x 256."""
    im = Image.new("L", (192, 256), 0)
    d = ImageDraw.Draw(im)
    for x0, x1 in ((40, 58), (134, 152)):                             # stilts
        d.polygon([(x0, 255), (x0 + 18, 255), (x1 - 4, 132), (x1 - 22, 132)], fill=255)
    d.line([(52, 230), (140, 150)], fill=255, width=10)                # bracing
    d.line([(52, 150), (140, 230)], fill=255, width=10)
    d.rectangle([24, 120, 168, 134], fill=255)                         # platform
    d.rectangle([36, 48, 156, 122], fill=255)                          # cabin
    d.rectangle([54, 64, 90, 96], fill=0)                              # windows
    d.rectangle([102, 64, 138, 96], fill=0)
    d.polygon([(14, 50), (96, 8), (178, 50)], fill=255)                # roof
    d.line([(96, 8), (96, 0)], fill=255, width=6)                      # flag
    d.polygon([(96, 0), (128, 6), (96, 14)], fill=255)
    return im


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


def emit_type(name, label=None):
    """Sprite directory and data for one type.

    Returns (consts, directory, data) lists of assembler lines. The
    directory is SIZES entries of 8 bytes; the never-drawn largest size
    aliases size 1."""
    fn, factor, shifts = TYPES[name]
    label = label or f"Scn_{name}"
    master = fn()
    master.save(f"assets/gfx/{name}.png")
    consts, dirl, data = [], [f"{label}:"], []
    for k, (h0, nshift) in enumerate(zip(SIZES, shifts)):
        if k == 0:
            dirl.append(f"        db {label}_1_w, {label}_1_h, {label}_1_m, 0")
            dirl.append(f"        dw {label}_1, {label}_1_s")
            continue
        h = max(2, round(h0 * factor))
        img = scaled(master, h)
        wb = (img.width + 7) // 8 + 1        # one byte of shift padding
        step = 8 // nshift
        mask = {1: 0, 2: 4, 4: 6, 8: 7}[nshift]
        lab = f"{label}_{k}"
        dirl.append(f"        db {wb}, {h}, {mask}, 0")
        dirl.append(f"        dw {lab}, {wb * h}")
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


def type_bytes(name):
    """Bytes of sprite data emit_type produces (for memory planning)."""
    fn, factor, shifts = TYPES[name]
    master = fn()
    tot = 0
    for k, (h0, nshift) in enumerate(zip(SIZES, shifts)):
        if k == 0:
            continue
        h = max(2, round(h0 * factor))
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
