"""Build the TMS9129 scanline pattern and colour streams for Speed Run."""
from functools import lru_cache
from pathlib import Path
import math
import random

from PIL import Image, ImageDraw
import einstein_illustration as art
import make_screens
import round_art


@lru_cache(maxsize=8192)
def pair(run):
    pattern, colour = art.encode(run)
    # Keep the more widespread ink in the low nibble. Objects drawn across
    # the landscape can then pick up the local background on each scanline.
    if pattern.bit_count() > 4:
        return pattern ^ 255, (colour >> 4) | ((colour & 15) << 4)
    return pattern, colour


def planes(im):
    width, height = im.size
    assert width % 8 == height % 8 == 0
    pixels = im.tobytes()
    pattern, colour = bytearray(), bytearray()
    for top in range(0, height, 8):
        for x in range(0, width, 8):
            for y in range(top, top + 8):
                start = y * width + x
                bits, inks = pair(pixels[start:start + 8])
                pattern.append(bits)
                colour.append(inks)
    return bytes(pattern), bytes(colour)


# Zenith, low sky, sunlight, distant ridge, accent, near ridge, valley floor.
LIGHT = {
    1:(5,7,11,5,11,12,7), 2:(5,7,15,3,11,12,2), 3:(7,11,15,10,9,6,11),
    4:(4,7,15,5,14,4,3), 5:(4,7,15,5,14,12,7), 6:(13,9,11,6,11,6,10),
    7:(7,15,11,2,10,12,3), 8:(5,14,15,4,15,5,14), 9:(13,9,11,6,13,4,4),
    10:(4,13,9,13,9,6,10), 11:(7,15,11,5,15,4,12), 12:(5,11,15,10,11,12,10),
    13:(13,9,11,5,11,4,5), 14:(4,13,9,5,13,1,4), 15:(9,11,15,6,10,6,11),
}


def landscape(stage, theme):
    seed, region = stage["seed"], stage["theme"]
    rng = random.Random(seed)
    default_seed = {"coast":1,"country":2,"desert":3,"alpine":4,"sunset":9}[region]
    high, low, sun, far, light, near, floor = stage.get("einstein_light", LIGHT.get(seed,LIGHT[default_seed]))
    art.rng.seed(331)
    art.rect(0, 0, 255, 191, 1)
    if region == "coast":
        art.background()
        im = art.scene.copy()
        if seed != 1 or "einstein_light" in stage:
            colours = list(range(256))
            for old, new in ((5, high), (7, low), (11, sun), (3, light)):
                colours[old] = new
            im = im.point(colours)
        # The village and its cliff stay on the same plane. The water and
        # boats immediately below form the independently scrolling near plane.
        coast = im.crop((0, 24, 256, 95)).resize((256, 56), Image.Resampling.NEAREST)
        im.paste(coast, (0, 24))
        water = ImageDraw.Draw(im)
        water.rectangle((0,80,255,95), fill=7 if seed != 13 else 5)
        for _ in range(62):
            x, y = rng.randrange(256), rng.randrange(81,96)
            water.line((x,y,x+rng.randrange(2,11),y), fill=rng.choice((4,light,15)))
        for x,h in ((48,11),(119,7),(202,9)):
            water.polygon([(x,92-h),(x,90),(x-h//2,90)],fill=15)
            water.polygon([(x+2,94-h),(x+2,90),(x+h//2,90)],fill=11)
            water.line((x-h//2,92,x+h//2,92),fill=6,width=2)
    else:
        art.rect(0,24,255,95,high)
        art.sky_blend(38,61,high,low)
        art.rect(0,61,255,95,low)
        sx = 62 + seed * 37 % 145
        art.d.ellipse((sx-12,37,sx+12,61),sun)
        for y in (54,58):
            art.line(sx-14,y,sx+14,y,low)
        art.cloud(-19 + seed*5%32,29,77,17)
        art.cloud(179 + seed*7%29,34,70,14)
        im = art.scene.copy()
        g = ImageDraw.Draw(im)
        if region == "alpine":
            for start, base, shade in ((-22,79,far),(-38,89,near)):
                x = start
                while x < 256:
                    w = rng.randint(35,69)
                    p, y = x+w//2, rng.randint(40,61)+(base-79)
                    g.polygon([(x-6,base),(p,y),(x+w+9,base)],fill=shade)
                    g.polygon([(p,y),(p+5,y+10),(p+2,y+9),(p+13,y+18),
                               (p-2,y+13),(p-8,y+18),(p-7,y+11),(p-15,y+16)],fill=15)
                    g.line([(p+1,y+5),(p+5,y+13),(p+3,y+14),(p+16,base-2)],fill=light)
                    x += w
        elif region == "desert":
            for base, shade, face in ((78,far,light),(89,near,10)):
                for x in range(-24,272,36):
                    w,h = rng.randint(18,46),rng.randint(10,28)
                    p = x+rng.randint(3,12)
                    g.polygon([(x-10,base),(p-3,base-8),(p,base-h),(p+w//2,base-h),
                               (p+w//2+3,base-8),(x+w+9,base)],fill=shade)
                    g.polygon([(p,base-h),(p+w//2,base-h),(p+w//2-4,base-h+3),
                               (p+3,base-h+3),(p+1,base-6),(p-3,base-4)],fill=face)
                    g.line((p+5,base-7,p+w//2+2,base-7),fill=face)
        elif region == "country":
            for base, height, col in ((66,7,far),(75,8,near),(84,5,light)):
                ridge = [(x,round(base+height*math.sin(x/29+seed+base))) for x in range(0,260,3)]
                g.polygon(ridge+[(255,95),(0,95)],fill=col)
            for x in range(3,256,17):
                y=73+round(7*math.sin(x/29+seed+75))
                g.line((x,y-3,x,y+2),fill=6)
                g.ellipse((x-3,y-7,x+3,y-2),fill=12)
            for x in (37+seed,166+seed):
                g.rectangle((x,69,x+12,75),fill=11)
                g.polygon([(x-2,69),(x+4,63),(x+10,64),(x+14,69)],fill=6)
                g.rectangle((x+7,71,x+9,75),fill=1)
        else:
            for base, col in ((77,far),(86,near)):
                x=-5
                while x<256:
                    w,h=rng.randint(6,17),rng.randint(8,34)
                    g.rectangle((x,base-h,x+w,base+3),fill=col)
                    g.line((x+2,base-h,x+w,base-h),fill=light)
                    if h>28: g.line((x+w//2,base-h-6,x+w//2,base-h),fill=col)
                    for y in range(base-h+4,base-2,4):
                        for dx in range(2,w-1,4):
                            if rng.random()<.55: g.line((x+dx,y,x+dx+1,y),fill=sun)
                    x+=w+2
        g.rectangle((0,80,255,95),fill=floor)
    # Region and route-specific near landmarks repeat seamlessly at the wrap.
    if region != "coast" or stage.get("vista"):
        mask=round_art.panorama(theme["horizon"]["style"],seed,stage.get("vista"))
        strip=Image.new("L",(256,16),near)
        draw=ImageDraw.Draw(strip)
        for y in range(16):
            for x in range(256):
                if mask.getpixel((x,y)) and (y==0 or not mask.getpixel((x,y-1))):
                    draw.point((x,y),fill=light)
        im.paste(strip,(0,80),mask)
    return im


def sprite_masters():
    """Rasterise the study's roadside palm and fastback at the existing aspect ratios."""
    art.scene.paste(0, (0, 0, 256, 192))
    art.palm(128, 115, 100)
    palm = art.scene.crop((78, 11, 178, 117)).point(lambda c: 255 if c else 0)
    palm = palm.resize((192, 256), Image.Resampling.NEAREST)
    art.scene.paste(0, (0, 0, 256, 192))
    art.rival(128, 60, 1, 10)
    car = art.scene.crop((113, 45, 143, 61))
    # Windows, tyres and the inset tail panel are negative space in a moving
    # two-ink tile. Retain the tyre outline so it reads against black asphalt.
    mask = car.point(lambda c: 255 if c > 1 else 0)
    pen = ImageDraw.Draw(mask)
    for x in (3, 22):
        pen.rectangle((x, 13, x+4, 15), outline=255)
    car = mask.resize((256, 128), Image.Resampling.NEAREST)
    return {"palm": palm, "citypalm": palm, "traffic": car}


def race_pack(stage, theme, palette):
    im=landscape(stage,theme)
    sky, ink=planes(im.crop((0,24,256,80)))
    horizon, horizon_ink=planes(im.crop((0,80,256,96)))
    # In command order, three inks for the upper, middle and lower parts of
    # each projected silhouette, including small objects and tunnel signs.
    materials = {
        "palm":(12,12,6), "citypalm":(1,12,6), "tree":(12,2,6), "pine":(12,12,6),
        "bush":(3,12,12), "tower":(8,15,6), "parasol":(9,15,6),
        "cactus":(3,12,12), "rock":(11,10,6), "windpump":(14,6,6),
        "tumbleweed":(11,10,6), "chalet":(6,11,6), "snowman":(15,14,15),
        "windmill":(15,10,6), "haybales":(11,10,6), "lamp":(11,14,4),
        "billboard":(13,11,14),
    }
    large, small, landmark, detail = (materials[n] for n in theme["types"])
    sign=(15,8,6)
    objects=[(7,8,6),sign,sign,(11,8,6),large,small,(15,5,4),(11,14,6),landmark,detail,sign]
    inks=bytes(c for profile in objects for c in profile)
    ground = {
        "coast":(0,0,0x10,0x28,0,0,0,0),
        "country":(0,0x04,0x0a,0,0,0,0x80,0),
        "desert":(0,0,0x18,0,0,0,0x40,0),
        "alpine":(0,0,0x04,0x0a,0,0x40,0,0),
        "sunset":(0,0,0,0x18,0,0,0,0),
    }[stage["theme"]]
    tms=(1,4,6,13,12,7,10,14,1,5,8,13,3,7,11,15)
    papers=[tms[(a>>3)&15] for a in palette[4:6]]
    # Closely related inks keep the tiled verge behind the racing line.
    highlights={1:4,2:12,3:2,4:5,5:4,6:9,7:5,8:6,9:8,10:11,11:10,12:2,13:5,14:15,15:14}
    terrain = bytes(ground) + bytes(((v<<3)|(v>>5))&255 for v in ground[4:]+ground[:4])
    terrain += bytes(highlights[paper]*16+paper for paper in papers for _ in range(8))
    streams=[sky,ink,horizon+horizon_ink,inks+terrain+bytes(papers)]
    data=palette+b"".join(make_screens.lz(s) for s in streams)
    assert len(data)<=0x1100
    return data


def car_row_masks(cells):
    """One byte per row, bit zero at the left edge of the Spider."""
    return [sum(1 << bit for bit in range(8) if cells[row + bit]) for row in range(0, 32, 8)]


def car_transitions(frames):
    """Encode the colour masks and contiguous pattern writes for each pose change."""
    poses = [(top[:192] + base[:64], top[192:] + base[64:]) for top, base in frames]
    records = bytearray()
    offsets = {}
    rows = []
    # The last row is for the first pose after a display reset.
    for previous in [*poses, None]:
        row = []
        for pose in poses:
            pixel_edits, ink_edits = (
                [previous is None or previous[plane][i:i+8] != data[i:i+8] for i in range(0, 256, 8)]
                for plane, data in enumerate(pose)
            )
            record = bytearray(car_row_masks(ink_edits))
            # The top and base are separate resident images. Never join a run across them.
            for first, end in ((0, 24), (24, 32)):
                cell = first
                while cell < end:
                    if not pixel_edits[cell]:
                        cell += 1
                        continue
                    start = cell
                    while cell < end and pixel_edits[cell]:
                        cell += 1
                    record.extend((start * 8, (cell - start) * 8))
            record.append(255)
            key = bytes(record)
            if key not in offsets:
                offsets[key] = len(records)
                records.extend(record)
            row.append(offsets[key])
        rows.append(row)
    assert len(records) <= 256
    asm = ['EinCarTransitions:']
    asm.extend('        db ' + ','.join(map(str, row)) for row in rows)
    asm.append('EinCarChanges:')
    asm.extend('        db ' + ','.join(map(str, records[i:i+16])) for i in range(0, len(records), 16))
    return asm


def cars(path):
    original=art.spider()
    frames=[]
    for frame in range(7):
        car=Image.new("L",(64,32),0)
        direction=0 if frame==0 else -1 if frame in (1,3,4) else 1
        for y in range(32):
            offset=round(direction*(15-y)/8)
            row=original.crop((0,y,64,y+1))
            car.paste(row,(offset,y),row.point(lambda i:255 if i else 0))
        if frame>=3:
            g=ImageDraw.Draw(car)
            x=48 if direction<0 else 1
            for dx,dy,r in ((1,0,3),(5,-2,4),(10,-4,3)):
                yy=29+dy-(frame in (4,6))*2
                g.ellipse((x+dx,max(24,yy-r),x+dx+2*r,yy+r),fill=14)
                g.line((x+dx+2,max(24,yy-r),x+dx+r,max(24,yy-r)),fill=15)
        pat,col=map(bytearray,planes(car))
        for y in range(32):
            for x in range(0,64,8):
                run=car.crop((x,y,x+8,y+1)).tobytes()
                if 0 not in run:
                    continue
                opaque=[c for c in run if c]
                ink=max(set(opaque),key=lambda c:(sum(art.dist[v][1]-min(art.dist[v][1],art.dist[v][c]) for v in opaque),c)) if opaque else 1
                at=(y//8*8+x//8)*8+y%8
                pat[at]=sum(128>>i for i,v in enumerate(run) if v and (ink==1 or art.dist[v][ink]<=art.dist[v][1]))
                col[at]=ink<<4  # low nibble replaced by the road or verge

        frames.append((pat[:192]+col[:192],pat[192:]+col[192:]))
    asm=['EinCarFrames:']
    for i,(top,bottom) in enumerate(frames):
        pose=(0,1,2,1,1,2,2)[i]
        assert top == frames[pose][0]
        asm.append(f'        dw EinSpiderTop{pose}, EinSpiderBase{i}')
        inks = top[192:] + bottom[64:]
        ground_masks = car_row_masks([any((ink & 15) == 0 for ink in inks[i:i+8])
                                     for i in range(0, 256, 8)])
        asm.append('        db ' + ','.join(map(str, ground_masks)))
    for i,(top,bottom) in enumerate(frames):
        parts=[(f'EinSpiderBase{i}',bottom)]
        if i<3: parts.append((f'EinSpiderTop{i}',top))
        for label,data in parts:
            asm.append(label+':')
            asm.extend('        db '+','.join(map(str,data[j:j+24])) for j in range(0,len(data),24))
    asm.extend(car_transitions(frames))
    Path(path).write_text('\n'.join(asm)+'\n',encoding='ascii')


def postcard(stage, theme, title, footer):
    """The top of a native postcard, with a normal writable score panel below."""
    backdrop=landscape(stage,theme)
    art.scene.paste(backdrop)
    art.road()
    if stage["theme"] != "coast":
        palette = {**theme["palette"], **stage.get("palette", {})}
        mapped = (1,4,6,13,12,7,10,14,1,5,8,13,3,7,11,15)
        colours = list(range(256))
        for old,key in ((2,"grass_d"),(3,"grass_l"),(15,"kerb_l"),(8,"kerb_d")):
            colours[old] = mapped[(palette[key] >> 3) & 15]
        art.scene.paste(art.scene.crop((0,96,256,192)).point(colours),(0,96))
    if stage["theme"]=="coast":
        art.verge()
    else:
        import make_scenery
        for name,x,base,h in ((theme["types"][0],8,143,49),(theme["types"][2],190,118,35)):
            master=make_scenery.TYPES[name][0]()
            mask=make_scenery.scaled(master,h)
            sprite=Image.new("L",mask.size,12)
            pen=ImageDraw.Draw(sprite)
            colours={"alpine":(15,4,12),"desert":(11,12,6),"country":(3,12,6),"sunset":(11,5,4)}
            top,mid,base_ink=colours[stage["theme"]]
            pen.rectangle((0,0,mask.width,h//4),fill=top)
            pen.rectangle((0,h//4,mask.width,2*h//3),fill=mid)
            pen.rectangle((0,2*h//3,mask.width,h),fill=base_ink)
            art.scene.paste(sprite,(x,base-h),mask)
    if not title:
        for y in range(142,150):
            for x in range(53,182):
                if ((x//5)+(y//4))%2: art.scene.putpixel((x,y),15)
    car=art.spider()
    height=168 if title else 136
    im=Image.new("L",(256,height),1)
    head=39 if title else 17
    view=art.scene.crop((0,24,256,159)).resize((256,height-head),Image.Resampling.NEAREST)
    im.paste(view,(0,head))
    im.paste(car,(96,height-34),car.point(lambda p:255 if p else 0))
    pen=ImageDraw.Draw(im)
    logo=make_screens.logo_mask("SPEED RUN" if title else "FINISH",4 if title else 2,4 if title else 2,.32)
    x=(256-logo.width)//2
    y=(head-logo.height)//2
    im.paste(6,(x+2,y+2),logo)
    for line in range(logo.height):
        fill=15 if line<logo.height//2 else 7 if line<logo.height*3//4 else 5
        im.paste(fill,(x,y+line),logo.crop((0,line,logo.width,line+1)))
    for x in list(range(0,24,6))+list(range(232,256,6)):
        pen.line((x,head-5,x+6,head-11),fill=9,width=2)
    pen.line((0,head-1,255,head-1),fill=13)
    pat,ink=planes(im)
    raw=bytearray(footer)
    for row in range(height//8):
        for line in range(8):
            y=row*8+line
            addr=((y&192)<<5)|((y&7)<<8)|((y&56)<<2)
            raw[addr:addr+32]=bytes(32)
        raw[6144+row*32:6144+row*32+32]=bytes(32)
    blob=bytes([height//8])+make_screens.lz(pat)+make_screens.lz(ink)+make_screens.lz(raw)
    assert (len(blob)+127)//128*128 <= 6912
    return blob
