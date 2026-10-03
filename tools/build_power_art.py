"""Author and export the Task 002B native pixel sources.

Normal artist workflow: edit .aseprite, then run this script (exports only).
--author reconstructs the original authored cels and overwrites those sources.
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


def string(s):
    b=s.encode("utf-8");return struct.pack("<H",len(b))+b


def chunk(kind,data): return struct.pack("<IH",len(data)+6,kind)+data


def write_ase(path,frames,layers,tags,durations,pivot):
    w,h=frames[0][0].size
    output=[]
    for f,images in enumerate(frames):
        chunks=[]
        if f==0:
            for layer in layers:
                chunks.append(chunk(0x2004,struct.pack("<6HB3x",3,0,0,0,0,0,255)+string(layer)))
            pal=struct.pack("<III8x",len(P),0,len(P)-1)
            for name in P: pal+=struct.pack("<H4B",1,*color(name))+string(name)
            chunks.append(chunk(0x2019,pal))
            chunks.append(chunk(0x2020,struct.pack("<I",1)+string("Task 002B / native pixel clusters / fixed projected contact pivot / nearest filter")))
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
    header=struct.pack("<IHHHHHIHII B3x HBBhhHH",len(payload)+128,0xA5E0,len(frames),w,h,32,1,100,0,0,0,len(P),1,1,0,0,w,h)
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
    filename={"small_top_002b":"small_top","power_fx_002b":"effects","power_icons_002b":"icons"}[name]+".png"
    sheet.save(OUT/filename,optimize=True)
    meta.update({"texture":filename,"columns":columns,"frame_count":len(frames),"source":"../source-art/"+name+".aseprite"})
    return meta


def main():
    parser=argparse.ArgumentParser();parser.add_argument("--author",action="store_true");args=parser.parse_args()
    SOURCE.mkdir(parents=True,exist_ok=True);OUT.mkdir(parents=True,exist_ok=True)
    if args.author:
        for name,factory in [("small_top_002b",small_frames),("power_fx_002b",effect_frames),("power_icons_002b",icon_frames)]:
            write_ase(SOURCE/(name+".aseprite"),*factory())
    manifest={"version":1,"native_pixels":True,"filter":"nearest","projection":"fixed 2:1 ground plane; no whole-sprite rotation", "small_top":export("small_top_002b",8),"effects":export("power_fx_002b",8),"icons":export("power_icons_002b",6)}
    (OUT/"manifest.json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
    # Review sheet is intentionally outside source assets; no arena source touched.
    print("Exported 3 editable Aseprite sources: 8 small-top, 48 effect, 6 icon frames.")


if __name__=="__main__": main()
