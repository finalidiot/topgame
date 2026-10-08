"""Native editable directional steel sparks; normal export never reauthors masters."""
from __future__ import annotations
import argparse, hashlib, json, math, subprocess, sys
from pathlib import Path
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
from build_power_art import read_ase,write_ase
from workspace.workspace import find_tool,create_task_workspace
SOURCE=ROOT/'assets/source-art/impact_003a1/contact_sparks.aseprite'
OUT=ROOT/'assets/powers/impact_003a1'
CELL=(64,48);PIVOT=(32,24);COLS=16
LAYERS=['01 forged contact core','02 directional steel ribbons','03 cooling flyaways']
TIERS=('light','strong','hard','extreme')
TIMES={'light':[18,26,45,80],'strong':[20,35,60,100],'hard':[20,40,75,130],'extreme':[25,45,90,155]}
PALETTE={'steel':'#8599a3','hot':'#f4c57a','silver':'#e2e8d8','cool':'#af744d'}
# Keyed directions/lengths form a coherent rake, rather than random particles.
RIBBONS=[(-.42,12),(-.24,20),(-.10,26),(.13,21),(.30,17),(.46,11)]

def author():
    frames=[];tags=[];durations=[]
    for tier_index,tier in enumerate(TIERS):
        for direction in range(8):
            first=len(frames)
            angle=direction*math.tau/8
            for pose in range(4):
                images=[Image.new('RGBA',CELL) for _ in LAYERS]
                core,ribbons,cooling=[ImageDraw.Draw(im) for im in images]
                alpha=[225,205,142,48][pose]
                if pose<2:
                    core.line([(30,24),(34,24)],fill=(226,232,216,alpha),width=1)
                    core.line([(32,22),(32,26)],fill=(244,197,122,alpha),width=1)
                amount=[2,3,5,6][tier_index]
                for i,(spread,length) in enumerate(RIBBONS[:amount]):
                    travel=[.12,.40,.72,.97][pose]
                    radius=length*(.42+tier_index*.16)
                    theta=angle+spread
                    v=(math.cos(theta),math.sin(theta)*.7)
                    start=(round(32+v[0]*radius*travel),round(24+v[1]*radius*travel))
                    end=(round(start[0]+v[0]*(4+tier_index*2)*(1-pose*.13)),round(start[1]+v[1]*(4+tier_index*2)*(1-pose*.13)))
                    color=(244,197,122,alpha) if i%2 else (226,232,216,alpha)
                    ribbons.line([start,end],fill=color,width=1)
                    if pose>0:
                        # A smaller opposing shear spray gives the contact width.
                        back=(round(32-v[0]*radius*travel*.45),round(24-v[1]*radius*travel*.45+pose))
                        cooling.line([back,(back[0]+1,back[1])],fill=(133,153,163,alpha),width=1)
                frames.append(images);durations.append(TIMES[tier][pose])
            tags.append((tier+'_'+str(direction),first,len(frames)-1))
    SOURCE.parent.mkdir(parents=True,exist_ok=True)
    write_ase(SOURCE,frames,LAYERS,tags,durations,PIVOT,note='003A.1 / four physical impact tiers / eight authored rake directions / one-shot cooling ribbons / actual contact attachment / nearest',palette=PALETTE)

def export(aseprite,qa,check):
    cells,meta=read_ase(SOURCE)
    assert meta['cell']==list(CELL) and meta['pivot']==list(PIVOT) and meta['layers']==LAYERS
    assert len(cells)==128 and len(meta['tags'])==32
    folder=qa/'temp'/('impact-sparks-check' if check else 'impact-sparks-export');folder.mkdir(parents=True,exist_ok=True)
    png=folder/'native.png';data=folder/'native.json'
    subprocess.run([aseprite,'--batch',str(SOURCE),'--list-layers','--list-tags','--list-slices','--sheet',str(png),'--sheet-columns',str(COLS),'--data',str(data),'--format','json-array'],capture_output=True,text=True,check=True)
    native=Image.open(png).convert('RGBA');expected=Image.new('RGBA',(CELL[0]*COLS,CELL[1]*8))
    for i,cell in enumerate(cells):expected.alpha_composite(cell,(i%COLS*CELL[0],i//COLS*CELL[1]))
    a,b=native.tobytes(),expected.tobytes()
    assert native.size==expected.size
    assert all(a[i+3]==b[i+3] and max(abs(a[i+j]-b[i+j]) for j in range(3))<=1 for i in range(0,len(a),4))
    topology=json.loads(data.read_text())
    assert [f['duration'] for f in topology['frames']]==meta['durations_ms']
    assert [l['name'] for l in topology['meta']['layers']]==LAYERS
    assert len(topology['meta']['frameTags'])==32
    assert topology['meta']['slices'][0]['keys'][0]['pivot']=={'x':32,'y':24}
    OUT.mkdir(parents=True,exist_ok=True);target=OUT/'contact_sparks.png'
    if check:assert Image.open(target).convert('RGBA').tobytes()==a
    else:native.save(target,optimize=True)
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    record={'schema':1,'task':'003A.1',**meta,'columns':COLS,'frame_count':128,'filter':'nearest','loop':False,
        'tiers':list(TIERS),'directions':8,'source':SOURCE.relative_to(ROOT).as_posix(),
        'texture':'res://'+target.relative_to(ROOT).as_posix(),'source_sha256':sha(SOURCE),'texture_sha256':sha(target),
        'native_runtime_rgba_exact':True,'reduced_flashing':'One-way cooling decay; no full-screen flash or oscillating brightness.'}
    manifest=OUT/'manifest.json'
    if check:assert json.loads(manifest.read_text())==record
    else:manifest.write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
    return record

def main():
    p=argparse.ArgumentParser();p.add_argument('--author',action='store_true');p.add_argument('--check',action='store_true');p.add_argument('--aseprite');args=p.parse_args()
    assert not(args.author and args.check)
    if args.author:author()
    record=export(find_tool('aseprite',args.aseprite),create_task_workspace('003A.1'),args.check)
    print(json.dumps({'passed':True,'master':str(SOURCE),'frames':record['frame_count'],'tags':len(record['tags']),'check':args.check},indent=2))
if __name__=='__main__':main()
