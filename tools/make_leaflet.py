#!/usr/bin/env python3
"""The route map leaflet (an insert for the tape release): the 15-stage
pyramid with its forks down to the five goals, in the style of an 80s
printed leaflet - cream paper, black and red spot inks with halftone tints
and a little misregistration, a fold. The stages, themes, endings and par
times come from the game's own data (assets/stages.yaml, make_stages.py);
the icons are the game's scenery shapes; the lettering is the cover's.
Rendered with Chromium, like the cover (tools/make_cover.py).

usage: make_leaflet.py OUT.png [OUT.svg]
"""
import base64
import io
import math
import os
import random
import sys

import yaml
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
import make_cover as mc             # noqa: E402
import make_screens as ms           # noqa: E402
import make_stages                  # noqa: E402

W, H = 1748, 2480                   # A5 at 300 dpi
INK, RED, PAPER = "#211b1b", "#d42a2c", "#f1e6cf"
REG = (2.5, 1.5)                    # the red plate's misregistration
rnd = random.Random(7)

BOX_W, BOX_H, PITCH = 256, 150, 298
ROW_Y0, ROW_DY = 670, 262           # first row's box top, row spacing
GUTTER = 150


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def icon_uri(name, h=46, scale=2, max_w=78):
    """A scenery shape from the game, as a black pixel-art icon (no wider than max_w)."""
    m = ms.silhouette(name, h)
    while m.width * scale > max_w and h > 20:
        h -= 2
        m = ms.silhouette(name, h)
    im = Image.new("RGBA", m.size, (0, 0, 0, 0))
    ink = Image.new("RGBA", m.size, (33, 27, 27, 255))
    im.paste(ink, (0, 0), m.point(lambda v: 255 if v > 127 else 0))
    im = im.resize((m.width * scale, m.height * scale), Image.NEAREST)
    buf = io.BytesIO()
    im.save(buf, "PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode(), im.size


def fmt_par(frames):
    s = frames / 50
    return f"{int(s // 60)}'{int(s % 60):02d}\""


def stages():
    cfg = yaml.safe_load(open("assets/stages.yaml"))
    themes, out = cfg["themes"], []
    for r, row in enumerate(cfg["rows"]):
        for k, st in enumerate(row):
            th = themes[st["theme"]]
            segs, objs, L = make_stages.make_track(r, st["seed"], th)
            out.append(dict(row=r, col=k, theme=st["theme"], name=th["name"],
                            landmark=th["types"][2], par=make_stages.par_time(segs, L)))
    return out, len(cfg["rows"])


def box_pos(r, k, rows):
    n = r + 1
    span = (n - 1) * PITCH
    cx = GUTTER + (W - GUTTER - 70) / 2 - span / 2 + k * PITCH
    return cx, ROW_Y0 + r * ROW_DY


def text(x, y, s, size, colour=INK, weight=700, anchor="start", family="Inter Display", style="normal",
         spacing=0, extra=""):
    return (f'<text x="{mc.f(x)}" y="{mc.f(y)}" font-family="{family}" font-size="{size}" font-weight="{weight}" '
            f'font-style="{style}" fill="{colour}" text-anchor="{anchor}" letter-spacing="{spacing}" {extra}>'
            f'{esc(s)}</text>')


def brush(word, x, y, s, fill, outline=INK, width=30):
    """The cover's brush lettering, in two flat inks (as printed)."""
    strokes, cx = [], x
    for ch in word:
        if ch == " ":
            cx += 118 * 0.55 * s
            continue
        strokes += mc.glyph_pts(ch, cx, y, s, 0.3)
        cx += 118 * s
    ws = [mc.wobble(st, 1.4, 10) for st in strokes]

    def layer(colour, w, dx=0, dy=0):
        return "".join(f'<path d="{mc.path_d([(px + dx, py + dy) for px, py in st])}" fill="none" stroke="{colour}" '
                       f'stroke-width="{mc.f(w)}" stroke-linecap="round" stroke-linejoin="round"/>' for st in ws)
    # the black plate: outline, the letters knocked out of it; the red plate: the letters
    return layer(outline, (width + 14) * s) + layer(PAPER, (width - 2) * s), layer(fill, width * s), cx


def road(p0, p1, width=22):
    """A road on the map: two kerb lines and a dashed centre."""
    (x0, y0), (x1, y1) = p0, p1
    dx, dy = x1 - x0, y1 - y0
    L = math.hypot(dx, dy)
    nx, ny = -dy / L * width / 2, dx / L * width / 2
    c = (x0 + dx * 0.5 + 0, y0 + dy * 0.15)        # a gentle S: down, then across
    path = f"M{mc.f(x0)},{mc.f(y0)} C{mc.f(x0)},{mc.f(y0 + dy * 0.55)} {mc.f(x1)},{mc.f(y1 - dy * 0.55)} {mc.f(x1)},{mc.f(y1)}"
    return (f'<path d="{path}" fill="none" stroke="{INK}" stroke-width="{width + 6}" stroke-linecap="butt"/>'
            f'<path d="{path}" fill="none" stroke="{PAPER}" stroke-width="{width - 4}" stroke-linecap="butt"/>'
            f'<path d="{path}" fill="none" stroke="url(#greytone)" stroke-width="{width - 4}" stroke-linecap="butt"/>'
            f'<path d="{path}" fill="none" stroke="{INK}" stroke-width="2.4" stroke-dasharray="10 9"/>')


def lr_badge(x, y, letter):
    return (f'<circle cx="{mc.f(x)}" cy="{mc.f(y)}" r="19" fill="{PAPER}" stroke="{INK}" stroke-width="3"/>'
            + text(x, y + 9, letter, 26, INK, 900, "middle"))


def chequered_flag(x, y, s=1.0):
    """A goal flag: pole and a 4 x 3 chequer."""
    o = [f'<path d="M{x},{y + 90 * s} L{x},{y}" stroke="{INK}" stroke-width="{5 * s}" stroke-linecap="round"/>']
    cw = 16 * s
    for i in range(4):
        for j in range(3):
            if (i + j) % 2 == 0:
                wave = 4 * s * math.sin(i * 1.3)
                o.append(f'<rect x="{mc.f(x + i * cw)}" y="{mc.f(y + j * cw + wave)}" width="{mc.f(cw)}" '
                         f'height="{mc.f(cw)}" fill="{INK}"/>')
    o.append(f'<path d="M{x},{y} L{mc.f(x + 4 * cw)},{mc.f(y + 4 * s * math.sin(3 * 1.3))} '
             f'L{mc.f(x + 4 * cw)},{mc.f(y + 3 * cw + 4 * s * math.sin(3 * 1.3))} L{x},{mc.f(y + 3 * cw)} Z" '
             f'fill="none" stroke="{INK}" stroke-width="{2.5 * s}"/>')
    return "".join(o)


def build():
    st, nrows = stages()
    black, red = [], []                 # the two plates

    # ---- masthead
    o, f_, _ = brush("SPEED RUN", 150, 80, 1.05, RED)
    black.append(o)
    red.append(f_)
    red.append(f'<rect x="100" y="330" width="{W - 200}" height="64" fill="{RED}"/>')
    red.append(text(W / 2, 377, "ROUTE MAP", 50, PAPER, 900, "middle", spacing=22))    # (knocked out of the red)
    black.append(text(W / 2, 450, "FIFTEEN STAGES  •  FIVE GOALS  •  ONE CLOCK", 30, INK, 800, "middle",
                      spacing=6))
    intro = ["At the end of every stage the road forks. Keep LEFT or RIGHT as the",
             "road splits and you choose the next stage. Each row of the map is longer,",
             "twistier and busier than the one before - and the clock never stops."]
    for k, line in enumerate(intro):
        black.append(text(W / 2, 512 + k * 40, line, 27, INK, 500, "middle", family="Inter"))

    # ---- row gutter: number and difficulty pips
    for r in range(nrows):
        y = ROW_Y0 + r * ROW_DY + BOX_H / 2
        red.append(text(78, y + 6, str(r + 1), 92, RED, 900, "middle", style="italic"))
        black.append(text(78, y - 62, "ROW", 22, INK, 800, "middle", spacing=4))
        for p in range(5):
            filled = p <= r
            cx = 38 + p * 20
            (red if filled else black).append(
                f'<circle cx="{cx}" cy="{mc.f(y + 46)}" r="7" fill="{RED if filled else "none"}" '
                f'stroke="{RED if filled else INK}" stroke-width="2"/>')

    # ---- roads first (under the boxes), with L / R at each fork
    for s in st:
        r, k = s["row"], s["col"]
        cx, y = box_pos(r, k, nrows)
        bottom = (cx, y + BOX_H)
        if r < nrows - 1:
            for side, kk in (("L", k), ("R", k + 1)):
                tx, ty = box_pos(r + 1, kk, nrows)
                black.append(road(bottom, (tx, ty)))
            black.append(lr_badge(cx - 44, y + BOX_H + 44, "L"))
            black.append(lr_badge(cx + 44, y + BOX_H + 44, "R"))
        else:
            black.append(road(bottom, (cx, y + BOX_H + 58)))

    # ---- the stage boxes
    n = 0
    for s in st:
        n += 1
        r, k = s["row"], s["col"]
        cx, y = box_pos(r, k, nrows)
        x0 = cx - BOX_W / 2
        black.append(f'<rect x="{mc.f(x0 + 7)}" y="{mc.f(y + 7)}" width="{BOX_W}" height="{BOX_H}" fill="{INK}"/>')
        black.append(f'<rect x="{mc.f(x0)}" y="{mc.f(y)}" width="{BOX_W}" height="{BOX_H}" fill="{PAPER}"/>')
        red.append(f'<rect x="{mc.f(x0)}" y="{mc.f(y)}" width="{BOX_W}" height="{BOX_H}" fill="url(#redtone)"/>')
        black.append(f'<rect x="{mc.f(x0)}" y="{mc.f(y)}" width="{BOX_W}" height="{BOX_H}" fill="none" '
                     f'stroke="{INK}" stroke-width="4"/>')
        uri, (iw, ih) = icon_uri(s["landmark"])
        black.append(f'<image href="{uri}" x="{mc.f(x0 + 14)}" y="{mc.f(y + BOX_H - ih - 12)}" width="{iw}" '
                     f'height="{ih}" style="image-rendering:pixelated"/>')
        words = s["name"].split()
        tx = x0 + 14 + iw + 10
        room = x0 + BOX_W - 12 - tx
        size = min(30, min(room / (len(w) * 0.66) for w in words))     # (Inter Display Black: ~0.66 em a letter)
        for j, w in enumerate(words):
            black.append(text(tx, y + 58 + j * (size + 4), w, mc.f(size), INK, 900, family="Inter Display"))
        red.append(text(x0 + BOX_W - 14, y + 34, str(n), 30, RED, 900, "end", style="italic"))
        black.append(text(tx, y + BOX_H - 18, "PAR " + fmt_par(s["par"]), 21, INK, 700, family="Inter",
                          spacing=1))

    # ---- the goals
    last = [s for s in st if s["row"] == nrows - 1]
    for s in last:
        cx, y = box_pos(s["row"], s["col"], nrows)
        gy = y + BOX_H + 60
        black.append(chequered_flag(cx - 32, gy - 4, 0.8))
        red.append(text(cx, gy + 112, "GOAL", 32, RED, 900, "middle", spacing=4, style="italic"))
        end = ms.ENDINGS[s["theme"]].replace("THE ", "")
        black.append(text(cx, gy + 142, end, 21, INK, 800, "middle"))

    # ---- tips panel
    py = 2172
    red.append(f'<rect x="100" y="{py}" width="{W - 200}" height="196" fill="url(#redtone)" opacity="0.6"/>')
    black.append(f'<rect x="100" y="{py}" width="{W - 200}" height="196" fill="none" stroke="{INK}" stroke-width="4"/>')
    red.append(text(130, py + 46, "DRIVER'S NOTES", 32, RED, 900, spacing=5, style="italic"))
    notes = [("CHECKPOINTS", "Every stage you finish adds time: 48 seconds on NORMAL."),
             ("EXTENDED PLAY", "Finish a stage inside its PAR time for ten seconds more."),
             ("THE FORK", "Signs warn you before the split - pick a side early, the kerbs are hard."),
             ("THE GOAL", "Every second left on the clock is worth 1000 points.")]
    for j, (h_, body) in enumerate(notes):
        black.append(text(130, py + 86 + j * 30, h_, 23, INK, 900, spacing=2))
        black.append(text(390, py + 86 + j * 30, body, 23, INK, 500, family="Inter"))
    black.append(text(W / 2, H - 46, "Par times are for the NORMAL level.  SPEED RUN for the ZX Spectrum 128K, +2, +2A and +3.",
                      19, INK, 500, "middle", family="Inter"))

    defs = f"""<defs>
  <pattern id="redtone" width="11" height="11" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
    <circle cx="5.5" cy="5.5" r="2.3" fill="{RED}" opacity="0.85"/></pattern>
  <pattern id="greytone" width="7" height="7" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
    <circle cx="3.5" cy="3.5" r="1.4" fill="{INK}" opacity="0.7"/></pattern>
  <filter id="paper" x="0" y="0" width="100%" height="100%">
    <feTurbulence type="fractalNoise" baseFrequency="0.7" numOctaves="2" seed="5" result="g"/>
    <feColorMatrix in="g" type="matrix" values="0 0 0 0 0.45  0 0 0 0 0.38  0 0 0 0 0.28  0 0 0 -1.3 1.0"/>
  </filter>
  <filter id="worn" x="0" y="0" width="100%" height="100%">
    <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="1" seed="9" result="n"/>
    <feColorMatrix in="n" type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 -3.0 2.55" result="m"/>
    <feComposite in="SourceGraphic" in2="m" operator="in"/>
  </filter>
  <filter id="inkspread" x="0" y="0" width="100%" height="100%">
    <feTurbulence type="fractalNoise" baseFrequency="0.05" numOctaves="2" seed="2" result="n"/>
    <feDisplacementMap in="SourceGraphic" in2="n" scale="1.6" xChannelSelector="R" yChannelSelector="G"/>
  </filter>
  <linearGradient id="fold" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#000" stop-opacity="0"/><stop offset="0.5" stop-color="#000" stop-opacity="0.10"/>
    <stop offset="0.52" stop-color="#fff" stop-opacity="0.25"/><stop offset="1" stop-color="#fff" stop-opacity="0"/>
  </linearGradient>
  <radialGradient id="age" cx="0.5" cy="0.45" r="0.75">
    <stop offset="0.65" stop-color="#7a5a20" stop-opacity="0"/><stop offset="1" stop-color="#7a5a20" stop-opacity="0.22"/>
  </radialGradient>
</defs>"""
    body = (f'<rect width="{W}" height="{H}" fill="{PAPER}"/>'
            f'<g filter="url(#inkspread)"><g filter="url(#worn)">{"".join(black)}</g></g>'
            f'<g transform="translate({REG[0]},{REG[1]})" style="mix-blend-mode:multiply" opacity="0.95">'
            f'<g filter="url(#worn)">{"".join(red)}</g></g>'
            f'<rect width="{W}" height="{H}" filter="url(#paper)" style="mix-blend-mode:multiply" opacity="0.28"/>'
            f'<rect x="0" y="{H / 2 - 30}" width="{W}" height="60" fill="url(#fold)"/>'
            f'<rect width="{W}" height="{H}" fill="url(#age)"/>')
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">'
            f'{defs}{body}</svg>')


def main(png, svg=None):
    svg = svg or os.path.splitext(png)[0] + ".svg"
    open(svg, "w").write(build())
    mc.render(svg, png, W, H)


if __name__ == "__main__":
    main(*sys.argv[1:])
