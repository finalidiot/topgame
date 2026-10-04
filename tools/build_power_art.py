"""Author and export the Task 002B / 002B.1 native pixel sources.

Normal artist workflow: edit .aseprite, then run this script (exports only).
--author reconstructs the original authored cels and overwrites those sources.
--author-cards reconstructs only the 002B.1 card/icon masters, retaining FX.
No resampling, blur, procedural runtime textures, or arena exports are used.
Requires Python 3 and Pillow. Aseprite RGBA normal layers, compressed/raw/linked
cels, layer/cel opacity, tags and slice pivots are supported by the exporter.
Format reference: https://github.com/aseprite/aseprite/blob/main/docs/ase-file-specs.md
"""
from pathlib import Path
import argparse
import json
import math
import struct
import zlib
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source-art"
OUT = ROOT / "assets/powers"
P = {
    "ink": "#10151f", "dark": "#202b36", "steel": "#4c626e",
    "silver": "#abc0c7", "white": "#e3e8dc", "blue": "#245c7b",
    "cyan": "#4595b5", "ice": "#a5e5e5", "oxide": "#a94c35",
    "orange": "#df8740", "gold": "#f3c36a", "red": "#ed654c",
}


def color(name, alpha=255):
    value = P.get(name, name).lstrip("#")
    return (*bytes.fromhex(value), alpha)


def canvas(n):
    return Image.new("RGBA", (n, n))


def pts(cx, cy, radius, angles, squash=.5):
    return [(round(cx + math.cos(t) * radius), round(cy + math.sin(t) * radius * squash)) for t in angles]


def sector(im, cx, cy, r, a, length, ink, width=2, squash=.5):
    # Each sector has explicit stepped ends; integer vertices only.
    angles = [a + length * i / 6 for i in range(7)]
    draw = ImageDraw.Draw(im)
    polygon = pts(cx, cy, r, angles, squash) + list(reversed(pts(cx, cy, max(0, r-width), angles, squash)))
    draw.polygon(polygon, fill=ink)


def ray(im, center, radius, length, a, ink, width=2, squash=.5):
    ends = pts(*center, radius, [a], squash) + pts(*center, radius+length, [a], squash)
    ImageDraw.Draw(im).line(ends, fill=ink, width=width)


def small_frames():
    frames = []
    layers = ["contact shadow", "steel rotor", "amber cap", "flash and retirement"]
    for f in range(8):
        images = [canvas(24) for _ in layers]
        shadow, body, cap, fx = [ImageDraw.Draw(i) for i in images]
        fade = [255]*5 + [235, 165, 70]
        alpha = fade[f]
        shadow.ellipse((4, 18, 20, 22), fill=(12, 19, 25, 100 if f<6 else 55))
        wobble = 0 if f<5 else f-5
        y = 11+wobble*2
        # Small hostile capsule: stepped chassis, thin warm rim, visible pointed bit.
        body.polygon([(11,y+6),(14,y+6),(13,20),(11,20)], fill=color("ink",alpha))
        body.line([(12,y+6),(12,19)], fill=color("silver",alpha))
        body.polygon([(5,y-3),(9,y-5),(16,y-5),(20,y-2),(20,y+2),(16,y+5),(8,y+5),(4,y+2),(4,y-1)], fill=color("ink",alpha))
        body.polygon([(5,y-2),(9,y-4),(16,y-4),(19,y-1),(18,y+2),(15,y+4),(9,y+4),(5,y+1)], fill=color("steel",alpha))
        body.line([(5,y+1),(9,y+3),(15,y+3),(18,y)], fill=color("oxide",alpha), width=2)
        body.line([(7,y-2),(10,y-3),(15,y-3)], fill=color("silver",alpha))
        for a in [f*math.pi/4, f*math.pi/4+math.pi]:
            q = pts(12,y-1,7,[a-.25,a+.17],.48) + pts(12,y-1,3,[a+.30,a-.05],.48)
            body.polygon(q,fill=color("white",alpha))
        cap.polygon([(10,y-3),(14,y-3),(16,y-1),(14,y+1),(10,y+1),(8,y-1)],fill=color("ink",alpha))
        cap.polygon([(11,y-2),(14,y-2),(14,y),(10,y)],fill=color("orange",alpha))
        cap.point((12+f%2,y-2),fill=color("gold",alpha))
        if f==4:
            fx.polygon([(12,2),(14,8),(22,6),(17,11),(22,16),(14,14),(12,20),(10,13),(2,16),(7,11),(3,6),(10,8)],fill=color("gold"))
            fx.polygon([(12,6),(14,10),(18,11),(14,12),(12,16),(10,12),(7,11),(10,10)],fill=color("white"))
        if f>=5:
            for k in range(3):
                x=3+k*8+(f-5)*(k-1)
                fx.line([(x,16+k%2*2),(x+2,16+k%2*2)],fill=color("orange",alpha))
        frames.append(images)
    tags=[("spin",0,3), ("contact",4,4), ("retire",5,7)]
    return frames,layers,tags,[90]*4+[55,90,105,145],(12,20)


def effect_frames():
    layers=["mechanical sectors", "edge teeth", "contact light", "angular scars"]
    frames=[]; tags=[]; timings=[]
    def frame(): return [canvas(128) for _ in layers]
    def append_tag(name, count, duration, paint):
        start=len(frames)
        for f in range(count):
            images=frame(); paint(images,f); frames.append(images); timings.append(duration)
        tags.append((name,start,len(frames)-1))
    def contact(im,f):
        r=[5,13,21,28,33,36][f]
        a=255 if f<3 else [215,145,70][f-3]
        d=ImageDraw.Draw(im[2])
        if f<3:
            size=[6,11,5][f]
            d.polygon([(64-size,64),(61,61),(64,64-size),(67,61),(64+size,64),(67,67),(64,64+size),(61,67)],fill=color("white",a))
        for k in range(6):
            angle=k*math.tau/6+.18
            ray(im[1],(64,64),r,max(2,10-f),angle,color("gold",a),2,.62)
        sector(im[0],64,64,r+4,math.pi*.15,math.pi*.63,color("orange",a),3,.62)
        sector(im[0],64,64,r+4,math.pi*1.15,math.pi*.63,color("white",a),2,.62)
    append_tag("contact_arc",6,45,contact)
    def pressure(im,f):
        r=[12,20,29,38,46,53,59,62][f]
        a=[255,255,255,235,215,185,135,60][f]
        for k in range(8):
            angle=k*math.tau/8+.1
            sector(im[0],64,64,r,angle,.57,color("cyan",a),3)
            sector(im[2],64,64,r-1,angle+.08,.37,color("ice",a),1)
            if f<6:
                ray(im[1],(64,64),r,4,angle+.22,color("gold",a),2)
        if f in [1,2,3]:
            for k in [1,3,5,7]:
                sector(im[3],64,64,r-7,k*math.tau/8,.3,color("blue",a),2)
    append_tag("pressure",8,50,pressure)
    def echo(im,f):
        a=[185,165,145,125,90,45][f]
        for k in range(3):
            angle=k*math.tau/3+f*.18
            sector(im[0],64,53,19+f,angle,.9,color("cyan",a),3)
            sector(im[2],64,53,19+f,angle+.12,.55,color("ice",a),1)
        d=ImageDraw.Draw(im[3])
        d.line([(46-f*2,61),(52-f,58),(57,58)],fill=color("cyan",a),width=2)
        d.line([(72,47),(81+f,47),(87+f*2,44)],fill=color("ice",a),width=1)
    append_tag("echo",6,65,echo)
    def corona(im,f):
        r=30+[0,2,1,3,0,2,1,3][f]
        for k in range(12):
            angle=k*math.tau/12+f*math.pi/24
            sector(im[0],64,50,r,angle,.30,color("oxide",210),3)
            sector(im[2],64,50,r-1,angle+.03,.17,color("gold"),1)
            tooth=pts(64,50,r,[angle+.15,angle+.3])+pts(64,50,r+6,[angle+.29,angle+.2])
            ImageDraw.Draw(im[1]).polygon(tooth,fill=color("orange",235))
        sector(im[3],64,50,25,f*math.pi/4,.9,color("red",210),2)
    append_tag("corona",8,45,corona)
    def recovery(im,f):
        r=[33,24,15,8,20,34,48,59][f]
        for k in range(8):
            angle=k*math.tau/8+.15
            sector(im[0],64,64,r,angle,.46,color("cyan" if f<4 else "gold",235 if f<6 else 140),3)
            ray(im[1],(64,64),r,-4 if f<4 else 5,angle+.2,color("white",230 if f<6 else 100),2)
        d=ImageDraw.Draw(im[2])
        if f in [3,4,5]:
            y=64-[0,0,0,9,28,39,0,0][f]
            d.polygon([(61,y+5),(61,y),(64,y-4),(67,y),(67,y+5),(64,y+2)],fill=color("white"))
            d.line([(64,y+8),(64,61)],fill=color("ice",185),width=1)
    append_tag("recovery",8,80,recovery)
    def comet(im,f):
        # Eight projected headings, so the atlas never rotates an isometric sprite.
        a=f*math.tau/8
        side=pts(64,50,21,[a+math.pi/2,a-math.pi/2])
        tail=pts(64,50,53,[a+math.pi])[0]
        near=pts(64,50,12,[a+math.pi])[0]
        d=ImageDraw.Draw(im[0]);d.polygon([side[0],tail,side[1],near],fill=color("oxide",180))
        d=ImageDraw.Draw(im[1]);d.line([side[0],tail,side[1]],fill=color("orange",235),width=2)
        sector(im[2],64,50,24,a-.8,1.6,color("gold"),3)
        sector(im[2],64,50,22,a-.6,1.2,color("white"),1)
    append_tag("comet_headings",8,80,comet)
    def stamp(im,f):
        r=11+f*3
        for k in range(4):
            sector(im[0],64,64,r,k*math.pi/2+.15,.75,color("orange",240-f*45),3)
            ray(im[2],(64,64),r+3,3,k*math.pi/2+.5,color("gold",255-f*45),2)
    append_tag("floor_stamp",4,70,stamp)
    return frames,layers,tags,timings,(64,64)


def icon_frames():
    frames=[]
    for name in ["impact_wake","second_wind","redline","iron_comet","afterimage","chain_impact"]:
        im=canvas(16); d=ImageDraw.Draw(im)
        d.rectangle((0,0,15,15),fill=color("ink"));d.line([(1,14),(14,14),(14,1)],fill=color("steel"))
        if name=="impact_wake":
            for a in [0,.5*math.pi,math.pi,1.5*math.pi]: sector(im,8,8,6,a+.12,1.1,color("cyan"),2,.55)
            d.polygon([(8,3),(9,7),(13,8),(9,9),(8,12),(7,9),(3,8),(7,7)],fill=color("white"))
        elif name=="second_wind":
            sector(im,8,10,6,.1,2.7,color("cyan"),2)
            d.polygon([(4,7),(8,2),(12,7),(9,7),(9,12),(7,12),(7,7)],fill=color("gold"))
        elif name=="redline":
            for k in range(8): ray(im,(8,8),4,3,k*math.pi/4,color("orange"),2,1)
            d.rectangle((6,6,9,9),fill=color("red"));d.point((7,6),fill=color("white"))
        elif name=="iron_comet":
            d.polygon([(2,12),(5,3),(12,4),(13,8),(9,12),(7,8)],fill=color("orange"))
            d.line([(4,11),(10,5)],fill=color("gold"),width=2);d.rectangle((10,3,12,5),fill=color("white"))
        elif name=="afterimage":
            for x,c in [(5,"blue"),(8,"cyan"),(11,"ice")]:
                sector(im,x,8,4,-1.1,2.2,color(c),2,.8)
        else:
            for x,y in [(4,10),(8,6),(12,10)]:
                d.rectangle((x-2,y-1,x+1,y+1),fill=color("gold"));d.point((x,y-1),fill=color("white"))
            d.line([(4,8),(8,4),(12,8)],fill=color("orange"))
        frames.append([im])
    return frames,["signature glyphs"],[(n,i,i) for i,n in enumerate(["impact_wake","second_wind","redline","iron_comet","afterimage","chain_impact"])],[100]*6,(8,8)


POWER_IDS = ["impact_wake", "second_wind", "redline", "iron_comet", "afterimage", "chain_impact"]
CARD_TIMINGS = [110, 90, 75, 75, 100, 170]


def stepped_ring(im, cx, cy, radius, inner, phase, count, squash, main, light=None, gaps=.12):
    """An authored polygon bearing; each six-vertex plate has a stepped end."""
    d = ImageDraw.Draw(im)
    for k in range(count):
        a = phase + k * math.tau / count
        length = math.tau / count - gaps
        outer = pts(cx, cy, radius, [a, a+length*.5, a+length], squash)
        inside = pts(cx, cy, inner, [a+length, a+length*.5, a], squash)
        d.polygon(outer+inside, fill=color(main))
        if light:
            d.line(outer[:2], fill=color(light), width=1)


def teeth(im, cx, cy, radius, phase, count, squash, main, length=5):
    d = ImageDraw.Draw(im)
    for k in range(count):
        a = phase + k * math.tau / count
        q = pts(cx, cy, radius-1, [a-.12, a+.17], squash)
        q += pts(cx, cy, radius+length, [a+.16, a+.03], squash)
        d.polygon(q, fill=color(main))


def bearing(im, cx, cy, radius, phase=0, hot=False, squash=.66):
    """Fixed projected rotor, with deep front wall and opposed bright lobes."""
    d = ImageDraw.Draw(im)
    warm = "oxide" if hot else "steel"
    rim = "orange" if hot else "silver"
    outline = pts(cx, cy, radius+1, [k*math.tau/12 for k in range(12)], squash)
    d.polygon([(x,y+5) for x,y in outline], fill=color("ink"))
    d.polygon([(x,y+3) for x,y in outline], fill=color(warm))
    d.line([(cx-radius+2,cy+4),(cx-radius//2,cy+round(radius*squash)+2),
            (cx+radius//2,cy+round(radius*squash)+2),(cx+radius-2,cy+4)], fill=color("dark"), width=2)
    d.polygon(outline, fill=color("ink"))
    teeth(im,cx,cy,radius-2,phase,8,squash,rim,3)
    stepped_ring(im,cx,cy,radius-2,max(3,radius-7),phase,8,squash,warm,rim,.1)
    for k in [0,4]:
        a=phase+k*math.tau/8
        sector(im,cx,cy,radius-4,a,.45,color("gold" if hot else "white"),2,squash)
    d.ellipse((cx-6,cy-4,cx+6,cy+4),fill=color("ink"))
    d.polygon([(cx-4,cy-2),(cx,cy-4),(cx+4,cy-2),(cx+4,cy+1),(cx,cy+3),(cx-4,cy+1)],fill=color("orange" if hot else "blue"))
    d.line([(cx-3,cy-2),(cx,cy-3),(cx+2,cy-2)],fill=color("gold" if hot else "ice"))
    d.rectangle((cx-1,cy-1,cx+1,cy+1),fill=color("white"))
    d.line([(cx-1,cy+8),(cx,cy+10),(cx+1,cy+8)],fill=color("silver"))


def card_backdrop(im, index):
    d=ImageDraw.Draw(im)
    d.polygon([(8,3),(56,3),(61,8),(61,55),(55,61),(8,61),(3,56),(3,8)],fill=color("ink"))
    d.polygon([(9,5),(55,5),(59,9),(59,54),(54,59),(9,59),(5,55),(5,9)],fill=color("dark"))
    # Sparse industrial hatch, not a busy pixel-noise texture.
    for x,y in [(9,14),(12,11),(47,53),(50,50),(53,47)]:
        d.line([(x,y),(x+2,y-2)],fill=color("steel"))
    d.line([(10,6),(53,6)],fill=color("steel"))
    d.line([(6,10),(6,52)],fill=color("blue" if index in [0,1,4] else "oxide"))
    d.line([(11,58),(52,58)],fill=color("ink"))
    for x,y in [(9,9),(54,9),(9,54),(54,54)]:
        d.rectangle((x-1,y-1,x+1,y+1),fill=color("ink"));d.point((x,y),fill=color("silver"))
    # Two tiny status slugs unify the collection without copying silhouettes.
    d.rectangle((48,7,50,7),fill=color("cyan" if index in [0,1,4] else "orange"))
    d.rectangle((52,7,53,7),fill=color("steel"))


def card_frames():
    layers=["industrial backplate", "machine depth and chassis", "authored moving bearings", "pressure and trajectory", "contact glints and fragments"]
    frames=[];tags=[]
    for row,name in enumerate(POWER_IDS):
        start=len(frames)
        for f in range(6):
            images=[canvas(64) for _ in layers]
            back,base,machine,energy,glints=images
            card_backdrop(back,row)
            b=ImageDraw.Draw(base);e=ImageDraw.Draw(energy);g=ImageDraw.Draw(glints)
            phase=f*math.pi/12
            if name=="impact_wake":
                b.ellipse((16,37,48,48),fill=color("ink"))
                bearing(machine,32,31,12,phase)
                r=[18,21,24,27,29,18][f]
                # Toothed pressure plates grow through a contact ring.
                teeth(energy,32,34,r,.1,10,.66,"blue",4)
                stepped_ring(energy,32,34,r,r-4,.1,10,.66,"cyan","ice",.16)
                for k in [1,4,6,9]:
                    a=k*math.tau/10+.23
                    ray(energy,(32,34),r,4,a,color("gold"),2,.66)
                if f in [0,1,2]:
                    n=[7,10,5][f]
                    g.polygon([(32-n,31),(29,28),(32,31-n),(35,28),(32+n,31),(35,34),(32,31+n),(29,34)],fill=color("white"))
                for x,y in [(14-f,22),(46+f,22),(15-f,47),(46+f,47)]:
                    if 8<x<57:g.line([(x,y),(x+2,y-2)],fill=color("orange"),width=1)
            elif name=="second_wind":
                b.ellipse((13,38,51,49),fill=color("ink"))
                # Individual broken races contract into a precise bearing.
                offsets=[6,4,2,0,0,3]
                spread=offsets[f]
                for k in range(8):
                    a=k*math.tau/8+.12
                    dx=round(math.cos(a)*spread);dy=round(math.sin(a)*spread*.7)
                    cx,cy=32+dx,31+dy
                    sector(base,cx,cy+4,19,a,.61,color("ink"),6,.68)
                    sector(machine,cx,cy,19,a,.61,color("steel"),5,.68)
                    sector(machine,cx,cy,18,a+.04,.51,color("silver"),2,.68)
                    ray(machine,(cx,cy),14,4,a+.25,color("cyan"),2,.68)
                bearing(machine,32,31,10,phase)
                if f in [2,3,4]:
                    stepped_ring(energy,32,31,22+(f-2)*2,21+(f-2)*2,.1,8,.68,"ice",None,.25)
                    g.line([(32,12),(32,21)],fill=color("gold"),width=2)
                    g.line([(32,41),(32,51)],fill=color("gold"),width=2)
                    g.polygon([(29,16),(32,12),(35,16),(33,16),(33,20),(31,20),(31,16)],fill=color("white"))
                else:
                    for k in [1,3,5,7]:
                        a=k*math.tau/8
                        q=pts(32,31,21+spread,[a],.68)[0]
                        g.line([(q[0],q[1]),(q[0]+2,q[1]-3)],fill=color("ice"))
            elif name=="redline":
                b.ellipse((12,40,53,52),fill=color("ink"))
                # Big axial overdrive rotor, glowing through cut-out teeth.
                bearing(machine,32,30,21,phase,True,.73)
                teeth(energy,32,30,21,phase+.1,10,.73,"red",5 if f in [2,3] else 3)
                for k in range(10):
                    a=phase+.1+k*math.tau/10
                    sector(energy,32,30,23,a,.24,color("gold"),2,.73)
                for k in [0,3,6]:
                    a=phase+k*math.tau/3
                    sector(glints,32,30,29,a,.4,color("orange"),2,.73)
                    ray(glints,(32,30),25,4,a+.3,color("gold"),1,.73)
                if f in [2,3]:
                    sector(glints,32,30,16,phase+.1,.7,color("white"),2,.73)
                    sector(glints,32,30,16,phase+math.pi+.1,.7,color("white"),2,.73)
                g.line([(27,48),(30,48),(32,45),(34,48),(38,48)],fill=color("red"),width=2)
            elif name=="iron_comet":
                # A grounded wall face and an unmistakable rebound angle.
                b.polygon([(10,15),(16,12),(22,20),(22,43),(16,49),(10,43)],fill=color("ink"))
                b.polygon([(11,16),(16,14),(20,21),(20,41),(16,46),(11,42)],fill=color("steel"))
                b.line([(16,15),(16,44)],fill=color("silver"),width=2)
                for y in [21,38]:b.rectangle((12,y,14,y+2),fill=color("ink"));b.point((13,y),fill=color("silver"))
                e.line([(27,48),(17,34),(37,24)],fill=color("oxide"),width=5)
                e.line([(27,48),(17,34),(37,24)],fill=color("orange"),width=2)
                # Knife-like mass, with a stepped steel top and warm leading edge.
                m=ImageDraw.Draw(machine)
                m.polygon([(24,35),(46,20),(55,23),(47,40),(32,44)],fill=color("ink"))
                m.polygon([(25,35),(47,22),(52,24),(44,36),(32,42)],fill=color("steel"))
                m.polygon([(29,34),(47,23),(49,25),(42,34),(33,39)],fill=color("silver"))
                m.polygon([(35,32),(44,26),(45,29),(38,35)],fill=color("blue"))
                m.line([(26,37),(32,42),(44,37),(53,24)],fill=color("oxide"),width=2)
                m.line([(32,40),(44,35),(51,25)],fill=color("gold"),width=1)
                m.rectangle((37,29,39,31),fill=color("ink"));m.point((38,29),fill=color("white"))
                if f<4:
                    x,y=[(25,44),(20,38),(19,32),(29,27)][f]
                    g.line([(x,y),(x+2,y-3)],fill=color("white"),width=2)
                else:
                    for x,y in [(53,17),(57,25),(54,33)]:
                        g.line([(x,y),(x-3,y+2)],fill=color("gold"),width=2)
                    g.polygon([(51,22),(53,18),(55,21),(58,21),(55,24),(54,28)],fill=color("white"))
            elif name=="afterimage":
                # Echoes share a visible diagonal path; the original has real depth.
                b.ellipse((33,27,54,34),fill=color("ink"))
                e.line([(10,49),(20,41),(31,31),(42,22)],fill=color("blue"),width=3)
                echo_count=[1,2,2,3,3,2][f]
                for k,(x,y) in enumerate([(16,44),(28,34)]):
                    if k>=echo_count-1:continue
                    stepped_ring(energy,x,y,11,7,phase+k*.35,6,.63,"blue" if k==0 else "cyan","cyan" if k==0 else "ice",.14)
                    sector(glints,x,y,11,phase+math.pi,.8,color("cyan" if k==0 else "ice"),2,.63)
                    e.line([(x-10,y+5),(x-5,y+2)],fill=color("cyan"),width=1)
                bearing(machine,43,23,12,phase)
                sector(glints,43,23,15,-.65,1.05,color("ice"),2,.63)
                for k in range(3):
                    x=12+k*10+f%2;y=49-k*8
                    g.line([(x,y),(x+3,y-2)],fill=color("cyan" if k<2 else "white"))
            else:
                # Three real rotors chained along a rising/falling ricochet route.
                points=[(15,40),(32,24),(49,40)]
                e.line(points,fill=color("oxide"),width=5)
                e.line(points,fill=color("orange"),width=2)
                for k,(x,y) in enumerate(points):
                    bearing(machine,x,y,8,phase+k*.6,True,.7)
                    active=(f//2)==k
                    if active:
                        r=11+(f%2)*3
                        stepped_ring(energy,x,y,r,r-3,.1,6,.7,"orange","gold",.24)
                        teeth(energy,x,y,r,.1,6,.7,"gold",3)
                        g.polygon([(x-5,y),(x-2,y-2),(x,y-6),(x+2,y-2),(x+5,y),(x+2,y+2),(x,y+5),(x-2,y+2)],fill=color("white"))
                    if k<2:
                        mx=(x+points[k+1][0])//2;my=(y+points[k+1][1])//2
                        g.line([(mx-2,my),(mx,my-2),(mx+2,my)],fill=color("gold"),width=2)
            frames.append(images)
        tags.append((name,start,len(frames)-1))
    return frames,layers,tags,CARD_TIMINGS*6,(32,32)


def compact_icon_frames():
    """HUD glyphs remain 16px: clear silhouettes, three tones, no downsampling."""
    frames=[]
    for name in POWER_IDS:
        im=canvas(16);d=ImageDraw.Draw(im)
        d.polygon([(2,0),(13,0),(15,2),(15,13),(13,15),(2,15),(0,13),(0,2)],fill=color("ink"))
        d.line([(2,14),(13,14),(14,13)],fill=color("steel"))
        if name=="impact_wake":
            stepped_ring(im,8,8,6,4,.1,6,.75,"cyan","ice",.2)
            teeth(im,8,8,5,.1,6,.75,"cyan",2)
            d.polygon([(8,3),(9,6),(12,8),(9,9),(8,12),(7,9),(4,8),(7,6)],fill=color("white"))
            d.point((8,8),fill=color("gold"))
        elif name=="second_wind":
            stepped_ring(im,8,8,6,3,.1,6,.85,"steel","silver",.32)
            d.line([(8,2),(8,5)],fill=color("gold"),width=2)
            d.line([(8,10),(8,13)],fill=color("gold"),width=2)
            d.rectangle((6,6,10,9),fill=color("blue"));d.line([(7,6),(9,6)],fill=color("ice"));d.point((8,7),fill=color("white"))
        elif name=="redline":
            teeth(im,8,7,4,0,8,.9,"orange",3)
            stepped_ring(im,8,7,5,2,0,8,.9,"red","gold",.12)
            d.rectangle((6,5,9,8),fill=color("oxide"));d.line([(6,5),(8,5)],fill=color("white"))
            d.line([(5,12),(8,10),(11,12)],fill=color("red"))
        elif name=="iron_comet":
            d.line([(2,3),(2,12)],fill=color("silver"),width=2)
            d.line([(6,13),(3,9),(8,5)],fill=color("orange"),width=2)
            d.polygon([(5,8),(12,2),(14,4),(11,10),(7,12)],fill=color("steel"))
            d.polygon([(7,8),(12,3),(12,6),(9,9)],fill=color("white"))
            d.line([(7,11),(11,9),(13,5)],fill=color("gold"))
        elif name=="afterimage":
            for x,y,c,light in [(4,11,"blue","cyan"),(8,8,"cyan","ice"),(11,5,"silver","white")]:
                sector(im,x,y,3,.1,math.tau-.7,color(c),2,.7)
                sector(im,x,y,3,3.3,1.4,color(light),1,.7)
            d.line([(2,13),(5,12)],fill=color("cyan"))
        else:
            d.line([(3,11),(8,4),(12,11)],fill=color("orange"))
            for x,y in [(3,11),(8,4),(12,11)]:
                d.polygon([(x-3,y),(x-1,y-1),(x,y-3),(x+1,y-1),(x+2,y),(x+1,y+1),(x,y+2),(x-1,y+1)],fill=color("gold"))
                d.rectangle((x-1,y-1,x,y),fill=color("white"))
        frames.append([im])
    return frames,["compact mechanical silhouettes"],[(n,i,i) for i,n in enumerate(POWER_IDS)],[100]*6,(8,8)


def string(s):
    b=s.encode("utf-8");return struct.pack("<H",len(b))+b


def chunk(kind,data): return struct.pack("<IH",len(data)+6,kind)+data


def write_ase(path,frames,layers,tags,durations,pivot,note="Task 002B / native pixel clusters / fixed projected contact pivot / nearest filter",palette=None):
    w,h=frames[0][0].size
    palette=P if palette is None else palette
    output=[]
    for f,images in enumerate(frames):
        chunks=[]
        if f==0:
            for layer in layers:
                chunks.append(chunk(0x2004,struct.pack("<6HB3x",3,0,0,0,0,0,255)+string(layer)))
            pal=struct.pack("<III8x",len(palette),0,len(palette)-1)
            for name,value in palette.items(): pal+=struct.pack("<H4B",1,*color(value))+string(name)
            chunks.append(chunk(0x2019,pal))
            chunks.append(chunk(0x2020,struct.pack("<I",1)+string(note)))
            data=struct.pack("<H8x",len(tags))
            for name,first,last in tags:
                data+=struct.pack("<HHBH6x3BB",first,last,0,0,69,149,181,0)+string(name)
            chunks.append(chunk(0x2018,data))
            data=struct.pack("<III",1,2,0)+string("contact_pivot")+struct.pack("<IiiIIii",0,0,0,w,h,*pivot)
            chunks.append(chunk(0x2022,data))
        for layer,im in enumerate(images):
            raw=struct.pack("<HhhBHh5xHH",layer,0,0,255,2,0,w,h)+zlib.compress(im.tobytes(),9)
            chunks.append(chunk(0x2005,raw))
        payload=b"".join(chunks)
        output.append(struct.pack("<IHHH2xI",len(payload)+16,0xF1FA,len(chunks),durations[f],len(chunks))+payload)
    payload=b"".join(output)
    header=struct.pack("<IHHHHHIHII B3x HBBhhHH",len(payload)+128,0xA5E0,len(frames),w,h,32,1,100,0,0,0,len(palette),1,1,0,0,w,h)
    path.write_bytes(header.ljust(128,b"\0")+payload)


def read_ase(path):
    data=path.read_bytes()
    size,magic,count,w,h,depth=struct.unpack_from("<IHHHHH",data)
    assert size==len(data) and magic==0xA5E0 and depth==32
    layers=[]; frames=[]; durations=[]; tags={};pivot=[w//2,h//2]; cells=[]
    offset=128
    def read_string(payload,pos):
        n=struct.unpack_from("<H",payload,pos)[0]
        return payload[pos+2:pos+2+n].decode(),pos+2+n
    for f in range(count):
        length,magic,old,duration,new=struct.unpack_from("<IHHH2xI",data,offset)
        assert magic==0xF1FA
        cellmap={};pos=offset+16
        for _ in range(new or old):
            n,kind=struct.unpack_from("<IH",data,pos); p=data[pos+6:pos+n]
            if kind==0x2004:
                flags,layer_type,child,_,_,blend,opacity=struct.unpack_from("<6HB",p)
                name,_=read_string(p,16)
                assert layer_type==0 and blend==0,"Exporter supports normal image layers; use Aseprite CLI for groups/blend effects."
                layers.append({"name":name,"visible":bool(flags&1),"opacity":opacity})
            elif kind==0x2005:
                layer,x,y,opacity,cel_type,z=struct.unpack_from("<HhhBHh",p)
                assert z==0,"Nonzero cel Z-order requires Aseprite CLI."
                if cel_type==1:
                    link=struct.unpack_from("<H",p,16)[0]
                    im=cells[link][layer][0].copy()
                else:
                    assert cel_type in [0,2]
                    cw,ch=struct.unpack_from("<HH",p,16)
                    raw=zlib.decompress(p[20:]) if cel_type==2 else p[20:]
                    im=Image.frombytes("RGBA",(cw,ch),raw)
                cellmap[layer]=(im,x,y,opacity)
            elif kind==0x2018:
                n_tags=struct.unpack_from("<H",p)[0];at=10
                for _ in range(n_tags):
                    first,last,direction=struct.unpack_from("<HHB",p,at)
                    name,at=read_string(p,at+17)
                    assert direction==0
                    tags[name]={"from":first,"to":last}
            elif kind==0x2022:
                keys,flags,_=struct.unpack_from("<III",p)
                name,at=read_string(p,12)
                if name=="contact_pivot" and keys and flags&2:
                    extra=16 if flags&1 else 0
                    pivot=list(struct.unpack_from("<ii",p,at+20+extra))
            pos+=n
        im=Image.new("RGBA",(w,h))
        for layer,info in enumerate(layers):
            if not info["visible"] or layer not in cellmap: continue
            cel,x,y,opacity=cellmap[layer]
            cel=cel.copy()
            total=opacity*info["opacity"]/65025
            if total<1: cel.putalpha(cel.getchannel("A").point(lambda a:round(a*total)))
            im.alpha_composite(cel,(x,y))
        cells.append(cellmap);frames.append(im);durations.append(duration);offset+=length
    assert offset==len(data)
    return frames,{"cell":[w,h],"pivot":pivot,"layers":[i["name"] for i in layers],"tags":tags,"durations_ms":durations}


def export(name,columns):
    frames,meta=read_ase(SOURCE/(name+".aseprite"))
    w,h=meta["cell"];rows=math.ceil(len(frames)/columns)
    sheet=Image.new("RGBA",(columns*w,rows*h))
    for i,im in enumerate(frames): sheet.alpha_composite(im,((i%columns)*w,(i//columns)*h))
    filename={"small_top_002b":"small_top","power_fx_002b":"effects","power_icons_002b":"icons","power_cards_002b1":"cards"}[name]+".png"
    sheet.save(OUT/filename,optimize=True)
    meta.update({"texture":filename,"columns":columns,"frame_count":len(frames),"source":"../source-art/"+name+".aseprite"})
    return meta


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--author",action="store_true",help="Overwrite only the three original 002B sources")
    parser.add_argument("--author-cards",action="store_true",help="Author 002B.1 cards and revised compact icons; preserve combat FX/small top sources")
    args=parser.parse_args()
    SOURCE.mkdir(parents=True,exist_ok=True);OUT.mkdir(parents=True,exist_ok=True)
    if args.author:
        for name,factory in [("small_top_002b",small_frames),("power_fx_002b",effect_frames),("power_icons_002b",icon_frames)]:
            write_ase(SOURCE/(name+".aseprite"),*factory())
    if args.author_cards:
        for name,factory in [("power_cards_002b1",card_frames),("power_icons_002b",compact_icon_frames)]:
            write_ase(SOURCE/(name+".aseprite"),*factory(),note="Task 002B.1 / hand-authored integer mechanical plates / 12 named colours / no resampling / six-frame card loops")
    manifest={"version":1,"native_pixels":True,"filter":"nearest","projection":"fixed 2:1 ground plane; no whole-sprite rotation", "small_top":export("small_top_002b",8),"effects":export("power_fx_002b",8),"icons":export("power_icons_002b",6)}
    if (SOURCE/"power_cards_002b1.aseprite").exists():
        manifest["version"]=2
        manifest["cards"]=export("power_cards_002b1",6)
    (OUT/"manifest.json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
    # Review sheet is intentionally outside source assets; no arena source touched.
    print("Exported native sources: 8 small-top, 48 effect, 6 icon" + (", 36 animated card frames." if "cards" in manifest else " frames."))


if __name__=="__main__": main()
