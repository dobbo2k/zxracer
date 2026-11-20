#!/usr/bin/env python3
"""The tape's loading screen from the cover art (tools/make_cover.py, wide
layout): scaled to 256 x 192 and converted to Spectrum colours - per 8 x 8
cell the ink / paper pair (one brightness) that best fits its pixels, the
pixels between them ordered-dithered. The bottom character row stays blank
with LOADING in it: the loader's progress bar fills that row.

usage: make_loading.py ART.png OUT.scr [PREVIEW.png]
"""
import sys

import numpy as np
from PIL import Image, ImageEnhance

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


def convert(art):
    im = art.convert("RGB").resize((256, 192), Image.LANCZOS)
    im = ImageEnhance.Color(im).enhance(1.5)
    im = ImageEnhance.Contrast(im).enhance(1.2)
    px = (np.asarray(im, dtype=float) / 255.0) ** 1.25      # darks towards black
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
            t = LEVELS[np.abs(t[:, :, None] - LEVELS).argmin(2)]          # five blends only
            mix = A[:, None, :] + t[:, :, None] * D[:, None, :]
            err = (((cell[None] - mix) ** 2) * WEIGHT).sum((1, 2))
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


def main(art, out, preview=None):
    scr = convert(Image.open(art))
    open(out, "wb").write(scr)
    if preview:
        ms.preview(scr).resize((512, 384), Image.NEAREST).save(preview)


if __name__ == "__main__":
    main(*sys.argv[1:])
