"""Original vector embroidery and subtle woven fabric, mapped to cloak UVs."""
from pathlib import Path
from PIL import Image, ImageDraw
import numpy as np
import math

OUT=Path(__file__).resolve().parents[3]/'assets/characters/human/q35/chinese_cloak'

def cloud(draw,x,y,s):
    gold=(184,133,53); pale=(232,190,104)
    # Scalloped ruyi cloud head with a curling stem, drawn as original paths.
    current=(-.40,.15)
    curves=[((-.66,.14),(-.78,-.05),(-.62,-.22)),
            ((-.58,-.43),(-.26,-.55),(-.12,-.38)),
            ((-.02,-.75),(.35,-.65),(.42,-.32)),
            ((.74,-.45),(.88,-.12),(.64,.04)),
            ((.80,.24),(.45,.38),(.30,.20)),
            ((.16,.45),(-.06,.30),(-.12,.16)),
            ((-.26,.32),(-.56,.36),(-.40,.15))]
    outline=[]
    for c1,c2,end in curves:
        for t in np.linspace(0,1,22):
            p=(1-t)**3*np.array(current)+3*(1-t)**2*t*np.array(c1)+3*(1-t)*t*t*np.array(c2)+t**3*np.array(end)
            outline.append((x+p[0]*s,y+p[1]*s))
        current=end
    draw.line(outline,fill=gold,width=max(3,int(s*.04)),joint='curve')
    points=[]
    for t in np.linspace(0,math.pi*3.3,130):
        r=s*(.22-.016*t)
        points.append((x+math.cos(t)*r,y+math.sin(t)*r))
    draw.line(points,fill=pale,width=max(2,int(s*.037)))
    draw.arc((x-s*.68,y-s*.23,x+s*.62,y+s*.52),0,205,fill=gold,width=max(3,int(s*.05)))
    draw.line([(x-s*.63,y+s*.18),(x-s*.94,y+s*.42),(x-s*1.12,y+s*.38)],fill=gold,width=max(2,int(s*.04)))

def make(name,base,kind):
    w=h=2048
    yy,xx=np.indices((h,w)); weave=((xx%4<2)^(yy%4<2))*2-1
    pixels=np.clip(np.array(base)[None,None,:]+weave[:,:,None]*2,0,255).astype('uint8')
    img=Image.fromarray(pixels); d=ImageDraw.Draw(img)
    gold=(188,143,68); dark=(92,65,28)
    for inset,width in [(15,9),(36,3),(60,5)]:
        d.rectangle((inset,inset,w-1-inset,h-1-inset),outline=gold,width=width)
    band=310 if kind=='main' else 470
    d.rectangle((65,h-band,w-66,h-66),fill=tuple(int(c*.8) for c in base))
    d.line((65,h-band,w-65,h-band),fill=dark,width=7)
    for x in range(190,w-100,330): cloud(d,x,h-band*.50,125 if kind=='main' else 150)
    if kind=='main':
        for x in (100,w-100):
            for y in range(230,h-260,230): cloud(d,x,y,52)
    if kind=='collar':
        for x in range(180,w-120,280): cloud(d,x,950,170)
    img.save(OUT/name)

if __name__=='__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    make('cloak_outer.png',(20,19,20),'main')
    make('mantle_outer.png',(23,22,23),'mantle')
    make('collar_outer.png',(26,24,24),'collar')
    make('cloak_lining.png',(113,13,24),'main')
