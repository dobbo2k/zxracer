#!/usr/bin/env python3
"""The tape's loading screen from the cover art (tools/make_cover.py, wide
layout): scaled to 256 x 192 and converted to Spectrum colours - per 8 x 8
cell the ink / paper pair (one brightness) that best fits its pixels, the
pixels between them ordered-dithered. The bottom character row stays blank
with LOADING in it: the loader's progress bar fills that row.

usage: make_loading.py ART.png OUT.scr [PREVIEW.png [STYLE]]   (STYLE: see STYLES)
"""
import sys

import numpy as np
from PIL import Image, ImageEnhance, ImageFilter

sys.path.insert(0, __file__.rsplit("/", 1)[0])
import make_screens as ms           # noqa: E402

# the dither: blends of 0, 1/4, 1/2, 3/4 or all ink, as fixed 2 x 2 patterns
LEVELS = np.array([0.0, 0.25, 0.5, 0.75, 1.0])
PATTERNS = {0: [[0, 0], [0, 0]], 1: [[1, 0], [0, 0]], 2: [[1, 0], [0, 1]], 3: [[1, 1], [0, 1]],
            4: [[1, 1], [1, 1]]}
WEIGHT = np.array([0.32, 0.5, 0.18])            # rough perceptual weights for R, G, B
LOADING_ATTR = 0x47                             # row 23: bright white on black


def palette(bright):
    return np.array([ms.rgb(c, bright) for c in range(8)], dtype=float) / 255.0


# Styles: how much dithering, and where
#   dither   blends 0, 1/4, 1/2, 3/4, 1 everywhere
#   flat     no dithering: each pixel the nearer of its cell's two colours
#   light    only 50 % checks, and only where they clearly help
#   bands    the sky in solid stepped bands; light dithering below the horizon
#   outline  flat, with the drawing's ink lines kept as black pixel lines
STYLES = ("dither", "flat", "light", "bands", "outline")
SKY_ROWS = 13                                   # character rows above the horizon (wide layout)


def ink_lines(art):
    """The drawing's dark ink lines at screen size: a pixel is ink if any of
    the art's pixels under it is near-black."""
    g = np.asarray(art.convert("L"), dtype=float)
    dark = (g < 34).astype(np.uint8) * 255
    m = Image.fromarray(dark).filter(ImageFilter.MaxFilter(3)).resize((256, 192), Image.BOX)
    return np.asarray(m) > 70


def convert(art, style="dither"):
    assert style in STYLES, style
    im = art.convert("RGB").resize((256, 192), Image.LANCZOS)
    im = ImageEnhance.Color(im).enhance(1.5)
    im = ImageEnhance.Contrast(im).enhance(1.2)
    px = (np.asarray(im, dtype=float) / 255.0) ** 1.25      # darks towards black
    if style == "outline":
        px = px.copy()
        px[ink_lines(art)] = 0.0
    # every ink / paper pair of one brightness (and plain cells)
    pairs = []
    for bright in (False, True):
        pal = palette(bright)
        for a in range(8):
            for b in range(a, 8):
                pairs.append((bright, a, b, pal[a], pal[b]))
    A = np.array([p[3] for p in pairs])                      # (P, 3) paper
    B = np.array([p[4] for p in pairs])                      # (P, 3) ink
    D = B - A
    DD = (D * D * WEIGHT).sum(1)
    bitmap = bytearray(6144)
    attrs = bytearray(768)
    for cy in range(23):
        for cx in range(32):
            cell = px[cy * 8:cy * 8 + 8, cx * 8:cx * 8 + 8].reshape(64, 3)
            # per pair and pixel: the mix between paper and ink that fits best
            diff = cell[None, :, :] - A[:, None, :]                       # (P, 64, 3)
            t = ((diff * D[:, None, :] * WEIGHT).sum(2) / np.maximum(DD[:, None], 1e-9)).clip(0, 1)
            lv = LEVELS
            penalty = 0.0
            if style in ("flat", "outline") or (style == "bands" and cy < SKY_ROWS):
                lv = np.array([0.0, 1.0])
            elif style in ("light", "bands"):
                lv = np.array([0.0, 0.5, 1.0])
                penalty = 0.04                                        # per checked pixel
            t = lv[np.abs(t[:, :, None] - lv).argmin(2)]
            mix = A[:, None, :] + t[:, :, None] * D[:, None, :]
            err = (((cell[None] - mix) ** 2) * WEIGHT).sum((1, 2))
            if penalty:
                err = err + penalty * ((t > 0) & (t < 1)).sum(1)
            k = int(err.argmin())
            bright, a, b, _, _ = pairs[k]
            lv = np.rint(t[k] * 4).astype(int).reshape(8, 8)
            bits = np.zeros((8, 8), bool)
            for y in range(8):
                for x in range(8):
                    bits[y, x] = PATTERNS[lv[y, x]][y & 1][x & 1]
            if a == b:
                bits[:] = False
            for y in range(8):
                v = 0
                for x in range(8):
                    if bits[y, x]:
                        v |= 0x80 >> x
                yy = cy * 8 + y
                bitmap[((yy & 0xC0) << 5) | ((yy & 7) << 8) | ((yy & 0x38) << 2) + cx] = v
            attrs[cy * 32 + cx] = (0x40 if bright else 0) | a << 3 | b
    # row 23: LOADING, for the progress bar to fill
    word = "LOADING"
    text = Image.new("RGB", (256, 8), (0, 0, 0))
    from PIL import ImageDraw
    ms.text(ImageDraw.Draw(text), (256 - 8 * len(word)) // 2, 0, word, (255, 255, 255))
    tp = np.asarray(text)
    for y in range(8):
        for cx in range(32):
            v = 0
            for x in range(8):
                if tp[y, cx * 8 + x, 0]:
                    v |= 0x80 >> x
            yy = 184 + y
            bitmap[((yy & 0xC0) << 5) | ((yy & 7) << 8) | ((yy & 0x38) << 2) + cx] = v
    for cx in range(32):
        attrs[23 * 32 + cx] = LOADING_ATTR
    return bytes(bitmap + attrs)


def main(art, out, preview=None, style="dither"):
    scr = convert(Image.open(art), style)
    open(out, "wb").write(scr)
    if preview:
        ms.preview(scr).resize((512, 384), Image.NEAREST).save(preview)


if __name__ == "__main__":
    main(*sys.argv[1:])
