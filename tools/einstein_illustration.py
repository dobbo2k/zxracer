"""Indexed-pixel artwork shared by the Einstein game and its original study."""
from collections import Counter
from itertools import combinations
import math
import random
from PIL import Image, ImageDraw

K, G, LEAF, BLUE, LILAC, RUST, AQUA, RED, CORAL, OCHRE, SAND, PINE, MAUVE, GREY, WHITE = range(1, 16)
colors = ['000000','000000','21C842','5EDC78','5455ED','7D76FC','D4524D','42EBF5','FC5554',
          'FF7978','D4C154','E6CE80','21B03B','C95BBA','CCCCCC','FFFFFF']
rgb = [tuple(bytes.fromhex(c)) for c in colors]
scene = Image.new('L',(256,192),K)
d = ImageDraw.Draw(scene)
rng = random.Random(331)

def line(x1,y1,x2,y2,c):
    d.line((x1,y1,x2,y2),c)

def rect(x1,y1,x2,y2,c):
    d.rectangle((x1,y1,x2,y2),c)

def poly(vertices,c):
    d.polygon(vertices,c)

def sky_blend(y0,y1,a,b):
    # Long offset horizontal stitches make a blend in the two native inks.
    matrix=((0,6,2,7),(4,1,5,3))
    for y in range(y0,y1):
        f=8*(y-y0+.5)/(y1-y0)
        for x in range(256):
            scene.putpixel((x,y),b if matrix[y%2][(x//2)%4]<f else a)

def cloud(x,y,w,h):
    # Overlapping towers with a sunlit edge and a broad, flat, shaded base.
    mask=Image.new('1',(w+4,h+6))
    md=ImageDraw.Draw(mask)
    for a,b,c,e in [(0,.77,.19,.97),(.10,.6,.26,.94),(.17,.42,.33,.91),
                    (.27,.36,.38,.91),(.32,.15,.47,.94),(.40,0,.57,.82),
                    (.49,.13,.65,.88),(.58,.43,.72,.92),(.66,.38,.80,.92),
                    (.73,.58,.88,.95),(.82,.74,.96,.96)]:
        md.ellipse((int(a*w),int(b*h),int(c*w),int(e*h)),1)
    md.rectangle((w//10,int(h*.79),int(w*.95),h-1),1)
    md.line((int(w*.20),h,int(w*.89),h),1)
    for j in range(h+1):
        for i in range(w):
            if not mask.getpixel((i,j)) or not (0<=x+i<256 and 24<=y+j<80): continue
            depth= j / h
            streak=.09*math.sin(i*.14)+.035*math.sin(i*.39)
            color=WHITE if depth<.57+streak else SAND if depth<.74+streak else CORAL if depth<.91+streak else MAUVE
            scene.putpixel((x+i,y+j),color)
    for ax,ay,aw,ah in ((.15,.56,.13,.17),(.38,.29,.12,.19),(.51,.48,.14,.17),
                         (.65,.61,.09,.12),(.76,.77,.12,.1)):
        left=x+int(ax*w);top=y+int(ay*h)
        d.arc((left,top,left+int(aw*w),top+max(2,int(ah*h))),12,133,SAND)
    for a,b,e,c in [(.07,.98,.35,MAUVE),(.48,1.06,.80,MAUVE),(.90,.94,1,CORAL),(.36,.54,.46,WHITE)]:
        line(x+int(a*w),y+int(b*h),x+int(e*w),y+int(b*h),c)

def background():
    rect(0,24,255,80, LILAC)
    sky_blend(45,57,LILAC,AQUA)
    rect(0,57,255,81,AQUA)
    # The sun is broken up by a thin bank of haze above the distant islands.
    d.ellipse((156,43,185,72), SAND)
    for yy in range(45,73):
        for xx in range(157,186):
            if scene.getpixel((xx,yy))==SAND and yy<57:
                scene.putpixel((xx,yy), WHITE)
    line(154,67,181,67,AQUA); line(166,70,189,70,AQUA)
    cloud(-23,30,121,32)
    cloud(201,32,68,22)
    cloud(94,49,40,9)
    for x,y in [(122,39),(131,37),(115,43)]:
        d.line([(x,y),(x+2,y+1),(x+3,y+2),(x+5,y)],BLUE)
    # Successive headlands recede into lavender and coral light.
    poly([(-4,65),(7,61),(18,62),(27,59),(36,61),(43,65),(52,64),(65,70),
          (76,69),(89,75),(104,78),(110,79),(0,84)],LILAC)
    poly([(80,80),(101,76),(112,76),(124,71),(131,72),(142,69),(154,71),
          (164,75),(171,76),(180,80)],LILAC)
    poly([(0,68),(7,64),(15,65),(27,69),(31,68),(43,74),(57,74),(66,78),
          (82,81),(77,82),(0,82)],BLUE)
    # Small sunny planes and scratches of scree break up the shaded headland.
    for x,y,n in [(6,66,9),(19,69,6),(28,70,9),(37,74,6),(52,76,7),(63,78,6)]:
        d.line([(x,y),(x+3,y+1),(x+n,y+2)],LILAC)
    for x,y in [(10,73),(16,72),(23,75),(31,76),(43,78)]:
        rect(x,y,x+3,y+2,SAND);line(x,y-1,x+3,y-1,RUST)
    line(96,79,170,79,BLUE)
    rect(0,82,255,95,AQUA)
    line(0,81,255,81,LILAC)
    for i in range(92):
        x=rng.randrange(256); y=rng.randrange(82,96)
        line(x,y,x+rng.randrange(2,13),y,BLUE if y>90 else LILAC)
    for y in (82,84,87,89,92):
        x=167+rng.randrange(-7,6)
        line(x,y,x+rng.randrange(7,21),y,SAND if y%2 else WHITE)
    # Cliff settlement. Roofs step to the contour instead of a uniform skyline.
    poly([(166,91),(175,85),(184,81),(189,75),(199,73),(211,67),(221,67),
          (229,62),(239,60),(248,59),(256,57),(256,95),(161,95)],PINE)
    poly([(171,90),(184,86),(195,85),(208,80),(220,81),(229,75),(240,75),
          (255,69),(255,94),(169,94)],OCHRE)
    poly([(181,89),(194,88),(207,83),(212,84),(206,87),(194,91),(190,93),(172,93)],SAND)
    poly([(212,91),(220,84),(230,83),(239,79),(249,77),(255,74),(255,86),(241,87),(230,93)],RUST)
    for x,y,length in [(187,89,7),(205,84,5),(215,86,5),(225,83,4),(241,78,6)]:
        line(x,y,x+length,y-2,SAND)
    for x,y,w in [(183,79,7),(193,75,8),(204,72,10),(214,70,7),(224,66,9),(240,63,9),(250,61,8)]:
        rect(x,y,x+w,y+5,WHITE); rect(x+w-2,y+1,x+w,y+5,SAND)
        poly([(x-1,y),(x+2,y-3),(x+w-2,y-3),(x+w+1,y)],RUST)
        line(x+2,y-2,x+w-2,y-2,CORAL)
        rect(x+2,y+2,x+3,y+4,BLUE)
    # Campanile with a lit clock, a roof lantern and dark arched opening.
    rect(231,49,237,66,SAND); rect(231,49,233,66,WHITE)
    rect(230,51,238,52,RUST); rect(232,47,236,50,SAND)
    poly([(230,48),(234,42),(238,48)],RUST); d.point((234,41),K)
    rect(233,54,235,57,BLUE); d.point((234,60),RUST)
    for x,y,h in [(178,83,5),(191,78,7),(200,74,9),(216,71,10),(246,62,8),(253,61,9)]:
        poly([(x-2,y),(x,y-h),(x+1,y-5),(x+2,y)],PINE)
    # The nearest yacht has a shadow sail and a sunlit sail on opposite sides.
    for x,y,h in [(72,88,18),(102,84,8),(145,83,5),(22,87,9)]:
        line(x,y-h,x,y,K if h>12 else BLUE)
        poly([(x-1,y-h+1),(x-1,y-2),(x-h//2,y-2)],WHITE)
        poly([(x+2,y-h+5),(x+2,y-2),(x+h//3,y-2)],SAND)
        poly([(x-h//2-1,y),(x+h//3+2,y),(x+h//3-1,y+2),(x-4,y+2)],RUST)
        line(x-3,y+4,x+5,y+4,AQUA)

def course(y):
    t=(y-96)/95
    return int(101+79*(1-t)**2.15),int(4+139*t)

def road():
    for y in range(96,192):
        c,half=course(y); depth=y-96
        band=sum(y>=mark for mark in (98,101,105,110,117,126,139,158,182))%2
        # Mown verge with a sunlit sand shoulder. Keep the tarmac quiet.
        line(0,y,255,y,LEAF if band else G)
        shoulder=max(2,depth//8+2); kerb=max(1,depth//13+1)
        line(c-half-shoulder,y,c+half+shoulder,y,SAND if band else OCHRE)
        line(c-half-kerb,y,c+half+kerb,y,WHITE if band else RED)
        line(c-half,y,c+half,y,K)
        # At each inside edge reserve its eight-pixel run for kerb + asphalt.
        # This leaves a sharp red/white line all the way through the bend.
        edge=WHITE if band else RED
        l=c-half; r=c+half
        if 0<l<256 and l%8:line(l//8*8,y,l-1,y,edge)
        if 0<=r<255 and r%8<7:line(r+1,y,r//8*8+7,y,edge)
    # Marine grass, in small clusters with a distinct ground line.
    for i in range(110):
        y=rng.randrange(98,188); x=rng.randrange(256)
        c,w=course(y)
        if abs(x-c)<w+14: continue
        height=1+(y-96)//30
        d.line([(x-2,y-1),(x,y),(x+height,y-height)],PINE)
        if height>2: line(x,y,x-1,y-height+1,G)

def palm(x,base,h,orient=1):
    # Hand-shaped fronds, tapered leaflets, a sunlit edge and a ringed trunk.
    def pt(a,b):return (round(x+orient*a*h/64), round(base+b*h/64))
    def shape(points,ink):poly([pt(*p) for p in points],ink)
    shape([(-8,0),(-5,-10),(-1,-22),(2,-36),(1,-46),(4,-49),
           (7,-40),(6,-26),(2,-13),(-2,0)],RUST)
    d.line([pt(-6,-1),pt(-3,-12),pt(1,-26),pt(3,-38),pt(2,-46)],OCHRE,max(1,round(h/44)))
    for j in range(4,41,7):
        u=-5+9*math.sin(j/42*math.pi/2)
        d.line([pt(u,-j),pt(u+2,-j-1)],RUST)
    fronds=[((-10,-65),(-24,-58)),((-14,-59),(-28,-47)),((-14,-52),(-25,-35)),
            ((-8,-47),(-13,-29)),((4,-57),(8,-64)),((13,-65),(22,-60)),
            ((18,-59),(29,-50)),((20,-52),(28,-40)),((12,-48),(16,-31))]
    for k,(control,end) in enumerate(fronds):
        crown=(3,-47)
        pts=[]
        leaves=[]
        for j in range(10):
            t=j/9
            a=(1-t)**2*crown[0]+2*(1-t)*t*control[0]+t*t*end[0]
            b=(1-t)**2*crown[1]+2*(1-t)*t*control[1]+t*t*end[1]
            pts.append((a,b))
            if 1<j<9:
                sign=1 if end[0]>3 else -1
                leaves.append([(a-sign*2,b),(a+sign*2,b+.5),
                               (a+sign*(2.5+2*t),b+6*(1-t)+2)])
        for leaf in leaves:shape(leaf,PINE)
        d.line([pt(*p) for p in pts],PINE,max(1,round(h/35)))
        if k in (1,3,7,8):
            d.line([pt(a,b+1) for a,b in pts[1:7]],K,max(1,round(h/54)))
        d.line([pt(a,b-.9) for a,b in pts[1:7]],G if k not in (2,3,8) else LEAF)
    for a,b in [(1,-47),(4,-46),(6,-47)]:d.point(pt(a,b),RUST)
    d.line([pt(-10,0),pt(1,0)],PINE)

def verge():
    for x,y,h,o in [(172,100,8,-1),(193,103,11,1),(151,105,13,1),
                    (205,109,18,-1),(125,115,22,1),(217,122,27,-1)]:
        palm(x,y,h,o)
    # Low stone parapet follows the left edge of the headland.
    for points,col in [([(0,141),(119,103),(130,102),(0,148)],OCHRE),
                       ([(0,139),(119,102),(131,101),(0,144)],SAND)]:
        poly(points,col)
    for x in (5,17,28,39,49,58,67,76,84,93,101,110):
        y=round(140-x*.318)
        line(x,y+1,x-1,y+3,RUST)
    palm(24,141,61,-1); palm(237,137,51,1)
    # Red and cream fingerboard marking the coastal turn, clear of the road.
    rect(56,119,57,129,RUST); rect(73,119,74,128,RUST)
    rect(53,111,77,120,RUST); rect(54,112,76,118,SAND)
    for x in (56,63,70):
        poly([(x,113),(x+2,113),(x+5,115),(x+1,118),(x-1,118),(x+2,115)],RED)

def rival(x,y,scale,color):
    # A compact square-tail coupe, distinctly smaller than the open spider.
    body=Image.new('L',(30,16),0); b=ImageDraw.Draw(body)
    b.polygon([(0,8),(3,7),(7,2),(9,1),(21,1),(25,6),(29,7),(28,13),(2,13)],color)
    b.polygon([(6,7),(9,3),(19,3),(23,7)],K)
    b.line((9,3,18,3),AQUA); b.line((12,4,10,6),BLUE)
    b.line((3,8,26,8),WHITE)
    b.rectangle((1,10,28,11),K)
    for xx in (2,23): b.rectangle((xx,9,xx+4,10),RED)
    b.line((12,11,17,11),WHITE); b.line((3,13,26,13),OCHRE)
    b.rectangle((3,14,7,15),K); b.rectangle((22,14,26,15),K)
    b.point((3,14),GREY);b.point((26,14),GREY)
    size=(round(30*scale),round(16*scale));body=body.resize(size,Image.Resampling.NEAREST)
    scene.paste(body,(x-size[0]//2,y-size[1]+1),body.point(lambda i:255 if i else 0))

def spider():
    # Draw the native 64 x 32 sprite in place; black asphalt is visible around the body.
    car=Image.new('L',(64,32),0); g=ImageDraw.Draw(car)
    g.polygon([(5,26),(2,22),(1,17),(2,12),(7,10),(12,9),(16,7),
               (47,7),(52,9),(60,11),(63,14),(62,22),(58,26)],RUST)
    g.polygon([(1,16),(3,12),(10,10),(16,8),(47,8),(55,10),(60,12),(63,16),
               (60,20),(3,20)],RED)
    # Slender windscreen and the crease above the front wings.
    g.line([(7,11),(13,2),(16,1),(46,1),(50,3),(56,11)],AQUA)
    g.line([(13,3),(16,2),(27,2)],WHITE)
    g.line([(30,2),(45,2),(50,5)],BLUE)
    g.polygon([(10,9),(14,9),(19,6),(25,6),(28,9),(35,9),(38,6),
               (46,6),(51,10),(52,11),(10,11)],K)
    # Driver with dark hair, passenger with loose golden hair.
    g.ellipse((18,3,25,9),RUST); g.line([(19,4),(21,3),(24,4)],K)
    g.line([(19,6),(23,6),(23,8)],SAND); g.line((18,9,25,9),AQUA)
    g.ellipse((38,2,45,9),OCHRE); g.line([(39,4),(41,3),(44,3)],SAND)
    g.line([(43,5),(46,5),(49,7),(51,7)],SAND)
    g.line([(43,7),(47,7),(48,9)],OCHRE)
    g.polygon([(12,11),(18,10),(47,10),(52,12),(56,16),(8,16)],RUST)
    for yy,x1,x2 in ((11,18,47),(13,15,49),(15,11,52)):
        g.line((x1,yy,x2,yy),K)
        g.line((x1+2,yy-1,30,yy-1),CORAL)
        g.point((32,yy),RED)
    for points in [[(1,15),(5,12),(11,11)],[(52,11),(58,12),(61,14)]]:
        g.line(points,CORAL);g.point(points[1],WHITE)
    g.line((5,16,59,16),CORAL)
    g.rounded_rectangle((2,17,61,23),radius=3,fill=K)
    for xx in (4,11,47,54):
        g.ellipse((xx,18,xx+5,22),RUST);g.line((xx+1,18,xx+3,18),CORAL)
    g.rounded_rectangle((25,18,38,22),radius=1,fill=GREY)
    g.line((26,18,37,18),WHITE)
    for xx in (28,30,33,35):g.line((xx,19,xx,20),K)
    g.line([(3,23),(9,24),(54,24),(61,22)],RED)
    g.line([(7,25),(13,26),(50,26),(57,25)],RUST)
    for xx in (4,51):
        g.rectangle((xx,26,xx+8,30),K);g.line((xx,26,xx,29),GREY)
        g.line((xx+1,30,xx+6,30),BLUE);g.line((xx+2,27,xx+5,27),BLUE)
    for xx in (18,41):
        g.rectangle((xx,26,xx+4,28),GREY);g.line((xx+1,27,xx+3,27),K)
    scene.paste(car,(96,160),car.point(lambda v:255 if v else 0))
    return car

LETTERS={
    'A':(6,9,15,9,9),'C':(7,8,8,8,7),'D':(14,9,9,9,14),'E':(15,8,14,8,15),
    'G':(7,8,11,9,7),'H':(9,9,15,9,9),'I':(7,2,2,2,7),'K':(9,10,12,10,9),
    'M':(17,27,21,17,17),'O':(6,9,9,9,6),'P':(14,9,14,8,8),'R':(14,9,14,10,9),
    'S':(7,8,6,1,14),'T':(31,4,4,4,4),'U':(9,9,9,9,6),'N':(9,13,11,9,9),
    'Y':(17,10,4,4,4),'/':(1,1,2,4,4),' ':(0,0,0,0,0)}
NUMS=('3e 63 67 6b 73 63 3e','0c 1c 3c 0c 0c 0c 3f','3e 63 03 0e 38 60 7f',
      '7e 03 06 1e 03 63 3e','0e 1e 36 66 7f 06 06','7f 60 7e 03 03 63 3e',
      '1e 30 60 7e 63 63 3e','7f 03 06 0c 18 18 18','3e 63 63 3e 63 63 3e','3e 63 63 3f 03 06 3c')
def letters(x,y,text,col):
    for ch in text:
        glyph=LETTERS[ch]; width=max(2,max(glyph).bit_length())
        for j,bits in enumerate(glyph):
            for i in range(width):
                if bits & (1<<(width-1-i)):d.point((x+i,y+j),col)
        x+=width+1

def digits(x,y,text,scale,col,shade):
    for ch in text:
        for j,bits in enumerate(bytes.fromhex(NUMS[int(ch)])):
            for i in range(7):
                if bits & (64>>i):
                    l=x+i*scale+(6-j)//3
                    rect(l,y+j*scale,l+scale-1,y+(j+1)*scale-1,col if j<5 else shade)
        x+=8*scale

def dash():
    rect(0,0,255,23,K)
    letters(5,2,'SCORE',AQUA);digits(4,11,'0012840',1,WHITE,GREY)
    letters(70,2,'STAGE',AQUA);digits(69,11,'01',1,WHITE,GREY)
    # A tiny chequer on the stage field and a separate gold clock block.
    for y in range(10,18):
        for x in range(92,101):
            if (x//3+y//2)%2==0:d.point((x,y),GREY)
    rect(112,1,156,21,BLUE)
    letters(114,3,'TIME',WHITE);digits(121,8,'54',2,SAND,WHITE)
    letters(168,2,'GEAR',AQUA);letters(168,12,'HIGH',SAND)
    digits(199,3,'196',2,WHITE,GREY);letters(235,18,'KM/H',AQUA)
    line(0,23,255,23,BLUE)

dist=[[sum(w*(a-b)**2 for w,a,b in zip((3,4,2),u,v)) for v in rgb] for u in rgb]
def encode(row):
    counts=Counter(row); cols=sorted(counts)
    if len(cols)==1:return 0,cols[0]*17
    pair=min(combinations(cols,2),key=lambda uv:sum(n*min(dist[c][uv[0]],dist[c][uv[1]]) for c,n in counts.items()))
    bg,fg=pair
    return sum((128>>i) for i,c in enumerate(row) if dist[c][fg]<dist[c][bg]),fg*16+bg

