"""Task 002C native editable production art: export by default, never rebuild 002B.

Edit the three new Aseprite masters, then run this script without flags. The
explicit --author-new switch recreates ONLY the 002C masters from the original
integer cluster definitions below. Do not use it after manually editing them.
The maintained normal-layer Aseprite reader/writer is shared with build_power_art.
No existing source file or atlas is exported, resampled or reconstructed here.
"""
from pathlib import Path
import argparse
import json
import math
from PIL import Image, ImageDraw
import build_power_art as native

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source-art"
OUT = ROOT / "assets/powers"
IDS = ["dead_centre", "redline_ii", "dead_centre_ii", "afterimage_ii",
       "runaway", "breakneck", "bulwark", "counterweight", "ghost_circuit", "slipstream"]
CARD_TIMINGS = [110, 90, 75, 75, 100, 170]
PALETTE = dict(native.P, mint="#72dcb1", green="#267969", violet="#796cac")
native.P.update(PALETTE)
color, canvas, pts, sector, ray = native.color, native.canvas, native.pts, native.sector, native.ray
bearing, teeth, stepped_ring = native.bearing, native.teeth, native.stepped_ring


def poly(im, points, ink, outline=None):
    d = ImageDraw.Draw(im)
    d.polygon([(round(x), round(y)) for x, y in points], fill=color(ink))
    if outline:
        d.line([(round(x), round(y)) for x, y in points] + [points[0]], fill=color(outline), width=1)


def line(im, points, ink, width=1, alpha=255):
    ImageDraw.Draw(im).line([(round(x), round(y)) for x, y in points], fill=color(ink, alpha), width=width)


def chevron(im, x, y, size=4, ink="ice", direction=1):
    line(im, [(x-size*direction,y-size*.5),(x,y),(x-size*direction,y+size*.5)], ink, 2)


def plate(im, x, y, sx, sy, ink="steel", light="silver"):
    poly(im, [(x-sx,y),(x,y-sy),(x+sx,y),(x,y+sy)], "ink")
    poly(im, [(x-sx+2,y),(x,y-sy+1),(x+sx-2,y),(x,y+sy-1)], ink)
    line(im, [(x-sx+3,y),(x,y-sy+2),(x+sx-3,y)], light)


def clamp(im, x, y, side=1, size=7, light="ice", depth=3):
    # Authored ground bracket: diagonal jaw, physical depth, bolt, locking tooth.
    poly(im, [(x,y),(x+size*side,y-size*.5),(x+(size+3)*side,y-size*.5+2),
              (x+(size+3)*side,y+depth),(x+3*side,y+size*.5+depth),(x,y+size*.5)], "ink")
    poly(im, [(x+side,y),(x+size*side,y-size*.5+1),(x+(size+2)*side,y-size*.5+3),
              (x+3*side,y+size*.5),(x+side,y+size*.5-1)], "steel")
    line(im, [(x+side,y),(x+size*side,y-size*.5+1),(x+(size+2)*side,y-size*.5+3)], light, 2)
    d=ImageDraw.Draw(im)
    d.rectangle((x+3*side-1,y,x+3*side+1,y+2),fill=color("ink"));d.point((x+3*side,y),fill=color("silver"))


def sparks(im, center, f, ink="gold", count=6, radius=14, squash=.5):
    for k in range(count):
        a=k*math.tau/count+.21
        r=radius+f*3
        ray(im,center,r,max(2,8-f),a,color(ink, max(40,255-f*30)),1 if f>2 else 2,squash)


def card_frames():
    layers=["industrial backplate", "ground braces and machine depth", "editable rotor and mechanism",
            "route force and stress", "confirmation glints and fragments"]
    frames=[];tags=[]
    for row,name in enumerate(IDS):
        first=len(frames)
        for f in range(6):
            im=[canvas(64) for _ in layers]
            back,base,machine,energy,glints=im
            native.card_backdrop(back,0 if name in ["dead_centre","dead_centre_ii","bulwark","ghost_circuit","slipstream","afterimage_ii"] else 2)
            m=ImageDraw.Draw(machine);e=ImageDraw.Draw(energy);g=ImageDraw.Draw(glints)
            phase=f*math.pi/12
            if name=="dead_centre":
                plate(base,32,39,24,12,"dark","steel")
                bearing(machine,32,29,14,phase,squash=.6)
                off=[5,3,1,0,0,1][f]
                for x,y,s in [(16-off,34,1),(48+off,34,-1),(19-off,44,1),(45+off,44,-1)]:
                    clamp(energy,x,y,s,6,"cyan",2)
                line(glints,[(32,40),(32,45),(28,48),(36,48)],"ice",2)
                if f in [2,3]:sparks(glints,(32,45),f-2,"ice",4,13)
            elif name=="redline_ii":
                # A hot rotor with two exhaust stacks and repeated pressure tears.
                for x in [14,45]:
                    poly(base,[(x,28),(x+4,24),(x+6,34),(x+6,43),(x,46)],"ink")
                    line(machine,[(x+1,29),(x+4,26),(x+4,40)],"oxide",3)
                    for y in [30,34,38]:line(machine,[(x+1,y),(x+4,y-1)],"gold")
                bearing(machine,32,30,18,phase,True,.64)
                teeth(energy,32,30,19,phase,10,.64,"red",6)
                for a in [phase,phase+math.pi]:sector(glints,32,30,22,a,.7,color("white"),2,.64)
                for k in range(3):
                    x=11+k*21; y=12+(f+k)%3
                    line(energy,[(x,y+9),(x+2,y+5),(x+1,y+1),(x+4,y-2)],"red",2)
                    line(glints,[(x,y+7),(x+1,y+3)],"gold")
                line(glints,[(20,50),(27,46),(32,51),(39,46),(45,49)],"red",2)
            elif name=="dead_centre_ii":
                plate(base,32,40,27,15,"steel","silver")
                for x,y,s in [(8,34,1),(56,34,-1),(10,46,1),(54,46,-1)]:clamp(machine,x,y,s,10,"ice",4)
                bearing(machine,32,29+[0,1,2,2,2,1][f],16,phase,squash=.6)
                for y in [42,46]:line(energy,[(24,y),(32,y+4),(40,y)],"cyan",2)
                if f in [2,3,4]:
                    line(glints,[(10,32),(14,30),(18,32)],"white",2)
                    line(glints,[(46,32),(50,30),(54,32)],"white",2)
                for x in [13,50]:line(glints,[(x,49),(x,53),(x+3,54)],"ice")
            elif name=="afterimage_ii":
                route=[(10,49),(18,40),(32,42),(44,26),(51,19)]
                line(base,route,"ink",5);line(energy,route,"blue",3);line(energy,route,"cyan")
                for k,(x,y) in enumerate(route[1:-1]):
                    plate(energy,x,y,5,3,"blue","ice")
                    chevron(glints,x+2+(f+k)%3,y-1,3,"ice")
                bearing(machine,46,21,11,phase,squash=.6)
                line(glints,[(10,46),(13,44),(16,44)],"ice")
                for k in range(2):sector(glints,18+k*12,40-k*6,9,phase,.9,color("cyan"),2,.6)
            elif name=="runaway":
                # Three torn directional wake lanes persist while the hot rotor jitters.
                for k in range(3):
                    y=26+k*9
                    line(base,[(9,y+10),(20,y+3),(28,y+4),(39,y-5)],"oxide",3)
                    line(energy,[(8,y+10),(17,y+6),(21,y+2),(27,y+3),(39,y-5)],"red",2)
                    line(glints,[(11+(f+k)%3,y+8),(20,y+4)],"gold")
                bearing(machine,37+(f%2),26,17,phase*2,True,.64)
                teeth(energy,37,26,18,phase*2+.3,9,.64,"orange",5+(f%3))
                for k in range(3):
                    a=phase*2+k*math.tau/3
                    q=pts(37,26,22,[a,a+.25],.64)
                    line(glints,[q[0],(q[0][0]+(3 if k%2 else -3),q[0][1]-4),q[1]],"white",2)
                for x,y in [(9,51),(15,54),(20,51)]:line(glints,[(x,y),(x+2,y-2)],"orange")
            elif name=="breakneck":
                # Charge is compressed on the left, then committed down one corridor.
                line(base,[(9,45),(52,24)],"oxide",7);line(energy,[(9,45),(52,24)],"red",3)
                for k in range(3):chevron(energy,31+k*8,36-k*4,5,"gold")
                x,y=[(24,36),(24,36),(26,35),(30,33),(41,27),(48,24)][f]
                bearing(machine,x,y,13,phase,True,.63)
                for k in range(3):
                    line(glints,[(x-18-k*3,y+4+k*3),(x-7,y+1+k*2)],"gold" if k==1 else "orange",2)
                if f>=4:
                    poly(glints,[(53,15),(54,20),(60,21),(56,24),(58,30),(53,27),(48,30),(49,24),(46,21),(51,20)],"white")
                    sparks(glints,(53,23),f-4,"gold",6,7,.75)
                else:
                    line(energy,[(11,39),(12,34),(16,31)],"white",2)
                    line(energy,[(18,48),(13,47),(11,44)],"gold",2)
            elif name=="bulwark":
                plate(base,35,41,24,13,"steel","silver")
                # Massive floor-locked vise, a small incoming body visibly fails.
                for x,y,s in [(12,34,1),(58,34,-1),(13,46,1),(57,46,-1)]:clamp(machine,x,y,s,12,"ice",5)
                bearing(machine,35,29,16,phase,squash=.58)
                poly(energy,[(20,38),(25,41),(35,46),(46,41),(50,37),(49,43),(36,51),(24,45)],"blue")
                line(glints,[(21,38),(27,41),(35,45),(44,41),(49,38)],"ice",2)
                incoming=[(9,27),(12,28),(15,29),(12,29),(9,30),(7,31)][f]
                bearing(energy,*incoming,6,phase,True,.58)
                if f in [2,3]:
                    sparks(glints,(18,32),f-2,"white",5,5,.85)
                    line(glints,[(20,23),(20,31),(24,34)],"white",2)
                for x in [25,44]:line(glints,[(x,48),(x,53)],"cyan",2)
            elif name=="counterweight":
                plate(base,31,42,23,11,"dark","steel")
                for x,s in [(11,1),(51,-1)]:clamp(machine,x,39,s,9,"gold",3)
                bearing(machine,31,30,15,phase,squash=.6)
                # Force visibly accumulates in paired flywheel stacks, then vents right.
                for k in range(4):
                    for x in [21,38]:
                        poly(energy,[(x,43-k*4),(x+5,41-k*4),(x+5,43-k*4),(x,45-k*4)],"gold" if k<=f%5 else "oxide")
                line(glints,[(7,23),(15,27),(19,29)],"cyan",2)
                chevron(glints,18,29,4,"ice")
                if f in [3,4]:
                    for k in range(3):chevron(glints,45+k*5,28-k*2,4,"gold")
                    line(glints,[(33,28),(54,19)],"white",2)
                else:sector(glints,31,30,19,phase,.7,color("gold"),2,.6)
            elif name=="ghost_circuit":
                route=[(10,33),(31,15),(54,31),(33,49),(10,33)]
                line(base,route,"ink",6);line(energy,route,"green",4);line(energy,route,"mint",2)
                for x,y in route[:-1]:plate(machine,x,y,5,3,"green","mint")
                # A filled enclosed pressure field distinguishes closure from a lane.
                if f>=2:
                    for y in [26,31,36,41]:
                        half=12-abs(33-y)//2
                        line(energy,[(32-half,y),(32+half,y)],"green",1,170)
                    plate(glints,32,32,8+(f%2),5,"green","ice")
                x,y=[(10,33),(20,24),(31,15),(43,23),(54,31),(33,49)][f]
                bearing(machine,x,y-3,7,phase,squash=.55)
                if f in [2,3]:
                    poly(glints,[(31,11),(33,15),(39,15),(35,18),(36,23),(31,20),(27,24),(27,18),(22,16),(28,15)],"white")
                for k in range(3):
                    x,y=route[(f+k)%4]
                    g.point((x+2,y),fill=color("white"))
            elif name=="slipstream":
                route=[(10,27),(16,20),(28,24),(37,39),(49,43),(55,36),(50,29),(37,31),(25,45),(13,43),(10,36),(16,30),(28,31),(40,20),(51,22)]
                line(base,route,"ink",5);line(energy,route,"blue",3);line(energy,route,"cyan")
                for x,y in [(21,29),(39,32),(49,39)]:chevron(glints,x+(f%2),y,4,"ice")
                x,y=[(16,22),(27,26),(35,34),(43,40),(51,34),(37,29)][f]
                bearing(machine,x,y-2,8,phase,squash=.6)
                # At the crossing, the lane becomes a local propulsion engine.
                if f>=2:
                    plate(glints,31,32,6,4,"cyan","white")
                    for k in range(3):line(glints,[(28-k*4,37+k*2),(36-k*3,31+k*2)],"ice",2)
                line(glints,[(12,43),(15,43),(18,40)],"ice")
            frames.append(im)
        tags.append((name,first,len(frames)-1))
    return frames,layers,tags,CARD_TIMINGS*len(IDS),(32,32)


def icon_frames():
    frames=[]
    for name in IDS:
        im=canvas(16);d=ImageDraw.Draw(im)
        d.polygon([(2,0),(13,0),(15,2),(15,13),(13,15),(2,15),(0,13),(0,2)],fill=color("ink"))
        line(im,[(2,14),(13,14),(14,13)],"steel")
        if name in ["dead_centre","dead_centre_ii","bulwark"]:
            plate(im,8,9,6,4,"dark","steel")
            d.rectangle((5,4,10,8),fill=color("silver"));d.rectangle((6,5,9,7),fill=color("blue"))
            for x,s in [(2,1),(13,-1)]:line(im,[(x,5),(x,10),(x+3*s,12)],"ice",2)
            if name!="dead_centre":line(im,[(4,11),(8,13),(12,11)],"cyan",2)
            if name=="bulwark":line(im,[(2,2),(2,4),(4,5)],"white",2);line(im,[(11,3),(13,3),(13,5)],"ice",2)
        elif name in ["redline_ii","runaway","breakneck"]:
            if name=="breakneck":
                line(im,[(2,12),(13,5)],"red",3);chevron(im,13,5,5,"white")
                d.rectangle((4,7,7,10),fill=color("gold"));line(im,[(1,8),(4,8)],"orange")
            else:
                teeth(im,9,6,4,.2,7,.7,"orange",3)
                sector(im,9,6,4,0,math.tau-.5,color("red"),2,.7)
                d.rectangle((8,5,10,7),fill=color("white"))
                if name=="runaway":
                    line(im,[(1,13),(4,9),(6,10),(8,6)],"red",2)
                    line(im,[(3,13),(7,11),(11,12)],"gold")
                else:line(im,[(3,3),(3,6)],"gold",2);line(im,[(12,10),(12,12)],"red",2)
        elif name=="counterweight":
            for k in range(3):line(im,[(4,11-k*3),(7,12-k*3)],"gold",2)
            d.rectangle((7,5,10,9),fill=color("silver"));line(im,[(1,7),(4,7)],"cyan",2)
            chevron(im,13,7,4,"white")
        elif name=="ghost_circuit":
            line(im,[(2,8),(8,2),(14,8),(8,14),(2,8)],"mint",2)
            d.rectangle((6,6,9,9),fill=color("green"));d.point((8,7),fill=color("white"))
        elif name=="slipstream":
            line(im,[(2,4),(5,3),(11,11),(14,10),(14,6),(11,5),(5,12),(2,11),(2,7),(5,6),(11,3)],"cyan",2)
            chevron(im,10,7,3,"white")
        else:
            line(im,[(2,12),(6,8),(10,8),(14,3)],"cyan",2)
            for x,y in [(4,10),(8,8),(12,5)]:line(im,[(x-2,y+2),(x+2,y-2)],"ice",2)
        frames.append([im])
    return frames,["independent compact mechanism glyphs"],[(n,i,i) for i,n in enumerate(IDS)],[100]*len(IDS),(8,8)


def effect_frames():
    layers=["projected floor locks and chassis", "stress trajectory and force plates", "energised mechanical surfaces", "contact flashes and fragments"]
    frames=[];tags=[];durations=[]
    def add(name,count,timing,paint):
        first=len(frames)
        for f in range(count):
            im=[canvas(128) for _ in layers];paint(im,f);frames.append(im)
            durations.append(timing[f] if isinstance(timing,list) else timing)
        tags.append((name,first,len(frames)-1))
    def corona(im,f,wild=False):
        # Segmented vented plates hug the rotor; no filled halo obscures the top.
        r=27+(f%2)*2
        for k in range(10):
            a=k*math.tau/10+f*.19
            sector(im[1],64,50,r,a,.30,color("oxide",220),4)
            tooth=pts(64,50,r,[a+.10,a+.26])+pts(64,50,r+(9 if wild else 5),[a+.26,a+.16])
            poly(im[2],tooth,"red" if wild else "orange")
            sector(im[3],64,50,r+1,a+.11,.13,color("gold"),2)
        if wild:
            for k in range(3):
                a=f*.32+k*math.tau/3
                q=pts(64,50,32,[a,a+.4])
                line(im[3],[q[0],(q[0][0]+4,q[0][1]-7),q[1]],"white",2)
            line(im[1],[(40,64),(47,59),(54,61),(61,57)],"red",2)
        else:
            for x in [37,89]:
                line(im[1],[(x,49),(x-2,42),(x+1,38),(x-1,33)],"red",2)
                line(im[3],[(x,47),(x-1,40)],"gold")
    add("redline_ii",6,45,lambda im,f:corona(im,f))
    add("runaway",6,[35,40,30,35,30,45],lambda im,f:corona(im,f,True))
    def hit(im,f):
        sparks(im[3],(64,50),f,"gold",9,10,.7)
        if f<3:
            poly(im[2],[(64-10+f*2,50),(61,47),(64,38+f*3),(67,47),(76-f*2,50),(67,53),(64,60-f*2),(61,53)],"white")
        for k in range(3):
            a=k*math.tau/3+f*.16
            sector(im[1],64,50,17+f*5,a,.6,color("red",240-f*30),3,.6)
    add("runaway_hit",6,45,hit)
    def charge(im,f):
        # Eight separately authored isometric headings; runtime never rotates cels.
        a=f*math.tau/8; center=(64,50)
        tail=pts(*center,52,[a+math.pi])[0]
        ends=pts(*center,15,[a-math.pi/2,a+math.pi/2])
        poly(im[1],[ends[0],tail,ends[1]],"oxide")
        line(im[2],[ends[0],tail,ends[1]],"red",2)
        for k in range(3):
            c=pts(*center,22+k*11,[a+math.pi])[0]
            side=pts(*c,8,[a+math.pi/2,a-math.pi/2])
            tip=pts(*c,8,[a])[0]
            line(im[3],[side[0],tip,side[1]],"gold",2)
        front=pts(*center,24,[a])[0]
        left,right=pts(*center,24,[a-.65,a+.65])
        line(im[3],[left,front,right],"white",3)
    add("breakneck_charge_headings",8,70,charge)
    def catastrophe(im,f):
        if f<3:
            size=[12,21,10][f]
            poly(im[3],[(64-size,52),(60,48),(64,52-size),(68,48),(64+size,52),(68,57),(64,52+size),(60,57)],"white")
        sparks(im[2],(64,52),f,"gold",10,14,.7)
        for k in range(5):
            a=k*math.tau/5+.23
            q=pts(64,64,18+f*6,[a],.5)[0]
            line(im[1],[q,(q[0]-3,q[1]+2),(q[0]+1,q[1]+5)],"oxide",2,240-f*30)
    add("breakneck_impact",6,[35,45,55,70,90,110],catastrophe)
    def anchor(im,f,strong=False,wall=False):
        phase=[4,3,1,0,0,1][f]
        size=12 if wall else 9 if strong else 6
        offset=4 if wall else 2 if strong else 0
        for x,y,s in [(44-phase-offset,58,1),(84+phase+offset,58,-1),(45-phase-offset,70,1),(83+phase+offset,70,-1)]:
            clamp(im[0],x,y,s,size,"ice" if strong or wall else "cyan",4 if wall else 2)
        if strong or wall:
            line(im[1],[(41-offset,70),(52,77),(64,81),(76,77),(87+offset,70)],"blue",3)
            line(im[2],[(42-offset,69),(53,75),(64,79),(75,75),(86+offset,69)],"ice",1 if not wall else 2)
            for x in [51,77]:line(im[2],[(x,76),(x,82),(x+3,84)],"cyan",2)
        else:line(im[2],[(56,68),(64,72),(72,68)],"cyan")
        if wall:
            for x,s in [(37,1),(91,-1)]:
                line(im[1],[(x,54),(x,66),(x+10*s,71)],"steel",4)
                line(im[3],[(x+s,54),(x+s,64),(x+10*s,69)],"ice",2)
    add("anchor",6,95,lambda im,f:anchor(im,f))
    add("anchor_ii",6,85,lambda im,f:anchor(im,f,True))
    def broken(im,f):
        for k,(x,y,s) in enumerate([(43,59,-1),(85,59,1),(43,70,-1),(85,70,1)]):
            line(im[1],[(x+f*3*s,y+f),(x+f*3*s+5*s,y+f-3)],"steel",2,240-f*30)
        sparks(im[3],(64,65),f,"ice",6,15)
    add("anchor_break",6,60,broken)
    add("bulwark",6,100,lambda im,f:anchor(im,f,True,True))
    def bulwark_hit(im,f):
        anchor(im,3,True,True)
        if f<3:
            for x,s in [(37,1),(91,-1)]:
                line(im[3],[(x,55),(x,66),(x+9*s,71)],"white",3)
        # Flattened pressure escapes under the brace, with vertical metal sparks.
        r=21+f*6
        for a in [.10,math.pi+.10]:sector(im[2],64,68,r,a,1.05,color("ice",255-f*35),2,.35)
        for x,s in [(38,-1),(90,1)]:
            line(im[3],[(x+f*3*s,62),(x+f*4*s,54-f*2)],"gold",2,255-f*33)
        for x in [43,84]:line(im[1],[(x,77),(x-4,81),(x-2,83)],"steel",2,230-f*28)
    add("bulwark_impact",6,[35,45,55,65,85,110],bulwark_hit)
    def store_state(im,f):
        anchor(im,3,True)
        # Six literal compression-stack stages correspond to stored physical force.
        for k in range(5):
            for x,s in [(43,1),(78,-1)]:
                line(im[1],[(x,62-k*4),(x+7*s,65-k*4)],"gold" if k<f else "oxide",2)
        if f>0:
            for k in range(f):sector(im[2],64,50,24,k*math.tau/5+.15,.55,color("gold"),2)
        if f>=4:line(im[3],[(54,66),(59,64),(64,67),(69,64),(74,66)],"white")
    add("counterweight",6,100,store_state)
    def store_hit(im,f):
        r=35-f*4
        for a in [math.pi*.2,math.pi*.8,math.pi*1.2,math.pi*1.8]:
            start=pts(64,53,r,[a])[0];end=pts(64,53,r-7,[a])[0]
            line(im[2],[start,end],"ice",2,255-f*20)
        if f in [3,4]:line(im[3],[(44,54),(50,58),(56,56),(64,60),(72,56),(78,58),(84,54)],"gold",2)
    add("counterweight_store",6,60,store_hit)
    def release(im,f):
        # A broken stored race becomes separate linear steel projectiles.
        for k in range(7):
            a=k*math.tau/7+.1
            q=pts(64,54,11+f*8,[a],.55)[0]
            ray(im[2],(64,54),11+f*8,7,a,color("gold",255-f*32),3,.55)
            line(im[3],[q,(q[0]+3,q[1]-1)],"white",1,255-f*32)
        if f<2:plate(im[3],64,55,13,7,"gold","white")
    add("counterweight_release",6,[35,45,55,65,85,110],release)
    def echo(im,f):
        for k in range(3):
            a=f*.22+k*math.tau/3
            sector(im[2],64,52,20,a,.85,color("cyan",220-f*28),3)
            sector(im[3],64,52,21,a+.1,.65,color("ice",235-f*31),1)
        line(im[1],[(39-f,63),(45-f,59),(53,59)],"blue",2,230-f*28)
    add("afterimage_ii",6,70,echo)
    def closure(im,f):
        # Four inward-closing sockets announce a route junction, not a blast.
        gap=[14,10,6,2,0,3][f]
        for a in range(4):
            angle=a*math.pi/2+.15
            q=pts(64,64,9+gap,[angle])[0]
            left,right=pts(*q,5,[angle+math.pi/2,angle-math.pi/2])
            tip=pts(*q,6,[angle+math.pi])[0]
            line(im[2],[left,tip,right],"mint",2)
        if f>=3:
            plate(im[3],64,64,8,4,"mint","white")
            line(im[3],[(64,50),(64,57)],"white",2)
    add("ghost_closure",6,[60,55,45,50,90,120],closure)
    def activation(im,f):
        # Circuit node pulse: squared lattice, inward pressure arrows, green light.
        r=9+f*6
        for k in range(4):
            a=k*math.pi/2
            q=pts(64,64,r,[a],.5)[0]
            plate(im[2],*q,5,3,"green","mint")
            ray(im[3],(64,64),r-5,-5,a,color("ice",255-f*30),2,.5)
        if f<3:
            for y in [58,62,66,70]:line(im[1],[(50,y),(78,y)],"green",1,200-f*40)
            plate(im[3],64,64,9-f*2,5,"mint","white")
    add("ghost_activation",6,65,activation)
    def slip(im,f):
        # Open chevrons and paired propulsion jets, visibly different from closure.
        for k in range(3):
            x=45+k*10+f*2;y=67-k*5-f
            chevron(im[2],x,y,8,"cyan")
            line(im[3],[(x-7,y+2),(x,y-2)],"ice",1,255-f*28)
        if f<3:
            line(im[3],[(49,72),(62,65),(76,60)],"white",2)
        for k in range(2):line(im[1],[(34-f*3,73+k*5),(46-f,66+k*5)],"cyan",2,255-f*31)
    add("slipstream_cross",6,55,slip)
    def acquisition(im,f,mutation=False):
        # Plates snap inward before the mechanic appears; no fabricated impact.
        r=[41,32,23,18,26,34][f]
        for k in range(4):
            a=k*math.pi/2+.2
            q=pts(64,58,r,[a],.55)[0]
            plate(im[1],*q,8 if mutation else 5,4,"steel","gold" if mutation else "ice")
            ray(im[3],(64,58),r-7,5,a,color("white",255-f*20),2,.55)
        if f in [2,3]:
            line(im[3],[(64,26),(64,39)],"gold" if mutation else "ice",2)
            poly(im[3],[(60,31),(64,26),(68,31),(66,31),(66,37),(62,37),(62,31)],"white")
        if mutation:
            for a in [.15,math.pi+.15]:sector(im[2],64,50,26,a,1.0,color("gold",255-f*20),3)
    add("rank_up",6,[50,55,65,75,95,120],lambda im,f:acquisition(im,f))
    add("mutation_select",6,[45,55,75,95,110,140],lambda im,f:acquisition(im,f,True))
    return frames,layers,tags,durations,(64,64)


def export(source_name,filename,columns):
    frames,meta=native.read_ase(SOURCE/(source_name+".aseprite"))
    w,h=meta["cell"]
    sheet=Image.new("RGBA",(columns*w,math.ceil(len(frames)/columns)*h))
    for i,im in enumerate(frames):sheet.alpha_composite(im,((i%columns)*w,(i//columns)*h))
    sheet.save(OUT/filename,optimize=True)
    meta.update(texture=filename,columns=columns,frame_count=len(frames),source="../source-art/"+source_name+".aseprite")
    return meta


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--author-new",action="store_true",help="Rebuild ONLY the three new 002C masters; do not use after manual edits")
    args=parser.parse_args()
    SOURCE.mkdir(parents=True,exist_ok=True);OUT.mkdir(parents=True,exist_ok=True)
    jobs=[("escalation_cards_002c",card_frames),("escalation_icons_002c",icon_frames),("escalation_fx_002c",effect_frames)]
    if args.author_new:
        for name,factory in jobs:
            frames,layers,tags,timings,pivot=factory()
            # This collection deliberately uses opaque pixel clusters. Runtime
            # fades a whole cel; overlapping fractional-alpha layer colours would
            # introduce extra colours and platform-dependent blend rounding.
            for images in frames:
                for image in images:
                    image.putalpha(image.getchannel("A").point(lambda a:255 if a else 0))
            native.write_ase(SOURCE/(name+".aseprite"),frames,layers,tags,timings,pivot,
                note="Task 002C / original integer mechanical phenomena / fixed 2:1 ground plane / native editable RGBA layers / do not rebuild artist edits",
                palette=PALETTE)
    manifest={"version":1,"native_pixels":True,"filter":"nearest","projection":"fixed 2:1 ground plane; authored headings; no whole-sprite rotation",
              "card_ids":IDS,"cards":export("escalation_cards_002c","escalation_cards.png",6),
              "icons":export("escalation_icons_002c","escalation_icons.png",len(IDS)),
              "effects":export("escalation_fx_002c","escalation_effects.png",8)}
    (OUT/"escalation_manifest.json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
    print("Exported Task 002C: %d card / %d icon / %d FX native cels. Existing masters untouched." %
          (manifest["cards"]["frame_count"],manifest["icons"]["frame_count"],manifest["effects"]["frame_count"]))


if __name__=="__main__":main()
