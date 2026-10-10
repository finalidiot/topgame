"""Saved native combat-acceptance venue and power motion art.

Normal invocation exports saved editable masters through Aseprite. --author is
an explicit, narrow authoring pass: venue plus the two requested card families.
Existing card layers/tags/timing/pivots are preserved by replacing only cel data.
There is no runtime texture synthesis or colour replacement.
"""
from __future__ import annotations
import argparse, hashlib, json, math, struct, subprocess, sys, tempfile, zlib
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from build_power_art import read_ase, write_ase, chunk
from author_identity_core import top, shadow, line as core_line
from export_power_identity import export_family, save_json, FAMILIES
from workspace.workspace import find_tool, create_task_workspace

SOURCE = ROOT / 'assets/source-art/combat_003a1'
OUT = ROOT / 'assets/powers/combat_003a1'
SIZE = (640, 360)
PAL = {'black':'#0b1219','ink':'#111b24','deep':'#1a2832','bed':'#253641',
       'floor':'#2a3e49','plate':'#314853','steel':'#526c76','edge':'#8aa0a1',
       'silver':'#bccac3','cold':'#588f97','cyan':'#90b8ba','ochre':'#806444',
       'amber':'#c3934f','hot':'#ce6a45','red':'#a84438','white':'#e7e5ca',
       'green':'#508570','mint':'#93c1a7'}
OUTER = [(-180,-110),(-110,-180),(110,-180),(180,-110),(180,110),(110,180),(-110,180),(-180,110)]
PLAYABLE = [(-166,-104),(-104,-166),(104,-166),(166,-104),(166,104),(104,166),(-104,166),(-166,104)]

def c(name, alpha=255): return (*bytes.fromhex(PAL.get(name,name).lstrip('#')),alpha)
def blank(size=SIZE): return Image.new('RGBA',size)
def projected(p,z=0): return (round(320+p[0]-p[1]),round(165+(p[0]+p[1])*.5-z))
def poly(im, pts, color): ImageDraw.Draw(im).polygon([(round(x),round(y)) for x,y in pts],fill=c(color))
def stroke(im,pts,color,width=1,alpha=255):
    # Muted authored colour, rather than fractional-alpha source layers whose
    # interlayer integer rounding differs between Pillow and native Aseprite.
    ink=c(color)
    if alpha<255:
        base=c('floor');ink=tuple(round(base[i]+(ink[i]-base[i])*alpha/255) for i in range(3))+(255,)
    ImageDraw.Draw(im).line([(round(x),round(y)) for x,y in pts],fill=ink,width=width)
def dot(im,p,color): ImageDraw.Draw(im).point((round(p[0]),round(p[1])),fill=c(color))
def loop(im,pts,color,width=1): stroke(im,pts+[pts[0]],color,width)
def arc(im,at,r,start,end,color,width=1):
    stroke(im,[(at[0]+math.cos(start+(end-start)*i/16)*r,at[1]+math.sin(start+(end-start)*i/16)*r*.5) for i in range(17)],color,width)
def bolt(im,at):
    x,y=round(at[0]),round(at[1]); poly(im,[(x-2,y),(x,y-1),(x+2,y),(x,y+2)],'black');dot(im,(x,y),'edge')

def venue():
    """A welded octagonal machine. Every playable/gate point stays unchanged."""
    backdrop,structure,surface,markings,rear,front=[blank() for _ in range(6)]
    backdrop.paste(c('black'),(0,0,*SIZE))
    # Quiet dark service floor, discrete plate seams instead of a decorative grid.
    for a,b in [((0,66),(143,0)),((0,276),(166,359)),((503,0),(640,68)),((491,359),(640,286))]:
        stroke(backdrop,[a,b],'ink')
    for x,y in [(16,41),(603,40),(36,321),(590,315),(188,344),(457,347)]:
        stroke(backdrop,[(x,y),(x+17,y-2),(x+21,y)],'deep');bolt(backdrop,(x+7,y-1))
    rim=[projected(p) for p in OUTER]
    well=[projected(p) for p in PLAYABLE]
    # Side-wall extrusion, underside ribs and heavy cast feet have real depth.
    deep_rim=[(x,y+28) for x,y in rim]
    poly(structure,rim+list(reversed(deep_rim)),'black')
    for i in [3,4,5,6,7]:
        a,b=rim[i],rim[(i+1)%8]
        poly(structure,[a,b,(b[0],b[1]+25),(a[0],a[1]+25)],'deep')
        stroke(structure,[(a[0],a[1]+24),(b[0],b[1]+24)],'steel')
        for k in range(1,8):
            q=(a[0]+(b[0]-a[0])*k/8,a[1]+(b[1]-a[1])*k/8)
            stroke(structure,[(q[0],q[1]+8),(q[0],q[1]+20)],'black',3)
            stroke(structure,[(q[0]+1,q[1]+9),(q[0]+1,q[1]+17)],'steel')
    # Eight diagonal bearing/rail posts carry the entire rim construction.
    for u,v in OUTER:
        x,y=projected((u,v)); flank=front if y>=165 else rear
        poly(flank,[(x-9,y-4),(x,y-9),(x+9,y-4),(x+9,y+12),(x,y+17),(x-9,y+12)],'ink')
        poly(flank,[(x-8,y-4),(x,y-8),(x+8,y-4),(x,y)],'steel')
        stroke(flank,[(x-7,y-4),(x,y-1),(x+7,y-4)],'edge');bolt(flank,(x,y+6))
    poly(surface,well,'floor');loop(surface,well,'ink',3)
    inset=[projected((u*.94,v*.94)) for u,v in PLAYABLE]
    loop(surface,inset,'plate',2)
    # Flat welded floor sectors. The contact space remains deliberately quiet.
    center=(320,165)
    for i,p in enumerate(PLAYABLE):
        q=PLAYABLE[(i+1)%8]
        edge=[projected((p[0]*.93,p[1]*.93)),projected((q[0]*.93,q[1]*.93))]
        inner=[projected((p[0]*.35,p[1]*.35)),projected((q[0]*.35,q[1]*.35))]
        poly(surface,edge+list(reversed(inner)),'plate' if i%3==0 else 'floor')
        seam=[projected((p[0]*.34,p[1]*.34)),projected((p[0]*.92,p[1]*.92))]
        stroke(markings,seam,'deep',2)
        stroke(markings,[(seam[0][0]+1,seam[0][1]),(seam[1][0]+1,seam[1][1])],'steel',1,95)
        for factor in [.65,.88]: bolt(markings,projected((p[0]*factor,p[1]*factor)))
    # Central socket sits flush in the floor. No brace, UI bar or obstruction.
    for start,end in [(.15,1.0),(1.3,2.25),(2.55,3.35),(3.7,4.65),(5.0,5.95)]:
        arc(markings,center,28,start,end,'deep',2);arc(markings,center,26,start,end,'steel')
    for u,v in [(33,33),(-33,33),(-33,-33),(33,-33)]:
        x,y=projected((u,v));stroke(markings,[(x-3,y),(x,y+1),(x+3,y)],'steel',1,150)
    # Deterministic authored wear: local blade scuffs, clipped away from gate.
    for u,v,length in [(-81,-14,16),(-66,48,9),(34,-78,13),(79,22,17),(-19,94,12),(66,79,8),(-90,-74,10),(6,-30,8)]:
        x,y=projected((u,v));stroke(markings,[(x-length,y+3),(x,y),(x+length*.35,y-1)],'steel',1,105)
        stroke(markings,[(x-length+3,y+5),(x-3,y+2)],'deep')
    # Peripheral floor access panels/vent slots: aligned to floor projection.
    for u,v in [(-95,54),(95,-54),(-28,-116),(28,116)]:
        panel=[projected((u-12,v-8)),projected((u+12,v-8)),projected((u+12,v+8)),projected((u-12,v+8))]
        poly(markings,panel,'deep');loop(markings,panel,'steel')
        for k in range(-7,8,4):stroke(markings,[projected((u+k,v-5)),projected((u+k,v+5))],'ink',2)
    # Rail architecture is segmented steel. The two canonical gate mouths stay
    # visually open at |u-v|>264 and |u+v|<=36, exactly matching Battle checks.
    for i in range(8):
        a,b=OUTER[i],OUTER[(i+1)%8]
        da,db=projected(a),projected(b)
        for k in range(12):
            t0=k/12;t1=(k+.89)/12
            pa=(a[0]+(b[0]-a[0])*t0,a[1]+(b[1]-a[1])*t0)
            pb=(a[0]+(b[0]-a[0])*t1,a[1]+(b[1]-a[1])*t1)
            mid=((pa[0]+pb[0])*.5,(pa[1]+pb[1])*.5)
            if abs(mid[0]-mid[1])>264 and abs(mid[0]+mid[1])<=36:continue
            target=front if sum(mid)>0 else rear
            q0,q1=projected(pa),projected(pb)
            p0,p1=projected((pa[0]*.965,pa[1]*.965),5),projected((pb[0]*.965,pb[1]*.965),5)
            poly(target,[(q0[0],q0[1]-5),(q1[0],q1[1]-5),p1,p0],'steel')
            poly(target,[q0,q1,(q1[0],q1[1]+5),(q0[0],q0[1]+5)],'deep')
            stroke(target,[(q0[0],q0[1]-6),(q1[0],q1[1]-6)],'edge')
            bolt(target,((p0[0]+p1[0])*.5,(p0[1]+p1[1])*.5))
            if k in [2,8]:stroke(target,[(q0[0],q0[1]-3),(q1[0],q1[1]-3)],'ochre',2)
    for sign in [-1,1]:
        x=320+sign*282
        poly(structure,[(x-sign*18,145),(x+sign*5,153),(x+sign*5,179),(x-sign*18,188)],'ink')
        stroke(markings,[(x-sign*6,155),(x+sign*4,157)],'amber',2)
        stroke(markings,[(x-sign*6,174),(x+sign*4,176)],'amber',2)
        for dy in [0,6]:stroke(markings,[(x-sign*15,160+dy),(x-sign*10,162+dy)],'steel')
    return [backdrop,structure,surface,markings,rear,front]

def venue_lights():
    frames=[]
    for stage in range(5):
        lens,hotmetal,ventkeys=[blank() for _ in range(3)]
        shade=['cold','cyan','amber','hot','red'][stage]
        for p in [(-170,-62),(-150,-124),(-80,-174),(62,-170),(150,-124),(174,-62),(170,62),(124,150),(62,170),(-62,170),(-150,124),(-174,62)]:
            x,y=projected(p,3);stroke(lens,[(x-5,y),(x+4,y+2)],shade,2)
            dot(lens,(x-2,y),'edge' if stage<2 else 'white')
            if stage>=2:stroke(hotmetal,[(x-7,y+7),(x+5,y+9)],'ochre' if stage==2 else 'hot',1,85+stage*20)
        # Exhaust remains attached to actual service ports, never fullfloor fog.
        if stage>=2:
            for x,y in [(144,45),(496,45)]:
                stroke(ventkeys,[(x,y-11),(x+3,y-15),(x+1,y-21)],'steel',1,90+stage*18)
                if stage>=3:stroke(ventkeys,[(x-3,y-9),(x-5,y-14),(x-3,y-17)],'cold',1,70)
        frames.append([lens,hotmetal,ventkeys])
    return frames,['01 embedded rim diode glass','02 local heated underside seams','03 port-attached exhaust keys'],[(t,i,i) for i,t in enumerate(['EARLY','BUILDING','MID','LATE','EXTREME'])],[100]*5,(0,0)

def power_motion():
    frames=[];tags=[];size=(48,32)
    headings=['e','se','s','sw','w','nw','n','ne']
    for tag in ['REDLINE_ROTATION']+['PREDATOR_FLOW_'+h for h in headings]+['CIRCUIT_CURRENT','CIRCUIT_LATCH']:
        first=len(frames)
        for key in range(8):
            ground,motion,sparks=[blank(size) for _ in range(3)]
            if tag=='REDLINE_ROTATION':
                for sector in [0,2.3,4.5]:
                    a=sector+key*.21;arc(motion,(24,16),15,a,a+.55,'red',1);arc(motion,(24,16),18,a-.14,a+.12,'hot')
                    if key in [2,3,5]:dot(sparks,(24+math.cos(a)*19,16+math.sin(a)*9),'amber')
            elif tag.startswith('PREDATOR_FLOW_'):
                # Eight separately authored native headings; runtime never rotates
                # a static pursuit sprite or attaches it to an unrelated target.
                a=headings.index(tag.rsplit('_',1)[1])*math.pi/4
                forward=(math.cos(a),math.sin(a));side=(-forward[1],forward[0]);distance=key-3
                x,y=24+forward[0]*distance,16+forward[1]*distance
                stroke(ground,[(x-forward[0]*6,y-forward[1]*6),(x,y)],'deep')
                for sign in [-1,1]:
                    origin=(x+side[0]*sign*3,y+side[1]*sign*3)
                    stroke(motion,[(origin[0]-forward[0]*5+side[0]*2,origin[1]-forward[1]*5+side[1]*2),origin,(origin[0]-forward[0]*5-side[0]*2,origin[1]-forward[1]*5-side[1]*2)],'amber' if key<5 else 'red')
                if key in [2,3,4]:dot(sparks,(x+forward[0]*2,y+forward[1]*2),'silver')
            elif tag=='CIRCUIT_CURRENT':
                x=8+key*4
                stroke(ground,[(7,17),(40,17)],'deep',2)
                stroke(motion,[(x-4,17),(x+2,17)],'mint',2);dot(sparks,(x+2,17),'white')
            else:
                gap=max(0,5-key*2)
                stroke(ground,[(17,20),(21-gap,18),(21-gap,13)],'steel',2)
                stroke(ground,[(31,12),(27+gap,14),(27+gap,19)],'steel',2)
                if key>=3:stroke(motion,[(21,16),(27,16)],'mint',2)
                if key in [3,4]:
                    stroke(sparks,[(24,12),(24,9)],'white');stroke(sparks,[(20,15),(16,14)],'amber');stroke(sparks,[(28,18),(32,20)],'amber')
            frames.append([ground,motion,sparks])
        tags.append((tag,first,len(frames)-1))
    return frames,['01 floor contact and physical socket','02 directed force/current key','03 finite contact glints'],tags,[70,60,50,45,50,60,70,90]*len(tags),(24,16)

def redline_ring():
    frames=[]
    for key,radius in enumerate([10,18,26,35,43,50,56,60]):
        seam,rim,streaks=[blank((128,128)) for _ in range(3)]
        for sector in range(4):
            start=sector*math.pi/2+.05
            arc(seam,(64,64),radius,start,start+1.38,'red',2)
            arc(rim,(64,64),radius-1,start+.15,start+1.08,'hot')
        # Finite tangential energy follows the ring rather than unrelated chips.
        if 1<=key<=5:
            for sector in [.6,3.8]:arc(streaks,(64,64),radius+3,sector+key*.08,sector+key*.08+.30,'amber')
        frames.append([seam,rim,streaks])
    return frames,['01 expanding red floor ring','02 hot turning rim edge','03 finite tangential streaks'],[('IGNITE',0,7)],[45]*8,(64,64)

def cel_edit(path: Path, editor):
    """Preserve every non-cel chunk byte, including artist palette/tags/slice."""
    data=path.read_bytes();w,h=struct.unpack_from('<HH',data,8);count=struct.unpack_from('<H',data,6)[0]
    output=[];offset=128;history=[]
    for frame in range(count):
        length,magic,old,duration,new=struct.unpack_from('<IHHH2xI',data,offset)
        chunks=[];at=offset+16;frame_layers={}
        for _ in range(new or old):
            n,kind=struct.unpack_from('<IH',data,at);p=data[at+6:at+n]
            if kind==0x2005:
                layer,x,y,opacity,typ,z=struct.unpack_from('<HhhBHh',p);assert opacity==255 and z==0
                if typ==1:im=history[struct.unpack_from('<H',p,16)[0]][layer].copy()
                else:
                    cw,ch=struct.unpack_from('<HH',p,16);raw=zlib.decompress(p[20:]) if typ==2 else p[20:]
                    im=blank((w,h));im.alpha_composite(Image.frombytes('RGBA',(cw,ch),raw),(x,y))
                frame_layers[layer]=im.copy()
                altered=editor(frame,layer,im)
                if altered is not None:
                    p=struct.pack('<HhhBHh5xHH',layer,0,0,255,2,0,w,h)+zlib.compress(altered.tobytes(),9)
            chunks.append(chunk(kind,p));at+=n
        assert at==offset+length
        payload=b''.join(chunks);output.append(struct.pack('<IHHH2xI',len(payload)+16,magic,len(chunks),duration,len(chunks))+payload)
        history.append(frame_layers);offset+=length
    header=bytearray(data[:128]);struct.pack_into('<I',header,0,128+sum(map(len,output)))
    path.write_bytes(bytes(header)+b''.join(output))

def native_layers(path):
    """Actual cel RGBA and untouched non-cel chunks for preservation evidence."""
    data=path.read_bytes();w,h=struct.unpack_from('<HH',data,8);offset=128;frames=[];chunks=[]
    for _ in range(struct.unpack_from('<H',data,6)[0]):
        length,_,old,_,new=struct.unpack_from('<IHHH2xI',data,offset);at=offset+16;layers={};meta=[]
        for _ in range(new or old):
            n,kind=struct.unpack_from('<IH',data,at);p=data[at+6:at+n]
            if kind==0x2005:
                layer,x,y,opacity,typ,z=struct.unpack_from('<HhhBHh',p);assert opacity==255 and z==0
                if typ==1:im=frames[struct.unpack_from('<H',p,16)[0]][layer].copy()
                else:
                    cw,ch=struct.unpack_from('<HH',p,16);raw=zlib.decompress(p[20:]) if typ==2 else p[20:]
                    im=blank((w,h));im.alpha_composite(Image.frombytes('RGBA',(cw,ch),raw),(x,y))
                layers[layer]=im
            else:meta.append(data[at:at+n])
            at+=n
        assert at==offset+length;frames.append(layers);chunks.append(meta);offset+=length
    return frames,chunks

def preservation(baseline):
    result={'baseline':str(baseline),'metadata_preserved':True,'canonical_geometry_byte_identical':True,'redline_main_top_and_stars_preserved':True,'checks':[]}
    geometry='assets/arena/manifest.json'
    assert (baseline/geometry).read_bytes()==(ROOT/geometry).read_bytes()
    result['checks'].append({'path':geometry,'sha256':hashlib.sha256((ROOT/geometry).read_bytes()).hexdigest(),'unchanged':True})
    for relative in ['assets/source-art/arena_foundry_eight.aseprite','assets/source-art/power_identity_002c5/redline_cards.aseprite','assets/source-art/power_identity_002c5/afterimage_cards.aseprite']:
        _,before=read_ase(baseline/relative);_,after=read_ase(ROOT/relative);assert before==after,(relative,'layers/tags/cell/pivot/durations')
        result['checks'].append({'path':relative,'exact_metadata':after,'preserved':True})
    relative='assets/source-art/power_identity_002c5/redline_cards.aseprite';before,bmeta=native_layers(baseline/relative);after,ameta=native_layers(ROOT/relative)
    assert bmeta==ameta,'Non-cel native Redline palette/tags/slice/layer chunks altered'
    for frame,(old,new) in enumerate(zip(before,after)):
        assert all(old[layer].tobytes()==new[layer].tobytes() for layer in [0,1,2]),(frame,'Redline floor/chassis/main rotor')
        a,b=old[4].tobytes(),new[4].tobytes()
        for k in range(0,len(a),4):
            r,g,blue,alpha=a[k:k+4]
            if alpha and not (r>g*1.65 and r>blue*1.6 and g<145):assert a[k:k+4]==b[k:k+4],(frame,'Redline stars/silver key light')
    relative='assets/source-art/power_identity_002c5/afterimage_cards.aseprite';_,bmeta=native_layers(baseline/relative);_,ameta=native_layers(ROOT/relative);assert bmeta==ameta,'Afterimage native palette/layer/tags/slice metadata altered'
    for family in ['redline','afterimage']:
        for group in ['icons','fx']:
            for relative in [f'assets/source-art/power_identity_002c5/{family}_{group}.aseprite',f'assets/powers/identity/{family}_{group}.png']:
                assert (baseline/relative).read_bytes()==(ROOT/relative).read_bytes(),relative
                result['checks'].append({'path':relative,'unchanged':True})
    return result

def correct_cards():
    path=ROOT/'assets/source-art/power_identity_002c5/redline_cards.aseprite'
    def redline(frame,layer,im):
        key=frame%12;state=frame//12
        if layer==3:
            # Replace disconnected rectangular heat blocks with coherent rotor arcs.
            out=blank((64,64));x=38 if state<2 else [29,29,30,28,31,28,32,30,33,29,31,30][key]
            y=31 if state<2 else [31,31,30,32,29,33,30,31,29,32,30,31][key]
            if state==3:
                x=[18,18,17,16,20,31,43,48,43,36,29,22][key];y=[36,36,37,38,36,31,26,23,27,31,34,35][key]
            heat=[0,1,1,2,3,4,5,6,5,4,2,1][key]
            for sector in [0.2,2.5,4.8]:
                a=sector+key*.19
                arc(out,(x,y+3),19,a,a+.45+heat*.045,'red',1)
                if heat>=2:arc(out,(x,y+3),22,a-.1,a+.25,'hot',1)
            if state==3:
                for off in [0,5]:stroke(out,[(max(2,x-23),y+9+off),(x-9,y+3+off)],'red')
            return out
        if layer==4:
            # Preserve silver/star key light and remove hot/oxide chip blocks.
            out=im.copy();px=out.load()
            for y in range(64):
                for x in range(64):
                    r,g,b,a=px[x,y]
                    if a and r>g*1.65 and r>b*1.6 and g<145: px[x,y]=(0,0,0,0)
            return out
        return None
    cel_edit(path,redline)
    path=ROOT/'assets/source-art/power_identity_002c5/afterimage_cards.aseprite'
    def afterimage(frame,layer,im):
        key=frame%12;state=frame//12;out=blank((64,64))
        # Same quiet framing and exact accepted native top scale as core cards.
        if layer==0:
            stroke(out,[(4,15),(4,5),(16,5)],'deep');stroke(out,[(48,59),(59,59),(59,48)],'deep')
            stroke(out,[(7,49),(28,38),(55,48)],'deep');return out
        lead=[(23,36),(23,36),(27,33),(31,30),(35,27),(39,24),(43,22),(46,20),(47,20),(46,21),(44,23),(41,25)][key]
        if state==2:lead=[(12,43),(13,36),(16,27),(24,20),(36,19),(46,24),(48,32),(44,41),(34,47),(22,49),(16,47),(12,43)][key]
        if state==3:lead=[(18,45),(19,44),(23,41),(28,37),(32,33),(37,29),(42,25),(46,22),(48,21),(47,22),(44,25),(38,29)][key]
        if layer==1:
            shadow(out,*lead,13)
            if state==2:shadow(out,33,31,10)
            return out
        if layer==2:
            if state==2:top(out,'bastion',33,28,key//2)
            return out
        if layer==3:
            route=[(7,53),(16,48),(24,45),(34,39),(42,32),(49,28)]
            if state==1:route=[(7,51),(16,46),(28,35),(28,19),(15,25),(21,44),(37,43),(51,31)]
            if state==2:route=[(12,43),(16,25),(29,17),(46,22),(50,37),(36,49),(17,49)]
            if state==3:route=[(8,27),(27,38),(53,52)]
            shade='green' if state==2 else 'cold'
            stroke(out,route,'deep',3);stroke(out,route,shade,1)
            if state==2 and 5<=key<=9:stroke(out,[route[-1],route[0]],'mint',2)
            return out
        if layer==4:
            top(out,'vane',*lead,key%8)
            # One physical echo is a blade scar, not a second complete top.
            if state!=2 and key>=2:
                for off in [0,6]:stroke(out,[(lead[0]-16-off,lead[1]+9+off*.5),(lead[0]-9-off,lead[1]+5+off*.5)],'cyan')
            return out
        if layer==5:
            if state==2:
                x,y=12,43;gap=4 if key<5 else 0
                stroke(out,[(x-4,y+2),(x-gap,y),(x-gap,y-3)],'steel');stroke(out,[(x+4,y-2),(x+gap,y),(x+gap,y+3)],'mint')
                if key in [5,6]:stroke(out,[(x,y-3),(x,y-6)],'white')
            elif state==3 and 3<=key<=7:dot(out,(29,39),'white')
            return out
        return None
    cel_edit(path,afterimage)
    for family in ['redline','afterimage']:
        p=ROOT/f'assets/powers/identity/{family}_design.json';design=json.loads(p.read_text())
        if family=='redline':
            design['grammar']['silhouette']='Preserved off-centre native metal rotor with coherent red heat arcs and restrained star accents.'
            design['grammar']['motion']='Authored rotor arcs and directional heat streaks; preserved stars and machine; no disconnected rectangular chip blocks.'
            design['grammar']['feature']='Open machine centre, physical rotor heat and tangential streaks; mutations retain their distinct action stories.'
            design['notes']='003A.1 human correction retains stars, native main rotor and card timing. Heat blocks are replaced with coherent rotor arcs; gameplay keeps its accepted expanding red ring.'
        else:
            design['grammar']['silhouette']='Accepted native Vane top at core-card scale, sparse actual trail, physical closure socket'
            design['notes']='003A.1 human correction adopts the quiet core-card framing and accepted native machine anatomy. Ghost route and Slipstream crossing retain distinct identities. Layers/tags/pivots/authored milliseconds preserved.'
        save_json(p,design)

def author():
    SOURCE.mkdir(parents=True,exist_ok=True)
    venue_source=ROOT/'assets/source-art/arena_foundry_eight.aseprite'
    _,old=read_ase(venue_source)
    write_ase(venue_source,[venue()],old['layers'],[],old['durations_ms'],old['pivot'],note='003A.1 authored welded foundry machine; exact canonical world vertices/isometric projection/gate dimensions; named editable layers',palette=PAL)
    write_ase(SOURCE/'venue_lights.aseprite',*venue_lights(),note='003A.1 same welded venue heats through five stages; embedded hardware only; no Director readout',palette=PAL)
    write_ase(SOURCE/'power_motion.aseprite',*power_motion(),note='003A.1 authored radial heat, pursuit current and physical circuit socket; finite native pixel keys',palette=PAL)
    write_ase(SOURCE/'redline_ring.aseprite',*redline_ring(),note='003A.1 accepted expanding red ring identity; no detached tooth blocks; native finite tangential streaks',palette=PAL)
    correct_cards()

def native_sheet(source,columns,aseprite,temp):
    png=temp/(source.stem+'.png');js=temp/(source.stem+'.json')
    subprocess.run([aseprite,'--batch',str(source),'--list-layers','--list-tags','--list-slices','--sheet-columns',str(columns),'--sheet',str(png),'--data',str(js),'--format','json-array'],check=True,capture_output=True)
    frames,meta=read_ase(source);sheet=Image.open(png).convert('RGBA');raw=json.loads(js.read_text())
    for i,frame in enumerate(frames):
        w,h=meta['cell'];a=sheet.crop((i%columns*w,i//columns*h,(i%columns+1)*w,(i//columns+1)*h)).tobytes();b=frame.tobytes()
        assert all(a[k:k+4]==b[k:k+4] for k in range(0,len(a),4) if a[k+3] or b[k+3]),(source.name,i,'native RGBA parity')
    assert meta['layers']==[l['name'] for l in raw['meta']['layers']]
    assert meta['durations_ms']==[f['duration'] for f in raw['frames']]
    assert meta['tags']=={t['name']:{'from':t['from'],'to':t['to']} for t in raw['meta'].get('frameTags',[])}
    piv=raw['meta']['slices'][0]['keys'][0]['pivot'];assert meta['pivot']==[piv['x'],piv['y']]
    return sheet,meta

def export(aseprite,check=False):
    qa=create_task_workspace('003A.1');OUT.mkdir(parents=True,exist_ok=True)
    report={'task':'003A.1 final combat art','native_runtime_parity':True,'geometry_unchanged':True,'masters':[]}
    with tempfile.TemporaryDirectory(prefix='combat-native-',dir=qa/'temp') as folder:
        temp=Path(folder);source=ROOT/'assets/source-art/arena_foundry_eight.aseprite'
        _,meta=native_sheet(source,1,aseprite,temp)
        for name in meta['layers']:
            dst=temp/(name+'.png');subprocess.run([aseprite,'--batch',str(source),'--layer',name,'--save-as',str(dst)],check=True,capture_output=True)
            out=ROOT/'assets/arena'/f'{name}.png'
            if check:assert Image.open(out).convert('RGBA').tobytes()==Image.open(dst).convert('RGBA').tobytes(),name
            else:out.write_bytes(dst.read_bytes())
        report['masters'].append({'source':str(source.relative_to(ROOT)).replace('\\','/'),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),**meta})
        manifest={'version':1,'filter':'nearest','presentation_only':True,'families':{},'base_arena':{**meta,'source':source.relative_to(ROOT).as_posix(),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'frame_count':1,'columns':1,'textures':{name:f'res://assets/arena/{name}.png' for name in meta['layers']}}}
        for name,columns in [('venue_lights',5),('power_motion',8),('redline_ring',8)]:
            source=SOURCE/(name+'.aseprite');sheet,meta=native_sheet(source,columns,aseprite,temp)
            meta.update(texture=f'res://assets/powers/combat_003a1/{name}.png',source=source.relative_to(ROOT).as_posix(),columns=columns,frame_count=len(meta['durations_ms']),source_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
            out=OUT/(name+'.png')
            if check:assert Image.open(out).convert('RGBA').tobytes()==sheet.tobytes()
            else:sheet.save(out,optimize=True)
            manifest['families'][name]=meta;report['masters'].append(meta)
        path=OUT/'manifest.json'
        if check:assert json.loads(path.read_text())==manifest
        else:save_json(path,manifest)
    if not check:
        for family in ['redline','afterimage']:export_family(family,aseprite)
        families={};art={}
        for family in FAMILIES:
            path=ROOT/f'assets/powers/identity/{family}_manifest.json'
            if path.exists():item=json.loads(path.read_text());families[family]=item;art.update(item['art'])
        save_json(ROOT/'assets/powers/identity_manifest.json',{'version':1,'filter':'nearest','scope':'artist-owned native per-family identity sources; no physics or RNG','families':families,'art':art})
    for family in ['redline','afterimage']:
        source=ROOT/f'assets/source-art/power_identity_002c5/{family}_cards.aseprite';frames,meta=read_ase(source)
        with tempfile.TemporaryDirectory(prefix='card-parity-',dir=qa/'temp') as folder:
            sheet,_=native_sheet(source,12,aseprite,Path(folder));assert Image.open(ROOT/f'assets/powers/identity/{family}_cards.png').convert('RGBA').tobytes()==sheet.tobytes()
        report['masters'].append({'source':source.relative_to(ROOT).as_posix(),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),**meta})
    return report

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--author',action='store_true');p.add_argument('--check',action='store_true');p.add_argument('--aseprite');p.add_argument('--report',type=Path);p.add_argument('--baseline',type=Path);a=p.parse_args()
    if a.author and a.check:p.error('--check is read only')
    if a.report and ROOT in a.report.resolve().parents:p.error('QA report must be external')
    if a.author:author()
    report=export(find_tool('aseprite',a.aseprite),a.check)
    if a.baseline:report['preservation']=preservation(a.baseline.resolve())
    if a.report:a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))

if __name__=='__main__':main()
