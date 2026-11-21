"""Riviera Spider race backdrops, drawn at the Spectrum's native resolution."""
import random

from PIL import Image, ImageDraw


def dash_header():
    """One fixed scanline strip for the instrument lettering and speed stripes."""
    glyphs = {
        "S": (7, 8, 6, 1, 14), "C": (7, 8, 8, 8, 7),
        "O": (6, 9, 9, 9, 6), "R": (14, 9, 14, 10, 9),
        "E": (15, 8, 14, 8, 15), "T": (15, 2, 2, 2, 2),
        "I": (7, 2, 2, 2, 7), "M": (9, 15, 15, 9, 9),
        "P": (14, 9, 14, 8, 8), "D": (14, 9, 9, 9, 14),
    }
    im = Image.new("1", (256, 8))
    draw = ImageDraw.Draw(im)
    for x, word in ((16, "SCORE"), (118, "TIME"), (199, "SPEED")):
        for ch in word:
            for y, bits in enumerate(glyphs[ch]):
                for i in range(4):
                    if bits & (8 >> i):
                        draw.point((x + i + (y < 2), y + 1), 1)
            x += 5
    for x in (0, 4, 8, 179, 183, 187):
        draw.line((x, 6, x + 4, 1), 1, width=2)
    return im.tobytes()


def panorama(style, seed, vista=None):
    """Draw a seamless strip. Overdraw across the join before cropping it."""
    rnd = random.Random(seed)
    strip = Image.new("1", (768, 16))
    draw = ImageDraw.Draw(strip)
    ridge = [rnd.randint(3, 12) for _ in range(16)]
    for origin in (0, 256, 512):
        def polygon(points, fill=1):
            draw.polygon([(origin + x, y) for x, y in points], fill)

        def line(points, fill=1):
            draw.line([(origin + x, y) for x, y in points], fill)

        def box(x, y, right, bottom, fill=1):
            draw.rectangle((origin + x, y, origin + right, bottom), fill)

        if style == "harbour":
            polygon([(-5, 10), (6, 5), (15, 6), (28, 2), (43, 5), (60, 8),
                     (78, 10), (88, 13), (88, 14), (-5, 14)])
            for x in range(2, 75, 7):
                y = 5 + abs(x - 23) // 10
                box(x, y, x + 4, y + 3, 0)
                box(x + 2, y + 2, x + 2, y + 3)
            line([(0, 13), (255, 13)])
            for x, height in ((103 + ridge[1], 8), (130 + ridge[3], 5),
                              (180 + ridge[5], 11), (207 + ridge[7], 6)):
                polygon([(x, 11 - height), (x, 11), (x - height // 2, 11)])
                polygon([(x + 2, 13 - height), (x + 2, 11), (x + 5, 11)])
                line([(x - 4, 13), (x + 5, 13)])
            for x in range(0, 256, 13):
                line([(x, 15), (x + 3, 15)])
        elif style == "mesas":
            for i, x in enumerate(range(0, 256, 32)):
                top = ridge[i] - 2
                polygon([(x - 8, 15), (x + 1, 10), (x + 6, top + 1),
                         (x + 8, top), (x + 20, top), (x + 23, top + 6),
                         (x + 31, 13), (x + 36, 15)])
                line([(x + 8, top + 2), (x + 16, top + 2)], 0)
                line([(x + 7, top + 5), (x + 5, 10), (x + 1, 12)], 0)
                line([(x + 13, 12), (x + 20, 11)], 0)
            x = 91 + ridge[9]
            box(x, 4, x + 3, 13)
            box(x - 1, 3, x + 4, 4)
        elif style == "peaks":
            for i, x in enumerate(range(0, 256, 16)):
                top = ridge[i] - 3
                polygon([(x - 16, 16), (x - 5, top + 3), (x, top),
                         (x + 5, top + 4), (x + 8, top + 4), (x + 20, 16)])
                polygon([(x, top + 1), (x - 6, top + 9), (x - 2, top + 7),
                         (x, top + 8), (x + 2, top + 5), (x + 6, top + 8)], 0)
            x = 80 + ridge[2] * 3
            box(x, 6, x + 36, 15)
            for arch in range(x + 2, x + 34, 7):
                draw.ellipse((origin + arch, 8, origin + arch + 4, 20), 0)
        elif style == "hills":
            points = [(i * 16, 5 + h // 2) for i, h in enumerate(ridge)]
            polygon(points + [(256, points[0][1]), (256, 16), (0, 16)])
            for i, x in enumerate(range(1, 256, 16)):
                line([(x, 15), (x + 7, 11 + ridge[i] % 3), (x + 12, 11)], 0)
            for x in (24 + ridge[3], 144 + ridge[4], 198 + ridge[8]):
                box(x, 5, x + 6, 11)
                polygon([(x - 2, 6), (x + 3, 1), (x + 8, 6)])
                box(x + 3, 7, x + 4, 9, 0)
            x = 85 + ridge[1]
            box(x, 3, x + 3, 10)
            polygon([(x - 1, 3), (x + 1, 0), (x + 4, 3)])
        elif style == "skyline":
            for i, x in enumerate(range(0, 256, 16)):
                top = max(1, ridge[i] - 2)
                box(x, top + 3, x + 14, 15)
                box(x + 2, top + 1, x + 12, 15)
                box(x + 5, top - 1, x + 9, 15)
                for y in range(top + 4, 15, 3):
                    for window in range(x + 2, x + 13, 4):
                        line([(window, y), (window + 1, y)], 0)
            x = 111 + ridge[1]
            box(x - 7, 0, x + 8, 13, 0)
            line([(x, 0), (x, 15)])
            draw.ellipse((origin + x - 6, 4, origin + x + 6, 7), 1)
            line([(x - 3, 5), (x + 3, 5)], 0)
        else:
            raise ValueError(style)
        if vista:
            # A recognisable place on this branch, silhouetted at the scale
            # of the scrolling band. Repeat at the same point in every copy.
            x = 104
            box(x - 2, 0, x + 37, 13, 0)
            if vista == "beacon":
                polygon([(x + 5, 14), (x + 8, 4), (x + 11, 4), (x + 14, 14)])
                box(x + 7, 2, x + 12, 3)
                line([(x + 9, 0), (x + 13, 2)])
                line([(x + 7, 10), (x + 12, 8)], 0)
                line([(x + 13, 13), (x + 28, 12), (x + 34, 13)])
            elif vista == "liner":
                polygon([(x, 10), (x + 35, 10), (x + 29, 14), (x + 6, 14)])
                box(x + 6, 7, x + 27, 10)
                box(x + 12, 4, x + 23, 7)
                box(x + 15, 1, x + 17, 4)
                for port in range(3, 29, 4):
                    box(x + port, 11, x + port + 1, 11, 0)
            elif vista == "mill":
                polygon([(x + 10, 15), (x + 13, 5), (x + 17, 5), (x + 20, 15)])
                for dx, dy in ((6, -5), (5, 5), (-6, 5), (-5, -5)):
                    line([(x + 15, 6), (x + 15 + dx, 6 + dy)])
                    line([(x + 15 + dx//2, 5 + dy//2), (x + 15 + dx, 5 + dy)])
                box(x + 14, 12, x + 16, 15, 0)
            elif vista == "manor":
                box(x + 3, 7, x + 31, 14)
                for dx in (2, 13, 25):
                    polygon([(x + dx, 7), (x + dx + 4, 2), (x + dx + 8, 7)])
                for dx in range(5, 31, 4):
                    box(x + dx, 9, x + dx + 1, 11, 0)
            elif vista == "gondola":
                line([(x - 2, 2), (x + 13, 5), (x + 35, 1)])
                line([(x + 8, 4), (x + 8, 8)])
                box(x + 5, 8, x + 11, 11)
                line([(x + 6, 9), (x + 9, 9)], 0)
                line([(x + 29, 15), (x + 32, 2), (x + 35, 15)])
            elif vista == "lodge":
                for dx, dy in ((0, 6), (11, 1), (23, 5)):
                    polygon([(x + dx, dy + 5), (x + dx + 6, dy), (x + dx + 12, dy + 5)])
                    box(x + dx + 2, dy + 5, x + dx + 10, 14)
                    box(x + dx + 4, dy + 6, x + dx + 6, dy + 7, 0)
            elif vista == "arch":
                polygon([(x - 2, 15), (x + 4, 10), (x + 8, 3), (x + 20, 1), (x + 27, 5), (x + 31, 12), (x + 36, 15)])
                draw.ellipse((origin + x + 9, 6, origin + x + 23, 22), 0)
                line([(x + 8, 5), (x + 18, 3)], 0)
            elif vista == "needles":
                for dx, h in ((2, 6), (10, 13), (20, 10), (28, 5)):
                    polygon([(x + dx - 3, 15), (x + dx, 15 - h), (x + dx + 2, 14 - h), (x + dx + 5, 15)])
            elif vista == "ruins":
                box(x + 2, 3, x + 32, 5)
                for dx in (4, 12, 20, 28):
                    box(x + dx, 6, x + dx + 2, 14)
                line([(x, 14), (x + 34, 14)])
            elif vista == "wheel":
                draw.ellipse((origin + x + 5, 0, origin + x + 19, 14), outline=1)
                for dx, dy in ((0, 7), (5, 2), (12, 0), (19, 3), (19, 8), (13, 14), (7, 13)):
                    line([(x + 12, 7), (x + dx, dy)])
                line([(x + 8, 15), (x + 12, 7), (x + 16, 15)])
            elif vista == "bridge":
                line([(x - 2, 10), (x + 37, 10)])
                for dx in (4, 28):
                    box(x + dx, 1, x + dx + 1, 14)
                line([(x - 2, 7), (x + 4, 1), (x + 11, 6), (x + 18, 8), (x + 23, 6), (x + 28, 1), (x + 37, 7)])
                for dx in (10, 16, 22):
                    line([(x + dx, 7), (x + dx, 10)])
            else:
                raise ValueError(vista)
    start = 256 + seed * 11 % 192
    return strip.crop((start, 0, start + 256, 16))


def sky(style, seed):
    """The protected 160 x 32 sky area between portraits and below the message."""
    image = Image.new("1", (160, 32))
    d = ImageDraw.Draw(image)
    rnd = random.Random(seed)
    if style == "skyline":
        x = rnd.randrange(22, 120)
        d.ellipse((x, 2, x + 29, 31), 1)
        for y in (20, 24, 25, 28, 29, 31):
            d.line((x, y, x + 29, y), 0)
        return image
    for x, y, width in ((rnd.randrange(0, 7), rnd.randrange(2, 9), 56),
                        (rnd.randrange(84, 97), rnd.randrange(8, 15), 60)):
        height = {"harbour": 16, "hills": 14, "peaks": 9, "mesas": 6}[style]
        for left, top, right in ((0, .66, .24), (.12, .35, .42), (.30, 0, .57),
                                 (.5, .25, .72), (.65, .5, .85), (.76, .7, .98)):
            d.ellipse((x + int(left * width), y + int(top * height),
                       x + int(right * width), y + height), 1)
        d.line((x + 2, y + height, x + width, y + height), 1)
        for left, top, right in ((.15, .75, .30), (.37, .59, .47), (.50, .85, .75)):
            yy = y + int(top * height)
            d.line((x + int(left * width), yy, x + int(right * width), yy), 0)
        d.line((x + width // 3, y + height + 2, x + width * 2 // 3, y + height + 2), 1)
    return image
