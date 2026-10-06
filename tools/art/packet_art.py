"""Original 003A hobby-packet pixel masters and saved-source runtime exporter.

Normal use exports saved Aseprite edits; --author deliberately reconstructs the
original pixel recipe. --check compares runtime pixels/metadata with both the
saved source and a real native Aseprite CLI export, including editable layers,
tags, contact pivots and per-frame timing. QA stays in the external workspace.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from build_power_art import read_ase, write_ase
sys.path.insert(0, str(ROOT / "tools/art"))
from build_front_end import PATTERNS, draw_pattern
sys.path.insert(0, str(ROOT / "tools/workspace"))
from workspace import create_task_workspace, find_tool

SOURCE = ROOT / "assets/source-art/shop_003a"
OUT = ROOT / "assets/ui/shop_003a"
PALETTE = {
    "outline": "#10151f", "bench": "#192832", "rubber": "#202b36",
    "seam": "#2c3d47", "steel": "#4c626e", "silver": "#abc0c7",
    "pouch": "#cfbea0", "pouch shade": "#a8987d", "pouch light": "#e3d2b1",
    "paper": "#e3e8dc", "paper shade": "#b8bfaf", "ink": "#3b413b",
    "oxide": "#a94c35", "amber": "#df8740", "brass": "#f3c36a",
    "reclaimed": "#91a48b", "reclaimed shade": "#6c806a", "reclaimed light": "#b2c1a7",
}
TAGS = [("SEALED", 0, 0), ("CRINKLE", 1, 3), ("TEAR_START", 4, 5),
        ("TEAR_OPEN", 6, 8), ("SPILL", 9, 11), ("EMPTY_PACKET", 12, 12)]
DURATIONS = [500, 100, 90, 100, 120, 120, 110, 110, 180, 130, 130, 180, 1000]
LAYERS = ["placed contact shadow", "opaque pouch body", "sealed and torn edges",
          "authored paper crinkles", "physical printed label", "detached tear strip"]

# Each silhouette is drawn as a separate native pose. In particular the top seam
# actually separates; late frames are a slack, empty paper pouch, not a warped PNG.
POSES = [
    [(23,8),(71,8),(73,13),(75,72),(72,84),(24,86),(21,76),(22,16)],
    [(24,9),(70,8),(73,16),(72,37),(76,59),(72,83),(25,85),(23,74),(21,43),(24,24)],
    [(24,10),(68,9),(72,16),(70,36),(75,54),(70,84),(25,85),(22,69),(25,47),(22,27)],
    [(23,9),(71,8),(73,14),(73,37),(75,62),(73,84),(24,86),(22,75),(23,40)],
    [(23,10),(70,9),(74,17),(73,36),(75,71),(72,84),(24,86),(21,76),(23,22)],
    [(23,11),(69,11),(73,18),(74,44),(75,71),(72,84),(24,86),(21,76),(23,26)],
    [(22,22),(27,20),(31,22),(35,19),(40,22),(45,20),(51,22),(56,20),(61,23),(68,21),
     (73,25),(75,71),(72,84),(24,86),(21,76)],
    [(21,25),(26,21),(32,23),(36,20),(41,24),(47,21),(54,24),(59,22),(65,25),(72,23),
     (75,70),(72,84),(24,86),(21,76)],
    [(20,28),(26,23),(31,25),(36,22),(42,26),(49,22),(55,26),(62,24),(68,28),(73,25),
     (76,69),(72,84),(24,86),(20,77)],
    [(18,34),(25,27),(31,28),(38,25),(44,29),(50,26),(57,29),(64,27),(71,32),(76,30),
     (80,69),(76,82),(28,86),(20,80)],
    [(17,42),(24,34),(30,35),(37,32),(44,36),(51,33),(59,37),(65,35),(72,41),(79,39),
     (84,68),(78,80),(30,86),(21,81)],
    [(18,50),(25,41),(31,43),(38,39),(45,44),(52,40),(60,45),(68,42),(75,48),(81,46),
     (84,69),(77,81),(31,85),(22,80)],
    [(16,62),(21,56),(28,58),(35,54),(41,59),(49,56),(56,62),(64,59),(72,64),(80,61),
     (83,76),(74,84),(30,86),(20,82)],
]
FOLDS = [
    [[(25,22),(30,34),(27,47)],[(70,24),(64,35),(70,50)],[(28,71),(36,65),(35,77)],[(63,64),(69,73),(64,79)]],
    [[(24,22),(34,37),(26,50)],[(70,25),(62,36),(74,55)],[(29,70),(38,62),(34,79)],[(63,62),(70,73),(62,81)]],
    [[(26,21),(36,36),(28,53)],[(68,25),(60,36),(72,55)],[(28,70),(38,62),(32,79)],[(61,61),(69,74),(62,81)]],
    [[(25,23),(31,36),(28,51)],[(70,25),(63,36),(72,52)],[(28,72),(36,66),(34,79)],[(64,63),(69,74),(63,81)]],
    [[(24,24),(32,37),(27,52)],[(69,27),(62,36),(72,54)],[(28,73),(37,66),(34,80)],[(65,63),(71,75),(64,81)]],
    [[(24,27),(32,39),(27,53)],[(69,29),(63,39),(72,55)],[(29,73),(38,65),(35,80)],[(66,65),(71,74),(64,82)]],
    [[(24,28),(31,39),(27,53)],[(69,30),(63,40),(72,54)],[(29,72),(37,64),(35,80)],[(65,64),(70,76),(64,81)]],
    [[(24,29),(31,40),(26,53)],[(69,31),(63,41),(72,56)],[(29,72),(37,65),(35,80)],[(66,64),(70,76),(64,81)]],
    [[(23,33),(31,42),(26,55)],[(70,33),(63,43),(73,57)],[(28,74),(37,66),(34,81)],[(66,66),(71,76),(64,82)]],
    [[(23,37),(31,46),(26,57)],[(73,38),(66,47),(76,58)],[(30,73),(39,66),(35,81)],[(69,65),(75,75),(68,81)]],
    [[(22,44),(31,51),(27,62)],[(76,44),(69,52),(79,62)],[(31,75),(41,68),(37,81)],[(71,67),(78,74),(72,80)]],
    [[(22,53),(31,57),(28,66)],[(78,52),(70,59),(81,67)],[(32,75),(42,69),(38,81)],[(71,71),(78,76),(71,81)]],
    [[(21,65),(31,66),(26,73)],[(77,65),(67,68),(79,76)],[(28,80),(39,74),(43,82)],[(58,78),(64,82),(70,80)]],
]


def color(name):
    return tuple(bytes.fromhex(PALETTE[name].lstrip("#"))) + (255,)


def blank(size=(96, 96)):
    return Image.new("RGBA", size)


def text(image, value, x, y, ink="ink"):
    for i, character in enumerate(value):
        draw_pattern(image, PATTERNS[character], x + i * 6, y, color(ink))


def packet_factory(reclaimed=False):
    frames = []
    base, shade, light = ("reclaimed", "reclaimed shade", "reclaimed light") if reclaimed else ("pouch", "pouch shade", "pouch light")
    for frame, shape in enumerate(POSES):
        shadow, body, edges, folds, label, strip = [blank() for _ in LAYERS]
        d = ImageDraw.Draw(shadow)
        d.polygon([(20,84),(25,81),(74,80),(82,84),(77,89),(24,90)], fill=color("outline"))
        d = ImageDraw.Draw(body)
        d.polygon(shape, fill=color(base), outline=color("outline"))
        # Matte laminate folded side: one narrow, slightly irregular highlight.
        left = shape[0]
        d.line([left, (left[0]+3,left[1]+13), (23 if frame<9 else 25,76), (26,83)], fill=color(light))
        d.line([(73 if frame<9 else 80,44 if frame<9 else 58),(72 if frame<9 else 79,77),(69,82)], fill=color(shade), width=2)
        d = ImageDraw.Draw(edges)
        # Bottom heat crimp follows the pouch, never reads as a rigid case.
        d.line([(25 if frame<9 else 29,82),(42,83),(58,82),(71 if frame<9 else 77,79)], fill=color(shade), width=2)
        d.line([(26 if frame<9 else 30,84),(48,85),(69 if frame<9 else 75,82)], fill=color(light))
        for x in range(29 if frame<9 else 33, 68 if frame<9 else 73, 4):
            d.line((x,83,x+1,84), fill=color(base))
        if frame <= 5:
            top_y = [10,11,12,11,12,14][frame]
            d.line([(25,top_y),(47,top_y-1),(70,top_y-1)], fill=color(shade), width=2)
            d.line([(25,top_y+3),(47,top_y+2),(70,top_y+2)], fill=color(light))
            for x in range(27,69,4):
                d.line((x,top_y,x,top_y+2), fill=color(base))
            # A genuine easy-tear notch in the left sealed margin.
            d.polygon([(22,18),(25,19),(22,21)], fill=color("outline"))
            if frame == 4:
                d.line([(24,19),(30,18),(33,20),(37,18)], fill=color("outline"))
            elif frame == 5:
                d.line([(24,21),(30,20),(34,22),(38,20),(43,22),(48,21),(53,23)], fill=color("outline"))
                d.line((27,24,47,24), fill=color(light))
        else:
            # Black interior with a distinct light torn front edge. Empty states
            # visibly flatten rather than imply a transparent window/content.
            top = shape[:10]
            d.polygon(top + [(top[-1][0]-2,top[-1][1]+7),(top[0][0]+3,top[0][1]+7)], fill=color("outline"))
            d.line([(x,y+5) for x,y in top], fill=color(shade), width=2)
            d.line([(x,y+7) for x,y in top], fill=color(light))
        d = ImageDraw.Draw(folds)
        for crease in FOLDS[frame]:
            d.line(crease, fill=color(shade))
            d.line([(x+1,y) for x,y in crease[:-1]], fill=color(light))
        if frame in (1,2,4,5):
            d.line([(27,61),(31,59),(34,62)], fill=color(shade))
        # Real printed paper label, with human-readable native pixel lettering.
        # Late empty pose folds its label rather than adding reward graphics.
        d = ImageDraw.Draw(label)
        label_y = 34 if frame<9 else (41 if frame<11 else (49 if frame==11 else 65))
        label_x = 29 if frame<9 else (31 if frame<12 else 32)
        label_h = 28 if frame<12 else 13
        d.polygon([(label_x,label_y),(label_x+38,label_y-1),(label_x+38,label_y+label_h-2),(label_x+1,label_y+label_h)], fill=color("paper shade"))
        d.polygon([(label_x+1,label_y),(label_x+37,label_y),(label_x+36,label_y+label_h-3),(label_x+1,label_y+label_h-1)], fill=color("paper"))
        text(label, "PARTS", label_x+4,label_y+3)
        if frame<12:
            text(label, "PACKET",label_x+1,label_y+12)
            d.line((label_x+4,label_y+23,label_x+32,label_y+23),fill=color("reclaimed shade" if reclaimed else "oxide"))
            for x,y in [(label_x+6,label_y+24),(label_x+18,label_y+24),(label_x+29,label_y+24)]:
                d.point((x,y),fill=color("ink"))
        else:
            d.line((label_x+3,label_y+11,label_x+33,label_y+10),fill=color("reclaimed shade" if reclaimed else "oxide"))
        if reclaimed:
            d.line((label_x+1,label_y,label_x+1,label_y+label_h-1),fill=color("reclaimed shade"))
        # Detached sealed strip has independently authored kinked positions.
        d = ImageDraw.Draw(strip)
        strip_shapes = {
            5:[(24,12),(38,11),(37,19),(24,20)],
            6:[(22,7),(47,6),(64,9),(66,15),(46,12),(24,15)],
            7:[(11,13),(29,8),(46,11),(53,17),(34,15),(15,20)],
            8:[(7,28),(17,18),(31,17),(40,23),(23,25),(13,33)],
            9:[(6,45),(13,36),(25,34),(34,40),(19,41),(10,51)],
            10:[(4,66),(12,60),(24,61),(32,67),(18,65),(8,71)],
            11:[(5,84),(12,78),(26,80),(34,85),(19,84),(8,88)],
            12:[(4,85),(11,79),(26,81),(33,86),(18,85),(7,89)],
        }
        if frame in strip_shapes:
            points=strip_shapes[frame]
            d.polygon(points,fill=color(base),outline=color("outline"))
            d.line([(x+1,y+2) for x,y in points[:3]],fill=color(light))
            d.line([(x,y+4) for x,y in points[:3]],fill=color(shade))
        frames.append([shadow,body,edges,folds,label,strip])
    return frames, LAYERS, TAGS, DURATIONS, (48,86)


def mat_factory():
    surface, lip, wear = [blank((272,134)) for _ in range(3)]
    d=ImageDraw.Draw(surface)
    d.polygon([(8,5),(262,5),(267,10),(267,121),(262,128),(8,128),(4,123),(4,10)],fill=color("outline"))
    d.rectangle((8,8,262,123),fill=color("rubber"))
    d.line([(8,123),(8,8),(261,8)],fill=color("seam"))
    d=ImageDraw.Draw(lip)
    d.line((8,124,260,124),fill=color("steel"))
    d.line((12,126,257,126),fill=color("seam"))
    d=ImageDraw.Draw(wear)
    for line in [(16,19,29,19),(16,19,16,29),(239,20,252,20),(252,20,252,29),
                 (16,113,28,113),(16,104,16,113),(241,114,253,114),(253,105,253,114)]:
        d.line(line,fill=color("oxide"))
    for line in [(26,94,39,94),(27,96,32,96),(232,90,243,89)]:
        d.line(line,fill=color("seam"))
    return [[surface,lip,wear]], ["quiet rubber spill surface","front rolled bench lip","placed corner wear"], [("REVEAL_MAT",0,0)], [1000], (136,124)


SPECS = {"packet": {"factory": packet_factory,"cell":[96,96]},
         "reclaimed_packet": {"factory": lambda: packet_factory(True),"cell":[96,96]},
         "reveal_mat": {"factory":mat_factory,"cell":[272,134]}}


def render_source(name):
    frames,meta=read_ase(SOURCE / f"{name}.aseprite")
    w,h=meta["cell"]
    atlas=blank((w*len(frames),h))
    for i,frame in enumerate(frames):
        atlas.alpha_composite(frame,(i*w,0))
    meta.update({"version":1,"texture":f"{name}.png","columns":len(frames),"frame_count":len(frames),
                 "source":f"../../source-art/shop_003a/{name}.aseprite","native_pixels":True,"filter":"nearest","task":"003A"})
    if name != "reveal_mat":
        meta.update({"sealed_mouth":[48,19],"open_mouth":[48,29],"spill_mouth":[52,45],
                     "material":"opaque matte laminate hobby pouch","reclaimed":name=="reclaimed_packet"})
    return frames,atlas,meta


def author():
    SOURCE.mkdir(parents=True,exist_ok=True)
    for name,spec in SPECS.items():
        write_ase(SOURCE / f"{name}.aseprite",*spec["factory"](),
                  note="Task 003A / original authored native pixel poses / opaque inexpensive hobby pouch / editable named layers / no resampling",palette=PALETTE)


def export():
    OUT.mkdir(parents=True,exist_ok=True)
    for name in SPECS:
        _,atlas,meta=render_source(name)
        atlas.save(OUT / f"{name}.png",optimize=True)
        (OUT / f"{name}.json").write_text(json.dumps(meta,indent=2)+"\n",encoding="utf-8")


def check(aseprite=None):
    exe=find_tool("aseprite",aseprite)
    qa=create_task_workspace("003A")
    report={"task":"003A","read_only":True,"aseprite_version":subprocess.check_output([exe,"--version"],text=True).strip(),"masters":[]}
    with tempfile.TemporaryDirectory(prefix="packet-native-",dir=qa / "temp") as folder:
        destination=Path(folder)
        for name,spec in SPECS.items():
            source=SOURCE / f"{name}.aseprite"
            frames,expected,meta=render_source(name)
            assert meta["cell"]==spec["cell"],f"{name}: native cell changed"
            assert Image.open(OUT / f"{name}.png").convert("RGBA").tobytes()==expected.tobytes(),f"{name}: source/runtime pixels"
            assert json.loads((OUT / f"{name}.json").read_text())==meta,f"{name}: source/runtime metadata"
            native_png,native_json=destination / f"{name}.png",destination / f"{name}.json"
            subprocess.run([exe,"--batch",str(source),"--list-layers","--list-tags","--list-slices",
                            "--sheet-type","horizontal","--sheet",str(native_png),"--data",str(native_json),"--format","json-array"],check=True,capture_output=True,text=True)
            assert Image.open(native_png).convert("RGBA").tobytes()==expected.tobytes(),f"{name}: native CLI pixels"
            info=json.loads(native_json.read_text())
            assert [item["name"] for item in info["meta"]["layers"]]==meta["layers"],f"{name}: native editable layers"
            assert {t["name"]:{"from":t["from"],"to":t["to"]} for t in info["meta"]["frameTags"]}==meta["tags"],f"{name}: native tags"
            assert [f["duration"] for f in info["frames"]]==meta["durations_ms"],f"{name}: native durations"
            pivot=info["meta"]["slices"][0]["keys"][0]["pivot"]
            assert [pivot["x"],pivot["y"]]==meta["pivot"],f"{name}: native pivot"
            if name != "reveal_mat":
                assert len({hashlib.sha256(f.tobytes()).hexdigest() for f in frames})==13,f"{name}: repeated pose"
                assert set(meta["tags"])=={tag[0] for tag in TAGS}
            report["masters"].append({"source":source.relative_to(ROOT).as_posix(),"runtime":f"assets/ui/shop_003a/{name}.png",
                                      "frames":len(frames),"cell":meta["cell"],"layers":meta["layers"],"tags":meta["tags"],"pivot":meta["pivot"],
                                      "timing_ms":meta["durations_ms"],"native_cli_parity":True,"source_runtime_parity":True,
                                      "source_sha256":hashlib.sha256(source.read_bytes()).hexdigest(),
                                      "runtime_sha256":hashlib.sha256((OUT / f"{name}.png").read_bytes()).hexdigest()})
    return report


def preview(path):
    sheet=Image.new("RGBA",(1152,672),color("outline"))
    for row,name in enumerate(["packet","reclaimed_packet"]):
        frames,_,_=render_source(name)
        for column,index in enumerate([0,2,5,8,10,12]):
            x,y=column*192,row*336
            text(sheet,["SEALED","CRINKLE","TEAR","OPEN","SPILL","EMPTY"][column],x+9,y+3,"paper")
            sheet.alpha_composite(frames[index].resize((192,192),Image.Resampling.NEAREST),(x,y+18))
            sheet.alpha_composite(frames[index],(x+48,y+224))
            text(sheet,"2X",x+8,y+18,"silver")
            text(sheet,"1X",x+8,y+227,"silver")
    path.parent.mkdir(parents=True,exist_ok=True)
    sheet.convert("RGB").save(path)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--author",action="store_true")
    parser.add_argument("--check",action="store_true")
    parser.add_argument("--aseprite")
    parser.add_argument("--report",type=Path)
    parser.add_argument("--preview",type=Path)
    args=parser.parse_args()
    for path in [args.report,args.preview]:
        if path and (path.resolve()==ROOT or ROOT in path.resolve().parents):
            raise ValueError("QA output must be outside game repository")
    if args.check and args.author:
        parser.error("--check is read-only; --author is explicit reconstruction")
    if args.author:
        author()
    if args.check:
        report=check(args.aseprite)
        if args.report:
            args.report.parent.mkdir(parents=True,exist_ok=True)
            args.report.write_text(json.dumps(report,indent=2)+"\n")
        print(json.dumps(report,indent=2))
    else:
        export()
    if args.preview:
        preview(args.preview)


if __name__=="__main__":
    main()
