"""Native pixel compositions for Wake, Chain, Centre and Afterimage.

This is an explicit authoring recipe, not the export authority. Saved named-layer
Aseprite masters are the authority after creation; export_power_identity reads
them and checks native Aseprite parity. Original accepted masters are read-only.
Each mechanic has its own composition and twelve deliberately staged card keys.
"""
from pathlib import Path
import argparse
import json
import math
import struct
import zlib
from PIL import Image, ImageDraw, ImageOps, ImageFont
from build_power_art import write_ase, read_ase

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source-art/power_identity_002c5"
OUT = ROOT / "assets/powers/identity"
PALETTE = {
    "deep": "#101923", "shadow": "#172631", "slate": "#2b404d",
    "steel": "#49636e", "edge": "#77929b", "silver": "#b5ced0",
    "light": "#ebf1dc", "blue": "#235d7b", "cyan": "#409fc0",
    "ice": "#9be4e5", "green": "#3d947e", "mint": "#b2efd1",
    "oxide": "#9c4531", "copper": "#d57943", "amber": "#efb95e",
    "dust": "#807760", "ash": "#423f3b", "dark_red": "#592a28",
}
LAYERS = ["01 floor and contact shadow", "02 load-bearing machine bodies",
          "03 mechanical jaws and bearings", "04 transmitted action and route",
          "05 reaction chips and key light", "06 developed structure"]
HEADINGS={"e":(1,0),"se":(.707,.707),"s":(0,1),"sw":(-.707,.707),
          "w":(-1,0),"nw":(-.707,-.707),"n":(0,-1),"ne":(.707,-.707)}

def ink(name, alpha=255):
    value = PALETTE.get(name, name).lstrip("#")
    return (*bytes.fromhex(value), alpha)

def layers(size): return [Image.new("RGBA", size) for _ in LAYERS]
def draw(im): return ImageDraw.Draw(im)
def line(im, points, c, width=1): draw(im).line([(round(x), round(y)) for x,y in points], fill=ink(c), width=width)
def poly(im, points, c): draw(im).polygon([(round(x), round(y)) for x,y in points], fill=ink(c))
def rect(im, box, c): draw(im).rectangle(tuple(round(v) for v in box), fill=ink(c))

def floor(im, corners, seams=()):
    poly(im,corners,"shadow")
    line(im,corners+[corners[0]],"slate")
    for seam in seams: line(im,seam,"slate")

def card_bed(ims):
    # A quiet UI bevel is shared; the illustrated floor and mechanical story
    # inside it are composed separately, rather than cloned from a power FX.
    rim=[(3,8),(8,3),(56,3),(61,8),(61,56),(56,61),(8,61),(3,56)]
    poly(ims[0],rim,"deep")
    line(ims[0],rim+[rim[0]],"slate")
    line(ims[0],[(5,9),(9,5),(54,5)],"steel")
    line(ims[0],[(59,12),(59,54),(54,59),(11,59)],"shadow",2)
    for x,y in [(8,9),(55,9),(8,54),(55,54)]:
        rect(ims[0],(x,y,x+1,y+1),"edge")

def floor_rail(im,points,c="cyan",width=3,teeth=False):
    # A gouged mechanical floor rail has a dark cut, a displaced steel lip,
    # and a single bright running edge. It is not a floating light wire.
    line(im,[(x,y+3) for x,y in points],"deep",width+3)
    line(im,[(x,y+1) for x,y in points],"steel",width+2)
    line(im,points,c,width)
    line(im,[(x,y-1) for x,y in points],"ice" if c=="cyan" else "mint",1)
    if teeth:
        for j,(x,y) in enumerate(points):
            if j%2==0:
                tooth(im,x-2,y+3,1,"silver",3)

def machine(ims,x,y,r,phase=0,accent="cyan",heavy=False):
    """A layered physical machine; the bit contacts y+r*.65+7.

    Shared mechanical anatomy is intentional. Its location, scale, action and
    surrounding story are authored separately for every family and state.
    """
    shadow,body,detail=ims[0],ims[1],ims[2]
    contact=y+r*.65+7
    poly(shadow,[(x-r+1,contact),(x,contact-3),(x+r-1,contact),(x,contact+3)],"deep")
    poly(body,[(x-3,y+4),(x+3,y+4),(x+2,contact),(x,contact+2),(x-2,contact)],"deep")
    points=[(x-r,y-2),(x-r+3,y-6),(x-3,y-r*.52),(x+5,y-r*.5),(x+r-2,y-4),(x+r,y+1),(x+r-3,y+6),(x+4,y+r*.6),(x-5,y+r*.6),(x-r+1,y+4)]
    depth=6 if heavy else 4
    poly(body,[(a,b+depth) for a,b in points],"deep")
    poly(body,[(x-r+1,y+2),(x-5,y+r*.6+depth),(x+5,y+r*.6+depth),(x+r-2,y+3)],"slate")
    poly(body,points,"steel")
    # The spindle emerges below the front bearing; drawing it through the
    # visible mass would make the grounded top read as a floating pedestal.
    line(detail,[(x,y+r*.6+depth-1),(x,contact)],"silver",2 if heavy else 1)
    poly(body,[(x-r+4,y-4),(x-4,y-r*.52+2),(x+4,y-r*.5+2),(x+r-4,y-3),(x+4,y+2),(x-4,y+2)],"edge")
    line(detail,points[:5],"silver")
    line(detail,[(x-r+1,y+3),(x-4,y+r*.5+3),(x+4,y+r*.5+3),(x+r-3,y+3)],accent,2)
    if r>=12:
        for sign in [-1,1]:
            poly(detail,[(x+sign*(r-2),y-3),(x+sign*(r+1),y),(x+sign*(r-2),y+5),(x+sign*(r-6),y+3)],"silver")
            rect(detail,(x+sign*(r-5),y+4,x+sign*(r-5)+1,y+5),"deep")
        for offset in [-5,0,5]:
            line(detail,[(x+offset,y+r*.5+5),(x+offset+1,y+r*.5+5)],"edge")
    for k in range(4):
        a=(phase%8)*math.pi/4+k*math.pi/2
        p=[(x+math.cos(a)*r*.42,y+math.sin(a)*r*.21),(x+math.cos(a+.17)*r*.86,y+math.sin(a+.17)*r*.43),(x+math.cos(a+.50)*r*.86,y+math.sin(a+.50)*r*.43),(x+math.cos(a+.57)*r*.42,y+math.sin(a+.57)*r*.21)]
        poly(detail,p,"light" if k%2==0 else "edge")
    poly(detail,[(x-5,y-2),(x-2,y-4),(x+3,y-4),(x+5,y-1),(x+2,y+2),(x-3,y+2)],"deep")
    poly(detail,[(x-2,y-3),(x+2,y-3),(x+3,y-1),(x,y+1),(x-3,y-1)],accent)
    rect(detail,(x,y-3,x+1,y-3),"light")

def sparks(im,x,y,f,c="amber",length=4):
    # Three discrete contact chips with unequal spacing, never a circular burst.
    for dx,dy,k in [(-1,-1,0),(1,-1,2),(-1,1,4)]:
        d=2+f*(1+k*.12)
        line(im,[(x+dx*d,y+dy*d*.5),(x+dx*(d+length),y+dy*(d*.5+2))],c)

def tooth(im,x,y,sign=1,c="silver",size=3):
    poly(im,[(x,y),(x+sign*size,y-size*.5),(x+sign*(size+1),y+2),(x+sign,y+3)],c)

def socket(im,x,y,c="ice",closed=False):
    line(im,[(x-4,y-2),(x-4,y+2),(x-1,y+3)],c)
    line(im,[(x+4,y-2),(x+4,y+2),(x+1,y+3)],c)
    if closed: line(im,[(x-2,y),(x+2,y)],"light",2)

def erode_material(ims,key):
    # Broken bearing blocks peel in authored two-pixel material clusters.
    # Kept clusters remain opaque normal RGBA, so layered native export is
    # exact rather than depending on two alpha-compositor rounding models.
    remaining=max(0,8-key)
    for im in ims:
        pixels=im.load()
        for y in range(im.height):
            for x in range(im.width):
                if ((x//2)+3*(y//2))%8>=remaining: pixels[x,y]=(0,0,0,0)

def layered_source(path):
    """Retain the accepted Wake illustration's actual editable layer cels."""
    flat,meta=read_ase(path);data=path.read_bytes();at=128;all_cells=[];result=[]
    for f in range(len(flat)):
        length,magic,old,duration,new=struct.unpack_from("<IHHH2xI",data,at)
        assert magic==0xF1FA
        pos=at+16;cells={}
        for _ in range(new or old):
            n,kind=struct.unpack_from("<IH",data,pos);payload=data[pos+6:pos+n]
            if kind==0x2005:
                layer,x,y,opacity,typ,z=struct.unpack_from("<HhhBHh",payload)
                assert z==0 and opacity==255
                if typ==1: im=all_cells[struct.unpack_from("<H",payload,16)[0]][layer].copy()
                else:
                    w,h=struct.unpack_from("<HH",payload,16);raw=zlib.decompress(payload[20:]) if typ==2 else payload[20:]
                    im=Image.frombytes("RGBA",(w,h),raw)
                target=Image.new("RGBA",tuple(meta["cell"]));target.alpha_composite(im,(x,y));cells[layer]=target
            pos+=n
        all_cells.append(cells)
        result.append([cells.get(i,Image.new("RGBA",tuple(meta["cell"]))).copy() for i in range(len(meta["layers"]))])
        at+=length
    return result,meta

def wake_cards():
    accepted,meta=layered_source(ROOT/"assets/source-art/power_cards_002b1.aseprite")
    first=int(meta["tags"]["impact_wake"]["from"]);frames=[]
    for state in range(2):
        for key in range(12):
            # I is pixel-identical to the strongest accepted six authored poses.
            ims=[im.copy() for im in accepted[first+key//2]]
            ims.append(Image.new("RGBA",(64,64)))
            if state:
                action=ims[-1];r=[8,8,12,12,17,17,21,21,24,24,25,25][key]
                for dx,dy in [(-1,-1),(1,-1),(-1,1),(1,1)]:
                    x=32+dx*r*.85;y=38+dy*r*.40
                    tooth(action,x,y,dx,"silver",4)
                    line(action,[(x-dx*3,y+3),(x-dx*5,y+4)],"blue",2)
                if 3<=key<=8:
                    for x,y in [(13,25),(48,31),(23,49)]: line(action,[(x,y),(x+3,y-2)],"ice",2)
            frames.append(ims)
    old=meta["layers"]
    durations=[55,55,45,45,38,37,38,37,50,50,85,85]*2
    return frames,old+["Rank II counter-pressure teeth"],[("impact_wake",0,11),("impact_wake_ii",12,23)],durations

def chain_card(tag,k):
    ims=layers((64,64));deep=tag.endswith("_ii")
    card_bed(ims)
    floor(ims[0],[(5,39),(41,7),(58,19),(58,41),(35,58),(5,58)], [[(8,52),(49,16)],[(24,58),(58,29)]])
    # The first receiver is a large foreground subject. Two visibly smaller
    # opponents provide depth, and the relay travels from front-left to back.
    positions=[(20,39,15),(39,28,11),(51,15,8)]
    stage=[-1,-1,0,0,0,1,1,1,2,2,2,2][k]
    for j,(x,y,r) in reversed(list(enumerate(positions))):
        kick=(2 if deep else 1) if stage==j and k>=3 else 0
        machine(ims,x+kick,y-kick,r,k+j*2,"copper" if j<=stage else "dust",j==0)
    # Broad fracture surfaces occupy the spaces between actual contacts; only
    # the currently reached receiver has a bright compressed contact tooth.
    for j in range(1,3):
        a=positions[j-1];x,y,r=positions[j]
        p=[(a[0]+9,a[1]-1),(a[0]+14,a[1]-5),(x-7,y+6)]
        line(ims[3],p,"dark_red",5 if deep else 3)
        line(ims[3],[(px,py-1) for px,py in p],"copper",2)
        if j<=stage:
            line(ims[3],p,"amber",2)
            tooth(ims[3],x-8,y+6,1,"light",5)
            if j==stage: sparks(ims[4],x-8,y+6,k%3,"light",3)
        if deep:
            line(ims[5],[(a[0]+10,a[1]+3),(x-7,y+10)],"steel",3)
            line(ims[5],[(a[0]+12,a[1]+2),(x-7,y+9)],"silver")
    if k<3:
        poly(ims[3],[(4,48),(12,44),(13,48),(7,52)],"oxide")
        line(ims[3],[(4,48),(10+k,45),(13,45)],"amber",2)
    if k>=9:
        for x,y in [(31,45),(47,33)]: line(ims[4],[(x,y),(x+2,y-2)],"copper")
    return ims

def jaw(im,x,y,dx,dy,weight=1,lit=False):
    # Paired load-bearing plates with a stepped inward tooth and dark underside.
    a=(x,y);b=(x+dx*7,y+dy*3);c=(x+dx*7,y+dy*3+3+weight);d=(x,y+3+weight)
    poly(im,[a,b,c,d],"deep")
    poly(im,[(x,y),(x+dx*7,y+dy*3),(x+dx*6,y+dy*3+2),(x,y+2)],"steel")
    line(im,[a,b],"silver" if lit else "edge",2 if weight>1 else 1)
    tooth(im,x,y,-dx,"ice" if lit else "silver",3)

def weight_jaw(ims,x,y,sign,gap,k,heavy=False,bounds=(5,59)):
    # A substantial bearing block, wide footprint and inward stepped face.
    # Its face moves toward the bit as the mass settles, instead of sprouting
    # weightless spider legs from the machine's silhouette.
    outer=max(bounds[0],min(bounds[1],x+sign*(22+gap*.45)));inner=x+sign*(7+gap)
    top=y-4;bottom=y+7+(2 if heavy else 0)
    points=[(outer,top),(inner,top-3),(inner-sign*2,top),(inner-sign*2,bottom-2),(outer,bottom)]
    poly(ims[1],[(a,b+3) for a,b in points],"deep")
    poly(ims[2],points,"slate")
    poly(ims[2],[(outer,top),(inner,top-3),(inner,top),(outer,top+4)],"steel")
    line(ims[2],[(outer,top),(inner,top-3),(inner-sign*2,top)],"silver",2)
    line(ims[2],[(inner-sign*2,top+1),(inner-sign*2,bottom-3)],"ice" if k>=4 else "edge",2)
    for j in range(2):
        bx=outer-sign*(3+j*5)
        rect(ims[2],(bx-1,top+4,bx+1,top+6),"deep")
        rect(ims[2],(bx,top+4,bx,top+4),"silver")
    line(ims[0],[(outer+sign*2,bottom+3),(outer+sign*4,bottom+5)],"ash",2)

def centre_card(tag,k):
    ims=layers((64,64));deep=tag!="dead_centre";bulwark=tag=="bulwark";counter=tag=="counterweight"
    card_bed(ims)
    floor(ims[0],[(5,31),(30,17),(58,33),(58,51),(35,59),(5,51)], [[(7,47),(32,31),(55,45)],[(21,57),(42,44)]])
    settle=[0,0,1,1,2,3,3,3,3,2,2,2][k];x=41 if counter else 32;y=24+settle
    machine(ims,x,y,18 if not counter else 16,k,"silver",True)
    contact=(x,y+18)
    rect(ims[2],(x-5,contact[1]-1,x+5,contact[1]+3),"deep")
    line(ims[2],[(x-4,contact[1]),(x+4,contact[1])],"silver",2)
    gap=[6,6,5,4,2,1,0,0,0,0,1,2][k]
    # Front bearing jaws span 44–49 pixels at native size and carry the mass.
    for sign in [-1,1]:
        weight_jaw(ims,x,contact[1]+2,sign,gap,k,bulwark)
    if deep:
        for sign in [-1,1]:
            jaw(ims[5],x+sign*(17+gap*.5),contact[1]-9,-sign,1,3,k>=4)
        line(ims[5],[(x-15,contact[1]-7),(x-9,contact[1]-3)],"silver",2)
        line(ims[5],[(x+15,contact[1]-7),(x+9,contact[1]-3)],"silver",2)
    if bulwark:
        # The attack meets planted mass; its fragments peel back out of the card.
        machine(ims,11,13,9,k,"copper")
        line(ims[3],[(5,26),(12,24),(20,29)],"copper",3)
        if 3<=k<=8:
            sparks(ims[4],18,28,k-3,"amber",4)
            line(ims[4],[(15,26),(9,21),(5,22)],"light",2)
    elif counter:
        # Side-view load cylinder and teeth are the composition, not a halo.
        poly(ims[1],[(5,29),(18,23),(30,32),(30,46),(17,53),(5,44)],"deep")
        poly(ims[2],[(5,28),(18,22),(28,29),(28,42),(16,49),(5,42)],"steel")
        poly(ims[2],[(5,28),(18,22),(28,29),(16,36)],"edge")
        line(ims[2],[(5,28),(18,22),(28,29)],"silver",2)
        line(ims[2],[(6,43),(16,49),(28,42)],"slate",2)
        compression=[7,6,5,4,3,2,2,2,3,5,7,8][k]
        for j in range(4):
            px=7+j*compression/2
            poly(ims[3],[(px,32-j),(px+3,30-j),(px+5,33-j),(px+2,36-j)],"amber" if j<=k//2 else "slate")
            line(ims[3],[(px,32-j),(px+3,30-j)],"light" if j<=k//2 else "edge")
        line(ims[3],[(25,33),(34,37)],"copper",3)
        line(ims[3],[(26,32),(34,36)],"light")
        if 8<=k<=10: sparks(ims[4],30,35,k-8,"light",4)
    elif 4<=k<=8:
        for px,py in [(12,47),(51,43),(28,57)]: line(ims[4],[(px,py),(px+2,py)],"dust")
    return ims

ROUTE_I=[(7,53),(16,48),(24,49),(34,40),(42,33),(49,29)]
ROUTE_II=[(7,51),(17,47),(30,34),(29,17),(14,23),(20,43),(39,43),(53,31)]
GHOST=[(10,43),(13,22),(31,11),(52,20),(55,42),(37,55),(12,50)]

def route(im,points,c="cyan",width=2,nodes=False):
    line(im,points,c,width)
    if nodes:
        for x,y in points:
            poly(im,[(x-2,y),(x,y-1),(x+2,y),(x,y+1)],"silver")

def afterimage_card(tag,k):
    ims=layers((64,64))
    card_bed(ims)
    floor(ims[0],[(5,35),(32,8),(59,24),(59,43),(35,59),(5,55)], [[(7,47),(45,11)],[(17,58),(54,20)],[(9,28),(49,52)]])
    if tag=="ghost_circuit":
        floor_rail(ims[0],GHOST,"green",3,True)
        close=3<=k<=9
        if close: floor_rail(ims[0],[GHOST[-1],GHOST[0]],"green",3)
        socket(ims[4],10,45,"mint",close)
        # A rival is enclosed; the subject is a route-machine, not a aura.
        machine(ims,32,33,10,k,"dust")
        machine(ims,46,18,13,k,"mint")
        if 5<=k<=8:
            line(ims[4],[(16,40),(23,36)],"mint",2);line(ims[4],[(45,39),(38,35)],"mint",2)
            sparks(ims[4],31,36,k-5,"light",2)
        for j,(x,y) in enumerate(GHOST[:-1]):
            if (j+k)%5==0: tooth(ims[5],x,y,1,"mint",2)
    elif tag=="slipstream":
        floor_rail(ims[0],[(6,24),(28,40),(55,54)],"blue",3,True)
        floor_rail(ims[0],[(8,54),(29,38),(52,17)],"cyan",3,True)
        p=[(20,43),(20,43),(23,40),(28,37),(32,33),(37,29),(43,24),(49,19),(51,18),(52,18),(52,18),(52,18)][k]
        machine(ims,*p,14,k,"ice")
        if 3<=k<=8:
            socket(ims[4],29,37,"light",True)
            for j in range(3): line(ims[4],[(p[0]-10-j*7,p[1]+5+j*4),(p[0]-5-j*7,p[1]+2+j*4)],"ice",2)
    else:
        points=ROUTE_II if tag.endswith("_ii") else ROUTE_I
        floor_rail(ims[0],points,"cyan",3,tag.endswith("_ii"))
        if tag.endswith("_ii"):
            floor_rail(ims[0],[(9,27),(26,40),(49,53)],"blue",2,True)
            if 4<=k<=7: socket(ims[4],27,37,"ice",True)
        # The leading top lives away from the centre. The route occupies space.
        x,y=[(24,38),(24,38),(28,35),(32,32),(37,29),(42,26),(45,23),(47,21),(47,21),(47,21),(46,22),(45,23)][k]
        machine(ims,x,y,15,k,"ice")
        for j,(px,py) in enumerate(points[:-2]):
            if j%2==0: line(ims[4],[(px-3,py+1),(px,py-1)],"ice")
    return ims

def icon(family,tag):
    ims=[Image.new("RGBA",(16,16)),Image.new("RGBA",(16,16))];base,detail=ims
    deep=tag.endswith("_ii")
    if family=="impact_wake":
        # Independent HUD drawing: a heavy centre and four outward pressure teeth.
        poly(base,[(5,5),(10,5),(12,8),(9,11),(5,10),(3,7)],"steel")
        line(detail,[(5,6),(9,6),(10,8)],"light");rect(detail,(6,8,8,9),"cyan")
        for x,y,dx,dy in [(1,4,-1,-1),(12,3,1,-1),(12,11,1,1),(1,11,-1,1)]: line(detail,[(x,y),(x+dx*2,y+dy)],"ice",2)
        if deep: line(base,[(2,2),(4,1),(7,1)],"silver");line(base,[(8,14),(11,14),(13,12)],"silver")
    elif family=="chain_impact":
        for j,(x,y) in enumerate([(3,12),(8,8),(13,3)]):
            poly(base,[(x-2,y),(x,y-2),(x+2,y),(x,y+2)],"copper" if j else "silver")
            rect(detail,(x,y,x,y),"light")
        line(detail,[(4,11),(6,9),(9,7),(11,5)],"amber",2)
        if deep: line(base,[(2,8),(5,5),(8,3)],"steel");rect(detail,(12,7,14,8),"amber")
    elif family=="dead_centre":
        # Low wide weight and inward jaws; no miniature complete effect.
        poly(base,[(3,4),(11,4),(13,8),(10,11),(5,11),(2,8)],"steel")
        line(detail,[(4,5),(10,5)],"light");rect(detail,(7,7,8,12),"silver")
        line(base,[(1,11),(1,14),(6,14)],"silver",2);line(base,[(14,11),(14,14),(9,14)],"silver",2)
        if deep or tag=="bulwark": rect(base,(0,8,2,10),"edge");rect(base,(13,8,15,10),"edge")
        if tag=="bulwark": line(detail,[(0,2),(3,5),(5,5)],"copper",2);rect(detail,(4,3,5,4),"light")
        if tag=="counterweight": line(detail,[(1,7),(5,5),(6,8),(10,8)],"amber",2)
    else:
        if tag=="ghost_circuit":
            line(base,[(2,11),(4,3),(11,2),(14,8),(10,13),(2,11)],"green",2)
            line(detail,[(1,10),(1,13),(4,13)],"mint");line(detail,[(5,12),(7,11)],"light")
        elif tag=="slipstream":
            line(base,[(1,3),(13,12)],"blue",2);line(detail,[(1,13),(12,3)],"ice",2)
            line(detail,[(9,1),(14,1),(14,5)],"light");line(base,[(1,9),(4,7)],"cyan",2)
        else:
            line(base,[(1,13),(4,10),(8,10),(11,6),(14,4)],"cyan",2)
            line(detail,[(2,11),(5,8),(9,8),(12,4)],"ice")
            if deep: line(base,[(3,3),(6,6),(10,6),(13,9)],"silver",2)
    return ims

def wake_fx(tag,k):
    ims=layers((96,80));r=[5,10,16,23,31,38,43,46][k]
    for j in range(8):
        a=j*math.pi/4+.12;cx=48+math.cos(a)*r;cy=48+math.sin(a)*r*.48
        tang=(-math.sin(a),math.cos(a)*.48);normal=(math.cos(a),math.sin(a)*.48)
        # Eight coherent pressure panels develop the accepted event language.
        # Each carries a backing plate and loaded edge; density is structural,
        # not an increased count of loose sparks or a larger footprint.
        p=[(cx-tang[0]*6-normal[0]*5,cy-tang[1]*6-normal[1]*5),
           (cx+tang[0]*6-normal[0]*5,cy+tang[1]*6-normal[1]*5),
           (cx+tang[0]*5,cy+tang[1]*5),(cx-tang[0]*5,cy-tang[1]*5)]
        poly(ims[2],p,"steel")
        line(ims[3],[(cx-tang[0]*5,cy-tang[1]*5),(cx+tang[0]*5,cy+tang[1]*5)],"cyan",3)
        line(ims[4],[(cx-tang[0]*4+normal[0],cy-tang[1]*4+normal[1]),
                    (cx+tang[0]*4+normal[0],cy+tang[1]*4+normal[1])],"ice",1)
        if k<6:
            tooth(ims[5],cx-normal[0]*3,cy-normal[1]*3,1 if math.cos(a)>0 else -1,"silver",3)
            line(ims[2],[(cx-normal[0]*6,cy-normal[1]*6),(cx-normal[0]*9,cy-normal[1]*9)],"blue",2)
    if k<3: sparks(ims[4],48,48,k,"light",3)
    if k>=6: erode_material(ims,3 if k==6 else 6)
    return ims

def chain_fx(tag,k):
    ims=layers((96,80));deep=tag.endswith("_ii")
    # Local receiver contact, not three invented machines. Root places accents
    # and short transmitted links along actual eligible receiver positions.
    compress=[7,6,4,1,0,3,7,10][k]
    for sign in [-1,1]:
        x=48+sign*(7+compress);y=48-sign*3
        tooth(ims[2],x,y,-sign,"copper",4 if deep else 3)
        line(ims[3],[(x+sign*6,y-2),(x+sign*2,y-1)],"amber",2)
        if deep: line(ims[5],[(x+sign*7,y+3),(x+sign*3,y+4)],"silver",2)
    if k in [2,3,4]:
        line(ims[4],[(43,45),(48,48),(53,45)],"light",2)
        sparks(ims[4],48,48,k-2,"amber",5)
    if k>=6:
        for im in ims: im.putalpha(im.getchannel("A").point(lambda a: round(a*(.6 if k==6 else .2))))
    return ims

def centre_fx(tag,k):
    if tag.startswith("counterweight_release"):
        ims=layers((96,80));suffix=tag.rsplit("_",1)[-1]
        dx,dy=HEADINGS.get(suffix,HEADINGS["ne"]);tx,ty=-dy,dx
        distance=[-12,-9,-5,0,4,10,17,24][k]
        for j in range(3):
            along=distance-j*3;across=(j-1)*5
            x=48+dx*along+tx*across;y=48+dy*along+ty*across
            poly(ims[3],[(x-dx*3,y-dy*3),(x+tx*2,y+ty*2),(x+dx*5,y+dy*5),(x-tx*2,y-ty*2)],"copper")
            line(ims[3],[(x-dx*2,y-dy*2),(x+dx*5,y+dy*5)],"amber",2)
            rect(ims[4],(x+dx*4,y+dy*4,x+dx*4+1,y+dy*4+1),"light")
        if k in [2,3]: sparks(ims[4],48,48,k-2,"light",3)
        if k>=5: erode_material(ims,[0,0,0,0,0,1,3,5][k])
        return ims
    ims=layers((96,80));deep=tag in ["ground_lock_ii","bulwark_lock","bulwark_impact"]
    gaps=[0,1,3,6,8,10,12,15] if tag=="jaw_break" else [10,8,6,3,1,0,0,0];g=gaps[k]
    for sign in [-1,1]:
        weight_jaw(ims,48,48,sign,g,k,tag in ["bulwark_lock","bulwark_impact"],(3,92))
    if deep:
        for sign in [-1,1]:
            jaw(ims[5],48+sign*(17+g*.5),40,-sign,1,3,k>=3)
            line(ims[5],[(48+sign*15,41),(48+sign*9,45)],"silver",2)
    if tag=="jaw_break":
        erode_material(ims,k)
        sparks(ims[4],32-k,53+k*.6,k,"dust",4)
    elif tag=="bulwark_impact":
        sparks(ims[4],26-k*.8,48-k*.3,k,"amber",4)
        if 2<=k<=4: line(ims[4],[(23,47),(29,43),(27,39)],"light",2)
    elif tag=="counterweight_store":
        for j in range(4):
            x=29+j*(5-k*.35)
            line(ims[3],[(x,53-j*.6),(x+3,54-j*.6)],"amber" if j<=k//2 else "steel",2)
        line(ims[2],[(28,56),(48,46),(64,52)],"silver")
    return ims

def afterimage_fx(tag,k):
    ims=layers((96,80))
    if tag in ["route_scar","route_scar_ii"]:
        for j in range(3 if tag.endswith("_ii") else 2):
            x=28+j*14-k*1.2;y=58-j*7+k*.4
            line(ims[3],[(x,y),(x+6,y-3),(x+9,y-3)],"cyan",2 if tag.endswith("_ii") else 1)
            if tag.endswith("_ii"): tooth(ims[2],x+7,y-3,1,"ice",2)
    elif tag in ["latch_endpoint","ghost_latch"]:
        gap=[7,6,4,2,0,0,1,2][k] if tag=="ghost_latch" else [2,2,1,1,2,2,3,3][k]
        socket(ims[2],48-gap,48,"mint",False);socket(ims[3],48+gap,48,"green",False)
        if tag=="ghost_latch" and 3<=k<=5: line(ims[4],[(40,48),(56,48)],"mint",2)
    elif tag=="circuit_lock":
        # Local route-jaw response. Actual circuit geometry remains the live route.
        distance=[12,9,6,3,1,2,4,7][k]
        for sign in [-1,1]:
            tooth(ims[2],48+sign*distance,48-sign*distance*.5,-sign,"mint",3)
            line(ims[3],[(48+sign*(distance+12),48-sign*(distance+12)*.5),(48+sign*(distance+5),48-sign*(distance+5)*.5)],"green",2)
        if k in [3,4]: rect(ims[4],(47,47,49,49),"light")
    else:
        # Crossing + fast local snap, with unequal expanding streak intervals.
        suffix=tag.rsplit("_",1)[-1];dx,dy=HEADINGS.get(suffix,HEADINGS["ne"]);tx,ty=-dy,dx
        route(ims[2],[(48-tx*13,48-ty*13),(48+tx*13,48+ty*13)],"blue",2)
        for j in range(3):
            along=-15+j*10+k*(1+j*.5);across=(j-1)*3
            x=48+dx*along+tx*across;y=48+dy*along+ty*across
            line(ims[3],[(x,y),(x+dx*6,y+dy*6)],"ice",2)
        if k in [1,2,3]: socket(ims[4],48,48,"light",True)
    if k>=5 and tag not in ["latch_endpoint"]:
        erode_material(ims,[0,0,0,0,0,2,4,6][k])
    return ims

DESIGNS={
 "impact_wake":{
  "grammar":{"silhouette":"Central physical impact and outward pressure teeth","motion":"Contact flash, spreading pressure fronts, staggered counter-pressure plates, fading chips","location":"At the actual heavy contact point near the floor","persistence":"Short paid contact event","palette":"Cyan pressure, pale steel, sparse amber contact teeth","feature":"Strong original ring composition; Rank II adds a second structural pressure response"},
  "event_tags":{"impact_wake":"wake"},"active_tags":{},"static_frames":{"impact_wake":4,"impact_wake_ii":6},
  "notes":"Rank I card preserves the original five editable layer cels and six accepted poses, each held for two half-duration keys. Rank I runtime must retain original 128px pressure tag in power_fx_002b.aseprite; no new wake tag is supplied so renderer falls through. New wake_ii is a structural counter-pressure response, not an enlarged recolour. Original source master retained intact."},
 "chain_impact":{
  "grammar":{"silhouette":"Unequal physical receivers joined by diagonal contact transmission","motion":"One machine hits, a tooth lights, then the next receiver reacts; alternating compressed contact accents","location":"Real elimination/contact origin and actual eligible receiver links","persistence":"Discrete transmitted events, no persistent player aura","palette":"Dark steel receivers, copper stress, short pale amber contact keys","feature":"Sequential local contact teeth and sparse physical receiver links instead of a radial blast"},
  "event_tags":{"chain_impact":"transmit"},"active_tags":{},"static_frames":{"chain_impact":6,"chain_impact_ii":8},
  "notes":"Cards deliberately show unequal machines in a diagonal relay; Rank II extends the relay rather than growing the source pulse. FX are local contact teeth only. Runtime must place accents and short links along actual eligible target positions captured in presentation metadata, not use the legacy fixed RIGHT or fake illustrated runtime tops. Cascade mechanics unchanged."},
 "dead_centre":{
  "grammar":{"silhouette":"Heavy compact machine borne by inward floor jaws","motion":"Jaws approach, machine settles, grounded teeth take a strike; Counterweight compresses then sends force outward","location":"Floor contact point and low weight-bearing braces","persistence":"Charge-stage floor lock, with short impact/release reactions","palette":"Pale steel and slate ground, restrained cyan teeth, amber stored force","feature":"Visible mass supported by closing ground jaws; Bulwark redirects incoming contact and Counterweight stores a mechanical load"},
  "event_tags":{"anchor":"ground_lock","anchor_ii":"ground_lock_ii","anchor_break":"jaw_break","bulwark_impact":"bulwark_impact","counterweight_store":"counterweight_store","counterweight_release":"counterweight_release"},
  "active_tags":{"anchor":"ground_lock","anchor_ii":"ground_lock_ii","bulwark":"bulwark_lock","counterweight":"counterweight_store"},
  "static_frames":{"dead_centre":6,"dead_centre_ii":6,"bulwark":5,"counterweight":7},
  "notes":"Retain accepted exact anchor charge/grounding state, signature posture and actual directional Counterweight force composition. New native jaw cels carry more weight at the same fixed floor pivot. Bulwark card shows a planted rig meeting an attack; Counterweight card gives the loaded side cylinder a different composition. No long trails, aura growth or new mechanics."},
 "afterimage":{
  "grammar":{"silhouette":"A leading physical machine and environmental scars; Ghost encloses a rival in an irregular latched route","motion":"Route is drawn behind motion, aged crossing snaps locally, Ghost sockets meet and the actual path locks","location":"Recorded routes, endpoints and actual crossing points","persistence":"Bounded route history plus finite latch/crossing responses","palette":"Sparse cyan and ice scars; Ghost uses green mechanical route teeth","feature":"The route occupies the illustration and gameplay space; Ghost closure and Slipstream crossing have different spatial and timing language"},
  "event_tags":{"afterimage":"route_scar","afterimage_ii":"route_scar_ii","ghost_closure":"ghost_latch","ghost_activation":"circuit_lock","slipstream_cross":"slipstream_snap"},
  "active_tags":{"ghost_preview":"latch_endpoint"},
  "static_frames":{"afterimage":6,"afterimage_ii":5,"ghost_circuit":6,"slipstream":6},
  "notes":"Retain strong actual-route geometry and native afterimage_fx_002c4 scar/crossing logic; do not substitute a pre-drawn circle for live recorded routes. New endpoint, lock and crossing tiles are local accents. Ghost card shows an enclosed rival and a closing irregular machine path; Slipstream shows a physical top accelerating across an old route. No persistent player aura."}
}

CARD_TIMINGS={
 "chain_impact":[150,100,90,45,45,80,45,55,85,100,130,190],
 "chain_impact_ii":[160,100,85,40,45,90,45,60,100,110,150,200],
 "dead_centre":[160,100,90,80,65,65,110,110,90,90,110,180],
 "dead_centre_ii":[140,90,80,75,60,65,120,120,95,80,110,170],
 "bulwark":[160,100,70,45,50,65,130,140,100,100,120,190],
 "counterweight":[140,100,90,85,100,100,130,140,55,45,75,170],
 "afterimage":[120,90,80,55,55,65,80,80,100,110,120,160],
 "afterimage_ii":[140,100,80,60,50,70,90,100,100,100,120,170],
 "ghost_circuit":[160,110,90,65,55,100,120,120,100,90,110,190],
 "slipstream":[150,100,70,40,40,45,55,65,90,120,140,180]
}

def write_family(family,replace=False):
    SOURCE.mkdir(parents=True,exist_ok=True);OUT.mkdir(parents=True,exist_ok=True)
    paths=[SOURCE/f"{family}_{kind}.aseprite" for kind in ["cards","icons","fx"]]
    if any(p.exists() for p in paths) and not replace: raise FileExistsError("Existing artist masters preserved; use --replace-authored only for deliberate recipe revision.")
    if family=="chain_impact":
        from restore_chain_art_002c5 import restore_chain
        restore_chain()
        return
    if family=="dead_centre":
        from author_identity_centre import author
        author()
        return
    states=[family,family+"_ii"]+({"dead_centre":["bulwark","counterweight"],"afterimage":["ghost_circuit","slipstream"]}.get(family,[]))
    if family=="impact_wake": frames,names,tags,timings=wake_cards()
    else:
        paint={"chain_impact":chain_card,"dead_centre":centre_card,"afterimage":afterimage_card}[family]
        frames=[];tags=[];timings=[];names=LAYERS
        for state in states:
            start=len(frames);frames.extend(paint(state,k) for k in range(12));tags.append((state,start,len(frames)-1))
            timings.extend(CARD_TIMINGS[state])
    write_ase(paths[0],frames,names,tags,timings,(32,32),note="Task002C5 visual identity / deliberately staged mechanical compositions / native64px / original masters retained",palette=PALETTE)
    write_ase(paths[1],[icon(family,state) for state in states],["Independent small-scale silhouette","Mechanic-specific recognition teeth"],[(state,k,k) for k,state in enumerate(states)],[120]*len(states),(8,8),note="Independently authored16px HUD silhouettes; never a shrunk effect",palette=PALETTE)
    fx_tags={"impact_wake":["wake_ii"],"chain_impact":["transmit","transmit_ii"],"dead_centre":["ground_lock","ground_lock_ii","bulwark_lock","bulwark_impact","jaw_break","counterweight_store","counterweight_release"],"afterimage":["route_scar","route_scar_ii","latch_endpoint","ghost_latch","circuit_lock","slipstream_snap"]}[family]
    directional={"dead_centre":"counterweight_release","afterimage":"slipstream_snap"}.get(family)
    if directional: fx_tags += [directional+"_"+heading for heading in HEADINGS]
    fx_paint={"impact_wake":wake_fx,"chain_impact":chain_fx,"dead_centre":centre_fx,"afterimage":afterimage_fx}[family]
    frames=[];tags=[];timings=[]
    for tag in fx_tags:
        start=len(frames);frames.extend(fx_paint(tag,k) for k in range(8));tags.append((tag,start,len(frames)-1))
        timings.extend([70,50,40,45,50,65,85,120] if family!="dead_centre" else [130,90,70,70,80,90,110,140])
    write_ase(paths[2],frames,LAYERS,tags,timings,(48,48),note="Fixed2:1 ground plane; no sprite rotation; eight deliberate anticipation/contact/reaction/follow-through keys",palette=PALETTE)
    design={"family":family,**DESIGNS[family]}
    (OUT/f"{family}_design.json").write_text(json.dumps(design,indent=2)+"\n",encoding="utf-8")
    print(f"Authored {family}: {len(states)} twelve-key card states, independent16px icons, {len(fx_tags)} eight-key FX tags")

def review(families,target):
    target.mkdir(parents=True,exist_ok=True)
    font=ImageFont.truetype(r"C:\Windows\Fonts\arial.ttf",12)
    reference,ref_meta=read_ase(SOURCE/"impact_wake_cards.aseprite")
    accepted=reference[int(ref_meta["tags"]["impact_wake"]["from"])+4]
    comparison=Image.new("RGB",(750,sum(len(DESIGNS[f]["static_frames"]) for f in families)*286+42),"#18242d")
    ImageDraw.Draw(comparison).text((10,8),"Actual 64px card / independently authored 16px icon / nearest-neighbour 4x / accepted Wake reference",font=font,fill="white")
    comparison_row=0
    for family in families:
        cards,meta=read_ase(SOURCE/f"{family}_cards.aseprite");icons,icon_meta=read_ase(SOURCE/f"{family}_icons.aseprite");fx,fx_meta=read_ase(SOURCE/f"{family}_fx.aseprite")
        rows=len(meta["tags"]);sheet=Image.new("RGB",(12*64+166,rows*86),"#1b222b")
        for row,(tag,span) in enumerate(meta["tags"].items()):
            ImageDraw.Draw(sheet).text((5,row*86+12),tag,font=font,fill="white")
            sheet.paste(icons[int(icon_meta["tags"][tag]["from"])],(130,row*86+32),icons[int(icon_meta["tags"][tag]["from"])])
            for k in range(12): sheet.paste(cards[int(span["from"])+k],(166+k*64,row*86+7),cards[int(span["from"])+k])
        sheet.save(target/f"{family}_card-keys-native.png");ImageOps.grayscale(sheet).save(target/f"{family}_card-keys-grayscale.png")
        for tag,key in DESIGNS[family]["static_frames"].items():
            card=cards[int(meta["tags"][tag]["from"])+key];ic=icons[int(icon_meta["tags"][tag]["from"])]
            y=42+comparison_row*286
            ImageDraw.Draw(comparison).text((10,y+5),tag,font=font,fill="white")
            comparison.paste(card,(10,y+34),card);comparison.paste(ic,(32,y+110),ic)
            enlarged=card.resize((256,256),Image.Resampling.NEAREST);comparison.paste(enlarged,(105,y+5),enlarged)
            comparison.paste(accepted,(397,y+34),accepted)
            enlarged=accepted.resize((256,256),Image.Resampling.NEAREST);comparison.paste(enlarged,(477,y+5),enlarged)
            comparison_row+=1
        effect_sheet=Image.new("RGB",(8*96+166,len(fx_meta["tags"])*90),"#24313a")
        for row,(tag,span) in enumerate(fx_meta["tags"].items()):
            ImageDraw.Draw(effect_sheet).text((5,row*90+32),tag,font=font,fill="white")
            for k in range(8): effect_sheet.paste(fx[int(span["from"])+k],(166+k*96,row*90+5),fx[int(span["from"])+k])
        effect_sheet.save(target/f"{family}_fx-keys-native.png")
    comparison.save(target/"foundation-single-card-native-and-4x.png")
    ImageOps.grayscale(comparison).save(target/"foundation-single-card-native-and-4x-grayscale.png")

if __name__=="__main__":
    parser=argparse.ArgumentParser();parser.add_argument("--family",action="append",choices=DESIGNS);parser.add_argument("--replace-authored",action="store_true");parser.add_argument("--review-dir",type=Path)
    args=parser.parse_args();selected=args.family or list(DESIGNS)
    for family in selected: write_family(family,args.replace_authored)
    if args.review_dir: review(selected,args.review_dir)
