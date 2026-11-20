#!/usr/bin/env python3
"""A printable cassette inlay (J-card) for the tape release, at 300 dpi:
101.6 mm tall; outside: back flap (15 mm), spine (12.7 mm), front (65 mm);
inside: screenshots and how to play. The front is the cover art and the
spine its lettering (tools/make_cover.py: release/cover.png,
assets/gfx/spine.png); the rest uses the game's own logo lettering and 5x7
font (tools/make_screens.py) on the cover's night sky - no fonts needed.

usage: make_inlay.py OUTDIR COVER.png SPINE.png SHOT.ppm...   (screenshots from zxsim)
-> OUTDIR/inlay_outside.png, inlay_inside.png, inlay_preview.png
"""
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(__file__))
import make_screens as ms           # noqa: E402
from make_font import G as GLYPHS   # noqa: E402

MM = 300 / 25.4
H = round(101.6 * MM)               # 1200
FLAP, SPINE, FRONT = round(15 * MM), round(12.7 * MM), round(65 * MM)
W = FLAP + SPINE + FRONT

RED, YELLOW, WHITE, CYAN = (215, 0, 0), (255, 255, 0), (255, 255, 255), (0, 215, 215)
NIGHT = (20, 8, 52)                 # the cover's sky
MAGENTA, GREEN, BLACK = (215, 0, 215), (0, 215, 0), (0, 0, 0)

HOW_TO_PLAY = [
    ("LOADING", "ON A 128K, +2, +2A OR +3 CHOOSE TAPE LOADER OR TYPE LOAD \"\". "
                "SPEEDRUN.TZX LOADS IN ABOUT 3 MINUTES, SPEEDRUN.TAP IN ABOUT 6."),
    ("CONTROLS", "Q ACCELERATE, A BRAKE, O AND P STEER, SPACE CHANGES GEAR, H PAUSES. "
                 "KEMPSTON JOYSTICK: FIRE CHANGES GEAR. ENTER ON THE TITLE SCREEN: "
                 "OPTIONS - JOYSTICKS, YOUR OWN KEYS, SOUND, LEVEL."),
    ("THE RACE", "DRIVE FROM THE COAST TO ONE OF FIVE GOALS BEFORE THE CLOCK RUNS OUT. "
                 "AT THE END OF A STAGE THE ROAD FORKS: KEEP LEFT OR RIGHT TO PICK THE NEXT. "
                 "CHECKPOINTS ADD TIME - BEAT A STAGE'S PAR TIME FOR EXTENDED PLAY, "
                 "TEN SECONDS MORE."),
    ("DRIVING", "START IN LOW, CHANGE UP AT ABOUT 180 KM. BENDS PUSH THE CAR OUT - THE "
                "FASTER, THE HARDER - SO LIFT OFF OR BRAKE, OR THE TYRES LET GO. GRASS "
                "SLOWS YOU. HIT A TREE OR A SIGN AND YOU CRASH, RAM SLOW TRAFFIC AND YOU "
                "SPIN. LATER STAGES: MORE TRAFFIC, AND DRIVERS WHO SWERVE."),
    ("SCORE", "POINTS FOR SPEED, AND 1000 FOR EACH SECOND LEFT AT THE GOAL. THE TOP FIVE "
              "SCORES AND EVERY STAGE'S RECORD TIME STAY UNTIL YOU SWITCH OFF."),
    ("LEVELS", "EASY: 80 SECONDS TO START, 55 A CHECKPOINT. NORMAL: 68 AND 48. "
               "HARD: 60 AND 44."),
]


def glyph_ok(s):
    for ch in s:
        assert ch == " " or ch in GLYPHS, f"no glyph for {ch!r} in {s!r}"


def text(d, x, y, s, colour, scale):
    glyph_ok(s)
    ms.text(d, x, y, s, colour, scale)


def wrap(s, width):
    lines, line = [], ""
    for word in s.split():
        if line and len(line) + 1 + len(word) > width:
            lines.append(line)
            line = word
        else:
            line = f"{line} {word}" if line else word
    return lines + [line]


def checker(d, x0, y0, x1, y1, cell):
    for y in range(y0, y1, cell):
        for x in range(x0, x1, cell):
            c = RED if ((x - x0) // cell + (y - y0) // cell) % 2 else YELLOW
            d.rectangle([x, y, min(x + cell, x1) - 1, min(y + cell, y1) - 1], fill=c)


def logo(word, height, colours=(RED, YELLOW)):
    """The title's slanted lettering, top half one colour, bottom the other."""
    mask = ms.logo_mask(word, 12, 12, 0.35)
    im = Image.new("RGB", mask.size, BLACK)
    ms.paste_mask(im, mask, 0, 0, colours[1])
    top = mask.crop((0, 0, mask.width, mask.height // 2))
    ms.paste_mask(im, top, 0, 0, colours[0])
    k = height / im.height
    return im.resize((round(im.width * k), height), Image.NEAREST), \
        mask.resize((round(mask.width * k), height), Image.NEAREST)


def centred(d, y, s, colour, scale, x0, width):
    text(d, x0 + (width - len(s) * 8 * scale) // 2, y, s, colour, scale)


def front(cover):
    """The cover art, scaled to the front panel (cropping its sides a little)."""
    k = H / cover.height
    im = cover.resize((round(cover.width * k), H), Image.LANCZOS)
    x = (im.width - FRONT) // 2
    return im.crop((x, 0, x + FRONT, H))


def strip(width, height, draw):
    """A panel drawn sideways (reading top to bottom once turned)."""
    im = Image.new("RGB", (height, width), NIGHT)
    draw(im, ImageDraw.Draw(im))
    return im.rotate(-90, expand=True)


def spine(art):
    """The cover's lettering, turned to read down the spine."""
    return art.resize((H, SPINE), Image.LANCZOS).rotate(-90, expand=True)


def flap():
    def draw(im, d):
        text(d, 40, 30, "SPEEDRUN.TZX - TURBO - ABOUT 3 MIN", YELLOW, 3)
        text(d, 40, 70, "SPEEDRUN.TAP - NORMAL - ABOUT 6 MIN", WHITE, 3)
        text(d, 40, 120, "ZX SPECTRUM 128K +2 +2A +3", CYAN, 3)
    return strip(FLAP, H, draw)


def outside(cover, spine_art):
    im = Image.new("RGB", (W, H), NIGHT)
    im.paste(flap(), (0, 0))
    im.paste(spine(spine_art), (FLAP, 0))
    im.paste(front(cover), (FLAP + SPINE, 0))
    d = ImageDraw.Draw(im)
    for x in (FLAP, FLAP + SPINE):                       # fold marks
        d.line([(x, 0), (x, 12)], fill=(90, 90, 90), width=2)
        d.line([(x, H - 12), (x, H)], fill=(90, 90, 90), width=2)
    return im


def inside(shots):
    im = Image.new("RGB", (W, H), NIGHT)
    d = ImageDraw.Draw(im)
    gap = (W - 4 * 256) // 5
    for k, s in enumerate(shots[:4]):
        im.paste(s, (gap + k * (256 + gap), 24))
    y = 24 + 192 + 20
    lg, mask = logo("HOW TO PLAY", 60, (YELLOW, RED))
    im.paste(lg, ((W - lg.width) // 2, y), mask)
    y += 60 + 24
    width = (W - 2 * 30) // 24
    colours = [CYAN, GREEN, YELLOW, MAGENTA, CYAN, GREEN]
    for (head, body), c in zip(HOW_TO_PLAY, colours):
        lines = wrap(head + ": " + body, width)
        for k, line in enumerate(lines):
            if k == 0:
                text(d, 30, y, head + ":", c, 3)
                text(d, 30 + (len(head) + 1) * 24, y, line[len(head) + 1:], WHITE, 3)
            else:
                text(d, 30, y, line, WHITE, 3)
            y += 26
        y += 8
    assert y <= H - 20, f"the instructions run off the inlay ({y} > {H - 20})"
    return im


def main(outdir, cover, spine_art, *shots):
    cover = Image.open(cover).convert("RGB")
    spine_art = Image.open(spine_art).convert("RGB")
    shots = [Image.open(s).convert("RGB").crop((32, 48, 288, 240)) for s in shots]
    out = outside(cover, spine_art)
    ins = inside(shots)
    out.save(os.path.join(outdir, "inlay_outside.png"), dpi=(300, 300))
    ins.save(os.path.join(outdir, "inlay_inside.png"), dpi=(300, 300))
    pv = Image.new("RGB", (W, 2 * H + 40), (60, 60, 60))
    pv.paste(out, (0, 0))
    pv.paste(ins, (0, H + 40))
    pv.resize((W // 2, (2 * H + 40) // 2), Image.LANCZOS).save(os.path.join(outdir, "inlay_preview.png"))


if __name__ == "__main__":
    main(*sys.argv[1:])
