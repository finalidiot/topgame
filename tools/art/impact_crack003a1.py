"""Authored local jagged steel-energy accent, never full-screen lightning."""
from __future__ import annotations
import argparse, hashlib, json, math, subprocess, sys, uuid
from pathlib import Path
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
from build_power_art import read_ase,write_ase
from workspace.workspace import find_tool,create_task_workspace
SOURCE=ROOT/'assets/source-art/impact_003a1/contact_crack.aseprite'
OUT=ROOT/'assets/powers/impact_003a1'
LAYERS=['01 contact socket','02 keyed jagged steel arc','03 one-way cooling edge']
PATHS={'hard':[(0,0),(4,-3),(8,1),(13,-3)],'extreme':[(0,0),(5,-3),(9,1),(14,-4),(19,0),(22,-2)]}
TIMES={'hard':[16,24,35,45],'extreme':[16,30,42,57]}
def author(repair=False):
    assert repair or not SOURCE.exists(),'Author only the new accent master; preserve saved artist work'
    frames=[];tags=[];durations=[]
    for tier,points in PATHS.items():
        for heading in range(8):
            first=len(frames);a=heading*math.tau/8
            for key in range(4):
                images=[Image.new('RGBA',(64,48)) for _ in LAYERS]
                ink=[(219,229,221,255),(204,210,190,255),(151,149,119,255),(83,86,73,255)][key]
                path=[(round(32+x*math.cos(a)-y*math.sin(a)),round(24+(x*math.sin(a)+y*math.cos(a))*.7)) for x,y in points]
                ImageDraw.Draw(images[1]).line(path,fill=ink,width=1)
                if key<2:ImageDraw.Draw(images[0]).point((32,24),fill=(244,197,122,255))
                if key>=2:ImageDraw.Draw(images[2]).line(path[-2:],fill=ink,width=1)
                frames.append(images);durations.append(TIMES[tier][key])
            tags.append((tier+'_'+str(heading),first,len(frames)-1))
    SOURCE.parent.mkdir(parents=True,exist_ok=True)
    write_ase(SOURCE,frames,LAYERS,tags,durations,(32,24),note='003A.1 / real high-work contact accent / 3 or5 jagged authored segments / local one-way cooling / sub0.2seconds',palette={'steel':'#dbe5dd','warm':'#f4c57a','cool':'#ac8c5d'})
def export(aseprite,check):
    cells,meta=read_ase(SOURCE);assert meta['layers']==LAYERS and len(cells)==64
    folder=create_task_workspace('003A.1')/'temp'/('crack-'+uuid.uuid4().hex);folder.mkdir()
    png=folder/'native.png';data=folder/'native.json'
    subprocess.run([aseprite,'--batch',str(SOURCE),'--list-layers','--list-tags','--list-slices','--sheet',str(png),'--sheet-columns','16','--data',str(data),'--format','json-array'],capture_output=True,text=True,check=True)
    native=Image.open(png).convert('RGBA');expected=Image.new('RGBA',(1024,192))
    for i,cell in enumerate(cells):expected.alpha_composite(cell,(i%16*64,i//16*48))
    assert native.tobytes()==expected.tobytes()
    topology=json.loads(data.read_text());assert [x['duration'] for x in topology['frames']]==meta['durations_ms']
    assert [x['name'] for x in topology['meta']['layers']]==LAYERS
    assert topology['meta']['slices'][0]['keys'][0]['pivot']=={'x':32,'y':24}
    target=OUT/'contact_crack.png';OUT.mkdir(parents=True,exist_ok=True)
    if check:assert Image.open(target).convert('RGBA').tobytes()==native.tobytes()
    else:native.save(target,optimize=True)
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    record={'schema':1,'task':'003A.1',**meta,'columns':16,'frame_count':64,'source':SOURCE.relative_to(ROOT).as_posix(),'texture':'res://'+target.relative_to(ROOT).as_posix(),'source_sha256':sha(SOURCE),'texture_sha256':sha(target),'native_runtime_rgba_exact':True,'segments':{'hard':3,'extreme':5},'maximum_lifetime_seconds':.145,'physical_work_threshold':500000,'filter':'nearest','loop':False,'reduced_flashing':'Local nonoscillating cooling at35%opacity; no flash.'}
    manifest=OUT/'crack_manifest.json'
    if check:assert json.loads(manifest.read_text())==record
    else:manifest.write_text(json.dumps(record,indent=2)+'\n')
    print(json.dumps({'passed':True,'frames':64,'tags':16,'max_seconds':.145,'check':check}))
def main():
    p=argparse.ArgumentParser();p.add_argument('--author',action='store_true');p.add_argument('--check',action='store_true');p.add_argument('--aseprite');args=p.parse_args()
    assert not(args.author and args.check)
    if args.author:author()
    export(find_tool('aseprite',args.aseprite),args.check)
if __name__=='__main__':main()
