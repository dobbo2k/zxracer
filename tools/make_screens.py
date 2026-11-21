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
import os
import random
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(__file__))
import round_art
import make_scenery as scn           # noqa: E402
from make_font import glyph_bytes, rows as glyph  # noqa: E402

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
        for gy, row in enumerate(glyph_bytes(ch)):
            for gx in range(8):
                if row & (0x80 >> gx):
                    x0 = x + k * 8 * scale + gx * scale
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


# ---------------------------------------------------------------- title
TITLE_TEXT_ROWS = (21, 22, 23)
HISCORE_AT = (21, 17)       # row, column of the hi-score digits (printed by the game)
PRESS_ROW = 22


def title_screen(loading=False):
    """The title screen, or (loading) the tape's loading screen."""
    im = Image.new("RGB", (W, H), (0, 0, 0))
    d = ImageDraw.Draw(im)
    # Sunlit fascia, with the same blue instrument panel and gold badge as the car HUD.
    d.rectangle((0, 0, 255, 47), fill=rgb(BLUE))
    logo = logo_mask("SPEED RUN", 4, 5, 0.33)
    lx = (W - logo.getbbox()[2]) // 2
    for y in range(logo.height):
        colour = rgb(WHITE if y < 15 else CYAN)
        paste_mask(im, logo.crop((0, y, logo.width, y + 1)), lx, 5 + y, colour)
    for x in (0, 5, 10, 225, 230, 235, 240, 245):
        d.line((x, 45, x + 6, 40), fill=rgb(CYAN), width=2)
    d.rectangle((0, 48, 255, 103), fill=rgb(CYAN))
    sky = round_art.sky("harbour", 1)
    im.paste(rgb(WHITE), (45, 50, 205, 82), sky)
    horizon = round_art.panorama("harbour", 1)
    im.paste(rgb(BLUE), (0, 88, 256, 104), horizon)
    for y in range(104, 168):
        t = (y - 104) / 63
        centre = round(119 + 39 * (1 - t) ** 2)
        width = round(5 + 127 * t)
        light = y // 8 % 2
        d.line((0, y, 255, y), fill=rgb(YELLOW, light))
        d.line((centre - width - 5, y, centre + width + 5, y), fill=rgb(WHITE if light else RED))
        d.line((centre - width, y, centre + width, y), fill=rgb(BLACK))
        if light:
            d.line((centre, y, centre + round(3 * t), y), fill=rgb(WHITE))
    for name, x, base, h in (("tower", 46, 124, 33), ("palm", -2, 147, 66),
                             ("palm", 197, 124, 40), ("palm", 215, 156, 74)):
        paste_mask(im, silhouette(name, h), x, base - h, rgb(BLACK))
    im.paste(car_frame(), (96, 136))
    # text panel
    d.rectangle([0, 168, W - 1, H - 1], fill=(0, 0, 0))
    over = [(21, 0, 32, 0x45), (22, 0, 32, 0x46), (23, 0, 32, 0x07)]
    if loading:
        text(d, 8 * 7, 168, "FOR THE 128K SPECTRUM", rgb(CYAN))
        text(d, 8 * 12, 184, "LOADING", rgb(YELLOW))
        over[2] = (23, 0, 32, 0x46)
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
    style = theme["horizon"]["style"]
    sky_panel = round_art.sky(style, theme["horizon"]["seed"])
    cloud_ink = BLUE if (sky >> 3) & 7 == WHITE else YELLOW if (sky >> 3) & 7 == MAGENTA else WHITE
    im.paste(rgb(cloud_ink, bool(sky & 64)), (48, 5, 208, 37), sky_panel)
    pano = round_art.panorama(**theme["horizon"])
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
            d.line([(span(y)[0], y), (span(y)[1], y)],
                   fill=(0, 0, 0))
    # theme scenery either side
    big, _, landmark, _ = theme["types"]
    for x, h, name in ((-6, 66, big), (29, 50, landmark), (183, 43, landmark), (219, 68, big)):
        m = silhouette(name, h)
        paste_mask(im, m, x, 128 - h, (0, 0, 0))
    # the finish gantry and its banner
    post = rgb(WHITE)
    d.rectangle([48, 16, 53, 127], fill=post)
    d.rectangle([202, 16, 207, 127], fill=post)
    d.rectangle([56, 16, 199, 47], fill=rgb(BLUE))
    for x in range(56, 200, 4):                      # chequered edges
        for y in (16, 20, 40, 44):
            if ((x // 4) + (y // 4)) % 2:
                d.rectangle([x, y, x + 3, y + 3], fill=rgb(WHITE))
    m = logo_mask("GOAL!", 3, 2, 0.3)
    paste_mask(im, m, 128 - m.width // 2 + 2, 24, rgb(YELLOW))
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


def ending_themes(config):
    """The ending postcard uses the palette and location actually reached."""
    endings = {}
    for stage in config["rows"][-1]:
        region = config["themes"][stage["theme"]]
        endings[stage["theme"]] = {
            **region,
            "palette": {**region["palette"], **stage.get("palette", {})},
            "horizon": {**region["horizon"], "seed": stage["seed"], "vista": stage.get("vista")},
        }
    return endings


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
    if sys.argv[1:] == ["--loading"]:
        data = title_screen(loading=True)
        with open("assets/gfx/loading.scr", "wb") as output:
            output.write(data)
        preview(data).resize((512, 384), Image.Resampling.NEAREST).save("assets/gfx/loading_preview.png")
        sys.exit(0)
    import yaml
    cfg = yaml.safe_load(open("assets/stages.yaml"))
    for k, (raw, packed) in build(ending_themes(cfg)).items():
        print(f"{k}: {len(packed)} bytes")
