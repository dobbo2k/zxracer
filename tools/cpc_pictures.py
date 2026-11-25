#!/usr/bin/env python3
"""The Amstrad CPC's pictures (docs/cpc_artwork.md): the title, the five goal
postcards and the loading screen, drawn for Mode 0 (128 x 192, 16 pens) with
the CPC's masters (tools/cpc_illustration.py).

A picture is a CPC screen's 16K block (line y at (y & 7) x $800 + (y / 8) x
64), in the shown parts its art; in the first 2K's unshown part ($600) its 17
inks (the pens' and the border's hardware colours) and the first row of its
text panel; in the next seven 2Ks' unshown parts ($E00, $1600, ...) the
Spectrum's cells of the panel's rows, one a 2K (256 bitmap bytes, 8 lines of
32, then 32 attributes): the front end prints and blinks its text there, in
the Spectrum's way (src/cpc/front.asm GfxPicture).
"""
import math
import random

from PIL import Image, ImageDraw

import cpc_art
import cpc_illustration as ci
import make_scenery as scn
import make_screens
import round_art

W, H = 128, 192


class Picture:
    """A Mode 0 picture: pens (ci's numbering), its palette, its text rows."""

    def __init__(self, pens, panel_row):
        self.im = Image.new("L", (W, H), ci.BLACK)
        self.d = ImageDraw.Draw(self.im)
        self.pens = pens                            # 16 firmware colours
        self.panel_row = panel_row                  # the text panel's first row

    def master(self, m, x, base, h):
        """A master (ci) at height H, its bottom line BASE, its left X."""
        rows = cpc_art.shrink(m, h)
        px = self.im.load()
        for y, row in enumerate(rows):
            for i, p in enumerate(row):
                if p and 0 <= x + i < W and 0 <= base - h + y < H:
                    px[x + i, base - h + y] = p

    def bits(self, im1, x0, y0, pen, xscale=0.5):
        """A 1-bit image (the Spectrum's art) in PEN, at half its width."""
        px = self.im.load()
        for y in range(im1.height):
            for x in range(int(im1.width * xscale)):
                if im1.getpixel((int(x / xscale), y)) and 0 <= x0 + x < W and 0 <= y0 + y < H:
                    px[x0 + x, y0 + y] = pen

    def text(self, x, y, s, pen, sx=1, sy=1):
        """The CPC font (3 x 7, a 4-pixel advance) scaled SX, SY."""
        for ch in s:
            rows = cpc_art.FONT.get(ch, "... ... ... ... ... ... ...").split()
            for j, r in enumerate(rows):
                for i, c in enumerate(r):
                    if c == "#":
                        self.d.rectangle((x + i * sx, y + j * sy, x + i * sx + sx - 1, y + j * sy + sy - 1), pen)
            x += 4 * sx

    def road(self, top, bottom, centre_top, centre_bot, w_top, w_bot, ground, kerbs, band=6):
        """The road in perspective from line TOP to BOTTOM (Mode 0 pixels)."""
        for y in range(top, bottom):
            t = (y - top) / (bottom - top)
            dark = ((y - top) // band) % 2
            self.d.line((0, y, W - 1, y), ground[dark])
            c = centre_top + (centre_bot - centre_top) * t * t
            hw = (w_top + (w_bot - w_top) * t) / 2
            k = max(1, hw * 0.15)
            self.d.line((c - hw - k, y, c + hw + k, y), kerbs[dark])
            self.d.line((c - hw, y, c + hw, y), ci.ROAD)
            if not dark and hw > 6:
                self.d.line((c - max(0, hw * 0.03), y, c + max(0, hw * 0.03), y), ci.WHITE)

    def block(self, panel):
        """The 16K block: the art, its inks, the text panel's cells (PANEL:
        the Spectrum screen whose rows panel_row.. are the text)."""
        out = bytearray(0x4000)
        px = self.im.load()
        for y in range(min(H, self.panel_row * 8)):
            for bx in range(64):
                out[(y & 7) * 0x800 + (y >> 3) * 64 + bx] = cpc_art.byte(px[2 * bx, y], px[2 * bx + 1, y])
        out[0x600:0x611] = bytes(ci.CPC[c][1] for c in self.pens) + bytes([ci.CPC[ci.BLACK_C][1]])
        out[0x611] = self.panel_row
        for k, row in enumerate(range(self.panel_row, 24)):
            at = (k + 1) * 0x800 + 0x600
            for line in range(8):
                src = ((row & 0x18) << 8) | (line << 8) | ((row & 7) << 5)
                out[at + line * 32:at + line * 32 + 32] = panel[src:src + 32]
            out[at + 256:at + 288] = panel[6144 + row * 32:6144 + row * 32 + 32]
        return bytes(out)

    def preview(self):
        colours = [ci.CPC[c][0] for c in self.pens]
        out = Image.new("RGB", (W * 2, H))
        px = self.im.load()
        for y in range(H):
            for x in range(W):
                out.putpixel((2 * x, y), colours[px[x, y]])
                out.putpixel((2 * x + 1, y), colours[px[x, y]])
        return out


def sky(p, top, bottom, style, seed, cloud_pen, sun=None):
    p.d.rectangle((0, top, W - 1, bottom - 1), ci.SKY)
    if sun:
        x, y, r = sun
        p.d.ellipse((x - r, y - 2 * r, x + r, y + 2 * r), ci.YELLOW)
    p.bits(round_art.sky(style, seed), 24, top + 4, cloud_pen)


def title(loading=False):
    """The title (or, LOADING, the disc's loading screen): the logo on its
    blue fascia, the coast, the Spider on the road."""
    p = Picture(ci.pens("coast"), 24 if loading else 21)
    d = p.d
    d.rectangle((0, 0, W - 1, 47), ci.HUD)                         # the fascia
    p.text(11, 7, "SPEED RUN", ci.S5, 3, 4)                         # its shadow
    p.text(10, 5, "SPEED RUN", ci.WHITE, 3, 4)
    for x in (0, 3, 6, 112, 115, 118, 121, 124):
        d.line((x, 45, x + 3, 40), ci.SKY, 1)
    sky(p, 48, 104, "harbour", 1, ci.WHITE, sun=(98, 66, 7))
    d.rectangle((0, 88, W - 1, 103), ci.PANO_PAPER)
    p.bits(round_art.panorama("harbour", 1), 0, 88, ci.PANO_INK)
    p.road(104, 168, 60, 64, 4, 120, (ci.GROUND_L, ci.GROUND_D), (ci.WHITE, ci.RED))
    pm = ci.palm()
    for x, base, h in ((-6, 150, 70), (-2, 124, 36), (100, 124, 40), (110, 160, 76)):
        p.master(pm, x, base, h)
    p.master(ci.tower(), 20, 122, 34)
    p.master(ci.parasol(), 92, 138, 20)
    p.master(ci.spider(0), 48, 166, 32)
    if loading:
        p.text(16, 21 * 8, "FOR THE AMSTRAD CPC 6128", ci.SKY)
        p.text(50, 23 * 8, "LOADING", ci.YELLOW)
    return p


def goal(theme_name, theme):
    """A goal's postcard: the region's sky, backdrop and scenery, the
    gantry's GOAL! banner, the Spider over the line; rows 17-23 its text."""
    pal = theme["palette"]
    p = Picture(_fw_pens(theme_name, pal), 17)
    d = p.d
    style, seed = theme["horizon"]["style"], theme["horizon"]["seed"]
    sky(p, 0, 72, style, seed, ci.WHITE, sun=(100, 40, 6) if theme_name == "sunset" else None)
    d.rectangle((0, 56, W - 1, 71), ci.PANO_PAPER)
    pano = round_art.panorama(**theme["horizon"])
    p.bits(pano, 0, 56, ci.PANO_INK)
    p.road(72, 136, 64, 64, 10, 100, (ci.GROUND_L, ci.GROUND_D), (ci.WHITE, ci.RED), band=8)
    big, _, landmark, _ = theme["types"]
    masters = ci.cpc_masters(theme_name)
    for x, h, name in ((-4, 66, big), (12, 46, landmark), (92, 42, landmark), (106, 68, big)):
        p.master(masters[name][1], x, 128, h)
    d.rectangle((24, 8, 26, 127), ci.WHITE)                         # the gantry
    d.rectangle((101, 8, 103, 127), ci.WHITE)
    d.rectangle((28, 8, 99, 31), ci.BLACK)
    for x in range(28, 100, 2):
        for y in (8, 10, 28, 30):
            if (x // 2 + y // 2) % 2:
                d.rectangle((x, y, x + 1, y + 1), ci.WHITE)
    p.text(46, 13, "GOAL!", ci.YELLOW, 2, 2)
    r = random.Random(theme["name"])
    for _ in range(30):                                             # confetti
        x, y = r.randrange(W), r.randrange(0, 24)
        if 26 <= x <= 102:
            continue
        d.rectangle((x, y, x, y + 1), r.choice((ci.RED, ci.YELLOW, ci.WHITE, ci.S2)))
    p.master(ci.spider(0), 48, 134, 32)
    return p


def _fw_pens(theme_name, pal):
    """A goal's pens: its theme's, the stage's own colours over them."""
    b = ci.stage_pens(theme_name, pal, pal)
    hw_to_fw = {v[1]: k for k, v in ci.CPC.items()}
    return [hw_to_fw[x] for x in b[:16]]


def pictures(cfg):
    """-> {name: 16K block} for 'title' and 'goal_<theme>' (the Spectrum's
    text panels from make_screens)."""
    out = {"title": title().block(title_panel())}
    endings = make_screens.ending_themes(cfg)
    for name, theme in endings.items():
        out[f"goal_{name}"] = goal(name, theme).block(make_screens.goal_screen(theme))
    return out


def spectrum_text(scr, row, col, text):
    """The CPC's font (each pixel doubled across) into a Spectrum screen's
    bitmap: TEXT from cell ROW, COL."""
    for k, ch in enumerate(text):
        rows = cpc_art.FONT.get(ch, "... ... ... ... ... ... ...").split()
        for line, r in enumerate(rows + ["..."]):
            at = ((row & 0x18) << 8) | (line << 8) | ((row & 7) << 5) | (col + k)
            scr[at] = sum(0xC0 >> (2 * c) for c, p in enumerate(r) if p == "#")


def title_panel():
    """The title's text rows as the Spectrum's (its attributes), its
    lettering in the CPC's font (the game prints the hi-score and the keys)."""
    scr = bytearray(make_screens.title_screen())
    for row in range(21, 24):
        for line in range(8):
            at = ((row & 0x18) << 8) | (line << 8) | ((row & 7) << 5)
            scr[at:at + 32] = bytes(32)
    spectrum_text(scr, 21, 7, "HI-SCORE")
    spectrum_text(scr, 22, 5, "PRESS ANY KEY TO START")
    return bytes(scr)
