"""Author/export saved native 003A foundry escalation fixtures.

Normal invocation exports artist-edited Aseprite masters. --author explicitly
reconstructs only this new family. --check reads native source/runtime parity.
Fixtures live on fixed peripheral machinery, never the playable floor.
"""
from pathlib import Path
import argparse, hashlib, json, subprocess, sys, tempfile
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from build_power_art import read_ase, write_ase
from workspace.workspace import create_task_workspace, find_tool

SOURCE = ROOT / 'assets/source-art/arena_escalation003a'
OUT = ROOT / 'assets/arena/escalation003a'
PALETTE = {'ink':'#101820','deep':'#1b2933','metal':'#354954','steel':'#4c626e',
           'edge':'#7b929b','paper':'#c7d2c5','cold':'#64939a','cyan':'#82babe',
           'ochre':'#876437','amber':'#ce963e','yellow':'#e5be66','oxide':'#814533',
           'orange':'#c56d3a','red':'#b55538','steam':'#5c7378'}

def ink(name, alpha=255):
    return tuple(bytes.fromhex(PALETTE[name][1:])) + (alpha,)

def layers(size, count):
    return [Image.new('RGBA', size) for _ in range(count)]

def fastener(d, x, y):
    d.rectangle((x,y,x+2,y+2),fill=ink('ink'))
    d.point((x+1,y),fill=ink('edge'))

def machinery():
    frames=[]
    for k in range(12):
        housing,shaft,drive,lamps=layers((64,40),4)
        d=ImageDraw.Draw(housing)
        d.polygon([(4,14),(15,8),(49,8),(60,14),(59,32),(48,38),(16,38),(4,32)],fill=ink('ink'))
        d.polygon([(5,14),(16,9),(48,9),(59,14),(48,20),(16,20)],fill=ink('steel'))
        d.polygon([(5,16),(16,22),(47,22),(58,16),(58,31),(47,36),(16,36),(5,31)],fill=ink('deep'))
        d.line([(6,16),(17,21),(47,21),(57,16)],fill=ink('edge'))
        d.rectangle((9,25,19,30),fill=ink('metal' if k<8 else 'oxide'));d.rectangle((44,25,54,30),fill=ink('metal' if k<8 else 'oxide'))
        if k>=8:
            d.line([(6,17),(17,22),(47,22),(57,17)],fill=ink('amber'))
            d.line((17,35,46,35),fill=ink('ochre'))
        for x in [10,50]:fastener(d,x,32)
        d=ImageDraw.Draw(shaft)
        d.rectangle((27,2,36,27),fill=ink('ink'));d.rectangle((29,4,34,26),fill=ink('metal'))
        d.line((30,5,30,24),fill=ink('edge'))
        d.polygon([(25,3),(29,0),(35,0),(39,3),(35,6),(29,6)],fill=ink('steel'))
        d=ImageDraw.Draw(drive)
        phase=k%4
        # Discrete isometric rotor keys; no runtime rotation or resampling.
        d.polygon([(16,13),(25,8),(40,8),(48,13),(40,18),(25,18)],fill=ink('ink'))
        d.polygon([(18,13),(26,9),(39,9),(46,13),(39,17),(26,17)],fill=ink('metal'))
        poses=[[(20,12),(26,9),(43,14),(38,17)],[(24,10),(28,9),(41,16),(37,17)],[(20,14),(23,16),(43,12),(39,9)],[(26,17),(31,17),(36,9),(31,9)]]
        d.polygon(poses[phase],fill=ink('edge' if k<8 else 'yellow'))
        d.polygon([(28,12),(32,10),(36,12),(32,15)],fill=ink('steel'))
        d=ImageDraw.Draw(lamps)
        active=k//4
        d.rectangle((23,27,40,32),fill=ink('ink'))
        for j in range(4):
            shade='cold' if active==0 else ('amber' if active==1 else 'orange')
            d.rectangle((25+j*4,28,26+j*4,30),fill=ink(shade if j<=active+phase%2 else 'metal'))
        frames.append([housing,shaft,drive,lamps])
    return frames,['01 bolted fixed housing','02 vertical drive shaft','03 authored isometric rotor keys','04 local load meter'],[('IDLE',0,3),('DRIVE',4,7),('OVERDRIVE',8,11)],[450]*4+[240]*4+[130]*4,(32,38)

def warning_bank():
    frames=[]
    for k in range(16):
        shell,lenses,state=layers((48,16),3);d=ImageDraw.Draw(shell)
        d.polygon([(2,2),(44,2),(47,5),(47,13),(43,15),(3,15),(0,12),(0,5)],fill=ink('ink'))
        d.rectangle((2,4,45,12),fill=ink('metal'));d.line((4,3,43,3),fill=ink('edge'))
        fastener(d,2,9);fastener(d,43,9)
        d=ImageDraw.Draw(lenses)
        for j in range(6):
            d.rectangle((7+j*6,5,11+j*6,11),fill=ink('ink'));d.rectangle((8+j*6,6,10+j*6,10),fill=ink('deep'))
        stage=k//4;phase=k%4;d=ImageDraw.Draw(state)
        if stage>=2:
            d.line((7,4,40,4),fill=ink('ochre' if stage==2 else 'amber'))
            d.line((7,12,40,12),fill=ink('oxide'))
        for j in range(6):
            lit=j<2 if stage==0 else (j<3 if stage==1 else (j%2==phase%2 if stage==2 else j!=phase+1))
            if lit:
                shade=['cold','amber','orange','red'][stage]
                d.rectangle((8+j*6,6,10+j*6,10),fill=ink(shade))
                d.point((9+j*6,6),fill=ink('edge' if stage==0 else 'yellow'))
        frames.append([shell,lenses,state])
    return frames,['01 bounded alarm hardware','02 inset individual glass lenses','03 slow local warning state'],[('SAFE',0,3),('BUILDING',4,7),('WARNING',8,11),('ALARM',12,15)],[1200]*4+[1000]*4+[600]*4+[500]*4,(24,12)

def vent():
    frames=[]
    for k in range(8):
        frame,fan,exhaust=layers((32,32),3);d=ImageDraw.Draw(frame)
        d.polygon([(3,14),(15,8),(28,14),(28,25),(16,31),(3,25)],fill=ink('ink'))
        d.polygon([(4,14),(15,9),(27,14),(16,20)],fill=ink('steel'))
        d.polygon([(4,16),(15,22),(27,16),(27,24),(16,29),(4,24)],fill=ink('deep'))
        d.line([(5,15),(16,21),(26,15)],fill=ink('edge'))
        d=ImageDraw.Draw(fan)
        d.polygon([(7,15),(15,11),(24,15),(16,19)],fill=ink('ink'))
        poses=[[(8,15),(13,12),(23,16),(18,18)],[(12,12),(15,11),(19,18),(16,19)],[(8,16),(11,18),(23,14),(20,12)],[(14,19),(17,19),(17,11),(14,11)]]
        d.polygon(poses[k%4],fill=ink('metal'));d.point((16,15),fill=ink('edge'))
        for y in [22,25]:d.line((8,y,14,y+3),fill=ink('steel'))
        d=ImageDraw.Draw(exhaust)
        if k>=4:
            phase=k%4
            d.line([(17,11),(18+phase,7),(15+phase,4),(17+phase,1)],fill=ink('steam'),width=1)
            d.line([(12,11),(10-phase,7),(13-phase,5)],fill=ink('metal'),width=1)
        frames.append([frame,fan,exhaust])
    return frames,['01 peripheral extraction housing','02 four keyed fan poses','03 controlled exhaust plume'],[('IDLE',0,3),('HOT',4,7)],[500]*4+[230]*4,(16,30)

def display_panel():
    frames=[]
    for k in range(8):
        frame,print_,meters=layers((40,24),3);d=ImageDraw.Draw(frame)
        d.polygon([(3,1),(36,1),(39,4),(39,20),(35,23),(3,23),(0,20),(0,4)],fill=ink('ink'))
        d.rectangle((3,4,36,19),fill=ink('deep'));d.line((4,2,35,2),fill=ink('edge'))
        fastener(d,2,18);fastener(d,35,18)
        d=ImageDraw.Draw(print_)
        d.line((6,6,14,6),fill=ink('steel'));d.line((6,8,10,8),fill=ink('steel'))
        d.line((6,12,6,17),fill=ink('steel'));d.line((7,17,32,17),fill=ink('steel'))
        d=ImageDraw.Draw(meters);load=k//4;phase=k%4
        for j in range(5):
            h=[3,5,4,6,3][(j+phase)%5]+load*2
            d.rectangle((10+j*4,16-h,11+j*4,16),fill=ink('cold' if load==0 else 'amber'))
        d.rectangle((27,5,32,7),fill=ink('metal' if load==0 else 'oxide'))
        frames.append([frame,print_,meters])
    return frames,['01 protected display housing','02 printed load scale','03 authored bounded bar-readout keys'],[('IDLE',0,3),('LOAD',4,7)],[700]*4+[300]*4,(20,22)

def sparks():
    frames=[]
    for k in range(6):
        source,grit=layers((24,24),2);d=ImageDraw.Draw(source)
        if k<3:d.line((10,19,12,17-k),fill=ink('orange' if k else 'yellow'))
        d=ImageDraw.Draw(grit)
        positions=[(8-k,15-k),(14+k,15-k*2),(11,11-k)]
        for j,(x,y) in enumerate(positions):
            if k<5-j:d.line((x,y,x+1,y+1),fill=ink('yellow' if k<2 else 'orange'))
        frames.append([source,grit])
    return frames,['01 fixed hardware contact source','02 six finite divergent pixel-grit keys'],[('SPARK',0,5)],[100,120,150,180,230,300],(12,19)

def perimeter():
    frames=[]
    for k in range(8):
        hardware,glass=layers((32,16),2);d=ImageDraw.Draw(hardware);left=k<4
        outline=[(2,2),(27,10),(30,13),(5,5)] if left else [(2,13),(27,5),(30,2),(5,10)]
        d.polygon(outline,fill=ink('ink'))
        d.line(outline[:2],fill=ink('steel'),width=2)
        d=ImageDraw.Draw(glass)
        for j in range(4):
            x=6+j*6;y=4+j*2 if left else 11-j*2
            d.line((x,y,x+3,y+1 if left else y-1),fill=ink('ochre' if j==k%4 else 'yellow'),width=2)
        frames.append([hardware,glass])
    return frames,['01 rim-mounted diode rail','02 stepped local industrial illumination'],[('LEFT',0,3),('RIGHT',4,7)],[600]*8,(16,8)

SPECS={'machinery':machinery,'warning_bank':warning_bank,'vent':vent,'display_panel':display_panel,'sparks':sparks,'perimeter':perimeter}

def author():
    SOURCE.mkdir(parents=True,exist_ok=True)
    for name,factory in SPECS.items():
        write_ase(SOURCE/f'{name}.aseprite',*factory(),note='003A final acceptance / peripheral foundry machinery / presentation only / fixed isometric authored poses / bounded local illumination / no attack telegraphs',palette=PALETTE)

def export(check=False):
    qa=create_task_workspace('003A');aseprite=find_tool('aseprite');report={'task':'003A final human acceptance','native_runtime_parity':True,'fixtures':[]}
    OUT.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='arena-native-',dir=qa/'temp') as temp:
        for name in SPECS:
            source=SOURCE/f'{name}.aseprite';frames,meta=read_ase(source)
            png=Path(temp)/f'{name}.png';js=Path(temp)/f'{name}.json'
            subprocess.run([aseprite,'--batch',str(source),'--list-layers','--list-tags','--list-slices','--sheet-type','horizontal','--sheet',str(png),'--data',str(js),'--format','json-array'],check=True,capture_output=True)
            actual=Image.open(png).convert('RGBA');info=json.loads(js.read_text())
            atlas=Image.new('RGBA',(meta['cell'][0]*len(frames),meta['cell'][1]))
            for i,frame in enumerate(frames):atlas.alpha_composite(frame,(i*meta['cell'][0],0))
            assert actual.tobytes()==atlas.tobytes(),(name,'source/native pixels')
            assert [l['name'] for l in info['meta']['layers']]==meta['layers']
            assert [f['duration'] for f in info['frames']]==meta['durations_ms']
            assert {t['name']:{'from':t['from'],'to':t['to']} for t in info['meta']['frameTags']}==meta['tags']
            pivot=info['meta']['slices'][0]['keys'][0]['pivot'];assert [pivot['x'],pivot['y']]==meta['pivot']
            meta.update(version=1,texture=f'res://assets/arena/escalation003a/{name}.png',columns=len(frames),frame_count=len(frames),filter='nearest',native_pixels=True,source=f'assets/source-art/arena_escalation003a/{name}.aseprite',presentation_only=True)
            if check:
                assert Image.open(OUT/f'{name}.png').convert('RGBA').tobytes()==actual.tobytes()
                assert json.loads((OUT/f'{name}.json').read_text())==meta
            else:
                actual.save(OUT/f'{name}.png',optimize=True);(OUT/f'{name}.json').write_text(json.dumps(meta,indent=2)+'\n')
            report['fixtures'].append({'name':name,'cell':meta['cell'],'pivot':meta['pivot'],'layers':meta['layers'],'tags':meta['tags'],'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'runtime_sha256':hashlib.sha256((OUT/f'{name}.png').read_bytes()).hexdigest()})
    return report

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--author',action='store_true');p.add_argument('--check',action='store_true');p.add_argument('--report',type=Path);a=p.parse_args()
    if a.check and a.author:p.error('--check is read only')
    if a.report and ROOT in a.report.resolve().parents:p.error('QA output must be external')
    if a.author:author()
    result=export(a.check)
    if a.report:a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))

if __name__=='__main__':main()
