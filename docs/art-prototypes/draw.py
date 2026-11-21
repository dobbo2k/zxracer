"""Redraw the three Speed Run style studies beside this script using Pillow.

The race, the 64 x 32 player sprite and the instrument readings are held at
the same positions. All drawing takes place on the 1-bit Spectrum bitmap.
The official screen decoder produces the enlarged previews from the SCRs.
"""
from pathlib import Path
import random
import sys
from PIL import Image, ImageDraw, ImageChops

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from make_font import rows
from make_screens import preview

K,B,R,M,G,C,Y,W = range(8)
ON = 255

class Screen:
    def __init__(self):
        self.bits = Image.new('L',(256,192))
        self.d = ImageDraw.Draw(self.bits)
        self.attrs = bytearray(768)

    def band(self, col, row, endcol, endrow, paper, ink, bright=1):
        for y in range(row,endrow):
            for x in range(col,endcol):
                self.attrs[y*32+x] = bright*64 + paper*8 + ink

    def stamp(self, mask, cx, bottom, height):
        size = (max(1, round(mask.width*height/mask.height)),height)
        mask = mask.resize(size,Image.Resampling.BOX).point(lambda p: 255 if p>=108 else 0)
        at = (cx-size[0]//2,bottom-height+1)
        layer = Image.new('L',self.bits.size)
        layer.paste(mask,at)
        self.bits.paste(ImageChops.difference(self.bits,layer))

    def export(self,name):
        bits = self.bits.convert('1').tobytes()
        scr = bytearray(6144)
        for y in range(192):
            offset = ((y&192)<<5) + ((y&7)<<8) + ((y&56)<<2)
            scr[offset:offset+32] = bits[y*32:y*32+32]
        data = scr + self.attrs
        (OUT/f'{name}.scr').write_bytes(data)
        preview(data).resize((768,576),Image.Resampling.NEAREST).save(OUT/f'{name}.png')

# Small capitals cut on a five-row grid, with a separate block-numeral face.
ABC = {
    'A':['0110','1001','1111','1001','1001'], 'C':['0111','1000','1000','1000','0111'],
    'D':['1110','1001','1001','1001','1110'], 'E':['1111','1000','1110','1000','1111'],
    'G':['0111','1000','1011','1001','0111'], 'H':['1001','1001','1111','1001','1001'],
    'I':['1']*5,'K':['1001','1010','1100','1010','1001'],'L':['1000','1000','1000','1000','1111'],
    'M':['10001','11011','10101','10001','10001'],'O':['0110','1001','1001','1001','0110'],
    'P':['1110','1001','1110','1000','1000'],'R':['1110','1001','1110','1010','1001'],
    'S':['0111','1000','0110','0001','1110'],'T':['11111','00100','00100','00100','00100'],
    'U':['1001','1001','1001','1001','0110'],' ':['00']*5,
    '1':['010','110','010','010','111'],'0':['0110','1001','1001','1001','0110'],
    '/':['001','001','010','100','100'], 'N':['1001','1101','1011','1001','1001'],
}
def letter(d,x,y,string,ink=ON,slant=0):
    for ch in string:
        glyph=ABC[ch]
        for j,line in enumerate(glyph):
            for i,v in enumerate(line):
                if v=='1': d.point((x+i+(4-j)*slant//4,y+j),ink)
        x+=len(glyph[0])+1

NUM = ['3e 63 67 6b 73 63 3e','0c 1c 3c 0c 0c 0c 3f','3e 63 03 0e 38 60 7f',
       '7e 03 06 1e 03 63 3e','0e 1e 36 66 7f 06 06','7f 60 7e 03 03 63 3e',
       '1e 30 60 7e 63 63 3e','7f 03 06 0c 18 18 18','3e 63 63 3e 63 63 3e',
       '3e 63 63 3f 03 06 3c']
SEG=['abcdef','bc','abdeg','abcdg','bcfg','acdfg','acdefg','abc','abcdefg','abcdfg']
def numeral(d,x,y,string,style,scale=1):
    for ch in string:
        if style==1:
            points={'a':(1,0,5,0),'b':(6,1,6,2),'c':(6,4,6,5),'d':(1,6,5,6),
                    'e':(0,4,0,5),'f':(0,1,0,2),'g':(1,3,5,3)}
            mask=Image.new('L',(7,7))
            for seg in SEG[int(ch)]: ImageDraw.Draw(mask).line(points[seg],255)
            data=[[mask.getpixel((i,j))!=0 for i in range(7)] for j in range(7)]
        elif style==2:
            data=[[a=='#' for a in line] for line in rows(ch)]
        else:
            data=[[(int(v,16) & (64>>i))!=0 for i in range(7)] for v in NUM[int(ch)].split()]
        for j,line in enumerate(data):
            for i,on in enumerate(line):
                if on:
                    xx=x+i*scale+int(style==0 and scale==1 and j<3)
                    d.rectangle((xx,y+j*scale,xx+scale-1,y+(j+1)*scale-1),ON)
        x+=8*scale

def dashboard(s,t):
    d=s.d
    if t==0:
        s.band(0,0,32,3,B,W)
        s.band(0,0,12,1,B,C); s.band(21,0,32,1,B,C)
        s.band(13,0,19,1,Y,K); s.band(13,1,19,3,K,Y)
        for x in [0,3,6,9,179,182,185,188]:
            d.line((x,6,x+4,1),255,2)
        d.line((77,19,94,19),255); d.line((162,19,190,19),255)
        letter(d,17,1,'SCORE',slant=1); letter(d,199,1,'SPEED',slant=1)
    elif t==1:
        s.band(0,0,32,3,K,C); s.band(0,0,32,1,K,M); s.band(13,1,19,3,K,Y)
        for x0,x1 in [(0,97),(158,255)]:
            d.line((x0,23,x1,23),ON); d.line((x0,21,x0+8,21),ON)
        for x0,x1 in [(38,98),(156,195),(226,255)]: d.line((x0,3,x1,3),ON)
        letter(d,7,1,'SCORE'); letter(d,200,1,'SPEED')
    else:
        s.band(0,0,32,3,W,K,0); s.band(13,0,19,3,K,W,0)
        s.band(24,0,32,1,Y,K,0)
        for i in range(6):
            d.polygon([(72+i*4,0),(75+i*4,0),(72+i*4,6),(69+i*4,6)],255)
        d.line((0,23,103,23),ON); d.line((152,23,255,23),ON)
        letter(d,8,1,'SCORE'); letter(d,200,1,'SPEED')
    letter(d,117,1,'TIME',slant=int(t==0))
    numeral(d,8,8,'0012840',t)
    numeral(d,113 if t!=2 else 115,9,'54',t,2)
    numeral(d,207,8,'196',t)
    letter(d,234,10,'KM/H'); letter(d,8,17,'STAGE 01'); letter(d,208,17,'HIGH')

def cumulus(d,x,y,w,h):
    # Flat-bottomed cumulus, with sunlit scallops and broken shadow contours.
    def box(a,b,c,e):
        return (round(x+w*a),round(y+h*b),round(x+w*c),round(y+h*e))
    for shape in [(0,.68,.15,.94),(.08,.56,.25,.89),(.15,.28,.31,.84),
                  (.23,.25,.34,.84),(.30,.20,.42,.84),(.34,0,.49,.70),
                  (.43,.08,.57,.77),(.51,.34,.64,.86),(.57,.29,.67,.79),
                  (.64,.41,.75,.86),(.68,.61,.82,.91),(.76,.64,.89,.95)]:
        d.ellipse(box(*shape),ON)
    d.rectangle(box(.08,.73,.88,.90),ON)
    for a,b,c in [(.03,.94,.16),(.25,.73,.34),(.36,.78,.55),(.58,.85,.75),(.22,.69,.27)]:
        d.line(box(a,b,c,b),0)
    d.line(box(.71,.96,1,.96),ON); d.line(box(-.10,.89,.07,.89),ON)
    for coords in [(.15,.45,.25,.62),(.30,.20,.43,.48),(.45,.24,.55,.54),
                   (.52,.50,.64,.72),(.67,.63,.78,.77)]:
        d.arc(box(*coords),9,107,fill=0)
    for a,b,c in [(.16,.98,.42),(.47,.94,.59),(.29,1.06,.46),(.92,.86,1.03)]:
        d.line(box(a,b,c,b),ON)

def alpine_etching(d):
    # An angular arête divides each illuminated face from its rock strata.
    # Hatch spacing follows the flank, and the valley fades into unprinted paper.
    peaks=[(-23,53,16,90),(6,60,33,85),(33,47,65,84),(62,64,87,83),
           (90,61,111,83),(119,70,141,83),(152,64,179,83),(180,52,208,84),
           (211,40,250,88),(252,59,275,86)]
    for idx,(cx,top,right,base) in enumerate(peaks):
        rr=random.Random(120+idx)
        left=cx-(right-cx)*1.45
        ridge=[(round(left),base)]
        for f in [.21,.35,.49,.63,.70,.82,.93,1]:
            ridge.append((round(left+(cx-left)*f),round(base+(top-base)*f+rr.choice([-2,0,1]))))
        ridge[-1]=(cx,top)
        fall=[(cx+4,top+4),(cx+5,top+3),(cx+11,top+10),
              (cx+14,top+11),(right,base)]
        crest=[(cx,top),(cx+2,top+6),(cx-1,top+9),(cx+3,top+13),
               (cx+1,top+17),(cx+7,top+23),(cx+5,base)]
        mask,md=master(256,96)
        md.polygon(ridge+fall+[(round(left),base)],255)
        for y in range(top,min(base+1,80)):
            for x in range(max(0,round(left)),min(right+1,256)):
                if mask.getpixel((x,y)): d.point((x,y),0)
        md.rectangle((0,0,255,95),0); md.polygon(crest+list(reversed(fall)),255)
        for y in range(top,min(base+1,80)):
            for x in range(max(0,cx-2),min(right+1,256)):
                if mask.getpixel((x,y)) and (x-2*y+int((y-top)/6))%6 not in (0,1):
                    d.point((x,y),ON)
        for segment in [ridge,fall,crest[:5]]:
            d.line(segment,ON)
        for f in [.27,.53,.78]:
            sx=round(left+(cx-left)*f); sy=round(base+(top-base)*f)
            d.line([(sx+1,sy+3),(sx-2,sy+8),(sx-5,sy+10),(sx-7,sy+14)],ON)
    for y in range(75,84):
        for x in range(256):
            if y>78 or (2*x+y)%7 < (y-74): d.point((x,y),0)

def sky(s,t):
    d=s.d
    if t==0:
        s.band(0,3,32,10,C,W)
        cumulus(d,-16,37,96,24); cumulus(d,148,31,90,27); cumulus(d,222,59,42,10)
        cumulus(d,78,66,34,7)
        # Three distant seabirds drawn at two sizes.
        for x,y in [(110,42),(119,39),(104,46)]:
            s.band(x//8,y//8,(x+5)//8+1,y//8+1,C,B)
            d.line([(x,y),(x+2,y+1),(x+4,y)],ON)
    elif t==1:
        s.band(0,3,32,7,B,C,0); s.band(0,7,32,10,M,B,0)
        for x,y in [(7,33),(19,49),(41,38),(78,47),(89,29),(103,52),(121,32),
                    (177,42),(186,29),(206,49),(218,37),(241,29),(247,47)]:
            d.point((x,y),255)
        for x,y in [(57,32),(192,44)]:
            d.line((x-2,y,x+2,y),ON); d.line((x,y-2,x,y+2),ON)
        # Punched-out scan lines open up towards the bottom of the disc.
        for y in range(31,80):
            dy=y-56
            radius=25
            half=round(max(0,radius**2-dy**2)**.5)
            if y in (55,60,65,66,71,72,73,77,78): continue
            for x in range(143-half,144+half):
                s.band(x//8,y//8,x//8+1,y//8+1,B if y<56 else M,Y,1)
                d.point((x,y),ON)
        # Keep the disc's surround on one brightness through each horizontal band.
        for row in range(3,10):
            for col in range(32): s.attrs[row*32+col]|=64
        for x0,x1,y in [(0,102,57),(179,255,57),(0,73,60),(202,255,60)]:
            d.line((x0,y,x1,y),ON)
        # Dusk cloud deck printed in blue over magenta, in very long, tapered strokes.
        for x,y,w in [(-12,62,65),(32,64,49),(69,61,25),(179,61,26),(199,61,73),(227,65,44)]:
            d.polygon([(x,y+1),(x+w//4,y),(x+w//3,y-2),(x+w//2,y-2),
                       (x+w//2+4,y),(x+w*3//4,y),(x+w,y+1)],ON)
        for x,y,w in [(6,67,28),(44,67,15),(209,68,23),(186,65,11)]:
            d.line((x,y,x+w,y),ON)
    else:
        s.band(0,3,32,10,W,B,0)
        # Ink engraving: thin, broken contours, with a bank of diagonally hatched cloud.
        for x,y,w,h in [(-20,29,82,9),(77,30,31,5),(123,33,64,9),(233,25,37,6)]:
            cloud=Image.new('L',(w+10,h+4))
            cumulus(ImageDraw.Draw(cloud),7,1,w,h)
            for j in range(1,h+2):
                for i in range(w+9):
                    if cloud.getpixel((i,j)) and (not cloud.getpixel((i,j-1)) or
                        (j>h*.62 and (i+j*2)%9==0) or (j>h*.89 and (i+j)%3==0)):
                        d.point((x+i,y+j),ON)
            d.line((x+6,y+h+2,x+w//2,y+h+2),ON)
        alpine_etching(d)

def panorama(s,t):
    p=Image.new('L',(256,16)); d=ImageDraw.Draw(p)
    s.band(0,10,32,12,[C,M,W][t],[B,K,B][t],int(t!=2))
    if t==0:
        # A tiled Mediterranean harbour with a headland, terraced houses and yachts.
        d.polygon([(0,4),(7,5),(15,3),(21,4),(28,2),(35,4),(42,4),(53,8),(66,9),
                   (78,13),(90,14),(93,15),(0,15)],ON)
        for x,y in [(3,6),(10,7),(17,5),(24,6),(31,4),(38,7),(46,8),(53,10),(62,11)]:
            d.rectangle((x,y,x+4,y+3),0); d.line((x+2,y+2,x+2,y+3),ON)
        d.line((0,11,255,11),255)
        for x,h in [(105,8),(119,5),(195,11),(209,6)]:
            d.polygon([(x,11-h),(x,10),(x-h//2,10)],ON)
            d.polygon([(x+2,13-h),(x+2,10),(x+5,10)],ON)
            d.line((x-5,12,x+6,12),ON); d.line((x-3,13,x+3,13),ON)
        d.polygon([(210,15),(222,10),(228,9),(238,5),(248,4),(255,4),(255,15)],ON)
        for x in range(2,251,11):
            d.line((x,15,x+3,15),ON)
    elif t==1:
        # Art deco stepped towers, roof terraces, aerials and lit ribbon windows.
        for x,w,h in [(0,11,7),(12,16,10),(30,10,6),(42,16,9),(60,9,12),(70,13,7),
                     (86,18,5),(106,11,8),(121,13,4),(139,11,5),(151,15,8),(168,11,12),
                     (181,13,7),(195,19,10),(218,10,13),(230,14,7),(246,10,8)]:
            y=16-h
            d.rectangle((x,y+2,x+w-1,15),ON); d.rectangle((x+2,y,x+w-3,15),ON)
            if h>9:
                d.line((x+w//2,y-3,x+w//2,y+1),ON)
            for j in range(y+3,15,3):
                for i in range(x+2,x+w-1,3): d.line((i,j,i+1,j),0)
        d.line((0,15,255,15),ON)
        # An observation tower, a wedding-cake hotel and low waterfront hangars.
        d.rectangle((39,0,78,15),0)
        for x,y,w in [(41,11,17),(44,8,13),(47,6,8),(49,4,4)]:
            d.rectangle((x,y,x+w,15),ON); d.line((x+1,y+1,x+w-2,y+1),0)
        d.line((51,1,51,5),ON)
        d.line((69,0,69,15),ON); d.ellipse((63,3,75,6),ON)
        d.line((65,4,73,4),0); d.line((65,15,69,7),ON)
        d.rectangle((114,0,151,15),0)
        for x in (115,125,135,145):
            d.polygon([(x,15),(x,12),(x+8,8),(x+8,15)],ON)
    else:
        peaks=[(-17,15),(2,5),(10,7),(18,3),(25,8),(39,1),(52,10),(58,8),(67,15),
               (81,7),(92,11),(99,9),(107,13),(124,6),(134,10),(150,14),(163,11),
               (178,12),(191,5),(200,8),(208,2),(221,12),(235,6),(244,8),(256,5)]
        d.polygon(peaks+[(256,16),(-17,16)],ON)
        for (x,y),(nx,ny) in zip(peaks,peaks[1:]):
            if ny>y:
                d.polygon([(x,y+1),(x+3,y+3),(nx,ny+2),(nx,ny+4),(x+4,y+5)],0)
                for i in range(x+1,nx,3): d.line((i,13,i-2,15),0)
        for x in range(111,169):
            for y in range(7,16): p.putpixel((x,y),0)
        d.line((108,8,172,8),ON)
        for x in range(109,169,10):
            d.rectangle((x,9,x+9,15),255); d.ellipse((x+2,10,x+9,20),0)
    s.bits.paste(p,(0,80))

def centre(y):
    t=(y-96)/95
    return round(100+76*(1-t)**2.45)

def road(s,t):
    d=s.d
    for by in range(12,24):
        y0=by*8
        edges=[]
        for y in range(y0,y0+8):
            depth=(y-95)/96
            c=centre(y); outer=round(150*depth); inner=round(outer*.85)
            edges.append((c-outer,c-inner,c+inner,c+outer))
        # The actual renderer assigns one kerb attribute to the whole sweep of an edge per cell row.
        band=[0,1,0,1,1,0,0,1,1,1,0,0][by-12]
        grass=([Y,Y],[M,M],[W,W])[t][band]
        kerb=([W,R],[C,B],[Y,B])[t][band]
        for col in range(32):
            l=8*col; r=l+7
            if r<min(e[0] for e in edges) or l>max(e[3] for e in edges):
                s.band(col,by,col+1,by+1,grass,K,band)
            elif l>max(e[1] for e in edges) and r<min(e[2] for e in edges):
                s.band(col,by,col+1,by+1,K,W,1)
            else:
                s.band(col,by,col+1,by+1,kerb,K,int(t!=2))
                for y,(_,a,b,_) in enumerate(edges,y0):
                    if max(l,a)<=min(r,b): d.line((max(l,a),y,min(r,b),y),ON)
        for y in range(y0,y0+8):
            # Paint dashes only where they fall on road cells.
            if not (y in range(100,102) or y in range(106,109) or y in range(115,120)
                    or y in range(131,141) or y>=163): continue
            c=centre(y); w=max(1,round((y-96)/24))
            for x in range(c,c+w):
                if s.attrs[by*32+x//8]&56==0: d.point((x,y),ON)

def master(w,h):
    m=Image.new('L',(w,h)); return m,ImageDraw.Draw(m)

def palm():
    m,d=master(43,52)
    d.polygon([(14,51),(18,38),(20,26),(20,15),(23,13),(24,22),(23,36),(21,49),(25,51)],ON)
    for y,x in [(23,21),(28,21),(34,20),(40,19),(45,17)]: d.line((x,y,x+2,y-1),0)
    fronds=[[(21,15),(13,8),(4,8),(0,12),(8,10),(14,11)],
            [(22,15),(15,4),(8,1),(6,1),(12,5),(15,10)],
            [(22,15),(20,7),(21,0),(23,2),(24,7),(23,12)],
            [(22,15),(29,4),(35,3),(39,5),(33,5),(28,10)],
            [(22,15),(32,9),(38,10),(42,15),(35,12),(29,13)],
            [(21,15),(32,15),(38,19),(40,25),(35,20),(28,18)],
            [(21,15),(15,14),(9,17),(4,23),(3,27),(9,21),(15,18)],
            [(21,15),(18,18),(14,25),(15,29),(17,23),(20,19)],
            [(21,15),(27,17),(30,22),(30,28),(28,24),(24,19)]]
    for f in fronds: d.polygon(f,ON)
    for x,y,side in [(4,11,-1),(8,10,-1),(12,11,-1),(11,5,-1),(15,8,-1),
                       (29,9,1),(33,6,1),(34,12,1),(37,13,1),(33,19,1),(9,20,-1)]:
        d.line((x,y,x+side,y+3),ON)
    for x,y in [(18,14),(21,13),(24,15)]: d.point((x,y),0)
    d.line((12,51,27,51),ON)
    return m

def lighthouse():
    m,d=master(24,45)
    d.polygon([(5,42),(9,13),(16,13),(20,42)],ON)
    d.rectangle((6,10,18,12),ON)
    d.rectangle((8,5,16,10),ON); d.rectangle((10,6,14,9),0)
    d.line((12,5,12,10),ON); d.polygon([(6,5),(12,1),(18,5)],ON); d.point((12,0),ON)
    d.polygon([(9,19),(16,16),(16,20),(8,24)],0)
    d.polygon([(8,30),(17,26),(18,30),(7,35)],0)
    d.rectangle((11,36,13,41),0); d.rectangle((3,42,22,44),ON)
    return m

def motel():
    m,d=master(38,44)
    d.polygon([(14,2),(18,7),(25,9),(18,11),(14,16),(12,10),(6,8),(12,7)],ON)
    d.point((14,8),0)
    d.rectangle((8,13,10,43),ON); d.line((29,15,29,43),ON,2)
    d.polygon([(1,14),(37,11),(34,26),(3,28)],ON)
    d.line((4,15,34,13),0)
    letter(d,6,17,'MOTEL',0)
    d.polygon([(4,30),(24,29),(24,26),(36,30),(25,36),(25,33),(4,35)],ON)
    d.line((7,32,22,31),0); d.line((6,43,12,43),ON); d.line((27,43,32,43),ON)
    return m

def lamp():
    m,d=master(29,48)
    d.polygon([(7,47),(9,28),(10,11),(12,6),(20,4),(22,6),(14,8),(13,27),(13,47)],ON)
    d.polygon([(16,4),(21,1),(27,1),(28,3),(23,6),(18,6)],ON)
    d.line((21,4,25,3),0)
    d.line((8,43,12,43),0); d.rectangle((6,46,15,47),ON)
    return m

def pine():
    m,d=master(27,42)
    d.rectangle((12,16,15,41),ON)
    for x,y,width,height in [(13,0,5,12),(13,6,8,12),(12,11,10,14),
                             (14,17,11,14),(13,23,13,12)]:
        d.polygon([(x,y),(x+width//2,y+height//2),(x+width//2-1,y+height//2),
                   (x+width,y+height-2),(x+3,y+height-3),(x+4,y+height),
                   (x-width//2,y+height-2),(x-width,y+height-1)],ON)
        d.line((x-1,y+4,x-width//2,y+height-4),0)
    d.line((4,40,24,41),ON)
    return m

def chevron():
    m,d=master(34,32)
    d.rectangle((4,11,6,31),ON); d.rectangle((27,10,29,31),ON)
    d.rectangle((0,0,33,20),ON); d.rectangle((1,1,32,18),0)
    for x in [3,13,23]:
        d.polygon([(x,3),(x+4,3),(x+9,10),(x+3,16),(x,16),(x+5,10)],ON)
    return m

def verge(t):
    m,d=master(24,12)
    if t==0:
        for (x,y) in [(0,6),(4,3),(11,0),(14,4),(20,6),(18,2),(6,7),(1,4)]:
            d.polygon([(10,11),(x,y),(12,9),(15,11)],ON)
        d.line((0,11,23,11),ON)
    elif t==1:
        d.polygon([(0,9),(0,5),(13,1),(23,2),(23,7),(10,10)],ON)
        for x in (5,10,15): d.line((x,5,x+3,4),0)
        d.line((4,8,4,11),ON,2); d.line((21,7,21,10),ON,2)
    else:
        d.polygon([(0,10),(4,6),(10,4),(13,0),(19,3),(22,8),(23,11)],ON)
        d.line([(4,8),(10,5),(12,6),(14,3),(18,5)],0)
        d.line((9,10,15,8),0)
    return m

def traffic(t):
    m,d=master(40,20)
    if t==0:
        d.polygon([(1,12),(5,9),(9,3),(12,2),(28,2),(33,9),(38,10),(39,15),
                   (37,17),(3,17),(0,15)],ON)
        d.polygon([(7,9),(11,4),(26,4),(31,9)],0)
        d.line((14,5,12,8),ON); d.line((26,5,29,8),ON)
        for x in [3,29]:
            d.rectangle((x,11,x+7,13),0); d.line((x+1,12,x+4,12),ON)
        d.line((4,15,35,15),0); d.rectangle((17,12,22,14),0)
    elif t==1:
        d.polygon([(0,8),(5,8),(10,3),(29,3),(35,8),(39,8),(38,15),(33,17),
                   (6,17),(1,15)],ON)
        d.polygon([(9,7),(12,4),(27,4),(31,7)],0)
        d.line((3,10,36,10),0); d.line((6,13,33,13),0)
        d.rectangle((16,14,23,15),0)
    else:
        d.polygon([(0,10),(5,9),(8,1),(29,1),(34,9),(39,10),(38,17),(1,17)],ON)
        d.polygon([(7,8),(10,3),(27,3),(30,8)],0)
        d.line((19,3,19,8),ON)
        for x in (3,31): d.rectangle((x,11,x+4,14),0)
        d.rectangle((15,11,24,13),0); d.line((1,16,37,16),0)
    d.rectangle((4,17,10,19),ON); d.rectangle((30,17,36,19),ON)
    return m

def roadside(s,t):
    big=[palm,lamp,pine][t](); landmark=[lighthouse,motel,chevron][t]()
    small=verge(t)
    for x,y,h in [(164,101,6),(187,103,8),(147,105,10),(198,108,13),
                  (126,110,16),(207,115,19),(226,128,32)]:
        s.stamp(big,x,y,h)
    for x,y,h in [(135,108,3),(210,111,3),(109,116,4),(218,120,5),
                   (83,125,5),(236,138,8),(54,141,9),(250,154,11),(12,165,12)]:
        s.stamp(small,x,y,h)
    s.stamp(landmark,61,134,39)
    s.stamp(big,15,148,48)
    s.stamp(big,249,153,48)
    rival=traffic(t)
    s.stamp(rival,158,111,6)
    s.stamp(rival,144,139,17)

def vehicle(s,t):
    # Paint the bitmap in native car coordinates, assigning each body panel an ink.
    m,d=master(64,32)
    if t==0:
        # Low, curved open spider. Twin headrests, split engine grille and four round lamps.
        d.line([(7,9),(12,2),(16,1),(47,1),(52,3),(56,9)],ON)
        d.line((16,1,25,1),0); d.line((28,1,36,1),0)
        for x,y,w in [(19,3,7),(38,2,9)]:
            d.ellipse((x,y,x+w,y+7),ON); d.line((x+2,y+2,x+4,y+1),0)
        d.line([(46,4),(49,6),(47,7)],ON)
        d.polygon([(0,13),(3,10),(10,9),(15,11),(24,10),(29,11),(36,11),
                   (41,10),(48,10),(53,9),(60,10),(63,14),(62,23),
                   (58,26),(6,26),(1,23)],ON)
        d.polygon([(14,11),(25,10),(39,10),(50,11),(54,15),(9,15)],0)
        for y,x1,x2 in [(11,18,46),(13,15,48),(15,11,52)]:
            d.line((x1,y,x2,y),ON); d.point((32,y),0)
        d.line((2,14,8,13),0); d.line((55,13,61,14),0)
        d.rounded_rectangle((2,16,61,22),radius=2,fill=0)
        for x in (4,11,47,54):
            d.ellipse((x,17,x+5,21),ON); d.point((x+2,19),0)
        d.rectangle((26,18,37,21),ON)
        for x in (28,30,33,35): d.line((x,19,x,20),0)
        for x in [20,22,40,42]: d.line((x,18,x-1,21),ON)
        d.line((6,24,57,24),0)
        colors=[[C,C,W,W,Y,Y,Y,C], [R,R,R,R,R,R,R,R], [R,R,R,W,W,R,R,R],
                [R,R,W,W,W,W,R,R]]
    elif t==1:
        # Targa wedge, raked buttresses, a louvred deck and a separate wing.
        d.line([(7,10),(14,2),(17,1),(47,1),(51,3),(57,10)],ON,2)
        d.line((19,3,45,3),ON)
        for x in [19,39]:
            d.rounded_rectangle((x,4,x+7,10),radius=2,fill=ON)
            d.line((x+2,6,x+5,6),0)
        d.polygon([(0,13),(8,8),(14,8),(19,11),(44,11),(50,8),(57,9),(63,13),
                   (62,23),(58,25),(4,25),(1,22)],ON)
        d.polygon([(14,8),(49,8),(53,15),(10,15)],0)
        for j in (9,11,13): d.line((17-(j-9),j,45+(j-9),j),ON)
        d.rectangle((1,15,62,17),0); d.line((0,15,63,15),ON)
        d.line((7,16,7,19),ON,2); d.line((56,16,56,19),ON,2)
        d.polygon([(2,18),(61,18),(58,23),(5,23)],0)
        for j in [18,20]:
            d.line((4,j,27,j),ON); d.line((36,j,59,j),ON)
            for x in [10,16,47,53]: d.point((x,j),0)
        d.rectangle((28,21,35,22),ON); d.line((9,24,54,24),0)
        colors=[[M,C,C,C,C,C,C,M],[M,M,C,C,C,C,M,M],[M,M,R,R,R,R,M,M],
                [M,M,C,C,C,C,M,M]]
    else:
        # Works rally roadster, compact cabin, raised ducktail, strapped boot and bumper overriders.
        d.line([(7,12),(13,4),(20,0),(43,0),(50,3),(56,11)],ON,2)
        d.line((20,2,44,2),ON)
        for x in (18,38):
            d.ellipse((x,3,x+8,10),ON); d.line((x+1,6,x+5,5),0)
        d.polygon([(1,14),(4,11),(10,10),(14,8),(48,8),(54,10),(60,11),(63,15),
                   (62,23),(57,26),(7,26),(1,22)],ON)
        d.line([(3,15),(10,12),(17,12),(19,10),(44,10),(47,12),(55,12),(60,15)],0)
        for x in (19,43): d.line((x,9,x-2,15),0,2)
        d.line((11,15,53,15),0); d.line((17,14,46,14),0)
        d.rectangle((2,17,61,22),0)
        for x in (3,9,49,55):
            d.rectangle((x,18,x+4,21),ON); d.point((x+2,19),0)
        d.rectangle((21,17,42,22),ON)
        for x in (24,26,29,31,34,36,39): d.line((x,18,x-1,21),0)
        d.line((5,24,58,24),0); d.rectangle((12,23,15,26),0); d.rectangle((48,23,51,26),0)
        colors=[[W,W,W,W,W,W,W,W],[Y,Y,Y,Y,Y,Y,Y,Y],[R,R,Y,W,W,Y,R,R],
                [W,W,W,W,W,W,W,W]]
    # Tyre animation samples these columns: only row 27 gets the cross tread.
    d.rectangle((0,26,63,31),0)
    for x in (4,51):
        d.line((x,26,x,31),ON); d.line((x+8,26,x+8,31),ON)
        for j in [2,5]: d.line((x+j,27,x+j+1,27),ON)
    for x in ([18,42] if t!=1 else [28,33]):
        d.rectangle((x,26,x+4,28),ON); d.line((x+1,27,x+3,27),0)
    for row,colourrow in enumerate(colors):
        for col,ink in enumerate(colourrow):
            s.band(12+col,20+row,13+col,21+row,K,ink,1)
    s.bits.paste(m,(96,160))

if __name__ == '__main__':
    names = ['01-riviera-spider', '02-neon-boulevard', '03-rally-annual']
    for style, name in enumerate(names):
        screen = Screen()
        sky(screen, style)
        panorama(screen, style)
        road(screen, style)
        roadside(screen, style)
        vehicle(screen, style)
        dashboard(screen, style)
        screen.export(name)
