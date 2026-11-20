#!/usr/bin/env python3
"""Hand-drawn style cover art (an original illustration of the game's title
scene): a seeded SVG of sketchy, doubled ink lines, hatching, washed colour
and paper grain, rendered to PNG with the pre-installed Chromium (Playwright).
The lettering is brush-stroked from letter skeletons defined here (no fonts).

usage: make_cover.py OUT.png [OUT.svg]
"""
import math
import os
import random
import subprocess
import sys
import tempfile

W, H = 1300, 2000
HZ = 1050                       # horizon
VX = W / 2                      # vanishing point x
INK = "#1b0f24"
rnd = random.Random(1984)

# ---------------------------------------------------------------- helpers
def f(v):
    return f"{v:.1f}"


def bez(p0, p1, p2, p3, n=24):
    out = []
    for i in range(n + 1):
        t = i / n
        a = (1 - t) ** 3
        b = 3 * (1 - t) ** 2 * t
        c = 3 * (1 - t) * t * t
        d = t ** 3
        out.append((a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0],
                    a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]))
    return out


def resample(pts, step):
    out = [pts[0]]
    for a, b in zip(pts, pts[1:]):
        L = math.dist(a, b)
        n = max(1, int(L / step))
        for i in range(1, n + 1):
            t = i / n
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out


def wobble(pts, amp, step=14):
    """A hand's wobble: smooth random drift along the line."""
    pts = resample(pts, step)
    dx = dy = 0.0
    out = []
    for x, y in pts:
        dx = dx * 0.7 + rnd.uniform(-amp, amp) * 0.3
        dy = dy * 0.7 + rnd.uniform(-amp, amp) * 0.3
        out.append((x + dx, y + dy))
    return out


def path_d(pts, closed=False):
    d = "M" + " L".join(f"{f(x)},{f(y)}" for x, y in pts)
    return d + (" Z" if closed else "")


def sketch(pts, width=3.0, colour=INK, passes=2, amp=2.2, closed=False, opacity=1.0, overshoot=6):
    """Ink line(s): each pass wobbles on its own, overshooting the ends a little."""
    out = []
    if closed:
        pts = pts + [pts[0]]
    for k in range(passes):
        p = list(pts)
        if overshoot and not closed and len(p) > 1:
            (x0, y0), (x1, y1) = p[0], p[1]
            L = math.dist(p[0], p[1]) or 1
            e = rnd.uniform(0, overshoot)
            p[0] = (x0 - (x1 - x0) / L * e, y0 - (y1 - y0) / L * e)
            (x0, y0), (x1, y1) = p[-1], p[-2]
            L = math.dist(p[-1], p[-2]) or 1
            e = rnd.uniform(0, overshoot)
            p[-1] = (x0 - (x1 - x0) / L * e, y0 - (y1 - y0) / L * e)
        w = width * (1 if k == 0 else rnd.uniform(0.45, 0.75))
        out.append(f'<path d="{path_d(wobble(p, amp))}" fill="none" stroke="{colour}" '
                   f'stroke-width="{f(w)}" stroke-linecap="round" stroke-linejoin="round" '
                   f'opacity="{opacity if k == 0 else opacity * 0.7:.2f}"/>')
    return "\n".join(out)


def fill(pts, colour, extra=""):
    return f'<path d="{path_d(wobble(pts, 1.5, 20), True)}" fill="{colour}" {extra}/>'


def hatch(clip, x0, y0, x1, y1, angle, spacing, colour=INK, width=1.6, opacity=0.5, amp=1.2):
    """Parallel pencil strokes over a box, clipped to a shape."""
    a = math.radians(angle)
    ux, uy = math.cos(a), math.sin(a)
    nx, ny = -uy, ux
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    R = math.hypot(x1 - x0, y1 - y0) / 2
    out = [f'<g clip-path="url(#{clip})">']
    s = -R
    while s < R:
        L = R * rnd.uniform(0.85, 1.0)
        px, py = cx + nx * s, cy + ny * s
        # a stroke or two along the line, with gaps
        t = -L
        while t < L:
            seg = rnd.uniform(L * 0.4, L * 1.4)
            a0 = (px + ux * t, py + uy * t)
            a1 = (px + ux * min(L, t + seg), py + uy * min(L, t + seg))
            out.append(f'<path d="{path_d(wobble([a0, a1], amp, 30))}" stroke="{colour}" '
                       f'stroke-width="{f(width * rnd.uniform(0.6, 1.2))}" fill="none" '
                       f'stroke-linecap="round" opacity="{opacity * rnd.uniform(0.6, 1.0):.2f}"/>')
            t += seg + rnd.uniform(4, 30)
        s += spacing * rnd.uniform(0.75, 1.25)
    out.append("</g>")
    return "\n".join(out)


clips = []


def clip_of(pts):
    cid = f"c{len(clips)}"
    clips.append(f'<clipPath id="{cid}"><path d="{path_d(pts, True)}"/></clipPath>')
    return cid


# ---------------------------------------------------------------- lettering
GLYPHS = {
    "S": ["M84,22 C62,0 16,4 16,36 C16,68 84,64 84,100 C84,138 28,142 10,114"],
    "P": ["M20,140 L20,6 L58,6 C96,6 96,72 58,72 L20,72"],
    "E": ["M84,6 L20,6 L20,140 L84,140", "M20,72 L68,72"],
    "D": ["M20,6 L20,140 L48,140 C100,140 100,6 48,6 L20,6"],
    "R": ["M20,140 L20,6 L58,6 C96,6 96,72 58,72 L20,72", "M48,72 L88,140"],
    "U": ["M18,6 L18,94 C18,150 82,150 82,94 L82,6"],
    "N": ["M18,140 L18,6 L82,140 L82,6"],
    "F": ["M84,6 L20,6 L20,140", "M20,72 L68,72"],
    "O": ["M50,6 C2,6 2,140 50,140 C98,140 98,6 50,6"],
    "T": ["M8,6 L92,6", "M50,6 L50,140"],
    "H": ["M18,6 L18,140", "M82,6 L82,140", "M18,72 L82,72"],
    "Z": ["M14,6 L86,6 L14,140 L86,140"],
    "X": ["M14,6 L86,140", "M86,6 L14,140"],
    "C": ["M88,26 C70,0 12,0 12,73 C12,146 70,146 88,120"],
    "M": ["M10,140 L10,6 L50,84 L90,6 L90,140"],
    "1": ["M28,28 L52,6 L52,140"],
    "2": ["M14,34 C18,0 86,0 86,38 C86,74 14,100 14,140 L88,140"],
    "8": ["M50,70 C10,70 10,6 50,6 C90,6 90,70 50,70 C4,70 4,140 50,140 C96,140 96,70 50,70"],
    "K": ["M20,6 L20,140", "M86,6 L20,86", "M44,64 L88,140"],
    "A": ["M10,140 L50,6 L90,140", "M26,90 L74,90"],
    "Y": ["M10,6 L50,72 L90,6", "M50,72 L50,140"],
    "L": ["M20,6 L20,140 L84,140"],
    "G": ["M88,26 C70,0 12,0 12,73 C12,146 70,146 88,120 L88,80 L58,80"],
}


def glyph_pts(ch, x, y, s, slant):
    """The letter's strokes as point lists (unit 100 x 146), slanted."""
    strokes = []
    for d in GLYPHS[ch]:
        toks = d.replace(",", " ").replace("M", " M ").replace("L", " L ").replace("C", " C ").split()
        pts, cur, i = [], None, 0
        while i < len(toks):
            t = toks[i]
            if t in "ML":
                cur = (float(toks[i + 1]), float(toks[i + 2]))
                pts.append(cur)
                i += 3
            elif t == "C":
                c1 = (float(toks[i + 1]), float(toks[i + 2]))
                c2 = (float(toks[i + 3]), float(toks[i + 4]))
                p = (float(toks[i + 5]), float(toks[i + 6]))
                pts += bez(cur, c1, c2, p)[1:]
                cur = p
                i += 7
            else:
                i += 1
        strokes.append([(x + (px + (146 - py) * slant) * s, y + py * s) for px, py in pts])
    return strokes


def lettering(word, x, y, s, width, slant=0.25, grad="logo", gap=118, outline=INK, wob=1.8,
              stripes=True, shadow=True):
    """Brush lettering: shadow, ink outline, gradient body, speed stripes, highlight."""
    strokes = []
    cx = x
    for ch in word:
        if ch == " ":
            cx += gap * 0.55 * s
            continue
        strokes += glyph_pts(ch, cx, y, s, slant)
        cx += gap * s
    ws = [wobble(st, wob, 10) for st in strokes]
    out = []
    lw = width * s

    def layer(dx, dy, colour, w, op=1.0, extra=""):
        return "\n".join(f'<path d="{path_d([(px + dx, py + dy) for px, py in st])}" fill="none" '
                         f'stroke="{colour}" stroke-width="{f(w)}" stroke-linecap="round" '
                         f'stroke-linejoin="round" opacity="{op}" {extra}/>' for st in ws)
    if shadow:
        out.append(layer(10 * s, 12 * s, "#0b0614", lw + 18 * s, 0.85))
    out.append(layer(0, 0, outline, lw + 14 * s))
    body = layer(0, 0, f"url(#{grad})", lw)
    if stripes:
        out.append(f'<g mask="url(#stripes)">{body}</g>')
    else:
        out.append(body)
    out.append(layer(-3 * s, -4 * s, "#fff6d8", 3.2 * s, 0.75, 'stroke-dasharray="40 26 12 30"'))
    return "\n".join(out), cx


# ---------------------------------------------------------------- scene
def sky():
    out = [f'<rect x="0" y="0" width="{W}" height="{HZ + 4}" fill="url(#sky)"/>']
    # washes of cloud
    for k in range(7):
        y = rnd.uniform(380, 860)
        x = rnd.uniform(-200, W)
        w = rnd.uniform(260, 560)
        h = rnd.uniform(14, 34)
        out.append(f'<ellipse cx="{f(x)}" cy="{f(y)}" rx="{f(w)}" ry="{f(h)}" fill="#ff9a6a" '
                   f'opacity="{rnd.uniform(0.10, 0.22):.2f}" filter="url(#soft)"/>')
        pts = [(x - w * 0.8, y + h * 0.3), (x - w * 0.2, y - h * 0.4), (x + w * 0.7, y + h * 0.2)]
        out.append(sketch(pts, 1.6, "#ffd0a8", 1, 2.5, opacity=0.35))
    # stars: little crosses and dots
    for k in range(70):
        x, y = rnd.uniform(20, W - 20), rnd.uniform(20, 520) ** 1.0
        if rnd.random() < 0.25:
            r = rnd.uniform(5, 10)
            out.append(sketch([(x - r, y), (x + r, y)], 2, "#fff3c4", 1, 0.6, overshoot=0))
            out.append(sketch([(x, y - r), (x, y + r)], 2, "#fff3c4", 1, 0.6, overshoot=0))
        else:
            out.append(f'<circle cx="{f(x)}" cy="{f(y)}" r="{f(rnd.uniform(1.2, 2.6))}" fill="#fff3c4" '
                       f'opacity="{rnd.uniform(0.5, 1):.2f}"/>')
    return "\n".join(out)


def sun():
    cx, cy, r = VX, 880, 330
    out = [f'<circle cx="{cx}" cy="{cy}" r="{r + 90}" fill="#ff5a7a" opacity="0.35" filter="url(#glow)"/>']
    out.append(f'<g mask="url(#sunbands)"><circle cx="{cx}" cy="{cy}" r="{r}" fill="url(#sung)" '
               f'filter="url(#wash)"/></g>')
    circ = [(cx + r * math.cos(a / 60 * 2 * math.pi), cy + r * math.sin(a / 60 * 2 * math.pi))
            for a in range(0, 61)]
    upper = [p for p in circ if p[1] < cy + 40]
    out.append(sketch(circ[30:] + circ[:1], 2.4, "#7a1a3a", 2, 2.5, opacity=0.6))
    # pencil shading on the lower bands
    cid = clip_of(circ)
    out.append(hatch(cid, cx - r, cy, cx + r, cy + r, -30, 13, "#c4245a", 1.4, 0.35))
    return "\n".join(out)


def ridge(y0, amp, seed, step=40):
    r = random.Random(seed)
    pts, x, y = [], -40, y0
    while x < W + 60:
        y = y0 - amp * abs(math.sin(x / r.uniform(120, 260))) * r.uniform(0.6, 1.0) - r.uniform(0, amp * 0.3)
        pts.append((x, y))
        x += r.uniform(step * 0.6, step * 1.4)
    return pts


def mountains():
    out = []
    for y0, amp, seed, col, hcol in ((HZ - 6, 150, 3, "#5a2a8a", "#2a1050"),
                                     (HZ + 2, 95, 9, "#33175e", "#140728")):
        top = ridge(y0, amp, seed)
        poly = top + [(W + 60, HZ + 8), (-40, HZ + 8)]
        out.append(fill(poly, col, 'filter="url(#wash)"'))
        cid = clip_of(poly)
        out.append(hatch(cid, -40, y0 - amp - 10, W + 60, HZ + 8, 62, 10, hcol, 1.5, 0.55))
        out.append(sketch(top, 2.6, INK, 2, 1.6))
        # snow-ish rim light on the peaks, from the sun
        rim = [p for p in top if p[1] < y0 - amp * 0.55]
        for p in rim[::2]:
            out.append(sketch([(p[0] - 14, p[1] + 10), p, (p[0] + 12, p[1] + 9)], 2.2, "#ff9ad0", 1, 1.0,
                              opacity=0.7))
    return "\n".join(out)


def depth_y(z):
    return HZ + 9000 / z


def ground():
    out = [f'<rect x="0" y="{HZ}" width="{W}" height="{H - HZ}" fill="url(#ground)"/>']
    # the grid: lines across at perspective depths, and lines from the vanishing point
    z = 9000 / (H - HZ) * 0.9
    zs = []
    zz = 9000 / 6
    while depth_y(zz) < H + 40:
        zs.append(zz)
        zz *= 0.78
    for zz in zs:
        y = depth_y(zz)
        out.append(sketch([(-20, y), (W + 20, y)], 1.4 + (y - HZ) / 300, "#ff4fe8", 1, 1.2,
                          opacity=min(0.85, 0.25 + (y - HZ) / 900), overshoot=0))
    for k in range(-22, 23):
        if abs(k) < 3:
            continue
        xb = VX + k * 120
        out.append(sketch([(VX + k * 2.2, HZ), (xb * 1.0 + (xb - VX) * 0.6, H + 40)], 1.6, "#ff4fe8", 1, 1.4,
                          opacity=0.55, overshoot=0))
    return "\n".join(out)


def road():
    out = []
    lt, rt = (VX - 14, HZ), (VX + 14, HZ)
    lb, rb = (-260, H + 40), (W + 260, H + 40)
    poly = [lt, rt, rb, lb]
    out.append(fill(poly, "url(#asphalt)", 'filter="url(#wash)"'))
    cid = clip_of(poly)
    out.append(hatch(cid, -260, HZ, W + 260, H, 4, 16, "#0c0716", 1.8, 0.45, 2))
    out.append(hatch(cid, -260, HZ + 300, W + 260, H, -70, 22, "#4a3a6a", 1.2, 0.3, 2))

    def edge(t, side):          # x of the road edge at screen y (t: 0 horizon .. 1 bottom)
        a, b = (lt, lb) if side < 0 else (rt, rb)
        return a[0] + (b[0] - a[0]) * t
    # kerbs and centre dashes at perspective steps
    zz, k = 9000 / 4, 0
    while True:
        y0 = depth_y(zz)
        zn = zz * 0.84
        y1 = depth_y(zn)
        if y0 > H + 40:
            break
        t0, t1 = (y0 - HZ) / (H + 40 - HZ), (min(y1, H + 40) - HZ) / (H + 40 - HZ)
        kw0, kw1 = 10 + 120 * t0, 10 + 120 * t1
        col = "#e8213a" if k % 2 else "#f4efe4"
        for side in (-1, 1):
            e0, e1 = edge(t0, side), edge(t1, side)
            q = [(e0, y0), (e0 + side * kw0, y0), (e1 + side * kw1, y1), (e1, y1)]
            out.append(fill(q, col, 'opacity="0.95"'))
            out.append(sketch(q, 1.3, INK, 1, 0.8, closed=True, opacity=0.6))
        if k % 2 == 0:
            dw0, dw1 = 2 + 22 * t0, 2 + 22 * t1
            q = [(VX - dw0, y0), (VX + dw0, y0), (VX + dw1, y1), (VX - dw1, y1)]
            out.append(fill(q, "#fdf6e0", 'opacity="0.9"'))
            out.append(sketch(q, 1.2, INK, 1, 0.8, closed=True, opacity=0.5))
        zz, k = zn, k + 1
    out.append(sketch([lt, lb], 3, INK, 2, 1.6))
    out.append(sketch([rt, rb], 3, INK, 2, 1.6))
    return "\n".join(out)


def palm(bx, by, tx, ty, s, lean):
    out = []
    col = "#150a24"
    # trunk: a tapering curve
    c1 = (bx + lean * 40 * s, by - (by - ty) * 0.35)
    c2 = (tx - lean * 30 * s, ty + (by - ty) * 0.3)
    spine = bez((bx, by), c1, c2, (tx, ty), 30)
    left, right = [], []
    for i, (x, y) in enumerate(spine):
        w = (26 - 16 * i / 30) * s
        x2, y2 = spine[min(i + 1, 30)]
        x1, y1 = spine[max(i - 1, 0)]
        dx, dy = x2 - x1, y2 - y1
        L = math.hypot(dx, dy) or 1
        nx, ny = -dy / L, dx / L
        left.append((x + nx * w, y + ny * w))
        right.append((x - nx * w, y - ny * w))
    poly = left + right[::-1]
    out.append(fill(poly, col))
    out.append(sketch(left, 2.4, INK, 1, 1.4))
    out.append(sketch(right, 2.4, INK, 1, 1.4))
    for i in range(2, 29, 2):                       # the trunk's rings
        x, y = spine[i]
        w = (26 - 16 * i / 30) * s
        out.append(sketch([(x - w, y + 3 * s), (x + w, y - 3 * s)], 1.6, "#5a2a6a", 1, 0.8, opacity=0.8,
                          overshoot=0))
    # sunlit rim on the trunk's sun side
    side = left if tx < VX else right
    out.append(sketch(side[8:], 2.0, "#ff6ad0", 1, 1.2, opacity=0.55))
    # fronds
    for k in range(9):
        a = math.radians(-180 + k * 22.5 + rnd.uniform(-8, 8))
        L = rnd.uniform(200, 280) * s
        droop = rnd.uniform(0.35, 0.6)
        end = (tx + math.cos(a) * L, ty + math.sin(a) * L * 0.55 + L * droop)
        mid = (tx + math.cos(a) * L * 0.55, ty + math.sin(a) * L * 0.55 - 30 * s)
        rib = bez((tx, ty), mid, mid, end, 18)
        leaf_l, leaf_r = [], []
        for i, (x, y) in enumerate(rib):
            w = 26 * s * math.sin(math.pi * i / 18) ** 0.8
            jag = w * (0.55 if i % 2 else 1.0)
            x2, y2 = rib[min(i + 1, 18)]
            x1, y1 = rib[max(i - 1, 0)]
            dx, dy = x2 - x1, y2 - y1
            Ln = math.hypot(dx, dy) or 1
            nx, ny = -dy / Ln, dx / Ln
            leaf_l.append((x + nx * jag, y + ny * jag))
            leaf_r.append((x - nx * jag * 0.7, y - ny * jag * 0.7))
        poly = leaf_l + leaf_r[::-1]
        out.append(fill(poly, col))
        out.append(sketch(rib, 1.8, "#4a2060", 1, 1.0, opacity=0.9))
        out.append(sketch(leaf_l, 1.8, INK, 1, 1.0))
    return "\n".join(out)


def car():
    out = []
    cx, gy = VX, 1790
    out.append(f'<ellipse cx="{cx}" cy="{gy + 8}" rx="420" ry="40" fill="#05020a" opacity="0.8" '
               f'filter="url(#soft)"/>')
    # tyres
    for x0 in (300, 862):
        q = [(x0, 1590), (x0 + 138, 1590), (x0 + 138, gy), (x0, gy)]
        out.append(fill(q, "#120c18"))
        cid = clip_of(q)
        out.append(hatch(cid, x0, 1590, x0 + 138, gy, 0, 12, "#3a3048", 2.2, 0.8, 1.2))
        out.append(sketch(q, 3, INK, 2, 1.4, closed=True))
    # lower body / rear panel
    panel = [(318, 1548), (982, 1548), (1006, 1700), (294, 1700)]
    out.append(fill(panel, "url(#carred)", 'filter="url(#wash)"'))
    cid = clip_of(panel)
    out.append(hatch(cid, 290, 1600, 1010, 1700, 20, 9, "#5a0610", 1.6, 0.6))
    # rear deck, catching the sunset
    deck = [(372, 1432), (928, 1432), (982, 1548), (318, 1548)]
    out.append(fill(deck, "url(#deck)", 'filter="url(#wash)"'))
    cid2 = clip_of(deck)
    out.append(hatch(cid2, 318, 1432, 982, 1548, -12, 14, "#ffcf8a", 1.4, 0.4))
    # tail-light bar
    bar = [(330, 1568), (970, 1568), (978, 1626), (322, 1626)]
    out.append(fill(bar, "#1a0c14"))
    for x0, x1 in ((338, 520), (780, 962)):
        lamp = [(x0, 1576), (x1, 1576), (x1 + 4, 1618), (x0 - 4, 1618)]
        out.append(f'<ellipse cx="{(x0 + x1) / 2}" cy="1597" rx="{(x1 - x0) / 2 + 40}" ry="46" '
                   f'fill="#ff2a3a" opacity="0.55" filter="url(#glow)"/>')
        out.append(fill(lamp, "url(#lamp)"))
        for xx in range(x0 + 14, x1, 22):            # louvres
            out.append(sketch([(xx, 1580), (xx + 2, 1614)], 1.6, "#7a0a14", 1, 0.5, overshoot=0))
        out.append(sketch(lamp, 2, INK, 1, 0.8, closed=True))
    out.append(sketch(bar, 2.6, INK, 2, 1.2, closed=True))
    # number plate: hand-lettered
    plate = [(570, 1636), (730, 1636), (730, 1688), (570, 1688)]
    out.append(fill(plate, "#f6efd8"))
    out.append(sketch(plate, 2.2, INK, 2, 0.8, closed=True))
    txt, _ = lettering("128K", 586, 1645, 0.24, 20, slant=0.0, grad="inkg", gap=118, outline=INK,
                       wob=0.6, stripes=False, shadow=False)
    out.append(txt)
    # exhausts
    for x in (430, 870):
        out.append(f'<ellipse cx="{x}" cy="1712" rx="34" ry="16" fill="#2a2430"/>')
        out.append(f'<ellipse cx="{x}" cy="1712" rx="20" ry="8" fill="#060308"/>')
        out.append(sketch([(x - 34 + 34 * math.cos(a / 12 * math.pi) + 34, 1712 + 16 * math.sin(a / 12 * math.pi))
                           for a in range(25)], 2, INK, 1, 0.6, overshoot=0))
    # smoke puffs
    for k in range(5):
        x = rnd.choice((400, 900)) + rnd.uniform(-60, 60)
        y = 1760 + rnd.uniform(-20, 40)
        r = rnd.uniform(30, 60)
        out.append(f'<circle cx="{f(x)}" cy="{f(y)}" r="{f(r)}" fill="#cbb8e0" opacity="0.18" filter="url(#soft)"/>')
    out.append(sketch(panel, 3.2, INK, 2, 1.6, closed=True))
    out.append(sketch(deck, 3.0, INK, 2, 1.6, closed=True))
    # highlight along the deck edge
    out.append(sketch([(380, 1440), (920, 1440)], 3, "#fff1cf", 1, 1.6, opacity=0.8))
    # windscreen frame behind the crew
    ws = [(430, 1434), (462, 1318), (838, 1318), (870, 1434)]
    out.append(sketch(ws, 4, "#2a2236", 2, 1.4))
    out.append(f'<path d="{path_d(ws, True)}" fill="#8fd8ff" opacity="0.12"/>')
    # mirrors
    for x, d in ((436, -1), (864, 1)):
        out.append(sketch([(x, 1416), (x + d * 14, 1410)], 3, INK, 1, 0.5, overshoot=0))
        x += d * 12
        m = [(x, 1396), (x + d * 50, 1388), (x + d * 54, 1416), (x + d * 4, 1422)]
        out.append(fill(m, "#c41824"))
        out.append(sketch(m, 2.2, INK, 1, 0.8, closed=True))
    # him: dark hair, striped shirt
    out.append(crew(560, 1360, "#2b1a12", "#f2f0e8", "#3050c8", False))
    # her: blonde hair streaming in the wind
    out.append(crew(745, 1362, "#ffd23a", "#ff6a9a", None, True))
    return "\n".join(out)


def crew(x, y, hair, shirt, stripe, long_hair):
    out = []
    # shoulders
    sh = [(x - 80, 1436), (x - 70, y + 48), (x + 70, y + 48), (x + 80, 1436)]
    out.append(fill(sh, shirt))
    if stripe:
        cid = clip_of(sh)
        out.append(hatch(cid, x - 80, y + 40, x + 80, 1436, 90, 16, stripe, 6, 0.85, 0.6))
    out.append(sketch(sh[:3] + [sh[3]], 2.4, INK, 1, 1.0))
    # neck and head (from behind: hair)
    out.append(fill([(x - 16, y + 50), (x - 14, y + 20), (x + 14, y + 20), (x + 16, y + 50)], "#e8a87a"))
    head = [(x + 52 * math.cos(a / 20 * math.pi), y + 58 * math.sin(a / 20 * math.pi)) for a in range(40)]
    if long_hair:
        # hair blown back and to the right: an irregular mass of locks
        mass = []
        for a in range(0, 40):
            t = a / 20 * math.pi
            r = 1.0 + 0.12 * math.sin(5 * t + 1) + rnd.uniform(-0.04, 0.06)
            mass.append((x + 54 * r * math.cos(t), y + 60 * r * math.sin(t)))
        tail = [(x + 50, y + 30), (x + 120, y + 58), (x + 175, y + 70), (x + 215, y + 42),
                (x + 180, y + 18), (x + 205, y - 6), (x + 140, y - 4), (x + 60, y - 30)]
        out.append(fill(mass, hair))
        out.append(fill(tail, hair))
        for k in range(26):                         # strands, on the head and streaming off it
            sy = y + rnd.uniform(-45, 45)
            sx = x + rnd.uniform(-40, 10)
            pts = bez((sx, sy), (sx + 60, sy - 25 + rnd.uniform(-10, 10)),
                      (sx + 130, sy + rnd.uniform(0, 35)), (sx + rnd.uniform(170, 240), sy + rnd.uniform(-15, 40)), 16)
            out.append(sketch(pts, rnd.uniform(1.2, 2.4), rnd.choice(("#b07a10", "#fff3a8", "#e0a020", "#c88a18")),
                              1, 1.0, opacity=0.9))
        out.append(sketch(mass[22:] + mass[:12], 2.4, INK, 1, 1.0, overshoot=0))
        out.append(sketch(tail[1:6], 2.0, INK, 1, 1.0))
        return "\n".join(out)
    else:
        out.append(fill(head, hair))
        for k in range(10):
            a = rnd.uniform(-math.pi, 0)
            out.append(sketch([(x + 40 * math.cos(a), y + 46 * math.sin(a)),
                               (x + 48 * math.cos(a + 0.4), y + 56 * math.sin(a + 0.4))],
                              1.6, "#6a4a30", 1, 0.6, opacity=0.8, overshoot=0))
    out.append(sketch(head + head[:1], 2.4, INK, 2, 1.0, overshoot=0))
    return "\n".join(out)


def speed_lines():
    out = []
    for k in range(26):
        side = rnd.choice((-1, 1))
        y = rnd.uniform(1200, 1950)
        x0 = VX + side * rnd.uniform(520, 640) * (y - HZ) / (H - HZ) + side * rnd.uniform(0, 80)
        L = rnd.uniform(80, 220)
        dx = (x0 - VX) / max(1, y - HZ) * L
        out.append(sketch([(x0, y), (x0 + dx, y + L)], rnd.uniform(1.4, 3), "#fff6e0", 1, 0.8,
                          opacity=rnd.uniform(0.35, 0.7)))
    return "\n".join(out)


def title_and_tag():
    out = []
    txt, end = lettering("SPEED", 120, 90, 1.12, 30, slant=0.3)
    out.append(txt)
    txt2, end2 = lettering("RUN", 470, 290, 1.12, 30, slant=0.3)
    out.append(txt2)
    # swoosh under the title
    sw = bez((90, 480), (500, 430), (900, 470), (1220, 400), 30)
    out.append(sketch(sw, 9, "#ffd23a", 1, 1.4, opacity=0.9))
    out.append(sketch([(x, y + 14) for x, y in sw], 4, "#ff3d7f", 1, 1.4, opacity=0.9))
    # bottom tag
    tag, _ = lettering("FOR THE ZX SPECTRUM 128K", 118, 1880, 0.3, 16, slant=0.2, grad="tagg", gap=118,
                       wob=0.9, stripes=False)
    out.append(tag)
    return "\n".join(out)


def defs():
    stripes = "".join(f'<rect x="0" y="{y}" width="{W}" height="{h}" fill="black"/>'
                      for y, h in ((210, 5), (230, 7), (252, 9), (400, 5), (420, 7), (442, 9)))
    bands = "".join(f'<rect x="0" y="{730 + k * 40 + k * k * 2}" width="{W}" height="{5 + k * 4}" fill="black"/>'
                    for k in range(8))
    return f"""
<defs>
  <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#140834"/><stop offset="0.42" stop-color="#4a1670"/>
    <stop offset="0.72" stop-color="#b8246e"/><stop offset="0.9" stop-color="#ff6a4a"/>
    <stop offset="1" stop-color="#ffb05a"/>
  </linearGradient>
  <linearGradient id="ground" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#3a1458"/><stop offset="1" stop-color="#0c0618"/>
  </linearGradient>
  <linearGradient id="asphalt" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#4a3060"/><stop offset="1" stop-color="#1c1428"/>
  </linearGradient>
  <linearGradient id="sung" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#fff27a"/><stop offset="0.45" stop-color="#ffc23a"/>
    <stop offset="0.75" stop-color="#ff7a2a"/><stop offset="1" stop-color="#ff2f6a"/>
  </linearGradient>
  <linearGradient id="carred" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#ff3a3a"/><stop offset="1" stop-color="#9a0c1a"/>
  </linearGradient>
  <linearGradient id="deck" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#ff8a5a"/><stop offset="1" stop-color="#e3242b"/>
  </linearGradient>
  <linearGradient id="lamp" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#ffb0a0"/><stop offset="0.5" stop-color="#ff2a3a"/><stop offset="1" stop-color="#a0081a"/>
  </linearGradient>
  <linearGradient id="logo" gradientUnits="userSpaceOnUse" x1="0" y1="90" x2="0" y2="460">
    <stop offset="0" stop-color="#fff58a"/><stop offset="0.3" stop-color="#ffd23a"/>
    <stop offset="0.55" stop-color="#ff8a2a"/><stop offset="0.8" stop-color="#ff3a4a"/>
    <stop offset="1" stop-color="#d0105a"/>
  </linearGradient>
  <linearGradient id="tagg" gradientUnits="userSpaceOnUse" x1="0" y1="1880" x2="0" y2="1930">
    <stop offset="0" stop-color="#9ff4ff"/><stop offset="1" stop-color="#3ac0ff"/>
  </linearGradient>
  <linearGradient id="inkg"><stop offset="0" stop-color="{INK}"/><stop offset="1" stop-color="{INK}"/></linearGradient>
  <mask id="stripes"><rect x="0" y="0" width="{W}" height="{H}" fill="white"/>{stripes}</mask>
  <mask id="sunbands"><rect x="0" y="0" width="{W}" height="{H}" fill="white"/>{bands}</mask>
  <filter id="wash" x="-10%" y="-10%" width="120%" height="120%">
    <feTurbulence type="fractalNoise" baseFrequency="0.018" numOctaves="3" seed="7" result="n"/>
    <feDisplacementMap in="SourceGraphic" in2="n" scale="9" xChannelSelector="R" yChannelSelector="G"/>
  </filter>
  <filter id="soft"><feGaussianBlur stdDeviation="14"/></filter>
  <filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="40"/></filter>
  <filter id="rough" x="-5%" y="-5%" width="110%" height="110%">
    <feTurbulence type="fractalNoise" baseFrequency="0.04" numOctaves="2" seed="3" result="n"/>
    <feDisplacementMap in="SourceGraphic" in2="n" scale="3.5" xChannelSelector="R" yChannelSelector="G"/>
  </filter>
  <filter id="paper" x="0" y="0" width="100%" height="100%">
    <feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves="2" seed="11" result="g"/>
    <feColorMatrix in="g" type="matrix" values="0 0 0 0 0.5  0 0 0 0 0.45  0 0 0 0 0.4  0 0 0 -1.6 1.1"/>
  </filter>
  <filter id="blotch" x="0" y="0" width="100%" height="100%">
    <feTurbulence type="fractalNoise" baseFrequency="0.006" numOctaves="3" seed="21" result="b"/>
    <feColorMatrix in="b" type="matrix" values="0 0 0 0 1  0 0 0 0 0.85  0 0 0 0 0.7  0 0 0 1.2 -0.45"/>
  </filter>
  <radialGradient id="vignette" cx="0.5" cy="0.5" r="0.75">
    <stop offset="0.6" stop-color="black" stop-opacity="0"/><stop offset="1" stop-color="black" stop-opacity="0.55"/>
  </radialGradient>
  {"".join(clips)}
</defs>"""


def build():
    body = "\n".join([
        f'<g filter="url(#rough)">{sky()}</g>',
        sun(),
        f'<g filter="url(#rough)">{mountains()}</g>',
        f'<g filter="url(#rough)">{ground()}</g>',
        f'<g filter="url(#rough)">{road()}</g>',
        f'<g filter="url(#rough)">{palm(900, 1086, 880, 890, 0.36, 1)}{palm(400, 1086, 420, 880, 0.34, -1)}</g>',
        f'<g filter="url(#rough)">{palm(1230, 1420, 1010, 610, 1.0, -1)}{palm(70, 1400, 290, 640, 1.0, 1)}</g>',
        f'<g filter="url(#rough)">{speed_lines()}</g>',
        f'<g filter="url(#rough)">{car()}</g>',
        f'<g filter="url(#rough)">{title_and_tag()}</g>',
        f'<rect width="{W}" height="{H}" filter="url(#blotch)" style="mix-blend-mode:soft-light" opacity="0.55"/>',
        f'<rect width="{W}" height="{H}" filter="url(#paper)" style="mix-blend-mode:multiply" opacity="0.35"/>',
        f'<rect width="{W}" height="{H}" fill="url(#vignette)"/>',
    ])
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">'
            f'<rect width="{W}" height="{H}" fill="#140834"/>{defs()}{body}</svg>')


def render(svg_path, png_path):
    js = f"""
const {{ chromium }} = require('playwright');
(async () => {{
  const b = await chromium.launch();
  const p = await b.newPage({{ viewport: {{ width: {W}, height: {H} }}, deviceScaleFactor: 1 }});
  await p.goto('file://{os.path.abspath(svg_path)}');
  await p.screenshot({{ path: '{os.path.abspath(png_path)}' }});
  await b.close();
}})();
"""
    with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False) as fjs:
        fjs.write(js)
    subprocess.run(["node", fjs.name], check=True)
    os.unlink(fjs.name)


def main(png, svg=None):
    svg = svg or os.path.splitext(png)[0] + ".svg"
    open(svg, "w").write(build())
    render(svg, png)


if __name__ == "__main__":
    main(*sys.argv[1:])
