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


# ---------------------------------------------------------------- the car, drawn "properly"
def smooth_d(pts, closed=True):
    """A smooth closed path through points (Catmull-Rom as cubic Beziers)."""
    n = len(pts)
    d = f"M{f(pts[0][0])},{f(pts[0][1])}"
    rng = range(n) if closed else range(n - 1)
    for i in rng:
        p0 = pts[(i - 1) % n] if closed or i > 0 else pts[i]
        p1, p2 = pts[i], pts[(i + 1) % n]
        p3 = pts[(i + 2) % n] if closed or i + 2 < n else p2
        c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
        d += f" C{f(c1[0])},{f(c1[1])} {f(c2[0])},{f(c2[1])} {f(p2[0])},{f(p2[1])}"
    return d + (" Z" if closed else "")


def mirror_d(d, cx=650):
    """A path string mirrored about x = cx (absolute M / L / C / Q / Z only)."""
    out, toks = [], d.replace(",", " ").split()
    i = 0
    while i < len(toks):
        t = toks[i]
        if t[0] in "MLCQZ" and not t[1:]:
            out.append(t)
            i += 1
            continue
        if t[0] in "MLCQ":
            out.append(t[0])
            toks[i] = t[1:]
            continue
        x, y = float(toks[i]), float(toks[i + 1])
        out.append(f"{f(2 * cx - x)},{f(y)}")
        i += 2
    return " ".join(out)


def lock(p0, p1, p2, p3, w0, colour, n=20):
    """A tapering lock of hair along a Bezier spine."""
    spine = bez(p0, p1, p2, p3, n)
    left, right = [], []
    for i, (x, y) in enumerate(spine):
        w = w0 * (1 - i / n) ** 0.9 + 0.6
        x2, y2 = spine[min(i + 1, n)]
        x1, y1 = spine[max(i - 1, 0)]
        dx, dy = x2 - x1, y2 - y1
        L = math.hypot(dx, dy) or 1
        nx, ny = -dy / L, dx / L
        left.append((x + nx * w, y + ny * w))
        right.append((x - nx * w, y - ny * w))
    return f'<path d="{smooth_d(left + right[::-1])}" fill="{colour}"/>', spine


def detailed_defs():
    return """
  <linearGradient id="cbody" x1="0" y1="1438" x2="0" y2="1716" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="#ff5a3c"/><stop offset="0.12" stop-color="#f02a2a"/>
    <stop offset="0.5" stop-color="#d41420"/><stop offset="1" stop-color="#7a0610"/>
  </linearGradient>
  <linearGradient id="cside" x1="296" y1="0" x2="1004" y2="0" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="#2a0010" stop-opacity="0.75"/><stop offset="0.16" stop-color="#2a0010" stop-opacity="0"/>
    <stop offset="0.84" stop-color="#2a0010" stop-opacity="0"/><stop offset="1" stop-color="#2a0010" stop-opacity="0.75"/>
  </linearGradient>
  <linearGradient id="cdeck" x1="0" y1="1438" x2="0" y2="1522" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="#ffb07a"/><stop offset="0.35" stop-color="#ff6a50"/><stop offset="1" stop-color="#e3242b"/>
  </linearGradient>
  <linearGradient id="clens" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#ff8a8a"/><stop offset="0.35" stop-color="#ff2030"/>
    <stop offset="0.75" stop-color="#c00818"/><stop offset="1" stop-color="#6a0410"/>
  </linearGradient>
  <linearGradient id="camber" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#ffd08a"/><stop offset="0.5" stop-color="#ff9a1a"/><stop offset="1" stop-color="#a04a00"/>
  </linearGradient>
  <linearGradient id="crev" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#ffffff"/><stop offset="0.6" stop-color="#d8dce8"/><stop offset="1" stop-color="#8a8ea0"/>
  </linearGradient>
  <linearGradient id="cchrome" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#ffffff"/><stop offset="0.45" stop-color="#b8bcc8"/>
    <stop offset="0.55" stop-color="#5a5e6a"/><stop offset="1" stop-color="#d8dce4"/>
  </linearGradient>
  <linearGradient id="ctyre" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0" stop-color="#2c2a34"/><stop offset="0.3" stop-color="#16141c"/><stop offset="1" stop-color="#060509"/>
  </linearGradient>
  <linearGradient id="cleather" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#5a2a26"/><stop offset="0.5" stop-color="#3a1614"/><stop offset="1" stop-color="#1e0a0a"/>
  </linearGradient>
  <linearGradient id="cglass" x1="0" y1="1320" x2="0" y2="1440" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="#ffd0a0" stop-opacity="0.35"/><stop offset="1" stop-color="#8fd8ff" stop-opacity="0.12"/>
  </linearGradient>
  <radialGradient id="hdark" cx="0.38" cy="0.3" r="0.8">
    <stop offset="0" stop-color="#6a4630"/><stop offset="0.45" stop-color="#3a2216"/><stop offset="1" stop-color="#160a06"/>
  </radialGradient>
  <radialGradient id="hblonde" cx="0.4" cy="0.3" r="0.85">
    <stop offset="0" stop-color="#fff6c0"/><stop offset="0.4" stop-color="#ffd650"/><stop offset="1" stop-color="#b8801a"/>
  </radialGradient>
  <linearGradient id="hlock" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0" stop-color="#e8b030"/><stop offset="0.5" stop-color="#ffd860"/><stop offset="1" stop-color="#fff0a8"/>
  </linearGradient>
  <linearGradient id="hlock2" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0" stop-color="#a06a10"/><stop offset="1" stop-color="#e0a830"/>
  </linearGradient>
  <linearGradient id="cskin" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0" stop-color="#c87a52"/><stop offset="0.5" stop-color="#f0b088"/><stop offset="1" stop-color="#b86a44"/>
  </linearGradient>
  <linearGradient id="cshade" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity="0.35"/>
  </linearGradient>
  <linearGradient id="cpink" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#ff8ab4"/><stop offset="1" stop-color="#d23a78"/>
  </linearGradient>
  <linearGradient id="hmass" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#ffe88a"/><stop offset="0.5" stop-color="#f0c040"/><stop offset="1" stop-color="#b8821c"/>
  </linearGradient>
  <linearGradient id="hshadow" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0.45" stop-color="#6a4208" stop-opacity="0"/><stop offset="1" stop-color="#6a4208" stop-opacity="0.45"/>
  </linearGradient>
  <linearGradient id="hlockv" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#ffeaa0"/><stop offset="0.45" stop-color="#f2c444"/><stop offset="1" stop-color="#b07a18"/>
  </linearGradient>
  <filter id="hsheen" filterUnits="userSpaceOnUse" x="0" y="0" width="1300" height="2000"><feGaussianBlur stdDeviation="3"/></filter>
  <pattern id="cstripe" width="16" height="40" patternUnits="userSpaceOnUse">
    <rect width="16" height="40" fill="#f4f2ec"/><rect x="5" width="5" height="40" fill="#2f55c8"/>
  </pattern>
  <filter id="cblur" filterUnits="userSpaceOnUse" x="0" y="0" width="1300" height="2000"><feGaussianBlur stdDeviation="6"/></filter>
"""


def car_detailed():
    o = []
    cx = 650
    # shadow on the road
    o.append(f'<ellipse cx="{cx}" cy="1796" rx="430" ry="34" fill="#030106" opacity="0.85" filter="url(#soft)"/>')
    # ---- the windscreen, then the crew in front of it (and behind their seats)
    ws = "M436,1440 L466,1322 Q468,1314 476,1314 L824,1314 Q832,1314 834,1322 L864,1440 Z"
    o.append(f'<path d="{ws}" fill="url(#cglass)"/>')
    o.append(f'<path d="{ws}" fill="none" stroke="#1a1420" stroke-width="7" stroke-linejoin="round"/>')
    o.append('<path d="M470,1318 L830,1318" stroke="#8a90a0" stroke-width="2" opacity="0.7"/>')
    # (the crew sit nearer to us than the windscreen)
    # him: dark hair, striped shirt
    o.append(person_him(560, 1316))
    # her: blonde, pink top, hair blown back
    o.append(person_her(742, 1318))
    # seats and headrests (in front of the crew, from here)
    for x in (560, 742):
        o.append(f'<path d="M{x - 82},1446 L{x - 80},1416 Q{x - 78},1398 {x - 58},1396 L{x + 58},1396 '
                 f'Q{x + 78},1398 {x + 80},1416 L{x + 82},1446 Z" fill="url(#cleather)" stroke="{INK}" stroke-width="2.5"/>')
        o.append(f'<path d="M{x - 66},1446 L{x - 64},1414 Q{x - 62},1406 {x - 48},1405 L{x + 48},1405 '
                 f'Q{x + 62},1406 {x + 64},1414 L{x + 66},1446" fill="none" stroke="#a0624a" stroke-width="1.6" '
                 f'stroke-dasharray="5 4" opacity="0.8"/>')
        for sx in (x - 24, x + 24):
            o.append(f'<rect x="{sx - 4}" y="1384" width="8" height="14" fill="url(#cchrome)"/>')
        o.append(f'<rect x="{x - 56}" y="1342" width="112" height="46" rx="20" fill="url(#cleather)" '
                 f'stroke="{INK}" stroke-width="2.5"/>')
        o.append(f'<rect x="{x - 46}" y="1349" width="92" height="32" rx="14" fill="none" stroke="#a0624a" '
                 f'stroke-width="1.4" stroke-dasharray="5 4" opacity="0.8"/>')
        o.append(f'<path d="M{x - 40},1348 Q{x},1342 {x + 40},1348" stroke="#c08a70" stroke-width="3" '
                 f'fill="none" opacity="0.6" stroke-linecap="round"/>')
    # her hair over her headrest, streaming back
    o.append(her_hair_front(742, 1318))
    # door mirrors
    for side in (-1, 1):
        x = cx + side * 214
        o.append(f'<path d="M{x},1430 L{x + side * 14},1412" stroke="#1a1420" stroke-width="6" stroke-linecap="round"/>')
        mx = x + side * 14
        o.append(f'<path d="M{mx},1414 Q{mx + side * 4},1392 {mx + side * 30},1390 L{mx + side * 56},1392 '
                 f'Q{mx + side * 66},1396 {mx + side * 64},1410 Q{mx + side * 60},1424 {mx + side * 44},1424 '
                 f'L{mx + side * 10},1424 Q{mx},1422 {mx},1414 Z" fill="url(#cbody)" stroke="{INK}" stroke-width="2.5"/>')
        o.append(f'<path d="M{mx + side * 10},1398 L{mx + side * 54},1398" stroke="#ffb08a" stroke-width="3" '
                 f'stroke-linecap="round" opacity="0.8"/>')
    # ---- tyres
    for x0 in (300, 862):
        o.append(f'<rect x="{x0}" y="1596" width="138" height="198" rx="26" fill="url(#ctyre)" '
                 f'stroke="{INK}" stroke-width="3"/>')
        for y in range(1640, 1790, 16):
            o.append(f'<path d="M{x0 + 10},{y} L{x0 + 128},{y}" stroke="#040306" stroke-width="5"/>')
            o.append(f'<path d="M{x0 + 12},{y + 3} L{x0 + 126},{y + 3}" stroke="#3a3844" stroke-width="1.2" opacity="0.6"/>')
    # ---- body
    body = ("M330,1714 C305,1702 296,1652 296,1600 C296,1540 312,1482 352,1452 C364,1444 376,1440 392,1438 "
            "L908,1438 C924,1440 936,1444 948,1452 C988,1482 1004,1540 1004,1600 C1004,1652 995,1702 970,1714 Z")
    o.append(f'<path d="{body}" fill="url(#cbody)"/>')
    o.append(f'<path d="{body}" fill="url(#cside)"/>')
    # rear deck (seen from a little above), with the sunset in it
    deck = "M392,1438 L908,1438 C938,1442 958,1470 966,1522 L334,1522 C342,1470 362,1442 392,1438 Z"
    o.append(f'<path d="{deck}" fill="url(#cdeck)"/>')
    o.append(f'<path d="{deck}" fill="url(#cside)" opacity="0.6"/>')
    o.append('<path d="M446,1452 L854,1452 Q874,1453 878,1468 L886,1510 L414,1510 L422,1468 Q426,1453 446,1452 Z" '
             'fill="none" stroke="#8a1018" stroke-width="2" opacity="0.75"/>')
    o.append('<path d="M450,1456 L850,1456" stroke="#fff0d0" stroke-width="2" opacity="0.6"/>')
    # the crease to the rear panel: light above, shadow below
    o.append('<path d="M336,1522 L964,1522" stroke="#ffd0a8" stroke-width="3" opacity="0.85"/>')
    o.append('<rect x="330" y="1524" width="640" height="16" fill="url(#cshade)" transform="rotate(180 650 1532)"/>')
    # rim light along the shoulders
    rim = "M298,1596 C298,1536 316,1480 354,1452 C366,1444 378,1440 394,1438"
    o.append(f'<path d="{rim}" fill="none" stroke="#ffb890" stroke-width="5" stroke-linecap="round" opacity="0.85"/>')
    o.append(f'<path d="{mirror_d(rim)}" fill="none" stroke="#ffb890" stroke-width="5" stroke-linecap="round" opacity="0.85"/>')
    # the magenta grid's glow along the lower sides
    o.append('<path d="M300,1640 C302,1680 312,1700 330,1712" stroke="#ff5ae8" stroke-width="4" fill="none" opacity="0.55"/>')
    o.append('<path d="M1000,1640 C998,1680 988,1700 970,1712" stroke="#ff5ae8" stroke-width="4" fill="none" opacity="0.55"/>')
    # ---- the tail-light band
    o.append('<rect x="322" y="1548" width="656" height="58" rx="12" fill="#140608" stroke="#1a0a10" stroke-width="3"/>')
    for x0, x1, amber_left in ((336, 568, True), (732, 964, False)):
        o.append(f'<ellipse cx="{(x0 + x1) / 2}" cy="1577" rx="{(x1 - x0) / 2 + 30}" ry="40" fill="#ff1a2a" '
                 f'opacity="0.45" filter="url(#glow)"/>')
        o.append(f'<rect x="{x0}" y="1556" width="{x1 - x0}" height="42" rx="8" fill="url(#clens)"/>')
        ax = x0 if amber_left else x1 - 50
        o.append(f'<rect x="{ax}" y="1556" width="50" height="42" rx="8" fill="url(#camber)"/>')
        rx = x1 - 40 if amber_left else x0
        o.append(f'<rect x="{rx}" y="1556" width="40" height="42" rx="8" fill="url(#crev)"/>')
        for y in range(1562, 1596, 7):
            o.append(f'<path d="M{x0 + 4},{y} L{x1 - 4},{y}" stroke="#ffffff" stroke-width="1" opacity="0.18"/>')
        o.append(f'<path d="M{x0 + 8},1560 L{x1 - 8},1560" stroke="#ffffff" stroke-width="2.5" opacity="0.55" '
                 f'stroke-linecap="round"/>')
        o.append(f'<rect x="{x0}" y="1556" width="{x1 - x0}" height="42" rx="8" fill="none" stroke="#0a0204" '
                 f'stroke-width="2.5"/>')
    o.append('<text x="650" y="1583" text-anchor="middle" font-family="DejaVu Sans" font-weight="bold" '
             'font-style="italic" font-size="17" letter-spacing="3" fill="url(#cchrome)">SPEED RUN</text>')
    # ---- number plate and its recess
    o.append('<rect x="566" y="1612" width="168" height="62" rx="6" fill="#4a0810" opacity="0.7"/>')
    o.append('<rect x="574" y="1618" width="152" height="50" rx="4" fill="#f6f2e2" stroke="#222" stroke-width="2"/>')
    o.append('<text x="650" y="1656" text-anchor="middle" font-family="DejaVu Sans Mono" font-weight="bold" '
             'font-size="38" fill="#141414">128K</text>')
    o.append('<path d="M578,1622 L722,1622" stroke="#ffffff" stroke-width="2" opacity="0.8"/>')
    # ---- lower valance, diffuser and the exhausts
    o.append('<path d="M372,1688 L928,1688 L950,1716 L350,1716 Z" fill="#100a12" stroke="#05030a" stroke-width="2"/>')
    for x in range(420, 900, 40):
        o.append(f'<path d="M{x},1690 L{x - (x - 650) * 0.06},1714" stroke="#2a2430" stroke-width="3"/>')
    for x in (456, 844):
        o.append(f'<ellipse cx="{x}" cy="1706" rx="34" ry="17" fill="url(#cchrome)" stroke="#111" stroke-width="2"/>')
        o.append(f'<ellipse cx="{x}" cy="1707" rx="23" ry="10" fill="#050305"/>')
        o.append(f'<path d="M{x - 26},1700 Q{x},1690 {x + 26},1700" stroke="#fff" stroke-width="2" fill="none" opacity="0.8"/>')
    # a soft highlight on the bodywork's flanks
    o.append('<path d="M318,1610 C316,1570 324,1530 340,1508" stroke="#ff8a7a" stroke-width="10" fill="none" '
             'opacity="0.35" stroke-linecap="round" filter="url(#cblur)"/>')
    o.append('<path d="M982,1610 C984,1570 976,1530 960,1508" stroke="#ff8a7a" stroke-width="10" fill="none" '
             'opacity="0.35" stroke-linecap="round" filter="url(#cblur)"/>')
    # a clean ink outline to sit with the drawing around it
    o.append(f'<path d="{body}" fill="none" stroke="{INK}" stroke-width="3.5" stroke-linejoin="round"/>')
    o.append(f'<path d="{deck}" fill="none" stroke="{INK}" stroke-width="2" opacity="0.8"/>')
    return "\n".join(o)


def head_shape(x, y, rx=48, ry=56):
    return (f"M{x},{y - ry} C{x + rx * 0.62},{y - ry} {x + rx},{y - ry * 0.55} {x + rx},{y} "
            f"C{x + rx},{y + ry * 0.62} {x + rx * 0.55},{y + ry} {x},{y + ry} "
            f"C{x - rx * 0.55},{y + ry} {x - rx},{y + ry * 0.62} {x - rx},{y} "
            f"C{x - rx},{y - ry * 0.55} {x - rx * 0.62},{y - ry} {x},{y - ry} Z")


def person_him(x, y):
    o = []
    # shoulders and back in a striped shirt
    sh = f"M{x - 92},1446 C{x - 90},1404 {x - 66},1384 {x - 30},1380 L{x + 30},1380 C{x + 66},1384 {x + 90},1404 {x + 92},1446 Z"
    o.append(f'<path d="{sh}" fill="url(#cstripe)" stroke="{INK}" stroke-width="2.5"/>')
    o.append(f'<path d="{sh}" fill="url(#cshade)"/>')
    # neck and ears
    o.append(f'<path d="M{x - 18},1384 L{x - 16},{y + 30} L{x + 16},{y + 30} L{x + 18},1384 Z" fill="url(#cskin)"/>')
    for s in (-1, 1):
        o.append(f'<ellipse cx="{x + s * 47}" cy="{y + 6}" rx="9" ry="17" fill="#e8a07a" stroke="#8a4a30" stroke-width="1.6"/>')
    # short dark hair
    o.append(f'<path d="{head_shape(x, y)}" fill="url(#hdark)" stroke="{INK}" stroke-width="2.5"/>')
    for k in range(16):
        a = -math.pi * (0.1 + 0.8 * k / 15)
        x0, y0 = x + 8 * math.cos(a), y - 46 + 8 * math.sin(a)
        x1, y1 = x + 46 * math.cos(a * 0.9 + 0.15), y + 10 + 52 * math.sin(-a * 0.5) * 0.9
        c = "#7a5238" if k % 3 == 0 else "#120804"
        o.append(f'<path d="M{f(x0)},{f(y0)} Q{f((x0 + x1) / 2 + 6)},{f((y0 + y1) / 2 - 4)} {f(x1)},{f(y1)}" '
                 f'stroke="{c}" stroke-width="1.6" fill="none" opacity="0.7" stroke-linecap="round"/>')
    o.append(f'<path d="M{x - 30},{y - 40} Q{x - 10},{y - 54} {x + 14},{y - 50}" stroke="#a07a5a" stroke-width="4" '
             f'fill="none" opacity="0.6" stroke-linecap="round"/>')
    return "\n".join(o)


def person_her(x, y):
    o = []
    sh = f"M{x - 88},1446 C{x - 86},1406 {x - 62},1388 {x - 28},1384 L{x + 28},1384 C{x + 62},1388 {x + 86},1406 {x + 88},1446 Z"
    o.append(f'<path d="{sh}" fill="url(#cpink)" stroke="{INK}" stroke-width="2.5"/>')
    o.append(f'<path d="{sh}" fill="url(#cshade)"/>')
    o.append(f'<path d="M{x - 16},1388 L{x - 14},{y + 30} L{x + 14},{y + 30} L{x + 16},1388 Z" fill="url(#cskin)"/>')
    # her hair, from behind (the locks over the headrest come later)
    o.append(her_hair_back(x, y))
    return "\n".join(o)


def ribbon(p0, p1, p2, p3, w0, n=28, full=0.55):
    """A lock of hair: full width for most of its length, tapering to a soft tip."""
    spine = bez(p0, p1, p2, p3, n)
    left, right = [], []
    for i, (x, y) in enumerate(spine):
        t = i / n
        w = w0 * (0.1 + 0.9 * math.sin(min(1, t / 0.3) * math.pi / 2)) * (min(1, (1 - t) / (1 - full)) ** 0.85) + 0.4
        x2, y2 = spine[min(i + 1, n)]
        x1, y1 = spine[max(i - 1, 0)]
        dx, dy = x2 - x1, y2 - y1
        L = math.hypot(dx, dy) or 1
        nx, ny = -dy / L, dx / L
        left.append((x + nx * w, y + ny * w))
        right.append((x - nx * w, y - ny * w))
    return left + right[::-1], spine, left, right


def strands_along(spine, w, colours, count, r, width=1.3, start=0.0, end=0.92):
    """Fine strands following a lock's flow, spread across its width."""
    o = []
    n = len(spine) - 1
    for k in range(count):
        off = r.uniform(-0.8, 0.8) * w
        a, b = int(n * (start + r.uniform(0, 0.15))), int(n * (end - r.uniform(0, 0.25)))
        pts = []
        for i in range(a, b + 1):
            x, y = spine[i]
            x2, y2 = spine[min(i + 1, n)]
            x1, y1 = spine[max(i - 1, 0)]
            dx, dy = x2 - x1, y2 - y1
            L = math.hypot(dx, dy) or 1
            taper = min(1, (1 - i / n) / 0.45)
            pts.append((x - dy / L * off * taper, y + dx / L * off * taper))
        if len(pts) > 2:
            o.append(f'<path d="{smooth_d(pts, False)}" stroke="{r.choice(colours)}" stroke-width="{f(width * r.uniform(0.6, 1.3))}" '
                     f'fill="none" opacity="{r.uniform(0.55, 0.9):.2f}" stroke-linecap="round"/>')
    return "\n".join(o)


def her_hair_back(x, y):
    """Her hair from behind: round over the skull, falling behind the headrest
    and swept a little right by the wind; strands follow the head's curve."""
    r = random.Random(31)
    o = []
    sil = [(x, y - 62), (x + 28, y - 57), (x + 48, y - 40), (x + 58, y - 12), (x + 64, y + 24),
           (x + 78, y + 54), (x + 94, y + 78), (x + 72, y + 92), (x, y + 94), (x - 58, y + 90),
           (x - 62, y + 48), (x - 58, y + 6), (x - 50, y - 34), (x - 30, y - 56)]
    d = smooth_d(sil)
    o.append(f'<path d="{d}" fill="url(#hmass)"/>')
    clip = clip_of_d(d)
    strokes = []
    for k in range(70):
        phi = math.radians(r.uniform(-168, -12))       # where on the crown it starts
        rad = r.uniform(0.78, 1.0)
        sx, sy = x + 52 * rad * math.cos(phi), y - 2 + 58 * rad * math.sin(phi)
        side = math.cos(phi)                          # -1 left .. 1 right
        ex = x + 62 * side + 8 + 14 * max(0, side) + r.uniform(-5, 5)
        ey = y + r.uniform(70, 95)
        c1 = (sx + side * 22, sy + 30)               # round the skull ...
        c2 = (ex - side * 4, ey - 45)                # ... then falling
        col = r.choice(("#fff4c0", "#ffe080", "#ffe080", "#e8b440", "#c8901e", "#a87010"))
        pts = bez((sx, sy), c1, c2, (ex, ey), 20)
        strokes.append(f'<path d="{smooth_d(pts, False)}" stroke="{col}" stroke-width="{f(r.uniform(1.0, 2.4))}" '
                       f'fill="none" opacity="{r.uniform(0.45, 0.85):.2f}" stroke-linecap="round"/>')
    o.append(f'<g clip-path="url(#{clip})">' + "".join(strokes))
    # a soft band of shine across the crown, shadow lower down
    o.append(f'<path d="M{x - 50},{y - 22} Q{x},{y - 44} {x + 50},{y - 22}" stroke="#fff6d0" stroke-width="12" '
             f'fill="none" opacity="0.35" filter="url(#hsheen)"/>')
    o.append(f'<path d="{d}" fill="url(#hshadow)"/></g>')
    rim = sil[12:] + sil[:4]
    o.append(f'<path d="{smooth_d(rim, False)}" stroke="#fff3c8" stroke-width="3" fill="none" opacity="0.8" '
             f'stroke-linecap="round"/>')
    o.append(f'<path d="{d}" fill="none" stroke="#7a5212" stroke-width="2"/>')
    return "\n".join(o)


def clip_of_d(d):
    cid = f"c{len(clips)}"
    clips.append(f'<clipPath id="{cid}"><path d="{d}"/></clipPath>')
    return cid


def her_hair_front(x, y):
    """Locks blown back over the top of her headrest and down onto her shoulder,
    and a few loose wisps - all inside the cockpit."""
    r = random.Random(47)
    o = []
    locks = [  # spine control points (relative), half-width
        (((20, 14), (46, 6), (66, 30), (70, 78)), 13),
        (((34, 18), (60, 14), (78, 46), (80, 104)), 14),
        (((10, 20), (40, 18), (56, 50), (56, 96)), 11),
        (((48, 16), (74, 22), (90, 60), (86, 112)), 10),
    ]
    for (pts, w) in locks:
        P = [(x + px, y + py) for px, py in pts]
        poly, spine, left, right = ribbon(*P, w)
        o.append(f'<path d="{smooth_d(poly)}" fill="url(#hlockv)"/>')
        o.append(strands_along(spine, w, ("#fff4c0", "#ffe080", "#d8a030", "#b07a18"), 9, r))
        o.append(f'<path d="{smooth_d(right[2:], False)}" stroke="#7a5212" stroke-width="1.8" fill="none" opacity="0.8"/>')
        o.append(f'<path d="{smooth_d(left[2:-3], False)}" stroke="#fff3c8" stroke-width="1.6" fill="none" opacity="0.7"/>')
    for k in range(5):                              # wisps in the wind
        sx, sy = x + r.uniform(20, 50), y + r.uniform(-40, 0)
        ex, ey = x + r.uniform(72, 86), y + r.uniform(-30, 20)
        pts = bez((sx, sy), (sx + 20, sy - 14), (ex - 16, ey - 10), (ex, ey), 14)
        o.append(f'<path d="{smooth_d(pts, False)}" stroke="#ffe8a0" stroke-width="1.1" fill="none" '
                 f'opacity="0.7" stroke-linecap="round"/>')
    return "\n".join(o)


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
    sw = bez((90, 545), (500, 515), (900, 530), (1220, 480), 30)
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
  <filter id="soft" filterUnits="userSpaceOnUse" x="0" y="0" width="1300" height="2000"><feGaussianBlur stdDeviation="14"/></filter>
  <filter id="glow" filterUnits="userSpaceOnUse" x="0" y="0" width="1300" height="2000"><feGaussianBlur stdDeviation="40"/></filter>
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
  {detailed_defs()}
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
        car_detailed(),
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
