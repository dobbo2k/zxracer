#!/usr/bin/env python3
"""Draw the title screen and the five goal screens, convert them to Spectrum
screens (bitmap + attributes, two colours per 8x8 cell) and compress them.

All artwork is original and procedural: the logo is the game's own 5x7 font
enlarged and slanted, the scenery comes from make_scenery.py, the backdrops
from make_stages.py and the car from assets/gfx/car.png.

Used by make_stages.py, which stores the compressed screens in bank 6 with
the screen code. Previews are written to assets/gfx/screen_*.png.

Compression (unpacked by UnLZ in src/screens_bank.asm), a byte stream of:
  $00-$7F n   n + 1 literal bytes follow
  $80-$FE n   copy n - $80 + 3 bytes from offset (next word) bytes back
  $FF         end
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(__file__))
import make_scenery as scn           # noqa: E402
from make_font import rows as glyph  # noqa: E402

W, H = 256, 192
BASE = [(0, 0, 0), (0, 0, 1), (1, 0, 0), (1, 0, 1), (0, 1, 0), (0, 1, 1), (1, 1, 0), (1, 1, 1)]
BLACK, BLUE, RED, MAGENTA, GREEN, CYAN, YELLOW, WHITE = range(8)


def rgb(c, bright=True):
    v = 255 if bright else 215
    return tuple(k * v for k in BASE[c])


def attr_rgb(attr, ink=True):
    """Colour of an attribute byte's ink or paper."""
    c = attr & 7 if ink else (attr >> 3) & 7
    return rgb(c, bool(attr & 0x40))


COLOURS = {}
for _c in range(8):
    for _b in (False, True):
        COLOURS[rgb(_c, _b)] = (_c, _b)


# ---------------------------------------------------------------- conversion
def to_zx(im, overrides=()):
    """RGB image in Spectrum colours -> 6912 bytes in screen memory order.
    Per cell: the two most common colours (black fits either brightness);
    other pixels take the nearer of the two. overrides: (row, col0, col1,
    attribute) forced on cells (text panels the game prints into)."""
    px = im.load()
    bitmap = bytearray(6144)
    attrs = bytearray(768)
    forced = {}
    for r, c0, c1, a in overrides:
        for c in range(c0, c1):
            forced[(r, c)] = a
    for cy in range(24):
        for cx in range(32):
            cells = [px[cx * 8 + x, cy * 8 + y] for y in range(8) for x in range(8)]
            counts = {}
            for p in cells:
                counts[p] = counts.get(p, 0) + 1
            order = sorted(counts, key=lambda p: -counts[p])
            if (cy, cx) in forced:
                a = forced[(cy, cx)]
                two = [attr_rgb(a, False), attr_rgb(a, True)]
            else:
                two = order[:2] if len(order) > 1 else [order[0], (0, 0, 0)]
            # brightness: of the most common non-black colour
            bright = next((COLOURS[p][1] for p in order if p != (0, 0, 0)), False)
            if (cy, cx) in forced:
                attr = forced[(cy, cx)]
                paper, ink = two
            else:
                # ink: the less common colour; plain black paper when present
                a0, a1 = two
                if a1 == (0, 0, 0):
                    paper, ink = a1, a0
                elif a0 == (0, 0, 0):
                    paper, ink = a0, a1
                else:
                    paper, ink = a0, a1
                attr = (0x40 if bright else 0) | (COLOURS[paper][0] << 3) | COLOURS[ink][0]
            for y in range(8):
                b = 0
                for x in range(8):
                    p = px[cx * 8 + x, cy * 8 + y]
                    if p == ink or (p != paper and dist(p, ink) < dist(p, paper)):
                        b |= 0x80 >> x
                yy = cy * 8 + y
                addr = ((yy & 0xC0) << 5) | ((yy & 7) << 8) | ((yy & 0x38) << 2)
                bitmap[addr + cx] = b
            attrs[cy * 32 + cx] = attr
    return bytes(bitmap + attrs)


def dist(a, b):
    return sum((x - y) ** 2 for x, y in zip(a, b))


def preview(data):
    im = Image.new("RGB", (W, H))
    px = im.load()
    for y in range(H):
        addr = ((y & 0xC0) << 5) | ((y & 7) << 8) | ((y & 0x38) << 2)
        for cx in range(32):
            b = data[addr + cx]
            a = data[6144 + (y // 8) * 32 + cx]
            for x in range(8):
                px[cx * 8 + x, y] = attr_rgb(a, bool(b & (0x80 >> x)))
    return im


# ---------------------------------------------------------------- compression
def lz(data):
    out = bytearray()
    lit = bytearray()
    heads = {}
    i, n = 0, len(data)

    def flush():
        while lit:
            chunk = lit[:128]
            out.append(len(chunk) - 1)
            out.extend(chunk)
            del lit[:128]

    while i < n:
        best_len, best_off = 0, 0
        key = bytes(data[i:i + 3])
        for j in reversed(heads.get(key, [])[-64:]):
            length = 0
            while i + length < n and length < 129 and data[j + length] == data[i + length]:
                length += 1
            if length > best_len:
                best_len, best_off = length, i - j
                if length == 129:
                    break
        if best_len >= 3:
            flush()
            out.append(0x80 + best_len - 3)
            out += bytes((best_off & 0xFF, best_off >> 8))
            step = best_len
        else:
            lit.append(data[i])
            step = 1
        for k in range(i, min(i + step, n - 2)):
            heads.setdefault(bytes(data[k:k + 3]), []).append(k)
        i += step
    flush()
    out.append(0xFF)
    assert unlz(out) == bytes(data)
    return bytes(out)


def unlz(src):
    out = bytearray()
    i = 0
    while src[i] != 0xFF:
        c = src[i]
        if c < 0x80:
            out += src[i + 1:i + 2 + c]
            i += 2 + c
        else:
            off = src[i + 1] | (src[i + 2] << 8)
            for _ in range(c - 0x80 + 3):
                out.append(out[-off])
            i += 3
    return bytes(out)


# ---------------------------------------------------------------- drawing aids
def text(d, x, y, s, colour, scale=1):
    """The game's 5x7 font at pixel (x, y)."""
    for k, ch in enumerate(s):
        for gy, row in enumerate(glyph(ch)):
            for gx in range(5):
                if row[gx] == "#":
                    x0 = x + k * 8 * scale + (gx + 1) * scale
                    y0 = y + gy * scale
                    d.rectangle([x0, y0, x0 + scale - 1, y0 + scale - 1], fill=colour)


def logo_mask(s, scale_x, scale_y, slant):
    """Big slanted letters with speed stripes: L image, 255 = letter."""
    cw = 6 * scale_x
    im = Image.new("L", (len(s) * cw + 7 * scale_y // 2 + 8, 7 * scale_y + 2), 0)
    d = ImageDraw.Draw(im)
    for k, ch in enumerate(s):
        for gy, row in enumerate(glyph(ch)):
            for gx in range(5):
                if row[gx] != "#":
                    continue
                for yy in range(scale_y):
                    y = gy * scale_y + yy
                    shift = int((7 * scale_y - y) * slant)
                    x0 = k * cw + gx * scale_x + shift
                    d.line([(x0, y), (x0 + scale_x - 1, y)], fill=255)
    for y in range(im.height // 2 + 3, im.height, 6):   # speed stripes, lower half
        d.line([(0, y), (im.width, y)], fill=0)
    return im


def paste_mask(im, mask, x, y, colour):
    solid = Image.new("RGB", mask.size, colour)
    im.paste(solid, (x, y), mask)


def silhouette(name, h):
    master = scn.TYPES[name][0]()
    return scn.scaled(master, h)


def car_frame():
    car = Image.open(os.path.join("assets", "gfx", "car.png")).convert("RGB")
    return car.crop((0, 0, 64, 32))


def bayer(level, x, y):
    """Ordered dither: True for `level` (0-16) of 16 pixels."""
    m = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
    return m[y & 3][x & 3] < level


# ---------------------------------------------------------------- title
TITLE_TEXT_ROWS = (21, 22, 23)
HISCORE_AT = (21, 17)       # row, column of the hi-score digits (printed by the game)
PRESS_ROW = 22


def title_screen(loading=False):
    """The title screen, or (loading) the tape's loading screen."""
    im = Image.new("RGB", (W, H), (0, 0, 0))
    d = ImageDraw.Draw(im)
    rnd = random.Random(42)
    # night sky with stars (rows 0-6), then sunset bands (rows 7-13)
    for _ in range(40):
        x, y = rnd.randrange(W), rnd.randrange(0, 56)
        im.putpixel((x, y), rgb(WHITE, rnd.random() < 0.5))
    # sunset bands (all bright): (top, colour, dither colour, dither level)
    bands = [(56, BLUE, MAGENTA, 5), (64, MAGENTA, MAGENTA, 0), (72, MAGENTA, RED, 8),
             (80, RED, RED, 0), (88, RED, YELLOW, 3), (96, RED, RED, 0), (104, RED, RED, 0)]
    sun_x, sun_r, horizon = 128, 46, 112
    for y0, c0, c1, lvl in bands:
        for y in range(y0, y0 + 8):
            for x in range(W):
                near_sun = abs(x - sun_x) < sun_r + 8 and y >= (horizon - sun_r) // 8 * 8
                dith = lvl and not near_sun and bayer(lvl, x, y)
                im.putpixel((x, y), rgb(c1 if dith else c0))
    # the sun, its stripes widening towards the horizon
    for y in range(horizon - sun_r, horizon):
        dy = horizon - y
        if dy < 30 and dy % 6 < (3 if dy < 12 else 2):
            continue
        hw = int(math.sqrt(sun_r * sun_r - dy * dy))
        d.line([(sun_x - hw, y), (sun_x + hw, y)], fill=rgb(YELLOW))
    # mountains either side of the sun
    from make_stages import panorama
    pano = panorama("mountains", 7)
    for x in range(W):
        if abs(x - sun_x) < sun_r + 10:
            continue
        for y in range(16):
            if pano.getpixel((x, y)):
                im.putpixel((x, horizon - 16 + y), (0, 0, 0))
    # neon ground: a perspective grid, the road clear of it
    gy0 = horizon
    for k in range(1, 12):                           # horizontal lines
        y = gy0 + int(56 * (k / 11) ** 2.2) + 1
        if y < 168:
            d.line([(0, y), (W, y)], fill=rgb(MAGENTA))
    for k in range(-12, 13):                         # lines to the vanishing point
        d.line([(128 + k * 6, gy0), (128 + k * 64, gy0 + 64 * 4)], fill=rgb(MAGENTA))
    road = [(124, gy0), (132, gy0), (128 + 112, 168), (128 - 112, 168)]
    d.polygon(road, fill=(0, 0, 0))
    d.line([(124, gy0), (128 - 112, 168)], fill=rgb(MAGENTA), width=3)
    d.line([(132, gy0), (128 + 112, 168)], fill=rgb(MAGENTA), width=3)
    for k in range(6):                               # centre dashes
        t0, t1 = (k / 6) ** 1.8, ((k + 0.5) / 6) ** 1.8
        y0, y1 = gy0 + int(56 * t0), gy0 + int(56 * t1)
        w0 = max(1, int(4 * t0))
        d.polygon([(128 - w0, y0), (128 + w0, y0), (128 + w0 + 1, y1), (128 - w0 - 1, y1)],
                  fill=rgb(WHITE))
    # palms against the sunset
    for x, h, base in ((-8, 84, 150), (30, 56, 136), (200, 60, 138), (222, 88, 152)):
        m = silhouette("palm", h)
        paste_mask(im, m, x, base - h, (0, 0, 0))
    # the logo
    m = logo_mask("ZX RACER", 4, 6, 0.3)
    lx = (W - m.width) // 2 + 4
    for y in range(m.height):
        colour = rgb(WHITE) if y < 8 else rgb(YELLOW) if y < 24 else rgb(RED)
        for x in range(m.width):
            if m.getpixel((x, y)) and 0 <= lx + x < W:
                im.putpixel((lx + x, 6 + y), colour)
    # the player's car on the road
    im.paste(car_frame(), (96, 136))
    # text panel
    d.rectangle([0, 168, W - 1, H - 1], fill=(0, 0, 0))
    over = [(21, 0, 32, 0x45), (22, 0, 32, 0x46), (23, 0, 32, 0x07)]
    if loading:
        text(d, 8 * 7, 168, "FOR THE 128K SPECTRUM", rgb(CYAN))
        text(d, 8 * 12, 176, "LOADING", rgb(YELLOW))
        over[1] = (22, 0, 32, 0xC6)                  # flashing
    else:
        text(d, 8 * 7, 168, "HI-SCORE", rgb(CYAN))
        text(d, 8 * 5, 176, "PRESS ANY KEY TO START", rgb(YELLOW))
    # row 23: the game prints its keys there; the tape loader, a progress bar
    return to_zx(im, over)


# ---------------------------------------------------------------- goal
GOAL_TEXT = {"congrats": 18, "ending": 19, "score": 21, "bonus": 22, "press": 23}


def goal_screen(theme):
    pal = theme["palette"]
    sky, pano_a, grass_l, grass_d = pal["sky"], pal["pano"], pal["grass_l"], pal["grass_d"]
    kerb_l, kerb_d = pal["kerb_l"], pal["kerb_d"]
    im = Image.new("RGB", (W, H), (0, 0, 0))
    d = ImageDraw.Draw(im)
    rnd = random.Random(theme["name"])
    horizon = 72
    d.rectangle([0, 0, W - 1, horizon - 1], fill=attr_rgb(sky, False))
    # backdrop
    from make_stages import panorama
    pano = panorama(**theme["horizon"])
    for x in range(W):
        for y in range(16):
            if pano.getpixel(((x + 40) % 256, y)):
                im.putpixel((x, horizon - 16 + y), attr_rgb(pano_a, True))
    # ground in light / dark bands, and the road to the finish with kerb
    # cells drawn the way the game draws them
    top_w, bot_w, rw = 40, 210, 4

    def span(y):
        hw = (top_w + (bot_w - top_w) * (y - horizon) / (136 - horizon)) / 2
        return int(128 - hw), int(128 + hw)

    for cy in range(horizon // 8, 136 // 8):
        y0 = cy * 8
        dark = (cy - horizon // 8) % 2
        grass = attr_rgb(grass_d if dark else grass_l, False)
        kerb = attr_rgb(kerb_d if dark else kerb_l, False)
        d.rectangle([0, y0, W - 1, y0 + 7], fill=grass)
        lefts = [span(y)[0] for y in range(y0, y0 + 8)]
        rights = [span(y)[1] for y in range(y0, y0 + 8)]
        for x0, x1 in ((min(lefts) - rw, max(lefts)), (min(rights), max(rights) + rw)):
            d.rectangle([x0 // 8 * 8, y0, x1 // 8 * 8 + 7, y0 + 7], fill=kerb)
        for y in range(y0, y0 + 8):
            d.line([span(y), (span(y)[1], y)] if False else [(span(y)[0], y), (span(y)[1], y)],
                   fill=(0, 0, 0))
    # theme scenery either side
    big, small = theme["types"]
    for x, h, name in ((0, 72, big), (34, 50, big), (186, 50, big), (220, 72, big)):
        m = silhouette(name, h)
        paste_mask(im, m, x, 128 - h, (0, 0, 0))
    # the finish gantry and its banner
    post = rgb(WHITE)
    d.rectangle([48, 16, 53, 127], fill=post)
    d.rectangle([202, 16, 207, 127], fill=post)
    d.rectangle([56, 16, 199, 47], fill=rgb(WHITE))
    for x in range(56, 200, 4):                      # chequered edges
        for y in (16, 20, 40, 44):
            if ((x // 4) + (y // 4)) % 2:
                d.rectangle([x, y, x + 3, y + 3], fill=(0, 0, 0))
    m = logo_mask("GOAL!", 3, 2, 0.3)
    paste_mask(im, m, 128 - m.width // 2 + 2, 24, rgb(RED))
    # confetti
    for _ in range(26):
        cx, cy = rnd.randrange(32), rnd.randrange(0, 2)
        if 6 <= cx <= 25:
            continue
        colour = rgb(rnd.choice([RED, YELLOW, MAGENTA, WHITE, GREEN]))
        for _ in range(3):
            x, y = cx * 8 + rnd.randrange(7), cy * 8 + rnd.randrange(7)
            d.rectangle([x, y, x + 1, y + 1], fill=colour)
    # the car crossing the line
    im.paste(car_frame(), (96, 104))
    d.rectangle([0, 136, W - 1, H - 1], fill=(0, 0, 0))
    over = [(r, 0, 32, a) for r, a in ((18, 0x46), (19, 0x47), (21, 0x45), (22, 0x44), (23, 0x46))]
    return to_zx(im, over)


ENDINGS = {
    "alpine": "THE SUMMIT LODGE",
    "country": "THE HARVEST FAIR",
    "coast": "THE HARBOUR PIER",
    "sunset": "THE CITY LIGHTS",
    "desert": "THE CANYON GATE",
}


def build(themes, preview_dir="assets/gfx"):
    """-> {name: (raw 6912 bytes, compressed)} for 'title' and 'goal_<theme>'."""
    out = {"title": title_screen()}
    for tname, theme in themes.items():
        out[f"goal_{tname}"] = goal_screen(theme)
    res = {}
    for name, raw in out.items():
        preview(raw).save(os.path.join(preview_dir, f"screen_{name}.png"))
        res[name] = (raw, lz(raw))
    return res


if __name__ == "__main__":
    import yaml
    cfg = yaml.safe_load(open("assets/stages.yaml"))
    for k, (raw, packed) in build(cfg["themes"]).items():
        print(f"{k}: {len(packed)} bytes")
