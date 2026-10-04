"""One-time bespoke motion-family authoring into editable native RGBA masters.

The five family painters deliberately use different subjects, framing, spatial
hierarchy and keyed stories. This is scripted pixel-cluster authorship, not
manual mouse painting. Saved Aseprite cels are the editing authority afterwards;
normal export must never rerun this constructor over an artist's edits.
"""
import argparse
import json
import math
from pathlib import Path
from PIL import Image, ImageDraw
from build_power_art import write_ase

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/source-art/power_identity_002c5'
OUT = ROOT / 'assets/powers/identity'
PAL = {
    'void':'#10151f', 'shadow':'#172b38', 'deep':'#263943',
    'steel':'#4c626e', 'edge':'#748d94', 'silver':'#abc0c7',
    'white':'#e3e8dc', 'blue':'#245c7b', 'cyan':'#4595b5',
    'ice':'#a5e5e5', 'oxide':'#a34335', 'hot':'#ef713b',
    'gold':'#ffc05a', 'red':'#ed654c', 'teal':'#247b79',
    'mint':'#52c8b5', 'pale':'#c8f5d4', 'brass':'#b9bb91',
}
CARD_LAYERS = ['01 scene floor and direction','02 cast shadow and load-bearing chassis',
               '03 rotor plates and bearing','04 mechanical action and recoil',
               '05 keyed highlights and fragments']
FX_LAYERS = ['01 grounded scar and contact reaction','02 physical mechanism and brackets',
             '03 moving force plates','04 keyed sparks and travel fragments']
ICON_LAYERS = ['01 compact mechanical silhouette','02 identifying action and negative space']
HEADINGS = {'e':0,'ne':-math.pi/4,'n':-math.pi/2,'nw':-3*math.pi/4,
            'w':math.pi,'sw':3*math.pi/4,'s':math.pi/2,'se':math.pi/4}
STATES = {
    'redline':['redline','redline_ii','runaway','breakneck'],
    'iron_comet':['iron_comet','iron_comet_ii'],
    'high_gear':['high_gear','high_gear_ii','terminal_velocity','flow_state'],
    'orbit_drive':['orbit_drive','orbit_drive_ii'],
    'clutch':['clutch','clutch_ii'],
}
CARD_TIMES = {
    'redline':[130,95,75,60,45,45,55,65,75,90,100,150],
    'runaway':[110,85,60,55,40,40,45,50,70,80,110,155],
    'breakneck':[160,120,90,75,50,35,35,45,80,105,140,190],
    'iron_comet':[145,110,85,65,40,35,35,50,75,100,140,175],
    'high_gear':[120,90,70,55,45,45,55,65,75,90,100,150],
    'terminal_velocity':[130,90,60,40,35,35,40,50,65,90,115,160],
    'flow_state':[95,90,85,80,75,75,75,80,85,90,100,115],
    'orbit_drive':[135,100,80,60,50,45,50,60,75,95,115,155],
    'clutch':[180,110,145,60,45,90,40,65,110,85,140,190],
}


def c(name):
    return (*bytes.fromhex(PAL.get(name,name).lstrip('#')),255)


def layers(size, names):
    return [Image.new('RGBA',size) for _ in names]


def polygon(im, points, fill, outline=None):
    points=[(round(x),round(y)) for x,y in points]
    ImageDraw.Draw(im).polygon(points,fill=c(fill))
    if outline:
        ImageDraw.Draw(im).line(points+[points[0]],fill=c(outline),width=1)


def line(im, points, fill, width=1):
    ImageDraw.Draw(im).line([(round(x),round(y)) for x,y in points],fill=c(fill),width=width)


def rect(im, bounds, fill):
    ImageDraw.Draw(im).rectangle(tuple(round(v) for v in bounds),fill=c(fill))


def oval(im,x,y,rx,ry,fill):
    ImageDraw.Draw(im).ellipse((round(x-rx),round(y-ry),round(x+rx),round(y+ry)),fill=c(fill))


def chip(im,x,y,kind='silver',length=4,dx=1,dy=-1):
    polygon(im,[(x,y),(x+dx*length,y+dy*length*.5),(x+dx*(length+1),y+dy*length*.5+2),(x+1,y+2)],kind)


def stepped_arc(im,cx,cy,rx,ry,start,end,fill,width=1):
    points=[(cx+math.cos(a)*rx,cy+math.sin(a)*ry) for a in [start+(end-start)*i/22 for i in range(23)]]
    line(im,points,fill,width)


def ground(im,x,y,rx=17):
    oval(im,x,y,rx,4,'void')
    line(im,[(x-rx+3,y+3),(x+rx-2,y+3)],'deep')


def rotor(im,x,y,r=16,phase=0,kind='heavy',lean=0,compression=0):
    """Solid layered machine with cut blade faces, never a thin generic glyph."""
    h=8-compression
    tip=(x+lean,y+h+13-compression)
    polygon(im,[(x-5,y+h),(x+5,y+h),(tip[0]+2,tip[1]-2),tip,(tip[0]-3,tip[1]-2)],'void')
    polygon(im,[(x-3,y+h),(x+3,y+h),(tip[0]+1,tip[1]-3),(tip[0]-1,tip[1]-1)],'steel')
    line(im,[(x-2,y+h+2),(tip[0],tip[1]-3)],'silver')
    # Thick visible ratchet face; compression changes the authored stack height.
    polygon(im,[(x-r+2,y),(x+r-2,y),(x+r-4,y+h),(x+9,y+h+4),(x-9,y+h+4),(x-r+4,y+h)],'void')
    polygon(im,[(x-r+3,y+2),(x+r-3,y+2),(x+r-5,y+h),(x+8,y+h+2),(x-8,y+h+2),(x-r+5,y+h)],'steel')
    for offset in [-9,-3,4,10]:
        rect(im,(x+offset,y+3,x+offset+2,y+h+1),'deep')
        line(im,[(x+offset,y+3),(x+offset+1,y+3)],'silver')
    count=6 if kind=='hot' else 3 if kind=='fast' else 4
    outer=[]
    for k in range(count*2):
        a=phase+k*math.pi/count
        radius=r if k%2==0 else r-5
        outer.append((x+math.cos(a)*radius,y+math.sin(a)*radius*.43))
    polygon(im,outer,'void')
    accent='oxide' if kind=='hot' else 'blue' if kind=='fast' else 'teal' if kind=='carve' else 'steel'
    for k in range(count):
        a=phase+k*math.tau/count
        q=[(x+math.cos(a-.19)*5,y+math.sin(a-.19)*3),
           (x+math.cos(a-.27)*(r-2),y+math.sin(a-.27)*(r-2)*.43),
           (x+math.cos(a+.20)*(r-1),y+math.sin(a+.20)*(r-1)*.43),
           (x+math.cos(a+.42)*7,y+math.sin(a+.42)*4)]
        polygon(im,q,'silver','steel')
        line(im,[q[0],q[1],q[2]],'white')
        line(im,[q[3],q[2]],accent,2)
    polygon(im,[(x-6,y-2),(x-2,y-5),(x+4,y-4),(x+7,y-1),(x+4,y+3),(x-3,y+3),(x-6,y)],'void')
    polygon(im,[(x-4,y-2),(x,y-4),(x+4,y-2),(x+4,y),(x,y+2),(x-4,y)],accent)
    line(im,[(x-3,y-2),(x,y-3),(x+3,y-2)],'white')
    rect(im,(x-1,y-1,x+1,y),'gold' if kind=='hot' else 'ice' if kind=='fast' else 'brass')


def floor_scene(im,family):
    # Family-specific environmental evidence, never a universal dark plinth.
    if family=='iron_comet':
        polygon(im,[(2,9),(24,2),(35,6),(12,17),(2,18)],'steel','silver')
        polygon(im,[(2,18),(12,17),(35,6),(35,16),(13,28),(2,27)],'deep','void')
        for x,y in [(5,16),(15,12),(26,8)]:
            polygon(im,[(x,y),(x+5,y-2),(x+5,y+5),(x,y+7)],'edge','void')
        line(im,[(3,30),(36,13)],'steel')
        line(im,[(5,52),(15,47),(20,48)],'shadow',2)
        line(im,[(23,57),(30,53),(35,54)],'deep')
    elif family=='orbit_drive':
        # The turning route itself paints the compact floor silhouette.
        for x,y in [(17,57),(28,48),(45,54)]:
            line(im,[(x,y),(x+4,y-2)],'deep')
    elif family=='clutch':
        polygon(im,[(32,53),(42,50),(50,54),(44,58),(35,58)],'shadow')
        line(im,[(38,57),(44,58),(49,55)],'deep')
    elif family=='redline':
        line(im,[(5,55),(14,50),(18,51)],'oxide')
        line(im,[(20,56),(26,53)],'deep')
    else:
        # A broken velocity corridor, long and sparse rather than a floor slab.
        for path in [[(1,60),(14,53),(21,49)],[(4,49),(12,45)],[(16,40),(26,35)]]:
            line(im,path,'shadow',2)


def impact(im,x,y,f,direction=(1,-.5),violent=False):
    if f<0 or f>5:return
    sizes=[3,7,11,8,5,2]
    r=sizes[f]
    if f<3:
        polygon(im,[(x-r,y),(x-2,y-2),(x,y-r),(x+2,y-2),(x+r,y),(x+2,y+2),(x,y+r*.7),(x-2,y+2)],'gold')
        line(im,[(x-r+2,y),(x+r-2,y)],'white',2)
    for k,(dx,dy) in enumerate([(-1,-.4),(.2,-1),(1,-.6),(1,.5),(-.5,.9)]):
        distance=r+3+f*2
        chip(im,x+dx*distance,y+dy*distance*.7,'white' if f<2 else 'gold' if k%2 else 'steel',max(2,6-f),dx,dy)
    if violent and f>=2:
        line(im,[(x-15,y+12),(x-7,y+8),(x-2,y+10),(x+7,y+6)],'steel')


def redline_card(state,f):
    im=layers((64,64),CARD_LAYERS);floor_scene(im[0],'redline')
    deep=state=='redline_ii';runaway=state=='runaway';strike=state=='breakneck'
    if strike:
        xs=[18,18,17,16,20,31,43,48,43,36,29,22]
        ys=[36,36,37,38,36,31,26,23,27,31,34,35]
        x,y=xs[f],ys[f]
        compression=[0,1,2,3,2,0,0,0,0,0,0,0][f]
        rotor(im[1],49,23,10,.4,'heavy')
        for k in range(3):
            line(im[3],[(max(2,x-22-k*4),y+10+k*3),(x-10,y+4+k*2)],'oxide',2)
        ground(im[1],x,y+21);rotor(im[2],x,y,15,f*.36,'hot',0,compression)
        if f<5:
            for xx,yy in [(x-12,y+4),(x-9,y-5)]:
                polygon(im[3],[(xx-3,yy),(xx+2,yy-3),(xx+5,yy+1),(xx,yy+3)],'hot','gold')
        if 5<=f<=9:impact(im[4],47,27,f-5,violent=True)
        if f>=8:
            line(im[3],[(x-9,y+15),(x-5,y+17),(x+5,y+16),(x+9,y+18)],'red')
        return im
    x=38 if not runaway else [29,29,30,28,31,28,32,30,33,29,31,30][f]
    y=31 if not runaway else [31,31,30,32,29,33,30,31,29,32,30,31][f]
    ground(im[1],x,y+22);rotor(im[2],x,y,17,f*.31,'hot')
    heat=[0,1,1,2,3,4,5,6,5,4,2,1][f]
    paths=[[(3,49),(11,46),(16,39),(22,39)],[(7,34),(17,35),(23,28)],[(12,25),(19,24),(22,19)],[(23,15),(30,18)],[(42,12),(46,17)],[(57,23),(53,28)]]
    for k,path in enumerate(paths[:3+int(deep)+int(runaway)*2]):
        moved=[(xx-(heat//2 if k<3 else 0),yy+(heat%2 if k%2 else -heat%2)) for xx,yy in path]
        line(im[3],moved,'oxide',3)
        line(im[3],moved[1:],'hot',2)
        if heat>1:line(im[4],moved[-2:],'gold')
    for k in range(heat+(3 if runaway else 0)):
        px=5+(k*11+f*3)%50;py=13+(k*7+f)%31
        chip(im[4],px,py,'gold' if k%3==0 else 'hot' if k%3==1 else 'steel',2+k%3)
    if deep:
        polygon(im[3],[(48,35),(54,31),(58,32),(55,37),(50,39)],'oxide','gold')
        line(im[3],[(21,47),(26,42),(29,44)],'hot',2)
    if runaway and f in [3,5,6,8]:
        line(im[4],[(9,49),(17,42),(14,38),(24,32)],'red',2)
    return im


def comet_card(state,f):
    im=layers((64,64),CARD_LAYERS);floor_scene(im[0],'iron_comet')
    deep=state.endswith('_ii')
    x=[16,16,14,13,19,29,41,45,40,30,21,16][f]
    y=[30,30,31,32,32,29,26,27,29,30,31,30][f]
    loaded=[0,1,2,3,1,0,0,0,0,0,0,0][f]
    ground(im[1],x,y+20)
    if f>=5:rotor(im[1],51,27,9,.3,'heavy')
    rotor(im[2],x,y,17,f*.23,'heavy',0,loaded)
    if f<5:
        line(im[3],[(5,27),(10,29),(12,35)],'gold',2)
        line(im[3],[(8,18),(11,21),(13,23)],'silver',2)
        if deep:line(im[3],[(3,24),(7,23),(11,27)],'white',2)
    if f in [4,5,6,7]:
        for k in range(2+int(deep)):
            xx=x-12-k*9;yy=y+7+k*4
            polygon(im[3],[(xx-5,yy+3),(xx+2,yy),(xx+4,yy+1),(xx-3,yy+4)],'steel','silver')
    if 6<=f<=10:impact(im[4],49,30,f-6,violent=True)
    if f>7:
        line(im[0],[(19,52),(30,47),(38,46),(47,42)],'edge')
        line(im[0],[(23,55),(32,51),(39,50)],'steel')
    return im


def speed_card(state,f):
    im=layers((64,64),CARD_LAYERS);floor_scene(im[0],'high_gear')
    flow=state=='flow_state';terminal=state=='terminal_velocity';deep=state=='high_gear_ii'
    if flow:
        x=[31,32,34,36,37,36,35,33,31,30,30,31][f]
        y=[26,26,25,25,26,27,28,29,29,29,28,27][f]
        # Long OPEN rails retain their bend, unlike Orbit's crescent floor cut.
        for offset,ink in [(0,'mint'),(4,'silver')]:
            line(im[3],[(2,47+offset),(9,49+offset),(18,49+offset),(27,45+offset),(34,39+offset),(x-3,y+14)],ink,2)
            line(im[4],[(6,47+offset),(15,47+offset),(24,43+offset)],'pale')
        ground(im[1],x,y+20,23);rotor(im[2],x,y,24,f*.27,'fast')
        # Broad front housing and separated guide plates are foreground
        # structure; the thin retained rails lead into this physical mass.
        polygon(im[3],[(x-16,y+6),(x-7,y+7),(x-2,y+11),(x-9,y+14),(x-17,y+11)],'blue','silver')
        line(im[4],[(x-15,y+7),(x-7,y+8),(x-3,y+11)],'ice')
        # Lower-profile split guide shoes, not a surrounding aura.
        line(im[3],[(x-11,y+12),(x-6,y+15),(x,y+16)],'mint',2)
        return im
    x=[39,40,41,43,45,47,49,48,46,44,42,40][f]+(3 if terminal else 0)
    y=[29,29,28,27,26,25,24,24,25,26,27,28][f]-(5 if terminal else 0)
    ground(im[1],x,y+20,24);rotor(im[2],x,y,26 if terminal else 24,f*.38,'fast')
    # A cropped forward mass has a broad machined undercut, rather than a
    # small round glyph centred over the wake. Its nose projects past the card.
    polygon(im[3],[(x+8,y+5),(x+19,y+2),(x+24,y+5),(x+20,y+10),(x+10,y+13)],'blue','silver')
    line(im[4],[(x+10,y+6),(x+18,y+4),(x+22,y+5)],'ice',2)
    spacing=[5,6,7,9,11,13,15,15,13,10,8,6][f]
    for lane in range(3 if deep or terminal else 2):
        yy=y+10+lane*6
        for band in range(3):
            xx=x-15-band*spacing
            length=3+band*2+(4 if terminal else 0)
            line(im[3],[(xx-length,yy+length*.5),(xx,yy)],'steel' if lane%2 else 'cyan',2)
            line(im[4],[(xx-length+1,yy+length*.5-1),(xx,yy-1)],'ice')
    if deep:
        polygon(im[3],[(x-7,y+11),(x+4,y+10),(x+9,y+13),(x+4,y+16),(x-7,y+17)],'blue','silver')
        rect(im[4],(x-2,y+12,x+3,y+13),'ice')
    if terminal and f in [4,5,6,7]:
        line(im[4],[(2,59),(14,53)],'gold')
        line(im[4],[(13,37),(27,30)],'white')
    return im


def orbit_card(state,f):
    im=layers((64,64),CARD_LAYERS);floor_scene(im[0],'orbit_drive')
    deep=state.endswith('_ii')
    xs=[21,25,32,39,44,47,46,42,35,29,24,21]
    ys=[32,29,25,24,26,29,34,37,38,38,36,33]
    x,y=xs[f],ys[f]
    # The scar follows the actual authored TIP route on the floor, not the
    # body-centre trajectory. Its low shallow hook never wraps the rotor.
    feet=[(xx+4,yy+21) for xx,yy in zip(xs,ys)]
    trail=feet[:max(2,f+1)]
    for offset,ink,width in [(2,'steel',4),(-1,'teal',2)]+([(5,'edge',1)] if deep else []):
        line(im[0],[(xx,yy+offset) for xx,yy in trail],ink,width)
    if f>2:
        line(im[3],[(xx,yy+2) for xx,yy in feet[max(0,f-2):f+1]],'mint',2)
    ground(im[1],x,y+20,24);rotor(im[2],x,y,26,f*.30,'carve',lean=4 if f<8 else 2)
    # Broad worn traction plates make the foreground carver unlike Gear's
    # forward-swept housing, even with their common steel world material.
    polygon(im[3],[(x-20,y+5),(x-10,y+7),(x-8,y+11),(x-18,y+10)],'steel','edge')
    line(im[4],[(x-18,y+6),(x-12,y+8)],'mint')
    line(im[4],[(x+11,y+7),(x+17,y+5)],'silver',2)
    for k in range(4 if deep else 2):
        xx=8+(f*4+k*9)%42;yy=51+k%2*4
        chip(im[4],xx,yy,'edge' if k%2 else 'brass',2+k%2,-1,1)
    if f in [3,4,5,6]:
        line(im[3],[(x+13,y+15),(x+9,y+19),(x+3,y+21)],'gold')
    return im


def clutch_card(state,f):
    im=layers((64,64),CARD_LAYERS);floor_scene(im[0],'clutch')
    deep=state.endswith('_ii')
    # Upper mass visibly falls off-axis while the contact bit stays near x41.
    # The catch partially recentres it; it remains under strain afterwards.
    x=[33,29,32,27,30,29,37,37,36,35,34,33][f]
    y=[24,28,25,30,27,29,23,23,24,25,24,25][f]
    lean=41-x
    ground(im[1],41,54,12)
    rotor(im[2],x,y,24,f*.12,'heavy',lean=lean)
    # The large tilted upper mass exposes a loaded lower bearing face. Its
    # teeth and asymmetric support are illustrated at foreground scale.
    polygon(im[3],[(x-15,y+7),(x-8,y+5),(x+10,y+6),(x+17,y+9),(x+9,y+14),(x-9,y+14)],'steel','silver')
    for tooth in [-9,-2,5,12]:
        line(im[4],[(x+tooth,y+8),(x+tooth,y+12)],'deep',2)
        line(im[4],[(x+tooth,y+7),(x+tooth+2,y+7)],'white')
    # The same contact bit remains planted throughout the lean/catch poses.
    # This is a mechanical partial recenter, never an airborne relaunch.
    polygon(im[2],[(39,y+20),(43,y+20),(43,51),(41,54),(39,52)],'steel','void')
    line(im[2],[(40,y+20),(41,51)],'silver')
    # Large single bearing pawl enters from LOW LEFT, not a recovery ring.
    jaw=[3,6,4,9,12,10,15,15,12,9,6,3][f]
    polygon(im[1],[(5,51),(9,44),(17,42),(17,48),(11,53)],'void')
    polygon(im[3],[(9,48),(15,44),(21+jaw,44),(21+jaw,39),(25+jaw,39),(26+jaw,48),(14,51),(9,51)],'steel','silver')
    rect(im[3],(14,45,19,48),'brass')
    for tooth in range(3):line(im[4],[(25+jaw,tooth+40),(27+jaw,tooth+40)],'gold')
    if deep:
        # A second small staggered stop supports the bearing after the first catch.
        polygon(im[3],[(51,44),(54,39),(59,40),(57,48),(51,50)],'steel','silver')
        line(im[4],[(51,43),(54,42)],'brass',2)
    if f in [3,4]:line(im[0],[(33,56),(37,58),(46,56)],'oxide',2)
    if f in [6,7]:
        line(im[4],[(37,42),(41,40),(45,41)],'white',2)
        chip(im[4],31,37,'gold',3,-1,-1)
        chip(im[4],45,45,'white',2,1,1)
    if f in [1,3,5]:
        # Short side-on scrape reveals a strained contact, not a reset ring.
        line(im[4],[(41,53),(46,55),(50,54)],'oxide',2)
    return im


PAINTERS={'redline':redline_card,'iron_comet':comet_card,'high_gear':speed_card,'orbit_drive':orbit_card,'clutch':clutch_card}


def icon(family,state):
    im=layers((16,16),ICON_LAYERS);d=im[0];a=im[1];deep=state.endswith('_ii')
    if family=='redline':
        polygon(d,[(5,4),(10,3),(13,7),(11,11),(6,12),(3,8)],'steel','silver')
        polygon(d,[(4,7),(7,5),(10,6),(12,8),(9,10),(5,9)],'oxide')
        line(d,[(6,6),(9,5),(11,7)],'white')
        line(d,[(6,11),(8,13),(10,11)],'deep',2)
        if state=='breakneck':
            line(a,[(1,13),(5,11),(9,7)],'hot',2)
            polygon(a,[(10,4),(14,4),(14,8),(12,7)],'gold')
        else:
            line(a,[(1,10),(3,7),(2,4),(5,2)],'hot',2)
            line(a,[(9,1),(12,2),(14,6)],'gold')
            if deep or state=='runaway':line(a,[(5,14),(7,12),(11,14),(14,11)],'red',2)
    elif family=='iron_comet':
        polygon(d,[(0,2),(4,0),(5,1),(1,4),(1,8),(0,8)],'edge')
        polygon(d,[(6,5),(11,4),(14,7),(12,11),(8,12),(5,9)],'steel','silver')
        polygon(d,[(6,9),(12,9),(12,12),(8,14),(6,12)],'deep','steel')
        polygon(d,[(7,6),(10,5),(12,7),(10,9),(7,8)],'silver')
        rect(d,(8,6,10,7),'brass')
        line(a,[(1,12),(4,10)],'brass',2)
        line(a,[(3,15),(6,13)],'silver')
        if deep:line(a,[(1,9),(3,8)],'gold')
    elif family=='high_gear':
        if state=='flow_state':
            line(a,[(0,10),(3,12),(6,12),(10,9)],'mint',2)
            line(a,[(1,14),(5,15),(8,13),(11,11)],'silver')
        else:
            for x,y,length in [(0,12,4),(3,8,4),(6,4,3)]:line(a,[(x,y),(x+length,y-2)],'ice',2)
            if state=='terminal_velocity':line(a,[(0,15),(6,12)],'gold')
        polygon(d,[(9,3),(13,2),(15,4),(14,8),(11,10),(8,7)],'steel','silver')
        polygon(d,[(9,4),(12,3),(14,5),(11,7)],'blue')
        line(d,[(10,4),(12,3),(14,4)],'ice')
        line(d,[(11,8),(13,8),(12,11)],'steel')
        if deep:line(a,[(10,10),(13,10)],'ice',2)
    elif family=='orbit_drive':
        # A concave hooked skid, deliberately not two long Flow rails.
        line(a,[(1,3),(0,6),(1,10),(4,13),(8,14),(12,12)],'steel',3)
        line(a,[(2,6),(3,10),(6,12),(9,12)],'mint')
        polygon(d,[(9,2),(13,1),(15,4),(13,7),(9,7),(7,4)],'steel','silver')
        polygon(d,[(10,2),(12,3),(11,5),(8,4)],'ice')
        line(d,[(11,6),(12,9)],'steel',2)
        if deep:line(a,[(0,9),(2,13),(5,15)],'brass')
    else:
        polygon(d,[(8,2),(12,3),(14,7),(12,11),(8,10),(6,6)],'steel','silver')
        polygon(d,[(8,3),(12,4),(11,7),(7,6)],'deep')
        line(d,[(9,3),(12,4)],'white')
        line(d,[(11,10),(12,13)],'steel',2)
        polygon(a,[(0,12),(3,9),(8,9),(8,6),(11,6),(11,12),(3,15),(0,15)],'brass','void')
        line(a,[(8,7),(10,7)],'gold')
        if deep:line(a,[(13,12),(15,10),(15,14)],'silver',2)
    return im


def vector_point(x,y,along,side,angle):
    dx,dy=math.cos(angle),math.sin(angle)
    return (x+dx*along-dy*side,y+dy*along+dx*side)


def fx_motion(tag,f,angle=0):
    im=layers((96,80),FX_LAYERS);deep=tag.endswith('_ii');base=tag.removesuffix('_ii')
    dx,dy=math.cos(angle),math.sin(angle)
    p=lambda along,side=0:vector_point(48,34,along,side,angle)
    if base in ['comet_charge','comet_flight']:
        if base=='comet_charge':
            push=[0,3,6,9,11,9,6,2][f]
            # Only WALL-SIDE hard brackets; the machine centre stays open.
            for side in [-13,13]+([-19,19] if deep else []):
                points=[p(-28+push,side+(-3 if side<0 else 3)),p(-20+push,side),p(-17+push,side-(-4 if side<0 else 4))]
                line(im[1],points,'steel',3);line(im[2],points[1:],'silver',2)
            if f in [2,3,4]:chip(im[3],*p(-22+push,16),'gold',3,dx,dy)
        else:
            interval=[6,8,11,15,18,20,23,25][f]
            for k in range(2+int(deep)):
                a,b=p(-14-k*interval,(-1 if k%2 else 1)*9),p(-8-k*interval,(-1 if k%2 else 1)*8)
                line(im[2],[a,b],'steel',3);line(im[3],[a,(b[0],b[1]-1)],'silver')
    elif base=='comet_impact':
        impact(im[3],48,34,min(5,max(0,f-1)),violent=True)
        if f>3:
            line(im[0],[(27,53),(38,49),(46,50),(62,44)],'steel')
            if deep:line(im[0],[(30,58),(43,54),(55,54)],'edge')
    elif base=='comet_scrape':
        for k in range(2+int(deep)):
            a=vector_point(48,48,-5-f*2,k*5-6,angle);b=vector_point(48,48,-19-f*2,k*5-6,angle)
            line(im[0],[a,b],'steel' if f>3 else 'edge')
    elif base in ['speed','terminal_velocity','flow_state']:
        if base=='flow_state':
            # Two open, continuous retained guide rails at rotor-wake height.
            for side,ink in [(-8,'mint'),(8,'silver')]:
                points=[p(-38,side+3),p(-29,side+4),p(-20,side+2),p(-12,side),p(-5,side)]
                line(im[2],points,ink,2)
                # One narrow guide glides from the bearing into the retained
                # bend, while the continuous rails remain intact underneath.
                advance=-8-f*4
                guide_side=side+(4 if f>=4 else 2 if f>=2 else 0)
                line(im[3],[p(advance,guide_side),p(advance-4,guide_side+1)],'pale')
        else:
            gap=[5,7,9,12,16,20,22,24][f]
            for side in [-8,8]+([0] if deep or base=='terminal_velocity' else []):
                for k in range(3):
                    length=4+k*2+(5 if base=='terminal_velocity' else 0)
                    line(im[2],[p(-10-k*gap-length,side),p(-10-k*gap,side)],'cyan',2)
                    line(im[3],[p(-10-k*gap-length,side-1),p(-10-k*gap,side-1)],'ice')
    elif base=='orbit_drift':
        # A short outside-turn hooked cut stays entirely at the floor pivot.
        # Headings place the contact route, never rotate a physical Top sprite.
        count=[2,2,3,4,5,5,5,5][f]
        track=[(-26,10),(-22,3),(-15,-1),(-7,0),(0,6)][:count]
        floor_p=lambda along,side:vector_point(48,48,along,side,angle)
        for offset,ink,width in [(2,'steel',3),(-1,'teal',1)]+([(5,'edge',1)] if deep else []):
            line(im[0],[floor_p(a,s+offset) for a,s in track],ink,width)
        if f<6:line(im[2],[floor_p(a,s+2) for a,s in track[-2:]],'mint')
        for k in range(2+int(deep)):
            px,py=floor_p(-25+f*1.2+k*5,15+k%2*3)
            chip(im[3],px,py,'brass' if k%2 else 'edge',2,-dx,dy)
    elif base in ['clutch_danger','clutch_catch']:
        catching=base=='clutch_catch';shift=([0,2,4,3,7,10,9,5] if not catching else [0,4,8,11,11,8,4,1])[f]
        polygon(im[1],[(24,56),(29,49),(36+shift,49),(36+shift,44),(40+shift,44),(40+shift,52),(31,58)],'steel','silver')
        rect(im[2],(29,51,34,54),'brass')
        line(im[2],[(37+shift,45),(40+shift,45)],'gold',2)
        if deep:polygon(im[1],[(60,49),(63,44),(67,45),(65,53),(60,55)],'steel','silver')
        if catching and f in [3,4]:
            line(im[3],[(45,45),(48,43),(52,45)],'white',2)
            chip(im[3],43,42,'gold',3,-1,-1)
        if not catching and f in [1,3,5]:line(im[0],[(42,59),(46,61),(54,58)],'oxide')
    else:
        # Redline's hot wake is fragmented and asymmetric, with open Top centre.
        chaotic=base in ['redline_heat','runaway'];charging=base=='breakneck_charge'
        if base=='breakneck_strike':
            line(im[2],[p(-29,7),p(-7,7)],'hot',3)
            line(im[3],[p(-24,-7),p(10,-7)],'gold',2)
            impact(im[3],*p(14,0),min(5,f),violent=False)
        elif base=='breakneck_recoil':
            for k in range(3):
                line(im[0],[(31+k*11-f,53+k%2*3),(37+k*11-f,55+k%2*3)],'oxide' if f>3 else 'hot')
        else:
            overcap=base=='redline_overcap'
            offsets=[(-28,10),(-20,-12),(-10,-19),(13,-11),(21,9),(-35,-3)]
            fragment_count=3+int(deep)+int(chaotic)+int(overcap)
            for k,(along,side) in enumerate(offsets[:fragment_count]):
                jitter=[0,0,1,-1,2,-2,1,0][f]*(2 if chaotic else 1)
                length=(8-f//2) if charging else [4,6,8,10,9,7,5,3][f]+(k%2)*2
                xx,yy=p(along+(f*2 if charging else jitter),side+jitter)
                line(im[1],[(xx-3,yy+2),(xx,yy),(xx+length,yy-3)],'oxide',3)
                line(im[2],[(xx,yy),(xx+length-1,yy-3)],'hot',2)
                if f in [2,3,4,5]:line(im[3],[(xx+2,yy-1),(xx+length,yy-3)],'gold')
            if overcap:
                # The overcap tears an extra trailing vent plate away, rather
                # than merely recolouring or brightening the active fragments.
                q=[p(-34-f*1.1,-2),p(-28-f*1.1,-5),p(-25-f*1.1,-2),p(-31-f*1.1,1)]
                polygon(im[2],q,'oxide','hot')
                if f in [2,3,4,5]:line(im[3],q[:2],'gold')
            if chaotic:
                for k in range(4):chip(im[3],22+(k*17+f*3)%54,20+(k*11+f)%27,'red' if k%2 else 'gold',2+k%2)
    return im


FX_BASES={
    'redline':['redline_active','redline_active_ii','redline_overcap','redline_overcap_ii','redline_heat','runaway','breakneck_charge','breakneck_strike','breakneck_recoil'],
    'iron_comet':['comet_charge','comet_charge_ii','comet_flight','comet_flight_ii','comet_impact','comet_impact_ii','comet_scrape','comet_scrape_ii'],
    'high_gear':['speed','speed_ii','terminal_velocity','flow_state'],
    'orbit_drive':['orbit_drift','orbit_drift_ii'],
    'clutch':['clutch_danger','clutch_danger_ii','clutch_catch','clutch_catch_ii'],
}
DIRECTIONAL={'redline_active','redline_active_ii','redline_overcap','redline_overcap_ii','redline_heat','runaway','breakneck_charge','breakneck_strike','breakneck_recoil',
             'comet_charge','comet_charge_ii','comet_flight','comet_flight_ii','comet_impact','comet_impact_ii','comet_scrape','comet_scrape_ii',
             'speed','speed_ii','terminal_velocity','flow_state','orbit_drift','orbit_drift_ii'}
DESIGNS={
    'redline':{
        'grammar':{'silhouette':'Off-centre metal rotor with broken hot plates and an asymmetric torn wake.','motion':'Ignition, growing splinter density and irregular heat stutter; Breakneck loads, strikes, recoils.','location':'Rotor edges and actual velocity wake; recoil near the floor.','persistence':'Only real active/overcap/heat states; discrete ignition, commitment, strike and vent events.','palette':'Oxide, hot orange, red and pale key flashes against cold steel.','feature':'Open machine centre with unequal broken fragment banks; mutations change motion, not just hue.'},
        'static_frames':{'redline':6,'redline_ii':6,'runaway':6,'breakneck':6},
        'event_tags':{'redline':'redline_active','redline_ii':'redline_active_ii','runaway':'runaway','redline_overcap':'redline_overcap','redline_heat':'redline_heat','runaway_hit':'runaway','breakneck_charge':'breakneck_charge','breakneck_impact':'breakneck_strike','breakneck_recovery':'breakneck_recoil'},
        'active_tags':{'active':'redline_active','overcap':'redline_overcap','heat':'redline_heat','runaway':'runaway','breakneck':'breakneck_charge'},
        'notes':['Successful C.4 fragmented Redline active signatures are intentionally retained by the integrated renderer. Fresh cards/icons and eight-key contact/overcap/heat/commit force-fragment states share their asymmetric hot mechanical grammar. No clean corona ring.','Runaway card frays after successive successful-contact action beats. Breakneck uses a visible small rival and loaded/strike/recoil poses.']},
    'iron_comet':{
        'grammar':{'silhouette':'Thick compressed physical rotor braced against a visible wall bank.','motion':'Wall-side squeeze, abruptly separated flight positions, violent contact and short scrape aftermath.','location':'Wall contact, actual rebound vector, then target contact and floor scars.','persistence':'Armed wall-rebound lifetime plus bounded charge/contact/aftermath events.','palette':'Cold iron, silver, brass and small white/gold contact flashes.','feature':'The wall and the whole spinning machine tell the slingshot story; disconnected heavy plates replace any wedge.'},
        'static_frames':{'iron_comet':5,'iron_comet_ii':6},
        'event_tags':{'comet_charge':'comet_charge','comet_release':'comet_impact'},
        'active_tags':{'charged':'comet_charge','flight':'comet_flight','aftermath':'comet_scrape'},
        'notes':['Rank II adds a second wall-side brace and denser separated metal wakes, not a larger surrounding aura.','Charge cels leave the machine centre open. Card stack height visibly compresses; runtime may compress cosmetic stack only, preserving collision geometry.']},
    'high_gear':{
        'grammar':{'silhouette':'Forward-cropped low rotor and widely spaced narrow wake lanes; Flow has two long open guide rails.','motion':'Intervals stretch as thrust rises. Terminal uses sparse long discontinuities; Flow retains a smooth bend.','location':'Behind the moving rotor along the actual velocity.','persistence':'Moving speed state; terminal surge is event-based.','palette':'Steel, ice and cool blue; muted mint retained rails; sparse terminal brass tips.','feature':'Terminal discontinuous spacing versus Flow continuous parallel retention remains distinct in grayscale.'},
        'static_frames':{'high_gear':5,'high_gear_ii':5,'terminal_velocity':6,'flow_state':6},
        'event_tags':{'high_gear_surge':'terminal_velocity'},
        'active_tags':{'speed':'speed','terminal_velocity':'terminal_velocity','flow_state':'flow_state'},
        'notes':['Rank II adds a second low transmission shoe and a third interrupted wake lane.','Flow rails are open rotor-height guides. Orbit instead cuts a compact concave floor crescent and ejects grit.']},
    'orbit_drive':{
        'grammar':{'silhouette':'Large sideways machine over a broad hooked contact-floor skid.','motion':'Enter turn, cut a growing outside hook, throw grit and release the arc.','location':'Floor/contact point outside the turn, below the rotor.','persistence':'Only actual brake-turn drift/arc state; scuffs settle after the carving beat.','palette':'Worn steel floor scars, muted teal edge and brass grit.','feature':'One short concave floor cut with displaced outer grit; no rotor aura or long Flow rails.'},
        'static_frames':{'orbit_drive':7,'orbit_drive_ii':7},
        'event_tags':{'orbit_drift':'orbit_drift'},'active_tags':{'drift':'orbit_drift'},
        'notes':['Rank II adds a second outside skid groove and extra displaced grit, staying at the contact plane.']},
    'clutch':{
        'grammar':{'silhouette':'Off-axis strained machine with a single large stepped pawl catching its bearing.','motion':'Uneven slips/misses, decisive pawl contact, a short stutter catch and restrained settlement.','location':'One side of the low bearing and contact-floor scrape.','persistence':'Intermittent actual danger window; bounded successful-contact catch.','palette':'Dull steel/brass, small gold tooth tips, oxide strain marks and one pale catch flash.','feature':'Asymmetric toothed L-shaped pawl and leaning bit; no recovery-ring expansion or relaunch.'},
        'static_frames':{'clutch':6,'clutch_ii':6},
        'event_tags':{'clutch_activate':'clutch_danger','clutch_recover':'clutch_catch'},
        'active_tags':{'danger':'clutch_danger','recover':'clutch_catch'},
        'notes':['Rank II adds a second small staggered bearing stop, not a surrounding symmetric clamp.','The authored catch never resets the physical player, reserve, collision radius or position.']},
}


def save_master(path,frames,names,tags,times,pivot,revise):
    if path.exists() and not revise:raise RuntimeError(f'Refusing to replace edited master: {path}; explicit --revise required for construction revision')
    write_ase(path,frames,names,tags,times,pivot,
              note='Task002C.5 identity addendum / deliberate named pixel cels / anticipation-action-reaction-follow-through / nearest / native RGBA',palette=PAL)


def author(family,revise):
    states=STATES[family];cards=[];tags=[];times=[]
    for state in states:
        start=len(cards)
        cards.extend(PAINTERS[family](state,f) for f in range(12))
        tags.append((state,start,len(cards)-1))
        times.extend(CARD_TIMES.get(state,CARD_TIMES[family]))
    save_master(SOURCE/f'{family}_cards.aseprite',cards,CARD_LAYERS,tags,times,(32,32),revise)
    icons=[icon(family,state) for state in states]
    save_master(SOURCE/f'{family}_icons.aseprite',icons,ICON_LAYERS,[(s,i,i) for i,s in enumerate(states)],[100]*len(states),(8,8),revise)
    frames=[];ftags=[];ftimes=[]
    for base in FX_BASES[family]:
        variants=[('',0)]+[(f'_{heading}',angle) for heading,angle in HEADINGS.items()] if base in DIRECTIONAL else [('',0)]
        for suffix,angle in variants:
            start=len(frames);frames.extend(fx_motion(base,f,angle) for f in range(8));ftags.append((base+suffix,start,len(frames)-1))
            ftimes.extend([85,60,45,35,45,65,90,130] if family=='clutch' else [75,55,40,35,45,65,90,130])
    save_master(SOURCE/f'{family}_fx.aseprite',frames,FX_LAYERS,ftags,ftimes,(48,48),revise)
    design={'family':family,**DESIGNS[family],'source_direction_contract':'Upright artwork; heading suffix chooses pre-authored screen-direction placement e/ne/n/nw/w/sw/s/se. No runtime rotation of isometric art.',
            'authoring':'Distinct pixel-cluster compositions and deliberate key poses assembled as normal editable native Aseprite layers. Scripted authorship, not manual mouse painting. Saved masters are the editing authority.',
            'review_tier':{'before':'C cards; runtime mixed B/C','after':'B/A candidate pending full roster, grayscale and motion review'},
            'card_story':'Twelve unequal-duration keys: anticipation, action, mechanical reaction, follow-through and intentional reset. Not six arbitrary cycling decorations.'}
    (OUT/f'{family}_design.json').write_text(json.dumps(design,indent=2)+'\n',encoding='utf-8')
    print(f'{family}: cards {len(cards)} / icons {len(icons)} / FX {len(frames)} in {len(ftags)} meaningful tags')


def main():
    p=argparse.ArgumentParser();p.add_argument('--family',choices=STATES);p.add_argument('--revise',action='store_true');args=p.parse_args()
    SOURCE.mkdir(parents=True,exist_ok=True);OUT.mkdir(parents=True,exist_ok=True)
    for family in [args.family] if args.family else STATES:author(family,args.revise)


if __name__=='__main__':main()
