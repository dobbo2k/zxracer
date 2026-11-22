"""Draw the Sunny Coast still and its 16 KiB TMS9129 VRAM image for review.

The pattern generator starts at 0000h, names at 1800h, sprite attributes
at 1B00h, colours at 2000h and the 16x16 sprite patterns at 3800h.
Each screen third uses its own 256 names. This is the still-display layout.
"""
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tools"))
from einstein_illustration import *

out = Path(__file__).resolve().parents[3] / "build" / "einstein-study"
out.mkdir(parents=True, exist_ok=True)
background();road();verge()
rival(168,111,.42,GREY);rival(151,138,.95,SAND);spider();dash()

ram=bytearray(16384)
base=Image.new('L',scene.size)
for cy in range(24):
    for cx in range(32):
        name=(cy%8)*32+cx
        ram[0x1800+cy*32+cx]=name
        for j in range(8):
            y=cy*8+j
            row=[scene.getpixel((cx*8+i,y)) for i in range(8)]
            patt,colorset=encode(row)
            addr=cy//8*2048+name*8+j
            ram[addr]=patt;ram[0x2000+addr]=colorset
            for i in range(8):
                base.putpixel((cx*8+i,y),colorset>>4 if patt&(128>>i) else colorset&15)

sprites=[]
def sprite(x,y,pattern,pixels,colour):
    idx=len(sprites)
    ram[0x1b00+4*idx:0x1b04+4*idx]=bytes(((y-1)&255,x,pattern*4,colour))
    for dx,dy in pixels:
        ram[0x3800+pattern*32+(dx//8)*16+dy] |= 128>>(dx%8)
        base.putpixel((x+dx,y+dy),colour)
    sprites.append((x,y))

for r in range(12):
    y=96+8*r
    coords=[]
    for yy in range(y,y+8):
        if not (102<=yy<=103 or 109<=yy<=111 or 120<=yy<=124 or 140<=yy<=148 or yy>=172):continue
        c,w=course(yy)
        for xx in range(c,c+max(1,round(w*.038))):
            if 96<=xx<160 and yy>=160:continue
            if 161<=xx<=174 and 105<=yy<=111:continue
            coords.append((xx,yy))
    left=min((xx for xx,yy in coords), default=0)
    sprite(left,y,r,[(xx-left,yy-y) for xx,yy in coords],WHITE)

for idx,x in enumerate((100,143)):
    points=[(xx,yy) for xx in (1,2,3,8,9,10) for yy in (1,2)]
    sprite(x,178,12+idx,points,RED)
ram[0x1b00+4*len(sprites)]=208
assert max(sum(top<=y<top+16 for _,top in sprites) for y in range(192))<=4
assert len(ram)==16384
(out/'coast.vram').write_bytes(ram)
base.putpalette([val for color in rgb for val in color]+[0]*720)
preview=base.convert('RGB')
preview.save(out/'native.png')
preview.resize((768,576),Image.Resampling.NEAREST).save(out/'review.png')
