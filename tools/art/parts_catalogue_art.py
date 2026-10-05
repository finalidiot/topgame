"""Native editable component masters and exports for Task 002C.5.2.

Default export reads artist-edited masters. --author deliberately authors only
this task's twenty masters. Integer top-plane outlines are projected separately
for each authored spin phase; no raster rotation, scaling, blur or AI imagery.
Review sheets are external QA output, never production source.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import os
import shutil
import subprocess
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from build_power_art import read_ase, write_ase, color

SOURCE = ROOT / "assets/source-art/parts_002c5_2"
OUT = ROOT / "assets/top/parts"
GROUPS = {
    "blade": ["hammerfall", "sawtooth", "puck", "outrigger", "lopsider", "crescent", "fork"],
    "ratchet": ["ballast", "flex", "kickback", "offset", "flywheel", "scrap"],
    "bit": ["skate", "claw", "freewheel", "eccentric", "chisel", "tripod", "groove"],
}
FOLDERS = {"blade": "blades", "ratchet": "ratchets", "bit": "bits"}
PALETTE = {
    "ink": "#10151f", "dark": "#202b36", "gunmetal": "#344451",
    "steel": "#4c626e", "steel light": "#768e99", "silver": "#abc0c7",
    "light": "#e3e8dc", "darkblue": "#16354b", "blue": "#245c7b",
    "accent": "#4595b5", "oxide": "#a94c35", "orange": "#df8740",
    "gold": "#f3c36a", "rubber": "#2f383e", "rubber light": "#68746f",
}
VISUAL_HEIGHT = {"ballast": 3, "flex": 0, "kickback": -2, "offset": -1, "flywheel": 1, "scrap": 2}


def c(name):
    return color(PALETTE.get(name, name))


def blank():
    return Image.new("RGBA", (48, 48))


def xy(point, phase=0, cx=24, cy=25):
    x, y = point
    a = phase * math.tau / 8
    return round(cx + x * math.cos(a) - y * math.sin(a)), round(cy + (x * math.sin(a) + y * math.cos(a)) * .5)


def project(points, phase=0):
    return [xy(p, phase) for p in points]


def circle(cx, cy, radius, count=32):
    return [(cx + math.cos(k * math.tau / count) * radius, cy + math.sin(k * math.tau / count) * radius) for k in range(count)]


def polygon_mask(polygons, phase):
    im = Image.new("L", (48, 48))
    d = ImageDraw.Draw(im)
    for points in polygons:
        d.polygon(project(points, phase), fill=255)
    return im


def paint_mask(im, mask, name):
    layer = Image.new("RGBA", im.size, c(name))
    layer.putalpha(mask)
    im.alpha_composite(layer)


def shifted(mask, y):
    im = Image.new("L", mask.size)
    im.paste(mask, (0, y))
    return im


def blade_outline(name):
    if name == "hammerfall":
        # Broad two opposing cast hammer blocks, joined by a thick waist.
        return [[(-22,-6),(-19,-10),(-11,-10),(-9,-6),(9,-6),(11,-10),(19,-10),(22,-6),(22,6),(19,10),(11,10),(9,6),(-9,6),(-11,10),(-19,10),(-22,6)]]
    if name == "sawtooth":
        return [[(math.cos(a)*r, math.sin(a)*r) for k in range(12) for a,r in [(k*math.tau/12,16),(k*math.tau/12+.07,20),(k*math.tau/12+.23,20),(k*math.tau/12+.45,16)]]]
    if name == "puck":
        return [circle(0,0,13,24)]
    if name == "outrigger":
        shapes = [circle(0,0,8,20)]
        # Three wide, rounded paddles with narrow roots and open gaps.
        paddle=[(5,-3),(13,-9),(19,-8),(22,-4),(23,1),(21,5),(17,6),(10,2),(5,3)]
        for k in range(3):
            a=k*math.tau/3
            shapes.append([(x*math.cos(a)-y*math.sin(a),x*math.sin(a)+y*math.cos(a)) for x,y in paddle])
        return shapes
    if name == "lopsider":
        # A whole heavy disc on one side; small counterweight at the opposite end.
        return [circle(-5,0,15,24),[(0,-5),(17,-5),(20,-3),(20,3),(17,5),(0,5)]]
    if name == "crescent":
        # One continuous C-shaped scoop, physically connected to the central hub.
        outer=[(math.cos(a)*22,math.sin(a)*22) for a in [math.radians(40+k*10) for k in range(29)]]
        inner=[(math.cos(a)*13,math.sin(a)*13) for a in [math.radians(320-k*10) for k in range(29)]]
        return [outer+inner,circle(0,0,7,20),[(-3,-4),(-17,-7),(-17,7),(-3,4)]]
    if name == "fork":
        # Opposed bifurcated tips leave two deep, readable contact recesses.
        return [[(-20,-12),(-10,-12),(-6,-5),(6,-5),(10,-12),(20,-12),(20,-7),(10,-4),(10,4),(20,7),(20,12),(10,12),(6,5),(-6,5),(-10,12),(-20,12),(-20,7),(-10,4),(-10,-4),(-20,-7)]]
    raise ValueError(name)


def blade_frames(name):
    layers=["cast underside and vertical rim", "cast steel contact plate", "material inserts and strike faces", "central locking hub"]
    frames=[]
    for phase in range(8):
        images=[blank() for _ in layers]
        depth,top,insert,hub=images
        mask=polygon_mask(blade_outline(name),phase)
        paint_mask(depth,shifted(mask,3 if name=="fork" else 4),"ink")
        paint_mask(depth,shifted(mask,2 if name=="fork" else 3),"dark")
        paint_mask(depth,shifted(mask,1),"gunmetal")
        paint_mask(top,mask,"ink")
        inner=mask.filter(ImageFilter.MinFilter(3))
        paint_mask(top,inner,"steel")
        # Bright top-facing casting edges, darker front rim: physical lighting
        # remains world-aligned while the authored top-plane shape turns.
        for y in range(48):
            for x in range(48):
                if mask.getpixel((x,y)) and (y==0 or not mask.getpixel((x,y-1))):
                    top.putpixel((x,y),c("silver"))
                elif inner.getpixel((x,y)) and y < 24:
                    top.putpixel((x,y),c("steel light"))
        d=ImageDraw.Draw(insert)
        def poly(points,main,outline=None):
            d.polygon(project(points,phase),fill=c(main))
            if outline:d.line(project(points+[points[0]],phase),fill=c(outline),width=1)
        def line(points,main,width=1):
            d.line(project(points,phase),fill=c(main),width=width)
        if name=="hammerfall":
            for sign in [-1,1]:
                poly([(sign*12,-7),(sign*18,-7),(sign*20,-4),(sign*20,4),(sign*18,7),(sign*12,7)],"oxide")
                line([(sign*19,-5),(sign*19,5)],"gold",2)
                line([(sign*10,-5),(sign*10,5)],"dark")
        elif name=="sawtooth":
            for k in range(12):
                a=k*math.tau/12+.12
                line([(math.cos(a)*15,math.sin(a)*15),(math.cos(a)*19,math.sin(a)*19)],"silver")
            for k in [0,4,8]:
                a=k*math.tau/12
                poly([(math.cos(a-.15)*9,math.sin(a-.15)*9),(math.cos(a-.15)*14,math.sin(a-.15)*14),(math.cos(a+.15)*14,math.sin(a+.15)*14),(math.cos(a+.15)*9,math.sin(a+.15)*9)],"darkblue")
        elif name=="puck":
            d.line(project(circle(0,0,9,24)+[circle(0,0,9,24)[0]],phase),fill=c("silver"),width=1)
            poly([(-3,-8),(3,-8),(3,-5),(-3,-5)],"blue")
        elif name=="outrigger":
            for k in range(3):
                a=k*math.tau/3
                local=[(8,-2),(15,-6),(20,-3),(19,1),(15,2),(10,0)]
                p=[(x*math.cos(a)-y*math.sin(a),x*math.sin(a)+y*math.cos(a)) for x,y in local]
                poly(p,"blue")
                line(p[:3],"accent")
        elif name=="lopsider":
            poly([(-17,-5),(-13,-10),(-5,-12),(3,-9),(5,-3),(2,4),(-6,8),(-14,4)],"gunmetal")
            line([(-16,-4),(-12,-8),(-5,-10),(1,-8)],"silver",2)
            poly([(14,-3),(18,-3),(18,3),(14,3)],"oxide")
            # Four large rivets show this eccentric mass is one cast plate.
            for p in [(-12,-4),(-10,3),(0,-7),(1,4)]:
                q=xy(p,phase);d.point(q,fill=c("light"))
        elif name=="crescent":
            arc=[(math.cos(math.radians(a))*18,math.sin(math.radians(a))*18) for a in range(60,301,12)]
            line(arc,"silver",2)
            line([(-15,-3),(-7,-1)],"blue",2)
        elif name=="fork":
            for sign in [-1,1]:
                for sy in [-1,1]:
                    line([(sign*11,sy*9),(sign*19,sy*9)],"silver",2)
                poly([(sign*7,-3),(sign*10,-3),(sign*10,3),(sign*7,3)],"blue")
        # Inserts cannot overhang their physical cast surface.
        insert.putalpha(Image.composite(insert.getchannel("A"),Image.new("L",(48,48)),inner))
        for y in range(48):
            for x in range(48):
                if insert.getpixel((x,y))[3]==0:insert.putpixel((x,y),(0,0,0,0))
        h=ImageDraw.Draw(hub)
        h.polygon([(18,24),(21,21),(27,21),(30,24),(28,28),(20,28)],fill=c("ink"))
        h.polygon([(20,24),(22,22),(26,22),(28,24),(26,26),(22,26)],fill=c("silver"))
        h.line([(21,23),(24,22),(27,23)],fill=c("light"))
        h.rectangle((23,24,25,25),fill=c("blue"))
        # The socket's keyed stripe rotates in the projected plane.
        h.line([xy((-2,0),phase),xy((2,0),phase)],fill=c("darkblue"))
        frames.append(images)
    return frames,layers,[("spin",0,7)],[100]*8,(24,40)


def ratchet_frames(name):
    images=[blank() for _ in range(4)]
    layers=["lower bit socket", "structural core and sidewall", "functional mass or flex ring", "blade collar and fastening"]
    socket,core,ring,collar=[ImageDraw.Draw(i) for i in images]
    y=29+VISUAL_HEIGHT[name]
    socket.polygon([(20,34),(28,34),(28,38),(25,40),(22,38),(20,37)],fill=c("ink"))
    socket.rectangle((22,34,26,37),fill=c("gunmetal"))
    socket.line([(22,37),(26,37)],fill=c("silver"))
    core.polygon([(18,y),(24,y-3),(31,y),(31,35),(27,38),(21,38),(18,35)],fill=c("ink"))
    core.polygon([(19,y+1),(24,y-1),(30,y+1),(30,34),(26,37),(21,36),(19,34)],fill=c("steel"))
    core.polygon([(24,y),(29,y+1),(29,34),(25,36),(24,35)],fill=c("gunmetal"))
    core.line([(20,y+2),(20,34)],fill=c("silver"),width=2)
    if name=="ballast":
        ring.polygon([(15,33),(19,31),(29,31),(34,33),(34,36),(29,39),(19,39),(15,36)],fill=c("ink"))
        ring.polygon([(16,33),(20,32),(29,32),(33,34),(32,36),(28,38),(20,38),(16,35)],fill=c("gunmetal"))
        ring.line([(17,33),(21,32),(29,32),(32,33)],fill=c("silver"))
        ring.line([(18,36),(29,37)],fill=c("steel"),width=2)
    elif name=="flex":
        # Open steel spring race, three visible dark gaps and one metal bridge.
        ring.polygon([(16,31),(21,29),(29,29),(32,31),(32,35),(28,37),(19,37),(16,35)],fill=c("ink"))
        for yy in [30,33,36]:
            ring.line([(18,yy),(21,yy+1),(29,yy+1),(31,yy)],fill=c("silver"))
        ring.line([(21,31),(23,32),(21,34),(23,35)],fill=c("blue"),width=2)
        ring.rectangle((27,31,29,35),fill=c("gunmetal"))
    elif name=="kickback":
        for xx in [15,31]:
            ring.polygon([(xx,31),(xx+3,29),(xx+3,34),(xx,36)],fill=c("ink"))
            ring.line([(xx+1,32),(xx+2,31),(xx+2,34)],fill=c("orange"),width=2)
        ring.line([(18,34),(21,36),(28,36),(31,34)],fill=c("silver"),width=2)
    elif name=="offset":
        ring.polygon([(13,31),(16,28),(21,28),(23,32),(22,37),(18,39),(13,36)],fill=c("ink"))
        ring.polygon([(14,31),(17,29),(20,29),(22,32),(21,36),(17,37),(14,35)],fill=c("gunmetal"))
        ring.line([(15,31),(18,30),(21,31)],fill=c("silver"))
        ring.rectangle((17,33,20,35),fill=c("oxide"))
    elif name=="flywheel":
        ring.polygon([(13,31),(18,28),(29,28),(35,31),(35,34),(29,38),(18,38),(13,34)],fill=c("ink"))
        ring.polygon([(14,31),(19,29),(29,29),(34,31),(34,33),(29,36),(19,36),(14,33)],fill=c("steel"))
        ring.line([(15,31),(20,30),(29,30),(33,31)],fill=c("silver"))
        ring.line([(17,34),(21,35),(29,35),(32,33)],fill=c("darkblue"),width=2)
    elif name=="scrap":
        ring.polygon([(16,32),(20,30),(23,32),(29,31),(32,34),(29,37),(22,38),(17,36)],fill=c("ink"))
        ring.polygon([(17,33),(21,31),(23,33),(28,32),(31,34),(28,36),(22,37),(18,35)],fill=c("oxide"))
        ring.line([(17,33),(21,32)],fill=c("orange"))
        ring.line([(25,33),(23,35),(25,36)],fill=c("dark"))
    collar.polygon([(18,y),(21,y-2),(27,y-2),(31,y),(28,y+2),(20,y+2)],fill=c("ink"))
    collar.polygon([(20,y),(22,y-1),(27,y-1),(29,y),(27,y+1),(21,y+1)],fill=c("silver"))
    collar.line([(23,y),(26,y)],fill=c("darkblue"),width=1)
    return [images],layers,[("assembly",0,0)],[200],(24,40)


def bit_frames(name):
    images=[blank() for _ in range(3)]
    layers=["locking stem", "contact body and material", "floor contact surface"]
    stem,body,contact=[ImageDraw.Draw(i) for i in images]
    stem.polygon([(21,34),(24,32),(27,34),(27,37),(24,39),(21,37)],fill=c("ink"))
    stem.polygon([(22,34),(24,33),(26,34),(26,37),(23,37),(22,36)],fill=c("steel"))
    stem.line([(22,35),(22,36)],fill=c("silver"))
    if name=="skate":
        body.polygon([(18,37),(21,35),(28,35),(31,37),(29,39),(20,39)],fill=c("ink"))
        body.line([(20,37),(29,37)],fill=c("silver"),width=2)
        contact.line([(21,40),(28,40)],fill=c("light"))
    elif name=="claw":
        body.polygon([(20,36),(28,36),(30,38),(29,40),(26,38),(25,41),(23,41),(22,38),(19,40),(18,38)],fill=c("ink"))
        body.line([(20,37),(23,37),(24,39),(26,37),(28,37)],fill=c("rubber light"),width=2)
        contact.point((20,40),fill=c("rubber light"));contact.point((24,40),fill=c("silver"));contact.point((28,40),fill=c("rubber light"))
    elif name=="freewheel":
        body.ellipse((19,35,29,40),fill=c("ink"))
        body.ellipse((20,36,28,39),fill=c("silver"))
        body.ellipse((22,36,26,38),fill=c("darkblue"))
        contact.line([(22,40),(26,40)],fill=c("light"))
    elif name=="eccentric":
        body.polygon([(18,37),(21,35),(27,35),(29,37),(28,40),(24,41),(19,39)],fill=c("ink"))
        body.polygon([(19,37),(22,36),(26,36),(28,37),(26,39),(22,40),(19,39)],fill=c("rubber"))
        body.line([(20,37),(23,36),(27,37)],fill=c("rubber light"))
        contact.line([(20,39),(23,40)],fill=c("orange"),width=1)
    elif name=="chisel":
        body.polygon([(20,35),(28,35),(28,38),(25,41),(22,40),(20,38)],fill=c("ink"))
        body.polygon([(21,36),(27,36),(26,38),(24,40),(22,39)],fill=c("silver"))
        contact.line([(23,40),(26,39)],fill=c("light"),width=1)
    elif name=="tripod":
        body.polygon([(19,37),(22,35),(26,35),(29,37),(28,40),(26,40),(24,38),(22,40),(20,40)],fill=c("ink"))
        body.line([(20,37),(24,36),(28,37)],fill=c("steel light"),width=2)
        contact.line([(20,39),(21,40)],fill=c("silver"))
        contact.line([(27,39),(28,40)],fill=c("silver"))
        contact.point((24,39),fill=c("light"))
    elif name=="groove":
        body.polygon([(19,36),(29,36),(30,38),(28,40),(20,40),(18,38)],fill=c("ink"))
        body.polygon([(20,37),(28,37),(29,38),(27,39),(21,39),(19,38)],fill=c("blue"))
        body.line([(21,37),(27,37)],fill=c("accent"))
        contact.line([(20,40),(22,40)],fill=c("silver"))
        contact.line([(26,40),(28,40)],fill=c("silver"))
        contact.line([(24,38),(24,40)],fill=c("ink"),width=1)
    else:
        raise ValueError(name)
    return [images],layers,[("assembly",0,0)],[200],(24,40)


def author():
    SOURCE.mkdir(parents=True,exist_ok=True)
    for category,ids in GROUPS.items():
        factory={"blade":blade_frames,"ratchet":ratchet_frames,"bit":bit_frames}[category]
        for name in ids:
            write_ase(SOURCE / f"{name}.aseprite", *factory(name),
                      note=f"Task 002C.5.2 / {category} {name} / editable named physical layers / fixed 2:1 projected geometry / ground contact pivot 24,40 / native 48px nearest",
                      palette=PALETTE)


def hash_file(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def export():
    manifest={"version":1,"task":"002C.5.2","native_pixels":True,"filter":"nearest","cell":[48,48],"contact_pivot":[24,40],"blade_hub":[24,25],"projection":"fixed 2:1 ground plane; independently authored top-plane spin phases","parts":{}}
    for category,ids in GROUPS.items():
        folder=OUT/FOLDERS[category]
        folder.mkdir(parents=True,exist_ok=True)
        for name in ids:
            source=SOURCE/f"{name}.aseprite"
            frames,meta=read_ase(source)
            frames[0].save(folder/f"{name}.png",optimize=True)
            runtime=[folder/f"{name}.png"]
            if category=="blade":
                sheet=Image.new("RGBA",(384,48))
                for i,im in enumerate(frames):sheet.alpha_composite(im,(i*48,0))
                sheet.save(folder/f"{name}_spin.png",optimize=True)
                runtime.append(folder/f"{name}_spin.png")
            manifest["parts"][name]={"category":category,"source":str(source.relative_to(ROOT)).replace("\\","/"),"source_sha256":hash_file(source),"runtime":[str(p.relative_to(ROOT)).replace("\\","/") for p in runtime],"runtime_sha256":[hash_file(p) for p in runtime],"frame_count":len(frames),**meta}
    (OUT/"catalogue_002c5_2_art.json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
    return manifest


def validate():
    problems=[]
    manifest=json.loads((OUT/"catalogue_002c5_2_art.json").read_text(encoding="utf-8"))
    entries=[]
    for category,ids in GROUPS.items():
        for name in ids:
            source=SOURCE/f"{name}.aseprite"
            frames,meta=read_ase(source)
            expected=8 if category=="blade" else 1
            assert meta["cell"]==[48,48] and meta["pivot"]==[24,40],name
            assert len(frames)==expected and len(meta["layers"])>=3,name
            assert len(set(meta["layers"]))==len(meta["layers"]),name
            assert all(0<duration<=250 for duration in meta["durations_ms"]),name
            assert meta["tags"].get("spin" if category=="blade" else "assembly")=={"from":0,"to":expected-1},name
            folder=OUT/FOLDERS[category]
            actual=Image.open(folder/f"{name}.png").convert("RGBA")
            assert actual.tobytes()==frames[0].tobytes(),f"{name} static source/runtime pixel mismatch"
            if category=="blade":
                sheet=Image.open(folder/f"{name}_spin.png").convert("RGBA")
                assert sheet.size==(384,48),name
                for i,im in enumerate(frames):
                    assert sheet.crop((i*48,0,(i+1)*48,48)).tobytes()==im.tobytes(),f"{name} phase{i} parity"
                    assert im.getbbox() is not None,name
                assert len(set(im.tobytes() for im in frames))>=2,name
            assert manifest["parts"][name]["source_sha256"]==hash_file(source),f"{name} manifest source hash stale"
            for path,digest in zip(manifest["parts"][name]["runtime"],manifest["parts"][name]["runtime_sha256"]):
                assert hash_file(ROOT/path)==digest,f"{name} runtime hash stale"
            entries.append({"id":name,"category":category,"frames":len(frames),"layers":meta["layers"],"bounds":list(actual.getbbox()),"source_runtime_parity":True})
    report={"task":"002C.5.2","masters":20,"runtime_sprites":27,"blade_spin_frames":56,"native_48px":True,"contact_pivot":[24,40],"source_runtime_parity":True,"parts":entries,"problems":problems}
    catalogue=ROOT/"assets/data/parts_catalogue.json"
    if catalogue.exists():report["assembly_structure"]=assembly_validate(json.loads(catalogue.read_text(encoding="utf-8"))["categories"])
    return report


def assembly_validate(metadata):
    """Check every legal visual combination and every authored Blade phase.

    Opaque joins prove components physically meet in the projected drawing.
    These structural checks do not claim that overlap alone proves visual quality.
    """
    masks={category:{} for category in metadata}
    blade_frames={}
    for category,parts in metadata.items():
        for name,info in parts.items():
            im=Image.open(ROOT/info["visual"]["sprite"].removeprefix("res://")).convert("RGBA")
            assert im.size==(48,48),f"{name}: wrong assembly cell"
            masks[category][name]=im.getchannel("A").point(lambda a:255 if a else 0)
            if category=="blade":
                spin=Image.open(ROOT/info["visual"]["spin"].removeprefix("res://")).convert("RGBA")
                assert spin.size==(384,48),f"{name}: wrong spin sheet"
                blade_frames[name]=[spin.crop((i*48,0,(i+1)*48,48)).getchannel("A").point(lambda a:255 if a else 0) for i in range(8)]
    combinations=0;poses=0;min_blade_join=2304;min_bit_join=2304
    for blade,phases in blade_frames.items():
        for ratchet,ratchet_mask in masks["ratchet"].items():
            height=int(metadata["ratchet"][ratchet]["physics"].get("visual_height",0))
            for bit,bit_mask in masks["bit"].items():
                bit_join=ImageChops.multiply(ratchet_mask,bit_mask)
                bit_pixels=sum(bit_join.histogram()[1:])
                assert bit_pixels>0,f"Floating bit: {blade}/{ratchet}/{bit}"
                min_bit_join=min(min_bit_join,bit_pixels)
                combinations+=1
                for phase,blade_mask in enumerate(phases):
                    blade_join=ImageChops.multiply(ratchet_mask,shifted(blade_mask,height))
                    blade_pixels=sum(blade_join.histogram()[1:])
                    assert blade_pixels>0,f"Floating blade: {blade}/{ratchet}/{bit} phase{phase}"
                    min_blade_join=min(min_blade_join,blade_pixels)
                    poses+=1
    return {"legal_assemblies":combinations,"spin_poses":poses,"all_cells_48px":True,"blade_collar_overlap_all_poses":True,"bit_socket_overlap_all_builds":True,"minimum_blade_collar_overlap_pixels":min_blade_join,"minimum_bit_socket_overlap_pixels":min_bit_join}


def native_validate(output):
    """Open and export every master with the actual Aseprite executable."""
    exe=os.environ.get("TOPGAME_ASEPRITE") or shutil.which("aseprite")
    fallback=Path("F:/SteamLibrary/steamapps/common/Aseprite/Aseprite.exe")
    if not exe and fallback.exists():exe=str(fallback)
    if not exe:raise RuntimeError("Aseprite not found; set TOPGAME_ASEPRITE")
    output.mkdir(parents=True,exist_ok=True)
    version=subprocess.run([exe,"--version"],capture_output=True,text=True,check=True).stdout.strip()
    entries=[]
    for category,ids in GROUPS.items():
        for name in ids:
            png=output/f"{name}_native.png"
            data=output/f"{name}_native.json"
            proc=subprocess.run([exe,"--batch",str(SOURCE/f"{name}.aseprite"),"--list-layers","--list-tags","--list-slices","--sheet",str(png),"--sheet-type","horizontal","--data",str(data),"--format","json-array"],capture_output=True,text=True,check=True)
            meta=json.loads(data.read_text(encoding="utf-8"))
            frames,source_meta=read_ase(SOURCE/f"{name}.aseprite")
            native=Image.open(png).convert("RGBA")
            expected=Image.new("RGBA",(48*len(frames),48))
            for i,im in enumerate(frames):expected.alpha_composite(im,(i*48,0))
            assert native.tobytes()==expected.tobytes(),f"{name} native Aseprite export differs"
            assert [l["name"] for l in meta["meta"]["layers"]]==source_meta["layers"],name
            tags=meta["meta"]["frameTags"]
            assert len(tags)==1 and tags[0]["from"]==0 and tags[0]["to"]==len(frames)-1,name
            slices=meta["meta"]["slices"]
            assert slices[0]["name"]=="contact_pivot" and slices[0]["keys"][0]["pivot"]=={"x":24,"y":40},name
            entries.append({"id":name,"native_open":True,"native_export_parity":True,"editable_layers":len(source_meta["layers"]),"tags":True,"contact_pivot":True})
    return {"aseprite_version":version,"masters_opened":len(entries),"native_export_parity":True,"parts":entries}


def font(size=16,bold=False):
    path=Path("C:/Windows/Fonts/consolab.ttf" if bold else "C:/Windows/Fonts/consola.ttf")
    return ImageFont.truetype(str(path),size) if path.exists() else ImageFont.load_default()


def review(metadata,output):
    """metadata may be a category->id dictionary or a PartCatalog matrix export."""
    if "parts" in metadata:metadata=metadata["parts"]
    if "categories" in metadata:metadata=metadata["categories"]
    if isinstance(metadata,list):
        grouped={category:{} for category in GROUPS}
        for item in metadata:grouped[item["category"]][item["id"]]=item
        metadata=grouped
    output.mkdir(parents=True,exist_ok=True)
    groups=[("blade","BLADES"),("ratchet","RATCHETS"),("bit","BITS")]
    rows=max(math.ceil(len(metadata[k])/4) for k,_ in groups)
    width=1280;section_h=56+rows*130
    sheet=Image.new("RGB",(width,108+section_h*3),(17,23,30))
    d=ImageDraw.Draw(sheet)
    d.text((24,18),"SPINNING METAL  |  PERMANENT PARTS",font=font(28,True),fill=(227,232,220))
    d.text((24,56),"002C.5.2 human review  /  native cells enlarged 2x with nearest neighbour",font=font(16),fill=(171,192,199))
    d.text((24,79),"Shape and construction identify components. Rarity describes specialisation, not raw power.",font=font(15),fill=(118,142,153))
    for group_index,(category,label) in enumerate(groups):
        base=108+group_index*section_h
        d.line((24,base,width-24,base),fill=(76,98,110),width=2)
        d.text((24,base+12),f"{label}  /  {len(metadata[category])} total",font=font(22,True),fill=(227,232,220))
        for i,(name,info) in enumerate(metadata[category].items()):
            x=24+(i%4)*310;y=base+48+(i//4)*130
            d.rectangle((x,y,x+298,y+119),fill=(26,35,44),outline=(52,68,81))
            sprite=Image.open(OUT/FOLDERS[category]/f"{name}.png").convert("RGBA")
            # Keep complete source cells and common pivot; never auto-fit parts.
            sheet.paste(sprite.resize((96,96),Image.Resampling.NEAREST),(x+4,y+8),sprite.resize((96,96),Image.Resampling.NEAREST))
            title=info.get("name",info.get("display_name",name.upper()))
            rarity=str(info.get("rarity","COMMON")).upper()
            d.text((x+105,y+17),str(title).upper(),font=font(18,True),fill=(227,232,220))
            d.text((x+105,y+46),category.upper(),font=font(15),fill=(171,192,199))
            d.text((x+105,y+70),rarity,font=font(15,True),fill=(118,142,153))
    sheet.save(output/"002c5_2_parts_catalogue.png")
    blades=metadata["blade"]
    h=126+math.ceil(len(blades)/4)*220
    silhouettes=Image.new("RGB",(1280,h),(17,23,30));d=ImageDraw.Draw(silhouettes)
    d.text((24,18),"BLADE CONSTRUCTION / SILHOUETTE REVIEW",font=font(27,True),fill=(227,232,220))
    d.text((24,56),"Native 48px cell beside material / grayscale / solid outline at 2x nearest",font=font(16),fill=(171,192,199))
    d.text((24,81),"Physical rotation stays in the top plane. Outer edges must remain distinct during combat.",font=font(15),fill=(118,142,153))
    for i,(name,info) in enumerate(blades.items()):
        x=24+i%4*310;y=116+i//4*220
        d.rectangle((x,y,x+298,y+208),fill=(26,35,44),outline=(52,68,81))
        d.text((x+10,y+10),str(info.get("name",name)).upper(),font=font(19,True),fill=(227,232,220))
        sprite=Image.open(OUT/"blades"/f"{name}.png").convert("RGBA")
        gray=ImageOps.grayscale(sprite).convert("RGBA");gray.putalpha(sprite.getchannel("A"))
        solid=Image.new("RGBA",sprite.size,(227,232,220));solid.putalpha(sprite.getchannel("A"))
        for k,im in enumerate([sprite,gray,solid]):
            bigger=im.resize((96,96),Image.Resampling.NEAREST)
            silhouettes.paste(bigger,(x+2+k*98,y+43),bigger)
        # Native row is deliberately unscaled: the pixel silhouette can be judged.
        silhouettes.paste(sprite,(x+8,y+154),sprite)
        spin=Image.open(OUT/"blades"/f"{name}_spin.png").convert("RGBA")
        for k in range(1,5):
            im=spin.crop((k*48,0,(k+1)*48,48))
            silhouettes.paste(im,(x+8+k*54,y+154),im)
    silhouettes.save(output/"002c5_2_blade_silhouettes.png")
    native=Image.new("RGBA",(640,360),(20,25,32,255));d=ImageDraw.Draw(native)
    d.text((12,8),"002C.5.2 / NATIVE 640x360 / UNCHANGED 48px CELLS / NEAREST",font=font(9),fill=c("light"))
    rats=["ballast","kickback","scrap"];bits=["tripod","skate","eccentric"]
    for i,name in enumerate(GROUPS["blade"]):
        x=18+i*86
        d.text((x,31),name.upper(),font=font(9),fill=c("silver"))
        for row in range(3):
            y=55+row*94
            for category,part in [("bit",bits[row]),("ratchet",rats[row])]:
                native.alpha_composite(Image.open(OUT/FOLDERS[category]/f"{part}.png").convert("RGBA"),(x,y))
            phase=Image.open(OUT/"blades"/f"{name}_spin.png").convert("RGBA").crop((row*48,0,(row+1)*48,48))
            height=int(metadata["ratchet"][rats[row]]["physics"].get("visual_height",0))
            native.alpha_composite(phase,(x,y+height))
            d.text((x,y+49),rats[row].upper(),font=font(9),fill=c("steel light"))
            d.text((x,y+62),bits[row].upper(),font=font(9),fill=c("steel light"))
    native.save(output/"002c5_2_native_assemblies.png")


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--author",action="store_true",help="Deliberately overwrite only the twenty initial 002C.5.2 masters")
    p.add_argument("--validate",action="store_true",help="Validate without changing masters or exports")
    p.add_argument("--report",type=Path)
    p.add_argument("--review-metadata",type=Path)
    p.add_argument("--review-out",type=Path)
    p.add_argument("--native-out",type=Path,help="Verify native Aseprite export parity; write intermediates to external QA")
    args=p.parse_args()
    if args.author:author()
    if not args.validate:export()
    report=validate()
    if args.native_out:report["native_aseprite"]=native_validate(args.native_out)
    if args.report:
        args.report.parent.mkdir(parents=True,exist_ok=True)
        args.report.write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
    if args.review_metadata:
        assert args.review_out,"--review-out required for external QA sheets"
        review(json.loads(args.review_metadata.read_text(encoding="utf-8-sig")),args.review_out)
    print(json.dumps({k:report[k] for k in ["masters","runtime_sprites","blade_spin_frames","native_48px","source_runtime_parity","problems"]}))


if __name__=="__main__":main()
