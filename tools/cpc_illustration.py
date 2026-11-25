#!/usr/bin/env python3
"""The Amstrad CPC's artwork masters (docs/cpc_artwork.md): drawn for Mode 0
(pixels twice as wide as tall, 16 pens of the CPC's 27 colours), not
converted from the Spectrum's or the Einstein's pictures, which only say
what each object is.

Masters are indexed images in Mode 0 pixels: each value a pen (src/cpc
pens: docs/cpc_artwork.md), TRANSPARENT where nothing is drawn. They are
drawn at twice the largest size the game shows and scaled down
(tools/cpc_art.py) to the Spectrum's ladder of sizes (make_scenery.SIZES).

Pens the same in every stage: 0 road (grey), 1 black, 2 bright white, 3
bright red, 12 bright yellow. Each theme's own: 4, 5 the ground, 6 the sky,
7, 8 the panorama, 9, 10, 13, 14, 15 its scenery, 11 the HUD's panel.
"""
from PIL import Image, ImageDraw

TRANSPARENT = 255
ROAD, BLACK, WHITE, RED = 0, 1, 2, 3
GROUND_L, GROUND_D, SKY, PANO_INK, PANO_PAPER = 4, 5, 6, 7, 8
S1, S2, HUD, YELLOW, S3, S4, S5 = 9, 10, 11, 12, 13, 14, 15

# The CPC's 27 colours: firmware number -> (RGB, the Gate Array's number)
CPC = {
    0: ((0, 0, 0), 0x14), 1: ((0, 0, 128), 0x04), 2: ((0, 0, 255), 0x15),
    3: ((128, 0, 0), 0x1C), 4: ((128, 0, 128), 0x18), 5: ((128, 0, 255), 0x1D),
    6: ((255, 0, 0), 0x0C), 7: ((255, 0, 128), 0x05), 8: ((255, 0, 255), 0x0D),
    9: ((0, 128, 0), 0x16), 10: ((0, 128, 128), 0x06), 11: ((0, 128, 255), 0x17),
    12: ((128, 128, 0), 0x1E), 13: ((128, 128, 128), 0x00), 14: ((128, 128, 255), 0x1F),
    15: ((255, 128, 0), 0x0E), 16: ((255, 128, 128), 0x07), 17: ((255, 128, 255), 0x0F),
    18: ((0, 255, 0), 0x12), 19: ((0, 255, 128), 0x02), 20: ((0, 255, 255), 0x13),
    21: ((128, 255, 0), 0x1A), 22: ((128, 255, 128), 0x19), 23: ((128, 255, 255), 0x1B),
    24: ((255, 255, 0), 0x0A), 25: ((255, 255, 128), 0x03), 26: ((255, 255, 255), 0x0B),
}
# Named firmware colours
BLACK_C, BLUE_C, BBLUE_C, RED_C, MAGENTA_C, MAUVE_C, BRED_C, PURPLE_C, BMAGENTA_C = range(9)
GREEN_C, CYAN_C, SKYBLUE_C, YELLOW_C, GREY_C, PBLUE_C, ORANGE_C, PINK_C, PMAGENTA_C = range(9, 18)
BGREEN_C, SEAGREEN_C, BCYAN_C, LIME_C, PGREEN_C, PCYAN_C, BYELLOW_C, PYELLOW_C, BWHITE_C = range(18, 27)

# Each theme's 16 pens (firmware colours) and its border
FIXED = {ROAD: GREY_C, BLACK: BLACK_C, WHITE: BWHITE_C, RED: BRED_C, YELLOW: BYELLOW_C}
THEMES = {
    "coast": {GROUND_L: PYELLOW_C, GROUND_D: BYELLOW_C, SKY: BCYAN_C, PANO_INK: BBLUE_C,
              PANO_PAPER: PCYAN_C, S1: GREEN_C, S2: BGREEN_C, HUD: BLUE_C, S3: ORANGE_C,
              S4: RED_C, S5: PBLUE_C},
}


def pens(theme):
    """A theme's 16 pens as firmware colours (pen order)."""
    table = {**FIXED, **THEMES[theme]}
    return [table[k] for k in range(16)]


# The Spectrum's colours (BRIGHT x 8 + colour) as the CPC's firmware colours
SPEC_FW = (BLACK_C, BLUE_C, RED_C, MAGENTA_C, GREEN_C, CYAN_C, YELLOW_C, GREY_C,
           BLACK_C, BBLUE_C, BRED_C, BMAGENTA_C, BGREEN_C, BCYAN_C, BYELLOW_C, BWHITE_C)


def stage_pens(theme_name, palette):
    """A stage's 16 pens and the border as the Gate Array's colours (17
    bytes, src/cpc/reset.asm CpcPalette): its theme's CPC palette if it has
    one, else (until its art, phase A) made from the stage's Spectrum
    palette (attributes: sky, pano, hud, grass_l, grass_d)."""
    if theme_name in THEMES:
        fw = pens(theme_name)
    else:
        def paper(a): return SPEC_FW[((a >> 3) & 7) + (8 if a & 0x40 else 0)]
        def ink(a): return SPEC_FW[(a & 7) + (8 if a & 0x40 else 0)]
        table = {**FIXED, GROUND_L: paper(palette["grass_l"]), GROUND_D: paper(palette["grass_d"]),
                 SKY: paper(palette["sky"]), PANO_INK: ink(palette["pano"]), PANO_PAPER: paper(palette["pano"]),
                 S1: BBLUE_C, S2: BLUE_C, HUD: paper(palette["hud"]), S3: BCYAN_C, S4: MAGENTA_C,
                 S5: GREEN_C}
        fw = [table[k] for k in range(16)]
    return bytes(CPC[c][1] for c in fw) + bytes([CPC[BLACK_C][1]])


def canvas(w, h):
    im = Image.new("L", (w, h), TRANSPARENT)
    return im, ImageDraw.Draw(im)


def outline(im, pen=BLACK):
    """A pen's edge round what is drawn: each transparent pixel next to a
    drawn one (left, right, above, below) becomes PEN."""
    src = im.copy()
    w, h = im.size
    px, out = src.load(), im.load()
    for y in range(h):
        for x in range(w):
            if px[x, y] != TRANSPARENT:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                u, v = x + dx, y + dy
                if 0 <= u < w and 0 <= v < h and px[u, v] not in (TRANSPARENT, pen):
                    out[x, y] = pen
                    break
    return im


# ---------------------------------------------------------------- the coast
# Masters in Mode 0 pixels at twice the largest size shown (so: twice its
# height in lines, and half that many pixels across for a square shape).
def palm():
    """A coconut palm: a gently curved, ringed trunk; long fronds arching out
    and down from the crown, each with its leaflets; coconuts under it."""
    im, d = canvas(56, 192)
    for y in range(44, 192):                       # the trunk, thinning upwards
        t = (191 - y) / 147
        x = 28 + 7 * t * t - 3 * t
        w = 3.2 - 1.4 * t
        d.line((x - w, y, x + w, y), S3)
        d.point((x + w, y), S4)                    # its shaded side
        if (191 - y) % 9 < 2:
            d.line((x - w, y, x + w - 1, y), S4)   # its rings
    cx, cy = 30, 46
    # each frond: (reach across in Mode 0 pixels, its rise, its drop)
    for reach, rise, drop in ((-26, 10, 34), (-20, 18, 26), (-11, 22, 18), (-3, 20, 12),
                              (5, 21, 14), (13, 22, 20), (21, 17, 28), (26, 9, 36)):
        pts = []
        for k in range(21):
            t = k / 20
            pts.append((cx + reach * t, cy - rise * t * 2 + (rise * 2 + drop) * t * t))
        for k, (x, y) in enumerate(pts[:-1]):
            t = k / 20
            w = 3.5 * (1 - t) + 1
            d.ellipse((x - w * 0.5, y - w, x + w * 0.5, y + w), S1)          # the leaf
        for k, (x, y) in enumerate(pts[:-1]):
            t = k / 20
            if k % 2 == 0 and t > 0.15:
                d.line((x, y, x + (1 if reach > 0 else -1), y + 3 + 3 * (1 - t)), S1)   # leaflets
        d.line(pts[:14], S2)                                                  # its lit rib
    d.ellipse((cx - 4, cy - 3, cx + 4, cy + 4), S1)
    for nx in (-3, 1):
        d.ellipse((cx + nx - 2, cy + 1, cx + nx + 1, cy + 6), S4)             # coconuts
    return outline(im)


def bush():
    """A low clump of scrub, light on its top."""
    im, d = canvas(40, 70)
    for x, y, r in ((10, 46, 12), (20, 40, 15), (30, 46, 11), (18, 52, 13), (28, 54, 10)):
        d.ellipse((x - r * 0.6, y - r, x + r * 0.6, y + r), S1)
    for x, y, r in ((14, 36, 6), (22, 31, 7), (30, 38, 5)):
        d.ellipse((x - r * 0.6, y - r, x + r * 0.6, y + r), S2)
    return outline(im)


def tower():
    """A lifeguard tower: a striped hut on long legs, a flag."""
    im, d = canvas(40, 160)
    d.line((8, 159, 14, 70), BLACK, 2)
    d.line((32, 159, 26, 70), BLACK, 2)
    for y in (100, 130):
        d.line((10, y, 30, y + 24), BLACK)
        d.line((30, y, 10, y + 24), BLACK)
    d.rectangle((6, 44, 34, 72), WHITE)
    for y in range(44, 73, 8):
        d.rectangle((6, y, 34, y + 3), RED)
    d.rectangle((12, 52, 28, 62), S5)
    d.polygon([(2, 44), (20, 26), (38, 44)], RED)
    d.line((20, 26, 20, 6), BLACK)
    d.polygon([(20, 6), (32, 11), (20, 16)], YELLOW)
    return outline(im)


def parasol():
    """A beach umbrella in stripes over a pole."""
    im, d = canvas(40, 90)
    d.line((20, 30, 20, 89), BLACK, 2)
    d.pieslice((0, 8, 39, 52), 180, 360, WHITE)
    for k in range(4):
        d.pieslice((0, 8, 39, 52), 180 + 45 * k, 180 + 45 * k + 22, S4 if k % 2 else RED)
    d.line((0, 30, 39, 30), BLACK)
    return outline(im)


def sign(direction):
    """A bend's warning board: chevrons on white, on two posts."""
    im, d = canvas(40, 100)
    d.line((8, 60, 8, 99), BLACK, 2)
    d.line((32, 60, 32, 99), BLACK, 2)
    d.rectangle((0, 20, 39, 62), WHITE)
    d.rectangle((0, 20, 39, 62), None, BLACK)
    for k in range(3):
        x = 6 + k * 11
        if direction > 0:
            d.polygon([(x, 26), (x + 5, 26), (x + 11, 41), (x + 5, 56), (x, 56), (x + 6, 41)], RED)
        else:
            d.polygon([(x + 11, 26), (x + 6, 26), (x, 41), (x + 6, 56), (x + 11, 56), (x + 5, 41)], RED)
    return im


def fork_sign():
    """The fork's board: a split arrow, yellow on blue."""
    im, d = canvas(40, 100)
    d.line((20, 60, 20, 99), BLACK, 2)
    d.rectangle((0, 18, 39, 62), S5)
    d.rectangle((0, 18, 39, 62), None, BLACK)
    d.line((20, 58, 20, 42), YELLOW, 3)
    d.line((20, 42, 9, 26), YELLOW, 3)
    d.line((20, 42, 31, 26), YELLOW, 3)
    d.polygon([(4, 24), (12, 22), (9, 30)], YELLOW)
    d.polygon([(36, 24), (28, 22), (31, 30)], YELLOW)
    return im


def tunnel_sign():
    """A tunnel's board: an arch, white on blue."""
    im, d = canvas(40, 100)
    d.line((20, 60, 20, 99), BLACK, 2)
    d.rectangle((0, 18, 39, 62), S5)
    d.rectangle((0, 18, 39, 62), None, BLACK)
    d.pieslice((8, 26, 32, 60), 180, 360, WHITE)
    d.rectangle((8, 43, 32, 56), WHITE)
    d.rectangle((14, 40, 26, 56), BLACK)
    return im


# ---------------------------------------------------------------- traffic
# Seen from behind (the camera follows the player): body, rear window,
# lamps, tyres. Fixed pens only: they drive through every theme.
def traffic_car():
    """A small hatchback, yellow."""
    im, d = canvas(48, 52)
    d.rounded_rectangle((2, 20, 45, 44), 4, YELLOW)
    d.polygon([(8, 20), (12, 6), (35, 6), (39, 20)], YELLOW)
    d.polygon([(11, 19), (14, 9), (33, 9), (36, 19)], BLACK)
    d.rectangle((4, 26, 10, 30), RED)
    d.rectangle((37, 26, 43, 30), RED)
    d.rectangle((16, 34, 31, 38), WHITE)
    d.rectangle((3, 44, 12, 51), BLACK)
    d.rectangle((35, 44, 44, 51), BLACK)
    return outline(im)


def van():
    """A delivery van, white with a red stripe."""
    im, d = canvas(48, 76)
    d.rectangle((2, 4, 45, 66), WHITE)
    d.rectangle((2, 30, 45, 36), RED)
    d.line((23, 4, 23, 66), BLACK)
    d.rectangle((25, 40, 27, 46), BLACK)
    d.rectangle((19, 40, 21, 46), BLACK)
    d.rectangle((3, 56, 7, 62), RED)
    d.rectangle((40, 56, 44, 62), RED)
    d.rectangle((3, 66, 12, 75), BLACK)
    d.rectangle((35, 66, 44, 75), BLACK)
    return outline(im)


def truck():
    """A lorry: a tall white box on red, its doors and lamps."""
    im, d = canvas(56, 104)
    d.rectangle((2, 2, 53, 82), WHITE)
    d.line((27, 2, 27, 82), BLACK)
    for y in (20, 44, 68):
        d.line((4, y, 25, y), BLACK)
        d.line((29, y, 51, y), BLACK)
    d.rectangle((2, 82, 53, 90), RED)
    d.rectangle((4, 84, 10, 88), YELLOW)
    d.rectangle((45, 84, 51, 88), YELLOW)
    for x in (4, 14, 34, 44):
        d.rectangle((x, 90, x + 8, 103), BLACK)
    return outline(im)


# ---------------------------------------------------------------- the Spider
CAR_W, CAR_H = 32, 32               # Mode 0 pixels: the Spectrum's 64 x 32 block


def spider(pose):
    """The Riviera Spider from behind, as the Spectrum's car block: 0
    straight, 1 left, 2 right (its top swung a little that way, more of the
    far wheel showing); 3-6 smoke (3, 4 steering left: puffs at its outer
    wheel, in two phases; 5, 6 right)."""
    im, d = canvas(CAR_W, CAR_H)
    turn = {0: 0, 1: -1, 2: 1, 3: -1, 4: -1, 5: 1, 6: 1}[pose]
    x0, x1 = 2, 29                                  # the body's sides at the bottom
    top = 2 * turn                                  # the top's swing
    # the tyres, the far one a little wider in a turn
    d.rectangle((x0, 22, x0 + 5 + (turn > 0), 31), BLACK)
    d.rectangle((x1 - 5 - (turn < 0), 22, x1, 31), BLACK)
    # the tail: wide and low, a black band of grille between the lamps
    d.polygon([(x0 + 1 + top, 12), (x1 - 1 + top, 12), (x1, 18), (x1, 25), (x0, 25), (x0, 18)], RED)
    d.rectangle((x0 + 1, 18, x1 - 1, 20), BLACK)
    for lx in (x0 + 2, x1 - 6):                     # round tail lamps
        d.rectangle((lx, 18, lx + 4, 20), RED)
        d.rectangle((lx + 1, 18, lx + 3, 20), YELLOW)
    d.rectangle((14, 22, 17, 24), WHITE)            # the plate
    d.line((x0 + 1, 25, x1 - 1, 25), BLACK)
    d.rectangle((x0 + 3, 26, x0 + 5, 27), WHITE)    # exhausts
    d.rectangle((x1 - 5, 26, x1 - 3, 27), WHITE)
    # the deck, lit along its crest; the roll hoop and the driver
    d.line((x0 + 2 + top, 13, x1 - 2 + top, 13), WHITE)
    d.polygon([(10 + top, 12), (12 + top, 6), (19 + top, 6), (21 + top, 12)], BLACK)
    d.ellipse((13 + top, 2, 18 + top, 8), WHITE)    # the helmet
    d.line((13 + top, 5, 18 + top, 5), RED)
    d.rectangle((x0 + top, 10, x0 + 2 + top, 11), BLACK)      # mirrors
    d.rectangle((x1 - 2 + top, 10, x1 + top, 11), BLACK)
    if pose >= 3:
        second = pose in (4, 6)
        right = pose in (3, 4)                      # (left turn: the right wheel)
        sx = x1 + 2 if right else x0 - 2
        for k, (dx, dy, r) in enumerate(((0, 28, 3), (3, 24, 2), (1, 19, 2))):
            if second and k == 0:
                dy -= 2
            if second and k == 2:
                continue
            x = sx + (dx if right else -dx)
            d.ellipse((x - r, dy - r, x + r, dy + r), WHITE)
    return outline(im)


def preview(im, theme, scale=4):
    """An image of a master in its theme's colours (Mode 0 pixels doubled
    across)."""
    colours = [CPC[c][0] for c in pens(theme)]
    w, h = im.size
    out = Image.new("RGB", (w * 2 * scale, h * scale), (40, 40, 40))
    px = im.load()
    for y in range(h):
        for x in range(w):
            if px[x, y] != TRANSPARENT:
                out.paste(colours[px[x, y]], (x * 2 * scale, y * scale, (x + 1) * 2 * scale, (y + 1) * scale))
    return out


MASTERS = {"palm": palm, "bush": bush, "tower": tower, "parasol": parasol,
           "sign_r": lambda: sign(1), "sign_l": lambda: sign(-1), "fork": fork_sign,
           "sign_tunnel": tunnel_sign, "traffic": traffic_car, "van": van, "truck": truck}


def cpc_masters(theme_name):
    """The CPC's masters for a theme's types and the resident traffic, as
    ("cpc", image) (tools/cpc_art.py emit_type): the coast's so far."""
    out = {t: ("cpc", MASTERS[t]()) for t in ("traffic", "van", "truck", "sign_r", "sign_l", "fork",
                                              "sign_tunnel")}
    if theme_name == "coast":
        out.update({t: ("cpc", MASTERS[t]()) for t in ("palm", "bush", "tower", "parasol")})
    return out
