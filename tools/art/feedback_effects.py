"""Editable floor/contact accents for the 002C.5.2 human feedback checkpoint.

Normal use exports artist-edited Aseprite masters. --author is the explicit
original key-pose recipe, never run implicitly by an exporter or the game.
Six deliberate integer-pixel poses per effect tag and one floor token pose.
Native Aseprite exports, layer/tag/pivot metadata and runtime parity are checked.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from build_power_art import read_ase, write_ase, color
from workspace.workspace import create_task_workspace, find_tool

SOURCE = ROOT / "assets/source-art/feedback_002c5_2"
OUT = ROOT / "assets/powers/feedback_002c5_2"
CELL = (96, 80)
PIVOT = (48, 48)
LAYERS = ["01 bit load and floor contact", "02 jointed steel grounding arms",
          "03 travelling pressure fronts", "04 contact flash and displaced grit"]
PALETTE = {"ink": "#10151f", "dark": "#202b36", "steel": "#4c626e",
           "silver": "#abc0c7", "grey": "#76818a", "light": "#e3e8dc",
           "white": "#fff8e7", "oxide": "#a94c35", "orange": "#df8740",
           "amber": "#f3c36a"}
TAG_DETAILS = {
    "centre_seek": {"loop": True, "causality": "anchor_charge > 0.07; floor at real bit; strength follows implemented bounded inward gravity",
                    "description": "Two staggered white/grey floor sweeps settle inward toward the physically anchored top."},
    "centre_brace": {"loop": False, "hold_last": True,
                     "causality": "actual anchor_charge 0.35..0.70 selects deployment key",
                     "description": "Four short jointed supports emerge from the bit collar and grip floor."},
    "centre_brace_full": {"loop": False, "hold_last": True,
                          "causality": "rank II or Bulwark and actual mature hold; deployment key 0..5",
                          "description": "Longer anchored outriggers with wider floor pads; open centre preserves rotor."},
    "centre_recoil": {"loop": False, "hold_last": False,
                      "causality": "real anchor_hit_time; accepted collision only",
                      "description": "A short grey force front breaks outward from planted contact; no invented damage."},
    "impact_light": {"loop": False, "hold_last": False,
                     "causality": "accepted collision contact location and elapsed event age",
                     "description": "Small contact knuckle and a short uneven pressure ripple."},
    "impact_heavy": {"loop": False, "hold_last": False,
                     "causality": "accepted collision strength; contact location and event age",
                     "description": "Hard white contact, paired broken floor waves and physical kicked fragments."},
    "impact_extreme": {"loop": False, "hold_last": False,
                       "causality": "accepted high impulse during ramp-up; never timer-only spawning",
                       "description": "Broad orange/white impact front and divergent grit; central top remains exposed."},
    "reroll_chip": {"loop": False, "hold_last": True,
                    "causality": "actual collectible floor token; driving within pickup radius consumes it",
                    "description": "Low steel disc with two opposed stamped recycle arrows; no floating UI marker."},
}
TIMINGS = {
    "centre_seek": [110, 90, 90, 110, 130, 160],
    "centre_brace": [90, 100, 110, 100, 100, 180],
    "centre_brace_full": [90, 100, 110, 100, 100, 180],
    "centre_recoil": [30, 35, 45, 55, 65, 90],
    "impact_light": [30, 35, 45, 55, 65, 90],
    "impact_heavy": [30, 40, 55, 70, 90, 125],
    "impact_extreme": [35, 45, 65, 90, 120, 155],
    "reroll_chip": [160],
}
GROUPS = {"centre": ["centre_seek", "centre_brace", "centre_brace_full", "centre_recoil"],
          "impact": ["impact_light", "impact_heavy", "impact_extreme"],
          "pickup": ["reroll_chip"]}
PICKUP_LAYERS = ["01 floor shadow and steel rim", "02 flat stamped token face",
                 "03 opposed recycle arrows"]


def ink(name, alpha=255):
    return color(PALETTE[name], alpha)


def blank():
    return [Image.new("RGBA", CELL) for _ in LAYERS]


def p(x, y):
    """Author in the floor plane; squash only geometry, never raster pixels."""
    return round(48 + x), round(48 + y * .5)


def stroke(im, points, name, width=1, alpha=255):
    ImageDraw.Draw(im).line([p(x, y) for x, y in points], fill=ink(name, alpha), width=width)


def arc(im, radius, start, stop, name, width=1, alpha=255, offset=(0, 0)):
    # Fifteen-degree authored steps create deliberate, legible pixel clusters.
    angles = [math.radians(start + (stop-start)*i/8) for i in range(9)]
    stroke(im, [(offset[0]+math.cos(a)*radius, offset[1]+math.sin(a)*radius)
                for a in angles], name, width, alpha)


def floor_bite(im, x, y, mature=False):
    d = ImageDraw.Draw(im)
    xx, yy = p(x, y)
    # Small contact pad is a steel floor foot, with physical two-pixel depth.
    width = 5 if mature else 4
    d.polygon([(xx-width,yy), (xx-1,yy-2), (xx+width,yy-1),
               (xx+width,yy+2), (xx+1,yy+3), (xx-width,yy+2)], fill=ink("ink"))
    d.line([(xx-width+1,yy), (xx-1,yy-1), (xx+width-1,yy)], fill=ink("silver"))
    d.line([(xx-width+1,yy+1), (xx+width-1,yy+1)], fill=ink("steel"), width=2)
    if mature:
        d.point((xx-2,yy+1), fill=ink("light"))
        d.point((xx+2,yy+1), fill=ink("light"))


def brace(im, phase, mature=False):
    extension = [0, .20, .45, .70, .95, 1.0][phase]
    reach = (29 if mature else 21) * extension
    if phase == 0:
        # Collapsed hinged collar remains attached to the real bit.
        stroke(im[1], [(-5,-8), (-2,-6), (2,-6), (5,-8)], "ink", 3)
        stroke(im[1], [(-4,-8), (0,-7), (4,-8)], "silver")
        return
    for dx, dy in [(-1,.45), (1,.45), (-.44,-1), (.44,-1)]:
        foot = (dx*reach, dy*reach)
        root = (dx*4, -7 + dy*2)
        elbow = (dx*(reach*.56+3), dy*reach*.33-5)
        stroke(im[1], [root, elbow, foot], "ink", 4)
        stroke(im[1], [root, elbow, foot], "steel", 2)
        stroke(im[1], [(root[0],root[1]-1), (elbow[0],elbow[1]-1),
                       (foot[0],foot[1]-1)], "silver")
        ex, ey = p(*elbow)
        d = ImageDraw.Draw(im[1])
        d.rectangle((ex-1,ey-1,ex+1,ey+1),fill=ink("ink"))
        d.point((ex,ey),fill=ink("light"))
        floor_bite(im[1], *foot, mature)
        if phase >= 3:
            stroke(im[0], [(foot[0]-3,foot[1]+5), foot,
                           (foot[0]+4,foot[1]+2)], "dark", 2)
            stroke(im[0], [(foot[0]-2,foot[1]+4), foot], "grey")
    if phase >= 4:
        arc(im[2], 13 if mature else 10, 10, 110, "grey", alpha=175)
        arc(im[2], 15 if mature else 11, 195, 290, "silver", alpha=190)
        stroke(im[0], [(-4,2), (0,4), (4,2)], "ink", 2)
        stroke(im[0], [(-3,2), (0,3), (3,2)], "light")


def centre(tag, phase):
    ims = blank()
    if tag == "centre_seek":
        radius = [28, 25, 21, 17, 13, 9][phase]
        # Draw only with actual anchor state and implemented bounded inward pull.
        arc(ims[2], radius, 12+phase*11, 123+phase*11, "silver", 2, 180)
        arc(ims[2], radius+2, 182+phase*11, 283+phase*11, "grey", 2, 200)
        arc(ims[2], radius-2, 28+phase*11, 103+phase*11, "light", 1, 220)
        if phase in [3,4,5]:
            stroke(ims[0], [(-4,2), (0,3), (5,1)], "dark", 2)
            stroke(ims[0], [(-3,2), (0,2), (3,1)], "silver", 1, 210)
        if phase < 4:
            for x,y in [(-radius,-4), (radius,4)]:
                stroke(ims[3], [(x,y), (x*.85,y*.85)], "light", 1, 170)
    elif tag in ["centre_brace", "centre_brace_full"]:
        brace(ims, phase, tag == "centre_brace_full")
    elif tag == "centre_recoil":
        radius = [8, 12, 18, 25, 30, 34][phase]
        alpha = [255,255,230,185,120,45][phase]
        arc(ims[2], radius, 3, 104, "light", 2 if phase < 3 else 1, alpha)
        arc(ims[2], radius+2, 163, 286, "silver", 2, alpha)
        arc(ims[0], radius+3, 18, 85, "dark", 2, alpha)
        if phase < 4:
            for angle in [25,155,275]:
                a=math.radians(angle)
                stroke(ims[3], [(math.cos(a)*(radius+1), math.sin(a)*(radius+1)),
                                (math.cos(a)*(radius+5), math.sin(a)*(radius+5))],
                       "grey", 2, alpha)
    return ims


def impact(tag, phase):
    ims = blank()
    strength = {"impact_light":0, "impact_heavy":1, "impact_extreme":2}[tag]
    radii = [[5,9,14,18,22,26], [7,13,21,29,35,39], [9,17,25,34,40,44]][strength]
    radius = radii[phase]
    alpha = [255,255,235,185,125,45][phase]
    # Two broken arcs rather than a universal closed glow ring; floor remains visible.
    arc(ims[2], radius, 8, 128, "amber" if phase < 3 else "orange", 2, alpha)
    arc(ims[2], radius-2, 178, 293, "light", 2 if strength > 0 else 1, alpha)
    arc(ims[0], radius+1, 22, 100, "oxide", 2, alpha)
    if strength > 0 and phase >= 2:
        arc(ims[2], max(3,radius-7), 38, 98, "silver", 1, alpha)
        arc(ims[2], radius-6, 199, 269, "orange", 1, alpha)
    if phase < 3:
        d=ImageDraw.Draw(ims[3])
        size=([3,5,2] if strength==0 else [5,9,3] if strength==1 else [7,12,4])[phase]
        # Contact knuckle sits on the true collision point; no replacement top sprite.
        d.polygon([(48-size,48),(45,46),(48,48-size),(51,46),
                   (48+size,48),(51,50),(48,48+size//2),(45,50)],fill=ink("amber",alpha))
        d.polygon([(48-size//2,48),(47,46),(48,48-size//2),(49,46),
                   (48+size//2,48),(49,49),(48,50),(47,49)],fill=ink("white",alpha))
    directions = [23,151,268] if strength==0 else [17,74,146,213,288,338]
    if phase < 5:
        for index, angle in enumerate(directions):
            a=math.radians(angle)
            reach=radius+3+(index%2)*3
            x,y=math.cos(a)*reach,math.sin(a)*reach
            # Short, divergent fragments depart the contact, never orbital UI widgets.
            length=(3+strength*2) if phase < 3 else 2
            stroke(ims[3], [(x,y), (x+math.cos(a)*length,y+math.sin(a)*length)],
                   "light" if index%2 else "amber", 2 if phase < 3 else 1, alpha)
    return ims


def pickup():
    ims=[Image.new("RGBA",(24,16)) for _ in PICKUP_LAYERS]
    base,face,stamp=[ImageDraw.Draw(i) for i in ims]
    base.ellipse((3,9,21,15),fill=ink("ink",200))
    base.polygon([(3,5),(7,1),(17,1),(21,5),(21,10),(17,14),(7,14),(3,10)],fill=ink("ink"))
    base.line([(4,9),(8,13),(16,13),(20,9)],fill=ink("steel"),width=2)
    face.polygon([(4,5),(8,2),(16,2),(20,5),(20,8),(16,11),(8,11),(4,8)],fill=ink("silver"))
    face.polygon([(5,5),(8,3),(16,3),(19,5),(19,8),(16,10),(8,10),(5,8)],fill=ink("dark"))
    face.line([(8,2),(16,2)],fill=ink("light"))
    # Independent 1px clear arrow stems with large 3px heads at real pickup size.
    stamp.line([(7,7),(7,5),(9,4),(13,4)],fill=(105,194,207,255))
    stamp.polygon([(13,2),(16,4),(13,6)],fill=(105,194,207,255))
    stamp.line([(17,6),(17,8),(15,9),(11,9)],fill=ink("white"))
    stamp.polygon([(11,7),(8,9),(11,11)],fill=ink("white"))
    return ims


def author():
    SOURCE.mkdir(parents=True, exist_ok=True)
    for group,tags in GROUPS.items():
        frames=[]; spans=[]; durations=[]
        for tag in tags:
            start=len(frames)
            if group=="pickup":frames.append(pickup())
            else:frames.extend((centre if group=="centre" else impact)(tag,i) for i in range(6))
            spans.append((tag,start,len(frames)-1))
            durations.extend(TIMINGS[tag])
        layers=PICKUP_LAYERS if group=="pickup" else LAYERS
        pivot=(12,10) if group=="pickup" else PIVOT
        write_ase(SOURCE/f"{group}.aseprite",frames,layers,spans,durations,pivot,
                  note=f"002C.5.2 human feedback / {group} authored physical keys / floor contact pivot {pivot[0]},{pivot[1]} / fixed 2:1 / nearest / no standalone top substitution",
                  palette=PALETTE)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def export_and_validate(aseprite, qa):
    OUT.mkdir(parents=True,exist_ok=True)
    native_out=qa/"temp/feedback-effects-native"
    native_out.mkdir(parents=True,exist_ok=True)
    manifest={"version":1,"task":"002C.5.2","scope":"human playtest runtime floor/contact accents",
              "filter":"nearest","projection":"fixed 2:1 floor plane; no texture rotation",
              "runtime_top_sprite_included":False,"effects":{}}
    checks=[]
    for group,tags in GROUPS.items():
        source=SOURCE/f"{group}.aseprite"
        frames,meta=read_ase(source)
        cell=(24,16) if group=="pickup" else CELL
        pivot=(12,10) if group=="pickup" else PIVOT
        layers=PICKUP_LAYERS if group=="pickup" else LAYERS
        columns=1 if group=="pickup" else 6
        count=1 if group=="pickup" else 6
        assert tuple(meta["cell"])==cell and tuple(meta["pivot"])==pivot
        assert meta["layers"]==layers
        assert list(meta["tags"])==tags
        assert all(span["to"]-span["from"]==count-1 for span in meta["tags"].values())
        png=native_out/f"{group}_native.png"
        data=native_out/f"{group}_native.json"
        subprocess.run([aseprite,"--batch",str(source),"--list-layers","--list-tags","--list-slices",
                        "--sheet",str(png),"--sheet-columns",str(columns),"--data",str(data),"--format","json-array"],
                       capture_output=True,text=True,check=True)
        native=Image.open(png).convert("RGBA")
        expected=Image.new("RGBA",(cell[0]*columns,cell[1]*len(tags)))
        for i,frame in enumerate(frames):expected.alpha_composite(frame,(i%columns*cell[0],i//columns*cell[1]))
        assert native.size==expected.size
        # Native Aseprite is the blending authority. Its normal alpha blend
        # rounds a few overlapping RGB channels one LSB differently to Pillow.
        # Alpha must match exactly and no visible channel may differ by >1.
        rounding_pixels=0
        native_pixels=native.tobytes()
        expected_pixels=expected.tobytes()
        for offset in range(0,len(native_pixels),4):
            a=native_pixels[offset:offset+4]
            b=expected_pixels[offset:offset+4]
            assert a[3]==b[3],f"{group}: native alpha mismatch"
            assert max(abs(a[channel]-b[channel]) for channel in range(3))<=1,f"{group}: source pixel mismatch"
            if a!=b:rounding_pixels+=1
        native_meta=json.loads(data.read_text(encoding="utf-8"))["meta"]
        assert [layer["name"] for layer in native_meta["layers"]]==layers
        assert native_meta["slices"][0]["keys"][0]["pivot"]=={"x":pivot[0],"y":pivot[1]}
        assert [tag["name"] for tag in native_meta["frameTags"]]==tags
        target=OUT/f"{group}.png"
        native.save(target)
        assert Image.open(target).convert("RGBA").tobytes()==native.tobytes(),f"{group}: exact native/runtime parity"
        specs={}
        for tag,span in meta["tags"].items():
            specs[tag]={**span,**TAG_DETAILS[tag],"duration_ms":sum(meta["durations_ms"][span["from"]:span["to"]+1])}
        item={**meta,"texture":"res://"+target.relative_to(ROOT).as_posix(),
              "source":source.relative_to(ROOT).as_posix(),"columns":columns,"frame_count":len(frames),
              "tags":specs,"source_sha256":digest(source),"texture_sha256":digest(target),
              "native_runtime_rgba_exact":True,"python_compositor_rounding_pixels":rounding_pixels}
        manifest["effects"][group]=item
        for tag,span in specs.items():
            assert all(frames[i].getbbox() is not None for i in range(span["from"],span["to"]+1)),tag
            checks.append({"group":group,"tag":tag,"frames":count,"native_export_parity":True,
                           "named_layers":True,"pivot":list(pivot),"duration_ms":span["duration_ms"]})
    (OUT/"manifest.json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
    report={"task":"002C.5.2","masters":3,"runtime_sheets":3,"authored_keys":43,
            "native_aseprite":subprocess.run([aseprite,"--version"],capture_output=True,text=True,check=True).stdout.strip(),
            "source_runtime_parity":True,"editable_named_layers":True,"tags_and_pivots":True,
            "runtime_pixels_equal_native_aseprite_rgba":True,"human_visual_acceptance_pending":True,
            "static_review_is_gameplay_evidence":False,"checks":checks}
    (qa/"manifests/002c5_2_feedback_effect_art.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
    return manifest,report


def review(manifest,qa):
    font_path=Path("C:/Windows/Fonts/consola.ttf")
    font=ImageFont.truetype(str(font_path),12) if font_path.exists() else ImageFont.load_default()
    height=34+sum(len(tags) for tags in GROUPS.values())*90
    image=Image.new("RGBA",(640,height),(20,25,32,255))
    d=ImageDraw.Draw(image)
    d.text((12,5),"Feedback effects: authored native keys (not gameplay)",font=font,fill=ink("silver"))
    row=0
    for group,item in manifest["effects"].items():
        frames,_=read_ase(SOURCE/f"{group}.aseprite")
        for tag,span in item["tags"].items():
            top=26+row*90
            d.text((12,top),f"{tag}  {span['duration_ms']}ms",font=font,fill=ink("silver"))
            for key in range(span["to"]-span["from"]+1):
                x=16+key*102
                d.line([(x+6,top+65),(x+89,top+65)],fill=ink("dark"))
                at=(x+36,top+49) if group=="pickup" else (x,top+8)
                image.alpha_composite(frames[span["from"]+key],at)
            row+=1
    image.save(qa/"images/002c5_2_feedback_effect_keys.png")
    enlarged=image.resize((1280,height*2),Image.Resampling.NEAREST)
    enlarged.save(qa/"images/002c5_2_feedback_effect_keys_2x.png")
    # Static fit reference deliberately labelled as art QA, never battle evidence.
    fit=Image.new("RGBA",(640,360),(38,46,52,255))
    draw=ImageDraw.Draw(fit)
    draw.text((12,8),"640x360 static fit / old floor FX + new accents / not gameplay",font=font,fill=ink("silver"))
    combinations=[("guard","low","needle"),("puck","ballast","tripod")]
    frames,meta=read_ase(SOURCE/"centre.aseprite")
    old_meta=json.loads((ROOT/"assets/powers/identity/dead_centre_manifest.json").read_text(encoding="utf-8"))["fx"]
    old_sheet=Image.open(ROOT/old_meta["texture"].removeprefix("res://")).convert("RGBA")
    for row,combo in enumerate(combinations):
        for col,tag in enumerate(["centre_seek","centre_brace","centre_brace_full"]):
            at=(108+212*col,118+132*row)
            old_tag="ground_lock_ii" if col==2 else "ground_lock"
            old_index=old_meta["tags"][old_tag]["to"]
            ox=old_index%old_meta["columns"]*96
            oy=old_index//old_meta["columns"]*80
            fit.alpha_composite(old_sheet.crop((ox,oy,ox+96,oy+80)),(at[0]-48,at[1]-48))
            key=meta["tags"][tag]["from"]+1 if col==0 else meta["tags"][tag]["to"]
            f=frames[key]
            fit.alpha_composite(f,(at[0]-48,at[1]-48))
            for category,name in [("bits",combo[2]),("ratchets",combo[1])]:
                part=Image.open(ROOT/f"assets/top/parts/{category}/{name}.png").convert("RGBA")
                fit.alpha_composite(part,(at[0]-24,at[1]-40))
            blade=Image.open(ROOT/f"assets/top/parts/blades/{combo[0]}.png").convert("RGBA").crop((0,0,48,48))
            offset=2+(3 if combo[1]=="ballast" else 0)
            fit.alpha_composite(blade,(at[0]-24,at[1]-40+offset))
            draw.text((at[0]-92,at[1]+22),tag,font=font,fill=ink("silver"))
            draw.text((at[0]-92,at[1]+40)," / ".join(combo),font=font,fill=ink("grey"))
    fit.save(qa/"images/002c5_2_feedback_native_fit.png")
    Image.open(OUT/"pickup.png").resize((192,128),Image.Resampling.NEAREST).save(qa/"images/002c5_2_reroll_chip_detail.png")


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--author",action="store_true",help="Explicitly reconstruct this task's three masters")
    parser.add_argument("--aseprite")
    parser.add_argument("--qa-root",type=Path)
    args=parser.parse_args()
    qa=create_task_workspace("002C.5.2",args.qa_root)
    if args.author:author()
    manifest,report=export_and_validate(find_tool("aseprite",args.aseprite),qa)
    review(manifest,qa)
    print(json.dumps(report))


if __name__=="__main__":
    main()
