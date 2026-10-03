"""Native starter enamel variants, preserving authored part silhouettes.

Normal export reads the edited .aseprite master. --author deliberately derives
the original enamel masks from the preserved rotational blade master and then
authors each identity's rim bands. It never writes original parts or sources.
"""
from pathlib import Path
import argparse
import json
import math
from PIL import Image
from build_power_art import read_ase, write_ase, color

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/"assets/source-art/starter_blade_accents_002b1.aseprite"
OUT=ROOT/"assets/top/starters"
PALETTE={
    "ink":"#10151f", "dark":"#202b36", "charcoal":"#344451",
    "steel":"#4c626e", "steel light":"#768e99", "silver":"#abc0c7", "white":"#e3e8dc",
    "blue shadow":"#16354b", "blue enamel":"#245c7b", "blue rim":"#4595b5",
    "red shadow":"#4b2024", "red enamel":"#a94c35", "red rim":"#ed654c",
    "green shadow":"#193f34", "green enamel":"#388d65", "green rim":"#7dc98d",
}
IDENTITIES=[("breaker","smash","red",65),("bastion","guard","blue",160),("vane","hook","green",100)]


def author():
    originals,meta=read_ase(ROOT/"assets/source-art/blade_rotation_family.aseprite")
    frames=[];tags=[];timings=[]
    layers=["preserved authored steel silhouette", "identity enamel plates", "rotational rim signature bands"]
    for identity,part,hue,duration in IDENTITIES:
        start=len(frames)
        old_start=meta["tags"][part]["from"]
        replacements={color("#16354b"):color(PALETTE[hue+" shadow"]),
                      color("#245c7b"):color(PALETTE[hue+" enamel"]),
                      color("#4595b5"):color(PALETTE[hue+" rim"])}
        for phase in range(8):
            steel=originals[old_start+phase].copy()
            enamel=Image.new("RGBA",(48,48));bands=Image.new("RGBA",(48,48))
            for y in range(48):
                for x in range(48):
                    rgba=steel.getpixel((x,y))
                    if rgba in replacements:
                        enamel.putpixel((x,y),replacements[rgba]);steel.putpixel((x,y),(0,0,0,0))
                        continue
                    # Only replace existing lit metal on the top plate: no
                    # change to blade outline, depth, cutouts or frame pivots.
                    dx=x-24;dy=(y-25)*2
                    radius=math.hypot(dx,dy)
                    angle=(math.atan2(dy,dx)-phase*math.tau/8+math.pi)%math.tau-math.pi
                    signature=False
                    if identity=="breaker":
                        signature=abs(angle)<.72 or abs(angle)>math.pi-.72
                    elif identity=="bastion":
                        signature=radius>14 and abs(angle)<2.6
                    elif identity=="vane":
                        signature=-1.2<angle<.65 or 2.55<angle<3.05
                    if signature and 9<radius<23 and y<29 and rgba in [color("#768e99"),color("#abc0c7"),color("#4c626e")]:
                        shade="enamel" if rgba==color("#4c626e") else "rim"
                        bands.putpixel((x,y),color(PALETTE[hue+" "+shade]));steel.putpixel((x,y),(0,0,0,0))
            frames.append([steel,enamel,bands]);timings.append(duration)
        tags.append((identity,start,len(frames)-1))
    write_ase(SOURCE,frames,layers,tags,timings,(24,40),
              note="Task 002B.1 / original smash guard hook silhouettes retained / enamel plates plus identity-specific rim masks / native nearest pixels",
              palette=PALETTE)


def export():
    frames,meta=read_ase(SOURCE)
    OUT.mkdir(parents=True,exist_ok=True)
    manifest={"version":1,"native_pixels":True,"filter":"nearest","cell":meta["cell"],"pivot":meta["pivot"],
              "source":"../../source-art/starter_blade_accents_002b1.aseprite","layers":meta["layers"],"starters":{}}
    for identity,part,hue,_duration in IDENTITIES:
        span=meta["tags"][identity]
        assert span["to"]-span["from"]+1==8
        sheet=Image.new("RGBA",(384,48))
        for i,index in enumerate(range(span["from"],span["to"]+1)):
            sheet.alpha_composite(frames[index],(i*48,0))
        filename=identity+"_spin.png"
        sheet.save(OUT/filename,optimize=True)
        manifest["starters"][identity]={"texture":filename,"blade":part,"columns":8,"frame_count":8,
                                         "durations_ms":meta["durations_ms"][span["from"]:span["to"]+1]}
    (OUT/"manifest.json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
    print("Exported three native 48px starter enamel blade sheets; original part sources/PNGs preserved.")


if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("--author",action="store_true",help="Overwrite only the starter accent master with its initial authored masks")
    args=parser.parse_args()
    if args.author:author()
    export()
