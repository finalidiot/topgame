"""One-time bespoke motion-family authoring into editable native RGBA masters.

The five family painters deliberately use different subjects, framing, spatial
hierarchy and keyed stories. This is scripted pixel-cluster authorship, not
manual mouse painting. Saved Aseprite cels are the editing authority afterwards;
normal export must never rerun this constructor over an artist's edits.
"""
import argparse
import json
import math
import struct
import zlib
from pathlib import Path
from PIL import Image, ImageDraw
from build_power_art import write_ase, read_ase

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
PHYSICAL_CARD_LAYERS = ['01 arena floor and contact story','02 accepted native bit and ratchet',
                        '03 accepted native blade silhouette','04 mechanic-specific motion and force',
                        '05 physical contact flashes and fragments']
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


# Restore the accepted game top as the literal subject, at native pixels.
# Read its original editable blade/ratchet/bit cels, rather than reconstructing
# the d0d pseudo chassis or shrinking a card into an icon.
_TOP_CELS = None
_TOP_META = None
def native_top_cels():
    global _TOP_CELS, _TOP_META
    if _TOP_CELS is not None: return _TOP_CELS, _TOP_META
    path=ROOT/'assets/source-art/starter_balance_mid_ball.aseprite'
    data=path.read_bytes();count=struct.unpack_from('<H',data,6)[0]
    frames=[];offset=128
    for _ in range(count):
        length,magic,old,duration,new=struct.unpack_from('<IHHH2xI',data,offset)
        result=[Image.new('RGBA',(48,48)) for _ in range(5)];pos=offset+16
        for _ in range(new or old):
            n,kind=struct.unpack_from('<IH',data,pos);payload=data[pos+6:pos+n]
            if kind==0x2005:
                layer,x,y,opacity,cel_type,z=struct.unpack_from('<HhhBHh',payload)
                assert z==0 and opacity==255
                if cel_type==1:
                    link=struct.unpack_from('<H',payload,16)[0];result[layer]=frames[link][layer].copy()
                else:
                    assert cel_type in [0,2]
                    w,h=struct.unpack_from('<HH',payload,16)
                    raw=zlib.decompress(payload[20:]) if cel_type==2 else payload[20:]
                    cel=Image.frombytes('RGBA',(w,h),raw);result[layer].alpha_composite(cel,(x,y))
            pos+=n
        frames.append(result);offset+=length
    assert offset==len(data)
    _TOP_CELS=frames;_TOP_META=read_ase(path)[1]
    return frames,_TOP_META


def physical_top(im,x,foot,pose='normal_rpm',key=0,compress=0,echo=False):
    frames,meta=native_top_cels();span=meta['tags'][pose]
    native=frames[span['from']+key%(span['to']-span['from']+1)]
    for original,destination,drop in [(1,1,0),(2,1,compress//2),(3,2,compress)]:
        cel=native[original].copy()
        if echo:
            # Sparse old body silhouettes are separated physical positions.
            # No soft blur: remap intact source clusters into four cold tones.
            for yy in range(cel.height):
                for xx in range(cel.width):
                    rgba=cel.getpixel((xx,yy))
                    if not rgba[3]:continue
                    # Hard, opaque cluster remap avoids native/Pillow alpha
                    # compositor rounding and preserves exact source parity.
                    lum=max(rgba[:3])
                    ink='steel' if lum>170 else 'deep' if lum>80 else 'shadow' if lum>40 else 'void'
                    cel.putpixel((xx,yy),c(ink))
        im[destination].alpha_composite(cel,(round(x-24),round(foot-40+drop)))
    ground(im[0],x,foot+2,12 if not echo else 9)


def blade_rim_fragment(im,x,foot,key=0,portion=0):
    """Sparse native blade highlights only: no chassis, bit, base or shadow.

    The physical subject is the live game top. Its rear motion memory is just
    a few separated rim/teeth clusters, with hard palette fade and no blur.
    This avoids the opaque rectangular rack made by whole-body ghost cels.
    """
    frames,meta=native_top_cels();native=frames[meta['tags']['high_rpm']['from']+key%8][3]
    fragment=Image.new('RGBA',(48,48))
    for yy in range(16,34):
        for xx in range(5,44):
            rgba=native.getpixel((xx,yy))
            if not rgba[3] or max(rgba[:3])<145:continue
            # Deliberate opposed blade tips plus an occasional short back rim.
            # Do not retain a filled plate, a complete ring, or arbitrary noise.
            left=xx<=15 and 21<=yy<=29
            right=xx>=33 and 20<=yy<=28
            back=20<=xx<=29 and yy<=20
            keep=(left or back) if portion==0 else (right or back) if portion==1 else (left or right)
            if not keep:continue
            ink='edge' if max(rgba[:3])>=210 else 'steel'
            fragment.putpixel((xx,yy),c(ink))
    im[2].alpha_composite(fragment,(round(x-24),round(foot-40)))


def rival_top(im,x,foot,key=0):
    native,meta=read_ase(ROOT/'assets/source-art/small_top_002b.aseprite')
    cel=native[key%4].copy()
    # The accepted hostile top remains native 24px, against the player's 48px cel.
    # Its source floor shadow is removed; our scene supplies the contact plane.
    cel.paste((0,0,0,0),(0,21,24,24))
    for yy in range(24):
        for xx in range(24):
            if 0 < cel.getpixel((xx,yy))[3] < 255:cel.putpixel((xx,yy),(0,0,0,0))
    im[1].alpha_composite(cel,(round(x-12),round(foot-20)))
    ground(im[0],x,foot+2,8)


# Six deliberately held physical beats, rather than 12 mushy interpolations.
BEAT=[0,0,1,1,2,2,3,3,4,4,5,5]


def comet_card(state,f):
    im=layers((64,64),PHYSICAL_CARD_LAYERS);deep=state.endswith('_ii');b=BEAT[f]
    # Upright arena wall: the actual top is compressed against its face, not
    # a wall above an unconnected spaceship or a triangular projectile.
    polygon(im[0],[(1,8),(7,5),(10,8),(10,43),(7,49),(1,46)],'void')
    polygon(im[0],[(2,9),(7,7),(8,10),(8,43),(6,47),(2,44)],'steel','edge')
    line(im[0],[(7,9),(7,44)],'silver')
    for yy in [17,35]:rect(im[0],(3,yy,5,yy+2),'void')
    x=[23,21,30,40,39,30][b];foot=[43,43,38,34,36,43][b]
    compressed=[0,3,1,0,0,0][b]
    physical_top(im,x,foot,'high_rpm' if b in [2,3] else 'normal_rpm',b,compressed)
    rival_top(im,53 if b<4 else 58,35 if b<4 else 32,b)
    if b<2:
        # Compression ripples are attached at the wall-to-blade contact.
        line(im[3],[(9,26),(12,29),(9,32)],'gold',2)
        line(im[4],[(9,27),(11,29)],'white')
        line(im[0],[(10,47),(17,48),(23,47)],'steel')
    if b in [2,3]:
        for yy,ink in [(41,'steel'),(46,'silver')]:
            line(im[3],[(11,yy),(18,yy-3),(x-12,foot-7)],ink,2 if yy==41 else 1)
        if deep:line(im[3],[(11,49),(21,44),(x-9,foot-4)],'gold')
    if b==3:impact(im[4],49,24,1,violent=True)
    if b==4:
        impact(im[4],51,27,3,violent=True)
        # Target recoil is part of the illustration, not a scripted game proc.
        line(im[3],[(55,35),(60,32),(63,31)],'oxide',2)
    if b==5:
        line(im[0],[(30,48),(37,45),(43,42)],'steel',2)
        chip(im[4],43,39,'silver',3,-1,1)
    return im


def speed_card(state,f):
    im=layers((64,64),PHYSICAL_CARD_LAYERS);b=BEAT[f]
    deep=state.endswith('_ii');terminal=state=='terminal_velocity';flow=state=='flow_state'
    if flow:
        # Flow keeps speed through an OPEN bend; no detached guide device.
        points=[(4,53),(10,52),(17,48),(24,42),(32,35),(41,32),(48,33)]
        line(im[0],points[:5+b//2],'steel',2)
        line(im[3],[(x,y-2) for x,y in points[:5+b//2]],'mint')
        x=[35,39,44,46,43,39][b];foot=[39,36,34,35,37,39][b]
        physical_top(im,18,48,'normal_rpm',0,echo=True)
        physical_top(im,x,foot,'high_rpm',b)
        for xx,yy in [(8,48),(19,42),(28,34)]:line(im[4],[(xx,yy),(xx+3,yy-2)],'pale')
        return im
    # Two visibly round native rotor echoes open into an accelerating gap.
    x=[37,40,44,48,48,42][b];foot=[44,41,38,35,35,41][b]
    gap=[8,10,13,17,19,12][b]+(4 if deep else 3 if terminal else 0)
    if deep or terminal:
        physical_top(im,max(5,x-gap*2),min(61,foot+gap),'normal_rpm',0,echo=True)
    physical_top(im,x-gap,foot+gap//2,'normal_rpm',2,echo=True)
    physical_top(im,x,foot,'high_rpm',b)
    # Spacing carries the speed read before colour; streaks connect actual
    # trailing top positions and end behind the live blade, never a nose.
    for lane in range(3 if deep or terminal else 2):
        xx=max(1,x-gap*2-8);yy=foot+lane*4+1
        line(im[3],[(xx,yy+7),(max(xx+1,x-17),yy-5)],'cyan',2 if lane==0 else 1)
        line(im[4],[(max(1,xx+gap),yy+2),(max(xx+gap+1,x-18),yy-5)],'ice')
    if terminal:
        line(im[4],[(1,51),(10,46)],'gold')
        line(im[4],[(3,58),(15,52)],'white')
    return im


def orbit_card(state,f):
    im=layers((64,64),PHYSICAL_CARD_LAYERS);b=BEAT[f];deep=state.endswith('_ii')
    # Broad C-shaped contact-tip route wraps the card composition, not the top.
    feet=[(17,52),(13,42),(19,32),(32,28),(44,33),(48,43)]
    trace=feet[:max(4,b+1)]
    line(im[0],trace,'steel',3)
    line(im[3],[(x-2,y+1) for x,y in trace],'teal',2)
    if deep:
        line(im[0],[(x-5,y+4) for x,y in trace],'edge',2)
        line(im[0],[(x-8,y+6) for x,y in trace],'steel')
    if b>=2:
        physical_top(im,*feet[max(0,b-2)],'normal_rpm',0,echo=True)
    x,foot=feet[b];physical_top(im,x,foot,'high_rpm',b)
    if b>=1:
        # The actual turning contact continues into the bit under the top.
        line(im[4],feet[max(0,b-1):b+1],'mint',2)
    for k in range(2+int(deep)):
        xx,yy=feet[max(0,b-1)]
        chip(im[4],xx-7-k*3,yy+4+k%2,'brass' if k==0 else 'edge',2,-1,1)
    return im


def clutch_card(state,f):
    im=layers((64,64),PHYSICAL_CARD_LAYERS);b=BEAT[f];deep=state.endswith('_ii')
    # A struggling real top remains the subject. The accepted wobble poses
    # retain their blade, ratchet and bit; there is no separate bearing machine.
    pose='heavy_wobble' if b<3 else 'normal_rpm'
    key=[4,1,3,1,3,4][b]
    x=[24,26,29,40,41,39][b]
    if b>=3:
        # The last strained position and the caught position are linked by
        # a broad uneven floor scrape. This is the same top's recovery story.
        physical_top(im,23,52,'heavy_wobble',4,echo=True)
        line(im[0],[(7,56),(14,58),(23,57),(31,54),(39,52)],'steel',2)
        line(im[3],[(16,57),(23,56),(30,54)],'oxide')
    physical_top(im,x,51,pose,key)
    if b<3:
        scrape=[[(17,55),(22,57),(30,56),(38,53)],
                [(22,53),(28,56),(37,55),(42,52)],
                [(15,53),(23,57),(31,56),(39,52)]][b]
        line(im[0],scrape,'oxide',2)
        line(im[3],scrape[-2:],'gold')
        # Side fragments show the same bit losing grip, rather than a reticle.
        chip(im[4],42,54,'steel',2,1,1)
    elif b==3:
        # One floor tooth bite and one brief flash at the actual contact bit.
        polygon(im[3],[(37,52),(40,49),(43,52),(40,54)],'gold')
        rect(im[4],(39,50,41,51),'white')
        chip(im[4],34,53,'gold',3,-1,1)
        if deep:
            line(im[0],[(34,57),(40,55),(47,52)],'silver',2)
            chip(im[4],46,53,'silver',3,1,1)
    else:
        # The stabilised top keeps an uneven scrape behind it, never an aura.
        line(im[0],[(16,57),(22,56),(29,55)],'steel')
        if b==4:
            stepped_arc(im[3],x,34,19,9,math.pi*.05,math.pi*.60,'silver')
            line(im[4],[(40,40),(44,39)],'white')
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
        # A wall and one round top leaning away from it: no projectile wedge.
        line(d,[(1,2),(1,12)],'silver',2)
        polygon(d,[(8,4),(12,4),(15,7),(14,10),(10,11),(6,9),(5,7)],'void')
        polygon(d,[(7,5),(11,4),(14,6),(12,8),(8,8),(6,7)],'silver')
        line(d,[(7,9),(10,11),(13,9)],'steel',2)
        line(d,[(10,11),(10,13)],'edge')
        line(a,[(3,11),(6,12)],'gold',2)
        line(a,[(4,14),(7,14)],'steel')
        if deep:rect(a,(3,6,4,7),'white')
    elif family=='high_gear':
        # Independent tiny disc with a pointed bit and separated rear marks.
        polygon(d,[(8,3),(12,2),(15,4),(14,7),(10,8),(7,6)],'void')
        polygon(d,[(9,3),(12,3),(14,4),(12,6),(9,6),(8,4)],'silver')
        line(d,[(9,7),(12,8),(14,6)],'steel')
        line(d,[(11,8),(11,10)],'edge')
        if state=='flow_state':
            line(a,[(0,13),(3,14),(6,12),(8,10)],'mint',2)
        else:
            for x,y,length in [(0,13,4),(2,9,4),(4,5,2)]:line(a,[(x,y),(x+length,y-1)],'ice')
            if state=='terminal_velocity':line(a,[(0,15),(6,13)],'gold')
        if deep:line(a,[(2,15),(6,14)],'silver')
    elif family=='orbit_drive':
        # A physical top placed at the open end of its turning contact path.
        line(a,[(2,3),(0,6),(1,10),(4,13),(8,14),(11,11)],'steel',2)
        line(a,[(1,6),(2,10),(5,12)],'mint')
        polygon(d,[(9,1),(13,1),(15,3),(14,6),(10,7),(7,5),(7,3)],'void')
        polygon(d,[(9,2),(13,2),(14,3),(12,5),(9,5),(8,3)],'silver')
        line(d,[(10,6),(12,7),(12,9)],'steel')
        if deep:line(a,[(0,11),(3,15),(7,15)],'brass')
    else:
        # Leaning disc above its visibly scraping bit; a tiny catch below.
        polygon(d,[(1,6),(5,2),(10,3),(13,6),(10,9),(5,10),(2,9)],'void')
        polygon(d,[(2,6),(5,3),(9,3),(11,5),(8,7),(4,8)],'silver')
        line(d,[(5,9),(9,10),(10,13)],'steel',2)
        line(a,[(3,14),(6,15),(10,14)],'oxide')
        rect(a,(9,13,11,14),'gold')
        if deep:rect(a,(11,11,12,12),'white')
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
            # Rebound compression sits directly at the wall-facing blade rim.
            # Short inward force ticks terminate on the real top silhouette.
            press=[0,2,4,6,7,5,3,0][f]
            for side in [-7,7]+([-12,12] if deep else []):
                points=[p(-24+press,side+(-3 if side<0 else 3)),p(-16+press,side)]
                line(im[1],points,'steel',2)
                line(im[2],points,'silver')
            if f in [2,3,4]:
                xx,yy=p(-12,0);rect(im[3],(xx-1,yy-1,xx+1,yy),'gold')
        else:
            # The live top remains the only solid body. Two separated native
            # blade-tip memories leave behind its genuine rebound velocity.
            # No dark bases, invented projectile body, rack or wedge.
            gap=[12,15,19,23,27,31,34,37][f]
            xx,yy=vector_point(48,48,-gap,0,angle)
            blade_rim_fragment(im,xx,yy,f,0)
            if deep:
                xx2,yy2=vector_point(48,48,-min(42,gap+12),0,angle)
                blade_rim_fragment(im,xx2,yy2,f+2,1)
            # One short broken wake chip directly behind the current rim.
            aa,bb=p(-13,4),p(-16,5)
            line(im[3],[aa,bb],'silver')
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
            # Open retained motion consists of three short bent floor groups.
            # Never draw a parallel opaque cyan rail/rack behind the player.
            floor_p=lambda along,side:vector_point(48,48,along,side,angle)
            groups=[[(-35,11),(-31,10)],[(-24,7),(-20,5)],[(-11,2),(-7,1)]]
            for k,group in enumerate(groups):
                line(im[0],[floor_p(a,b) for a,b in group],'steel')
                if k==f//3 or k==2:line(im[3],[floor_p(a,b-1) for a,b in group],'mint')
        else:
            gap=[7,10,14,19,24,29,34,39][f]
            if base=='terminal_velocity':gap+=7
            # Sparsely separated real blade-rim clusters carry acceleration.
            # Palette fading is hard opaque pixel clusters, so native export
            # parity stays exact without any whole-body shadow or filled base.
            if deep or base=='terminal_velocity':
                xx2,yy2=vector_point(48,48,-min(43,gap*1.70),0,angle)
                blade_rim_fragment(im,xx2,yy2,f+2,1)
            xx,yy=vector_point(48,48,-gap,0,angle)
            blade_rim_fragment(im,xx,yy,f,0)
            if base=='terminal_velocity' and f in [2,3,4,5]:
                # One distant broken glint, never a long continuous speed bar.
                aa,bb=p(-39,5),p(-42,5)
                line(im[3],[aa,bb],'silver')
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
        catching=base=='clutch_catch'
        # The floor under the real bit is the mechanism. Never draw a pawl
        # widget floating next to the player or add a targeting/revival ring.
        if not catching:
            skid=[[(37,50),(43,53),(49,52)],[(40,52),(46,54),(53,51)],
                  [(36,49),(41,52),(48,53)],[(39,51),(44,54),(51,52)]][f%4]
            line(im[0],skid,'oxide',2 if f in [1,3,5] else 1)
            if f in [1,3,5]:line(im[2],skid[-2:],'gold')
            chip(im[3],52+(f%3),52,'steel',2,1,1)
        elif f<3:
            line(im[0],[(38,53),(43,54),(48,50)],'steel',2)
        elif f in [3,4]:
            polygon(im[2],[(45,49),(48,46),(51,49),(48,52)],'gold')
            rect(im[3],(47,47,49,48),'white')
            chip(im[3],42,51,'gold',3,-1,1)
            if deep:chip(im[3],54,52,'silver',3,1,1)
        else:
            line(im[0],[(39,54),(43,54),(46,52)],'steel')
            if f==5:line(im[3],[(49,49),(52,48)],'white')
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
        'grammar':{'silhouette':'Accepted round blade, ratchet and contact bit compressed against a physical arena wall.','motion':'Wall-side squeeze, abruptly separated flight positions, violent contact and short scrape aftermath.','location':'Wall contact, actual rebound vector, then target contact and floor scars.','persistence':'Armed wall-rebound lifetime plus bounded charge/contact/aftermath events.','palette':'Cold iron, silver, brass and small white/gold contact flashes.','feature':'The whole top survives every compression, launch, target-contact and recoil beat; never a wedge.'},
        'static_frames':{'iron_comet':5,'iron_comet_ii':6},
        'event_tags':{'comet_charge':'comet_charge','comet_release':'comet_impact'},
        'active_tags':{'charged':'comet_charge','flight':'comet_flight','aftermath':'comet_scrape'},
        'notes':['Rank II adds a second wall-side compression beat and heavier path fragments, never a larger surrounding aura.','Charge cels leave the machine centre open. Card stack height visibly compresses; runtime may compress cosmetic stack only, preserving collision geometry.']},
    'high_gear':{
        'grammar':{'silhouette':'Recognisable native top plus physically separated round rotor echoes; Flow retains an open contact path.','motion':'Sparse native rim fragments separate as thrust rises. Terminal opens longer gaps; Flow retains three disconnected bent floor groups.','location':'Sparse rear blade-rim memories along the actual velocity; the real live top stays dominant.','persistence':'Moving speed state; terminal surge is event-based.','palette':'Steel, ice and cool blue; muted mint retained rails; sparse terminal brass tips.','feature':'Terminal separated blade-tip glints versus Flow short bent floor groups remain distinct in grayscale; no opaque rack or rail.'},
        'static_frames':{'high_gear':5,'high_gear_ii':5,'terminal_velocity':6,'flow_state':6},
        'event_tags':{'high_gear_surge':'terminal_velocity'},
        'active_tags':{'speed':'speed','terminal_velocity':'terminal_velocity','flow_state':'flow_state'},
        'notes':['Rank II adds one further sparse blade-rim memory; no housing, filled base, shadow block or continuous speed bars.','Flow preserves a long open floor-contact bend. Orbit instead cuts a compact concave hook and ejects grit.']},
    'orbit_drive':{
        'grammar':{'silhouette':'Accepted physical top travelling around a broad C-shaped contact-tip route.','motion':'Enter turn, cut a growing outside hook, throw grit and release the arc.','location':'Floor/contact point outside the turn, below the rotor.','persistence':'Only actual brake-turn drift/arc state; scuffs settle after the carving beat.','palette':'Worn steel floor scars, muted teal edge and brass grit.','feature':'One short concave floor cut with displaced outer grit; no rotor aura or long Flow rails.'},
        'static_frames':{'orbit_drive':8,'orbit_drive_ii':8},
        'event_tags':{'orbit_drift':'orbit_drift'},'active_tags':{'drift':'orbit_drift'},
        'notes':['Rank II deepens two outside skid grooves and ejects extra grit, staying at the contact plane.']},
    'clutch':{
        'grammar':{'silhouette':'Accepted wobbling blade and ratchet on a visibly scraping bit, followed by a small physical floor catch.','motion':'Uneven scrape, loaded bit bite, and the same top settling back upright.','location':'One side of the low bearing and contact-floor scrape.','persistence':'Intermittent actual danger window; bounded successful-contact catch.','palette':'Dull steel/brass, small gold tooth tips, oxide strain marks and one pale catch flash.','feature':'The top itself leans and catches; one tiny floor bite replaces the detached bearing device.'},
        'static_frames':{'clutch':6,'clutch_ii':6},
        'event_tags':{'clutch_activate':'clutch_danger','clutch_recover':'clutch_catch'},
        'active_tags':{'danger':'clutch_danger','recover':'clutch_catch'},
        'notes':['Rank II adds a second small redirected catch fragment, never a separate supporting device.','The authored catch never resets the physical player, reserve, collision radius or position.']},
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
    save_master(SOURCE/f'{family}_cards.aseprite',cards,CARD_LAYERS if family=='redline' else PHYSICAL_CARD_LAYERS,tags,times,(32,32),revise)
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
            'review_tier':{'before':'Human review rejected ambiguous pseudo-machine subjects','after':'Corrected physical-top scenes; human visual acceptance pending'},
            'card_story':'Six deliberately held physical poses in twelve timed source cels: anticipation, action, reaction and recovery. No added frames for smoothness.'}
    if family != 'redline':
        design['historical_direction'] = {
            'human_rejected_checkpoint':'d0d37e5',
            'accepted_physical_subject':'d551867 assets/source-art/starter_balance_mid_ball.aseprite',
            'components_restored':['native blade cels','native ratchet cels','native bit cels'],
            'motion_cues_inspected':'32bb56e roster cards/icons/FX; bdcc24e cards/icons; f72526e runtime effects',
            'source_authority':'Native saved Aseprite masters; six deliberately held card poses in twelve timed cels',
            'human_visual_acceptance':'pending'}
    (OUT/f'{family}_design.json').write_text(json.dumps(design,indent=2)+'\n',encoding='utf-8')
    print(f'{family}: cards {len(cards)} / icons {len(icons)} / FX {len(frames)} in {len(ftags)} meaningful tags')


def main():
    p=argparse.ArgumentParser();p.add_argument('--family',choices=STATES);p.add_argument('--revise',action='store_true');args=p.parse_args()
    SOURCE.mkdir(parents=True,exist_ok=True);OUT.mkdir(parents=True,exist_ok=True)
    for family in [args.family] if args.family else STATES:author(family,args.revise)


if __name__=='__main__':main()
