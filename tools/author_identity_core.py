"""Individually directed Task002C.5 Bank/Predator/Crosscut/Guard pixel cels.

Initial native authoring history, not the normal export command. The four
compositions, key poses, silhouettes and timings below are intentionally
separate. Existing pre-addendum sources are never edited. Saved named-layer
Aseprite masters are authoritative after authoring; --revise explicitly
replaces only these four new masters during this art pass.
"""
import argparse
import json
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageOps
from build_power_art import write_ase, read_ase

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source-art/power_identity_002c5"
DESIGNS = ROOT / "assets/powers/identity"
PALETTE = {
    "ink":"#111b24", "shadow":"#1b2d39", "iron":"#354954",
    "steel":"#617880", "silver":"#afc4c5", "paper":"#e7e5ca",
    "white":"#fff3d1", "brass":"#b88e50", "gold":"#f0c572",
    "rust":"#804537", "red":"#bd5b3c", "hot":"#f29558",
    "sea":"#2f6969", "mint":"#80b7a5", "ice":"#c5e7d6",
    "blue":"#37627b", "pale":"#94b4cb",
}
def rgba(c, a=255):
    return (*bytes.fromhex(PALETTE.get(c,c).lstrip("#")),a)
def layer(size): return Image.new("RGBA",size)
def poly(im, points, c):
    ImageDraw.Draw(im).polygon([(round(x),round(y)) for x,y in points],fill=rgba(c))
def line(im, points, c, w=1):
    ImageDraw.Draw(im).line([(round(x),round(y)) for x,y in points],fill=rgba(c),width=w)
def box(im, xy, c): ImageDraw.Draw(im).rectangle(tuple(round(v) for v in xy),fill=rgba(c))
def oval(im, xy, c): ImageDraw.Draw(im).ellipse(tuple(round(v) for v in xy),fill=rgba(c))
def pixel(im,x,y,c): ImageDraw.Draw(im).point((round(x),round(y)),fill=rgba(c))

def panel(im):
    # Common material, not a common composition: a quiet chamfered card face.
    poly(im,[(7,3),(56,3),(61,8),(61,56),(56,61),(7,61),(3,57),(3,7)],"ink")
    poly(im,[(8,5),(55,5),(59,9),(59,55),(55,59),(8,59),(5,56),(5,8)],"shadow")
    line(im,[(9,6),(54,6)],"iron")
    line(im,[(6,10),(6,54)],"iron")
    for x,y in [(9,9),(55,9),(9,55),(55,55)]: pixel(im,x,y,"steel")

def rotor(im,x,y,r,pose=0,accent="brass",blade="smash"):
    # A physical illustrated top, used only in cards; runtime keeps real tops.
    a=[k*math.tau/12 for k in range(12)]
    edge=[(x+math.cos(t)*r,y+math.sin(t)*r*.54) for t in a]
    poly(im,[(xx,yy+5) for xx,yy in edge],"ink")
    poly(im,[(xx,yy+3) for xx,yy in edge],"iron")
    line(im,[(x-r+2,y+3),(x-r//2,y+r*.54+3),(x+r//2,y+r*.54+3),(x+r-2,y+3)],"steel",2)
    poly(im,edge,"ink")
    for k in range(6):
        t=k*math.tau/6+pose*.19
        outer=[(x+math.cos(z)*r,y+math.sin(z)*r*.54) for z in [t,t+.35,t+.75]]
        inner=[(x+math.cos(z)*(r-5),y+math.sin(z)*(r-5)*.54) for z in [t+.75,t+.35,t]]
        poly(im,outer+inner,"silver" if k in [0,3] else "steel")
        line(im,outer[:2],"paper")
        if blade=="hook":
            tip=(x+math.cos(t+.7)*(r+2),y+math.sin(t+.7)*(r+2)*.54)
            poly(im,[outer[1],outer[2],tip],accent)
        else:
            line(im,[outer[1],outer[2]],accent,2)
    oval(im,(x-r+5,y-r*.54+3,x+r-5,y+r*.54-3),"iron")
    poly(im,[(x-5,y-2),(x,y-4),(x+5,y-2),(x+4,y+2),(x,y+4),(x-4,y+2)],accent)
    line(im,[(x-3,y-2),(x,y-3),(x+2,y-2)],"white")
    box(im,(x-1,y-1,x+1,y+1),"ink");pixel(im,x,y-1,"paper")
    poly(im,[(x-3,y+r*.54+4),(x+3,y+r*.54+4),(x,y+r*.54+11)],"ink")
    line(im,[(x,y+r*.54+4),(x,y+r*.54+9)],"silver")

def spring(im,x1,x2,y,coils=5,deep=False):
    # Flat projected coil: alternating stepped lobes around a real guide rod.
    line(im,[(x1,y+2),(x2,y+2)],"ink",4)
    line(im,[(x1,y),(x2,y)],"steel")
    pitch=(x2-x1)/coils
    for k in range(coils):
        x=x1+k*pitch
        q=[(x,y),(x+pitch*.25,y-3),(x+pitch*.55,y-3),(x+pitch*.85,y+3),(x+pitch,y)]
        line(im,[(a,b+1) for a,b in q],"rust",2)
        line(im,q,"gold" if deep else "brass",2)
        pixel(im,x+pitch*.4,y-3,"white")
    box(im,(x1-2,y-5,x1,y+5),"steel")
    line(im,[(x1-2,y-5),(x1-2,y+4)],"silver")
    box(im,(x2,y-5,x2+2,y+5),"brass")

def bank_card(f,deep):
    im=[layer((64,64)) for _ in range(5)];panel(im[0])
    # Foreground open cassette is the illustration's primary mechanical mass.
    # Coil lobes are new native pixels at this scale, not an enlarged old glyph.
    x=[45,45,44,44,43,43,45,49,51,51,48,45][f]
    y=[18,18,19,20,21,22,20,17,15,15,17,18][f]
    stop=[40,39,37,35,32,30,34,40,44,43,41,40][f]
    oval(im[1],(11,51,49,59),"ink")
    # Deep cast brake shoes, with broad pad faces and fastener recesses.
    poly(im[1],[(5,38),(12,34),(18,38),(18,53),(12,58),(5,53)],"ink")
    poly(im[1],[(6,40),(12,37),(15,40),(15,51),(11,54),(6,51)],"iron")
    line(im[1],[(7,41),(11,39),(13,41)],"silver",2)
    line(im[1],[(7,50),(11,52),(14,50)],"brass",3)
    box(im[1],(9,43,12,46),"ink");pixel(im[1],10,43,"paper")
    poly(im[2],[(10,30),(38,24),(47,29),(47,49),(39,56),(10,50)],"ink")
    poly(im[2],[(11,31),(38,27),(44,30),(14,35)],"steel")
    line(im[2],[(13,31),(37,28),(43,30)],"silver",2)
    poly(im[2],[(11,47),(39,52),(44,48),(44,52),(39,56),(11,50)],"iron")
    line(im[2],[(12,48),(38,53),(43,50)],"brass",2)
    # Exposed helix with wide negative gaps and a clear translating end-stop.
    cy=40 if not deep else 36
    line(im[2],[(14,cy+1),(stop,cy+1)],"steel",3)
    pitch=(stop-14)/4
    for k in range(4):
        xx=14+k*pitch
        q=[(xx,cy),(xx+pitch*.25,cy-6),(xx+pitch*.55,cy-6),(xx+pitch*.86,cy+6),(xx+pitch,cy)]
        line(im[2],[(a,b+1) for a,b in q],"rust",3)
        line(im[2],q,"gold",2)
        line(im[2],q[1:3],"white",2)
    box(im[2],(stop,cy-8,stop+3,cy+8),"brass")
    line(im[2],[(stop+1,cy-7),(stop+1,cy+6)],"paper",2)
    box(im[2],(11,cy-8,14,cy+8),"steel")
    if deep:
        spring(im[2],14,stop,48,4,True)
        box(im[2],(7,31,10,50),"silver")
        line(im[2],[(14,52),(34,55)],"gold",2)
    line(im[2],[(stop+2,cy-2),(46,30),(48,26)],"steel",3)
    rotor(im[3],x,y,12,f,"brass")
    # Braking rails compress behind the shoe, release runs forward into space.
    if f in [1,2,3,4,5]:
        for k in range(3):
            xx=5+k*4
            line(im[4],[(xx,56-k),(xx+3,54-k)],"gold" if f>=4 else "steel",2)
    if f in [6,7,8,9]:
        for k in range(2+(1 if deep else 0)):
            line(im[4],[(x-20-k*4,y+10+k*3),(x-10-k*2,y+5+k*3)],"gold" if k==0 else "brass",2 if k==0 else 1)
        if f==7:poly(im[4],[(38,29),(42,27),(45,29),(41,31)],"white")
    return im

def pressure_tooth(im,x,y,bright=False,size=5):
    # A bent mechanical plate with a broad trailing face and one forward tooth.
    poly(im,[(x-size,y+3),(x-2,y-1),(x+3,y-2),(x+4,y),(x,y+1),(x-size+2,y+5)],"ink")
    poly(im,[(x-size+1,y+2),(x-2,y),(x+2,y-1),(x+3,y),(x,y+2),(x-size+2,y+4)],"hot" if bright else "red")
    line(im,[(x-size+1,y+2),(x-2,y)],"paper" if bright else "brass")

def predator_card(f,deep):
    im=[layer((64,64)) for _ in range(5)];panel(im[0])
    # A quarry high/right and a large low/left hunter create a chase, not a HUD.
    hunter=[(17,43),(17,43),(18,42),(19,41),(20,40),(22,39),(26,37),(28,36),(28,36),(25,38),(21,41),(17,43)][f]
    quarry=[(47,19),(48,18),(49,18),(49,17),(48,17),(48,18),(47,18),(47,19),(48,18),(49,17),(48,18),(47,19)][f]
    line(im[1],[(10,53),(21,46),(34,34),(51,24)],"ink",5)
    line(im[1],[(10,52),(22,44),(34,33),(51,23)],"iron")
    oval(im[1],(hunter[0]-17,hunter[1]+12,hunter[0]+18,hunter[1]+19),"ink")
    oval(im[1],(quarry[0]-8,quarry[1]+9,quarry[0]+9,quarry[1]+12),"ink")
    rotor(im[2],*quarry,9,f,"blue","hook")
    rotor(im[3],*hunter,17,f,"red","smash")
    if deep:
        # Heavy paired leading jaws visibly change the hunter's machine shape.
        for xx,yy in [(hunter[0]+11,hunter[1]-6),(hunter[0]+15,hunter[1])]:
            poly(im[3],[(xx-3,yy+2),(xx+5,yy-4),(xx+9,yy-3),(xx+6,yy+1),(xx,yy+5)],"ink")
            poly(im[3],[(xx-1,yy+2),(xx+5,yy-2),(xx+7,yy-2),(xx+4,yy+1),(xx,yy+3)],"hot")
            line(im[3],[(xx,yy+1),(xx+5,yy-2)],"paper",2)
    steps=[(31,32),(39,27),(45,23)]
    for k,(xx,yy) in enumerate(steps):
        pressure_tooth(im[4],xx,yy,2+k<=f<=8,5)
        if deep:
            pressure_tooth(im[4],xx-4,yy-6,4+k<=f<=9,4)
    if f in [6,7,8]:
        line(im[4],[(hunter[0]-11,hunter[1]+7),(hunter[0]-5,hunter[1]+4)],"hot",2)
        pixel(im[4],41,23,"white")
    # Quarry-facing bite marks stop short of its body, never bracket a reticle.
    if f in [7,8]: line(im[4],[(39,24),(43,21)],"white",2)
    return im

def crosscut_card(f,deep):
    im=[layer((64,64)) for _ in range(5)];panel(im[0])
    # Contact occurs off center; both bodies peel into unequal exit lanes.
    own=[(17,21),(18,22),(20,24),(23,26),(27,29),(31,32),(35,35),(38,38),(42,40),(46,43),(33,34),(21,24)][f]
    rival=[(47,38),(47,38),(47,37),(46,36),(45,35),(43,34),(45,29),(48,25),(50,23),(51,22),(49,30),(48,37)][f]
    line(im[1],[(8,24),(19,32),(31,37)],"iron",2)
    if f>=5:
        line(im[1],[(30,36),(49,49)],"sea",2)
        line(im[1],[(34,35),(51,27)],"iron",2)
    oval(im[1],(own[0]-10,own[1]+11,own[0]+9,own[1]+14),"ink")
    oval(im[1],(rival[0]-9,rival[1]+11,rival[0]+10,rival[1]+14),"ink")
    rotor(im[2],*rival,13,f,"steel","smash")
    rotor(im[3],*own,17,f,"sea","hook")
    if deep:
        poly(im[3],[(own[0]+8,own[1]+4),(own[0]+19,own[1]+7),(own[0]+22,own[1]+5),(own[0]+16,own[1]+1),(own[0]+9,own[1]+1)],"ink")
        line(im[3],[(own[0]+10,own[1]+3),(own[0]+18,own[1]+5),(own[0]+20,own[1]+4)],"silver",2)
    if 3<=f<=9:
        advance=[0,0,0,0,3,8,14,19,23,25,0,0][f]
        # One broad offset shear, deliberately no symmetric X or radial blast.
        poly(im[4],[(27,28),(32,30),(35+advance//2,36+advance//3),(30+advance//2,35+advance//3)],"sea")
        line(im[4],[(29,28),(34,32),(37+advance//2,37+advance//3)],"ice",2)
        if deep:
            line(im[4],[(25,30),(31,35),(39+advance//2,40+advance//3)],"mint")
        if f in [5,6]:
            poly(im[4],[(34,33),(36,32),(38,34),(36,36)],"white")
        if f>=6:
            for k in range(3): line(im[4],[(36+k*5,30-k*2),(39+k*5,29-k*2)],"silver" if k==0 else "steel")
    return im

def damper(im,x,y,length,deep=False):
    # Exposed guide rods and a broad end-stop, not a floor shield/ring.
    poly(im,[(x-2,y-6),(x+5,y-8),(x+6,y+8),(x,y+10),(x-3,y+5)],"ink")
    poly(im,[(x-1,y-5),(x+3,y-6),(x+4,y+6),(x,y+7)],"steel")
    line(im,[(x,y-4),(x+2,y-5)],"paper")
    for yy in [y-3,y+3]:
        line(im,[(x+3,yy+1),(x+length,yy+1)],"ink",3)
        line(im,[(x+3,yy),(x+length,yy)],"silver",2)
        line(im,[(x+3,yy),(x+5,yy)],"brass",2)
    poly(im,[(x+length,y-6),(x+length+4,y-8),(x+length+4,y+5),(x+length,y+7)],"ink")
    line(im,[(x+length+1,y-5),(x+length+1,y+5)],"mint",3)
    line(im,[(x+length+3,y-6),(x+length+3,y+4)],"paper")
    if deep:
        box(im,(x+1,y+9,x+8,y+12),"iron")
        line(im,[(x+1,y+9),(x+7,y+9)],"silver")
        box(im,(x+3,y+10,x+6,y+11),"sea")

def guard_card(f,deep):
    im=[layer((64,64)) for _ in range(5)];panel(im[0])
    ownx=[23,23,23,22,21,20,21,22,23,23,23,23][f]
    hitx=[67,65,63,60,57,55,55,58,61,64,66,67][f]
    length=[14,14,13,11,8,5,6,9,11,13,14,14][f]
    oval(im[1],(7,47,39,56),"ink")
    line(im[1],[(8,52),(18,51),(24,53)],"iron")
    # Incoming machine is cropped; the local absorber is the clear subject.
    rotor(im[2],hitx,24,14,f,"brass","smash")
    rotor(im[3],ownx,31,20,f,"mint","hook")
    # Larger exposed contact mechanism: two rods, chunky face, physical seals.
    gx=ownx+14;gy=34
    poly(im[4],[(gx-3,gy-8),(gx+3,gy-10),(gx+5,gy+8),(gx,gy+11),(gx-3,gy+7)],"ink")
    poly(im[4],[(gx-1,gy-7),(gx+2,gy-8),(gx+3,gy+7),(gx,gy+8)],"steel")
    for yy in [gy-5,gy+5]:
        line(im[4],[(gx+3,yy+2),(gx+length,yy+2)],"ink",4)
        line(im[4],[(gx+3,yy),(gx+length,yy)],"silver",3)
        line(im[4],[(gx+3,yy),(gx+6,yy)],"brass",3)
    poly(im[4],[(gx+length,gy-9),(gx+length+5,gy-12),(gx+length+6,gy+8),(gx+length+1,gy+11)],"ink")
    poly(im[4],[(gx+length+2,gy-7),(gx+length+4,gy-8),(gx+length+4,gy+7),(gx+length+2,gy+8)],"mint")
    line(im[4],[(gx+length+5,gy-9),(gx+length+5,gy+7)],"paper",2)
    if deep:
        poly(im[4],[(gx-2,gy+11),(gx+9,gy+9),(gx+12,gy+12),(gx+4,gy+16),(gx-2,gy+15)],"ink")
        line(im[4],[(gx,gy+11),(gx+8,gy+11),(gx+10,gy+12)],"silver",3)
        box(im[4],(gx+3,gy+12,gx+7,gy+14),"sea")
    if f in [4,5,6]:
        line(im[4],[(ownx+length+14,26),(ownx+length+17,24)],"white",2)
        pixel(im[4],ownx+length+14,39,"gold")
    if f in [5,6]:
        line(im[1],[(8,52),(5,54)],"steel",2)
    return im

CARD_PAINT={"momentum_bank":bank_card,"predator_line":predator_card,"crosscut":crosscut_card,"crash_guard":guard_card}
CARD_TIMES={
    "momentum_bank":[160,100,95,100,140,180,45,40,55,100,180,190],
    "predator_line":[150,100,100,85,85,75,70,65,85,105,150,190],
    "crosscut":[170,110,85,70,55,40,45,55,70,95,160,200],
    "crash_guard":[180,110,85,65,50,75,65,85,105,130,160,200],
}

def icon(family,deep):
    im=[layer((16,16)) for _ in range(2)]
    if family=="momentum_bank":
        box(im[0],(1,3,3,13),"iron");line(im[0],[(1,3),(1,12)],"silver")
        line(im[0],[(3,8),(13,8)],"steel")
        line(im[1],[(3,8),(5,4),(7,11),(9,4),(11,11),(12,8)],"gold",2)
        box(im[0],(12,3,14,12),"steel");line(im[0],[(14,3),(14,11)],"paper")
        if deep:line(im[1],[(4,14),(11,14)],"brass")
    elif family=="predator_line":
        poly(im[0],[(1,10),(5,8),(8,10),(8,13),(4,15),(1,13)],"iron")
        line(im[0],[(1,10),(5,9),(7,10)],"silver",2)
        poly(im[1],[(8,4),(11,1),(15,2),(15,5),(11,7)],"steel")
        line(im[1],[(9,4),(12,2),(14,3)],"paper")
        line(im[1],[(6,8),(8,7),(8,5)],"hot",2)
        if deep:line(im[1],[(9,10),(11,9),(11,7)],"brass")
    elif family=="crosscut":
        poly(im[0],[(1,4),(4,2),(7,4),(5,7),(2,7)],"steel")
        poly(im[0],[(10,8),(13,7),(15,10),(13,12),(10,11)],"iron")
        poly(im[1],[(3,2),(8,7),(14,13),(9,11),(5,7)],"mint")
        line(im[1],[(4,3),(8,7),(13,12)],"paper")
        if deep:line(im[1],[(8,4),(11,3),(14,4)],"steel")
    else:
        box(im[0],(2,3,5,12),"iron");line(im[0],[(2,3),(2,11)],"silver")
        line(im[0],[(5,5),(11,5)],"paper",2)
        line(im[0],[(5,10),(11,10)],"steel",2)
        box(im[1],(11,2,14,13),"sea");line(im[1],[(14,2),(14,12)],"ice")
        if deep:box(im[1],(4,13,9,14),"mint")
    return im

def bank_fx(f,deep,kind):
    im=[layer((96,80)) for _ in range(4)]
    if kind=="bank_stored":
        # Eight physically meaningful charge poses, selected from real charge.
        end=32-f
        spring(im[1],14,end,47,4,deep)
        poly(im[1],[(10,43),(14,41),(14,52),(10,54)],"steel")
        line(im[0],[(9,55),(24,53)],"iron")
        if deep:spring(im[1],13,end-1,55,4,True)
        line(im[2],[(end+2,43),(end+4,41)],"gold")
    elif kind=="bank_load":
        end=[33,30,26,23,22,25,29,32][f]
        spring(im[1],13,end,47,4,deep)
        line(im[0],[(10,56),(25,53)],"steel",2)
        if deep:spring(im[1],12,end-1,54,4,True)
        if f<5:
            for k in range(2):line(im[2],[(8+k*5,49-f//2),(11+k*5,47-f//2)],"gold")
    else:
        extension=[1,3,8,14,20,24,28,32][f]
        if f<4:spring(im[1],14,28+f*3,47,4,deep)
        if f>=1:
            # A sparse released rear line, not an energy ring or large wedge.
            line(im[2],[(14-extension//2,44),(33,37)],"brass",2)
            line(im[2],[(12-extension//2,48),(29,42)],"gold")
            if deep:line(im[2],[(9-extension//3,52),(26,46)],"paper")
        if f in [2,3]:poly(im[3],[(30,40),(34,38),(36,39),(32,42)],"white")
        if f>=4:
            for k in range(2):line(im[0],[(20-f-k*6,48+k*3),(25-f-k*6,46+k*3)],"steel")
    return im

def predator_fx(f,deep,kind):
    im=[layer((96,80)) for _ in range(4)]
    # Root places these physical plate marks on the actual hunter-target axis.
    if kind=="predator_tracking":
        count=min(3,1+f//3)
        for k in range(count):pressure_tooth(im[1],68+k*5,31-k*3,True,4)
        if deep:line(im[2],[(64,36),(72,31)],"brass")
    else:
        travel=[-5,-3,0,3,5,7,9,11][f]
        for k in range(3 if deep else 2):
            if f>=k and f<6+k:
                pressure_tooth(im[1],66+travel+k*5,34-k*3,f in [2+k,3+k],4)
                if f<=3+k:line(im[2],[(60+travel+k*5,38-k*3),(64+travel+k*5,36-k*3)],"rust")
        if f in [3,4]:pixel(im[3],79,25,"white")
    return im

def crosscut_fx(f,deep,_kind):
    im=[layer((96,80)) for _ in range(4)]
    reach=[3,7,14,22,29,34,39,43][f]
    # The contact pivot is the scrape origin. There is no repeated crossed X.
    if f<6:
        poly(im[2],[(46,50),(50,45),(50+reach,45-reach*.42),(48+reach,49-reach*.42)],"sea")
        line(im[2],[(48,47),(53+reach,44-reach*.42)],"ice",2 if f<4 else 1)
        if deep:line(im[1],[(45,54),(52+reach,49-reach*.42)],"mint")
    if f>=2:
        for k in range(3):
            xx=50+k*8+f*2;yy=51+k*3
            line(im[0],[(xx,yy),(xx+5,yy+1)],"steel" if k==0 else "iron")
    if f in [1,2]:poly(im[3],[(47,47),(49,44),(53,46),(51,49)],"white")
    return im

def guard_fx(f,deep,_kind):
    im=[layer((96,80)) for _ in range(4)]
    length=[15,13,9,5,4,7,11,15][f]
    # Empty center preserves the actual top. Absorber lives on incoming side.
    damper(im[1],65,36,length,deep)
    if f in [2,3]:
        line(im[3],[(66+length,26),(70+length,24)],"paper",2)
        line(im[2],[(69+length,43),(73+length,45)],"brass")
    if f>=3:line(im[0],[(62,54),(68,56),(72,55)],"iron")
    return im

HEADINGS={"e":(1,0),"se":(.7071,.7071),"s":(0,1),"sw":(-.7071,.7071),"w":(-1,0),"nw":(-.7071,-.7071),"n":(0,-1),"ne":(.7071,-.7071)}

def shift_cels(cells,dx,dy):
    # Integer translation retains upright authored machinery; no image rotation
    # or resampling is used to synthesize projected heading variants.
    out=[layer((96,80)) for _ in cells]
    for dest,src in zip(out,cells):dest.alpha_composite(src,(round(dx),round(dy)))
    return out

def directed_tooth(im,x,y,v,bright,size=5):
    vx,vy=v;px,py=-vy,vx
    def p(forward,side):return(x+vx*forward+px*side,y+vy*forward+py*side)
    poly(im,[p(-size,3),p(-size,-3),p(1,-3),p(5,0),p(0,2)],"ink")
    poly(im,[p(-size+1,2),p(-size+1,-2),p(1,-2),p(4,0),p(0,1)],"hot" if bright else "red")
    line(im,[p(-size+1,-2),p(1,-2)],"paper" if bright else "brass")

def headed_fx(family,f,deep,kind,heading):
    vx,vy=HEADINGS[heading];perp=(-vy,vx)
    if family=="momentum_bank":
        cells=bank_fx(f,deep,kind)
        # Behind the contact plane. Vertical reach is bounded to the 80px cel.
        cells=shift_cels(cells,48-vx*25-23,48-vy*17-47)
        if kind=="bank_release":
            cells[2]=layer((96,80));cells[3]=layer((96,80))
            for k in range(3 if deep else 2):
                lateral=(k-1)*4
                start=(48-vx*(15+f*2)+perp[0]*lateral,42-vy*(15+f*2)+perp[1]*lateral)
                end=(48-vx*11+perp[0]*lateral,42-vy*11+perp[1]*lateral)
                if 1<=f<=5:line(cells[2],[start,end],"gold" if k==0 else "brass",2 if k==0 else 1)
            if f in [2,3,4]:
                line(cells[3],[(48+vx*18,42+vy*18),(48+vx*(22+f),42+vy*(22+f))],"paper",2)
        return cells
    if family=="predator_line":
        cells=[layer((96,80)) for _ in range(4)]
        tracking=kind=="predator_tracking"
        count=min(3,1+f//3) if tracking else (3 if deep else 2)
        for k in range(count):
            if not tracking and (f<k or f>=6+k):continue
            distance=(k-1)*7 if tracking else 18+k*6+min(f,4)*2
            x=48+vx*distance;y=(48 if tracking else 34)+vy*distance
            directed_tooth(cells[1],x,y,(vx,vy),tracking or f in [2+k,3+k],4)
            if deep and tracking:
                line(cells[2],[(x-vx*3+perp[0]*4,y-vy*3+perp[1]*4),(x+vx*3+perp[0]*4,y+vy*3+perp[1]*4)],"brass")
        return cells
    if family=="crosscut":
        cells=[layer((96,80)) for _ in range(4)]
        reach=[3,6,10,15,19,23,25,28][f]
        def p(forward,side):return(48+vx*forward+perp[0]*side,48+vy*forward+perp[1]*side)
        if f<6:
            poly(cells[2],[p(-3,2),p(1,-3),p(reach,-2),p(reach-3,2)],"sea")
            line(cells[2],[p(0,-1),p(reach+2,-2)],"ice",2 if f<4 else 1)
            if deep:line(cells[1],[p(-3,5),p(reach,4)],"mint")
        if f>=2:
            for k in range(3):line(cells[0],[p(5+k*5,5+k*2),p(9+k*5,6+k*2)],"steel" if k==0 else "iron")
        if f in [1,2]:poly(cells[3],[p(-1,-3),p(2,-4),p(5,-1),p(2,1)],"white")
        return cells
    cells=guard_fx(f,deep,kind)
    cells=shift_cels(cells,48+vx*26-73,34+vy*20-36)
    cells[2]=layer((96,80));cells[3]=layer((96,80))
    if f in [2,3,4]:
        x=48+vx*32;y=34+vy*25
        line(cells[3],[(x+vx*3,y+vy*3),(x+vx*6,y+vy*6)],"paper",2)
        line(cells[2],[(x-vx*1+perp[0]*5,y-vy*1+perp[1]*5),(x+vx*3+perp[0]*5,y+vy*3+perp[1]*5)],"brass")
    return cells

FX_PAINT={"momentum_bank":bank_fx,"predator_line":predator_fx,"crosscut":crosscut_fx,"crash_guard":guard_fx}
FX_TAGS={"momentum_bank":["bank_load","bank_stored","bank_release"],"predator_line":["predator_pressure","predator_tracking"],"crosscut":["shear_slice"],"crash_guard":["damper_contact"]}
FX_TIMES={"momentum_bank":[75,55,45,70,95,90,140,180],"predator_line":[65,55,60,85,75,85,105,155],"crosscut":[60,35,40,45,65,90,140,180],"crash_guard":[75,45,40,65,80,100,130,180]}

GRAMMARS={
"momentum_bank":{"silhouette":"rear open spring cassette and broad brake shoe, forward moving top","motion":"gradual compression, held load, abrupt extension and sparse directed release","location":"rear braking side/contact plane; release follows actual movement vector","persistence":"real charge stages while stored; compression/release are events","palette":"brass, graphite, warm ivory with steel mount","feature":"visible helical coil pitch shrinks as real stored force rises"},
"predator_line":{"silhouette":"unequal two-top rising chase and short serrated pressure comb","motion":"quarry leads, hunter closes; sequential teeth bite one chase line","location":"actual hunter-to-rival axis, never a radial HUD reticle","persistence":"target-related while actual hunt is live, plus brief accepted-contact pressure","palette":"oxidized iron and vermilion hunter against cool steel quarry","feature":"directional pressure teeth repeat toward exactly one physical rival"},
"crosscut":{"silhouette":"offset glancing bodies, oblique stepped shear ribbon and forked skid","motion":"fast approach, narrow lateral contact, unequal divergent exits","location":"glancing contact and actual lateral displacement vector","persistence":"brief paid glancing event, sparse follow-through scar","palette":"sea green, bone and desaturated steel","feature":"one asymmetric slash and split skid, no symmetric X or ring"},
"crash_guard":{"silhouette":"contact-side telescoping twin rods and broad end-stop","motion":"incoming compression, mechanical shortening, damped rebound","location":"incoming contact side of real top, no floor fortress","persistence":"contact event only; no automatically orbiting shield","palette":"cool gray steel, pale mint faceplate and restrained brass seals","feature":"an exposed piston physically changes length rather than expanding an aura"},
}
EVENTS={"momentum_bank":{"momentum_store":"bank_load","momentum_release":"bank_release"},"predator_line":{"predator_lock":"predator_pressure"},"crosscut":{"crosscut":"shear_slice"},"crash_guard":{"crash_guard":"damper_contact"}}

def preview_sources(paths,review):
    if not review:return
    review.mkdir(parents=True,exist_ok=True)
    for p in paths:
        flat,meta=read_ase(p)
        columns=12 if p.stem.endswith("_cards") else 2 if p.stem.endswith("_icons") else 8
        w,h=meta["cell"];sheet=Image.new("RGBA",(w*columns,h*math.ceil(len(flat)/columns)),rgba("ink"))
        for i,img in enumerate(flat):sheet.alpha_composite(img,(i%columns*w,i//columns*h))
        sheet.save(review/(p.stem+".png"));ImageOps.grayscale(sheet).save(review/(p.stem+"_gray.png"))
        if p.stem.endswith("_cards"):
            index={"momentum_bank":5,"predator_line":7,"crosscut":6,"crash_guard":5}[p.stem[:-6]]
            flat[index].save(review/(p.stem+"_single.png"))
            flat[index].resize((512,512),Image.Resampling.NEAREST).save(review/(p.stem+"_single_nearest.png"))

def make(family,revise,review,cards_only=False,fx_only=False):
    SOURCE.mkdir(parents=True,exist_ok=True);DESIGNS.mkdir(parents=True,exist_ok=True)
    paths=[SOURCE/f"{family}_{group}.aseprite" for group in ["cards","icons","fx"]]
    if not revise and any(p.exists() for p in paths):raise RuntimeError(f"Refusing native artist overwrite for {family}; use --revise only during this owned art pass")
    cards=[];icons=[];tags=[];times=[]
    for deep in [False,True]:
        tag=family+("_ii" if deep else "");start=len(cards)
        for f in range(12):cards.append(CARD_PAINT[family](f,deep))
        tags.append((tag,start,len(cards)-1));times.extend(CARD_TIMES[family])
        icons.append(icon(family,deep))
    named={"momentum_bank":"rear brake and open spring cassette","predator_line":"quarry and pursuing hunter","crosscut":"glancing bodies and divergent exits","crash_guard":"incoming contact and telescoping rods"}[family]
    if not fx_only:write_ase(paths[0],cards,["01 quiet chamfered card","02 floor depth and scars",f"03 {named}","04 physical top illustration","05 force response and key highlights"],tags,times,(32,32),note=f"Task002C.5 bespoke {family}; individually keyed 12-pose physical story; fixed projected integer pixels; native layers editable",palette=PALETTE)
    if cards_only:
        preview_sources([paths[0]],review)
        print(f"{family}: card-only composition revision; separate icons and bounded FX retained")
        return
    itags=[(family,0,0),(family+"_ii",1,1)]
    if not fx_only:write_ase(paths[1],icons,["01 purpose-designed mechanism silhouette","02 identifying force and rank structure"],itags,[150,150],(8,8),note=f"Dedicated 16px {family} recognition; not a reduced card or full FX",palette=PALETTE)
    fx=[];ftags=[];ftimes=[]
    for base in FX_TAGS[family]:
        for deep in [False,True]:
            for heading in HEADINGS:
                tag=base+("_ii" if deep else "")+"_"+heading;start=len(fx)
                for f in range(8):
                    fx.append(headed_fx(family,f,deep,base,heading))
                ftags.append((tag,start,len(fx)-1));ftimes.extend(FX_TIMES[family])
    write_ase(paths[2],fx,["01 contact scar and ground depth",f"02 {named}","03 mechanical force direction","04 contact accents and fragments"],ftags,ftimes,(48,48),note=f"Task002C.5 {family}; eight authored event/stage poses across all eight projected headings; upright fixed-isometric mechanisms; no rotation/resampling; actual runtime top stays visible",palette=PALETTE)
    static={"momentum_bank":5,"predator_line":7,"crosscut":6,"crash_guard":5}[family]
    design={"family":family,"initial_tier":"C","target_tier":"A or B after runtime motion review","grammar":GRAMMARS[family],"static_frames":{family:static,family+"_ii":static},"event_tags":EVENTS[family],"notes":["New individually directed native master; old source retained for before/after.","Anticipation, action, reaction and follow-through are separate authored poses, not a uniformly spinning six-frame loop.","Rank II adds physical structure rather than palette substitution.","Cards illustrate actual machines; FX deliberately omit replacement rotors to keep gameplay subjects visible.","Icon is a separately drawn small-scale silhouette.","All eight projected headings have native keyed placements/strokes. Machinery stays upright; no sprite rotation/resampling. No duplicate base tags: directional variants cover every actual heading while the largest bank sheet remains below 4096 pixels tall."]}
    if family=="momentum_bank":
        design["active_tags"]={"stored":"bank_stored"}
        design["notes"].append("bank_stored is eight charge stages: select by actual momentum_charge/cap, do not auto-play the charge filling. bank_load is only the contact/compression event.")
    if family=="predator_line":
        design["active_tags"]={"tracking":"predator_tracking"}
        design["notes"].append("Tracking frame stages map actual hunt_stacks 1/2/3 to 0/3/6; place marks on the real hunter-target segment, never draw a target reticle.")
    (DESIGNS/f"{family}_design.json").write_text(json.dumps(design,indent=2)+"\n",encoding="utf-8")
    preview_sources(paths,review)
    print(f"{family}: 24 card poses, 2 designed icons, {len(fx)} directional FX poses; native masters authored")

def main():
    parser=argparse.ArgumentParser();parser.add_argument("--family",choices=list(CARD_PAINT));parser.add_argument("--revise",action="store_true");parser.add_argument("--review",type=Path);parser.add_argument("--cards-only",action="store_true");parser.add_argument("--fx-only",action="store_true")
    args=parser.parse_args()
    assert not(args.cards_only and args.fx_only)
    for family in [args.family] if args.family else CARD_PAINT:make(family,args.revise,args.review,args.cards_only,args.fx_only)
if __name__=="__main__":main()
