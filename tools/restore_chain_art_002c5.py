"""Restore the accepted 002B.1 Chain story, retaining current native pipeline.

Historical card layers and icon pixels are copied without resampling. Six good
poses use paired holds. Runtime retains the original native pressure source
burst and places restored warm contact reactions on actual paid recipients.
"""
import argparse, hashlib, json, subprocess
from pathlib import Path
import tempfile
from PIL import Image, ImageDraw
from build_power_art import read_ase, write_ase, P
from author_identity_foundation import layered_source

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'assets/source-art/power_identity_002c5'
OUT=ROOT/'assets/powers/identity'
HISTORICAL='bdcc24e'

def restore_chain():
    card_path=ROOT/'assets/source-art/power_cards_002b1.aseprite'
    icon_path=ROOT/'assets/source-art/power_icons_002b.aseprite'
    fx_path=ROOT/'assets/source-art/power_fx_002b.aseprite'
    for path in [card_path,icon_path,fx_path]:
        old=subprocess.check_output(['git','show',HISTORICAL+':'+str(path.relative_to(ROOT)).replace('\\','/')],cwd=ROOT)
        assert old==path.read_bytes(),'Accepted historical master changed: '+str(path)
    cards,cm=layered_source(card_path)
    icons,im=layered_source(icon_path)
    effects,fm=layered_source(fx_path)
    cstart=cm['tags']['chain_impact']['from'];istart=im['tags']['chain_impact']['from']
    frames=[];durations=[]
    names=cm['layers']+['Rank II second receiver follow-through']
    for rank in [1,2]:
        for pose in range(6):
            layers=[cell.copy() for cell in cards[cstart+pose]]
            extra=Image.new('RGBA',(64,64))
            if rank==2:
                d=ImageDraw.Draw(extra)
                # Develop the same physical relay rather than replacing its
                # accepted triangular arrangement with unrelated machinery.
                if pose in [2,3]:
                    d.line([(38,31),(42,34)],fill='#f3c36a',width=2)
                    d.line([(37,33),(40,35)],fill='#df8740')
                if pose in [4,5]:
                    d.line([(54,44),(59,47)],fill='#e3e8dc' if pose==4 else '#df8740')
                    d.line([(49,50),(54,52)],fill='#a94c35',width=2)
                    d.line([(45,49),(48,50)],fill='#4c626e')
            layers.append(extra)
            duration=cm['durations_ms'][cstart+pose]
            for hold in [duration//2,duration-duration//2]:
                frames.append([cell.copy() for cell in layers]);durations.append(hold)
    write_ase(SOURCE/'chain_impact_cards.aseprite',frames,names,
              [('chain_impact',0,11),('chain_impact_ii',12,23)],durations,(32,32),
              note='Restored bdcc24e Chain original editable layers; six native physical collision poses held twice; Rank I exact pixels and total timing',palette=P)
    icon_frames=[]
    for rank in [1,2]:
        original=Image.new('RGBA',(16,16))
        for cell in icons[istart]:original.alpha_composite(cell)
        detail=Image.new('RGBA',(16,16))
        if rank==2:
            d=ImageDraw.Draw(detail)
            d.line([(10,12),(13,12)],fill='#f3c36a')
            d.point((13,11),fill='#e3e8dc')
        icon_frames.append([original,detail])
    write_ase(SOURCE/'chain_impact_icons.aseprite',icon_frames,
              ['Restored independent triangular chain silhouette','Rank II final contact pressure'],
              [('chain_impact',0,0),('chain_impact_ii',1,1)],[120,120],(8,8),
              note='Original independently authored bdcc24e native16px icon; no card shrinking',palette=P)
    # Native 128px historical source burst stays in its accepted master.
    # Receiver accents crop the original contact keys without resampling;
    # all nontransparent contact pixels fit inside this local96x80 rectangle.
    fstart=fm['tags']['contact_arc']['from'];fxframes=[];tags=[];times=[]
    # Aseprite is authoritative for historical translucent overlap. Distribute
    # its exact final clusters to the highest contributing named layer so each
    # visible pixel blends once in both native and technical readers.
    with tempfile.TemporaryDirectory() as temp:
        native=Path(temp)/'historical.png'
        subprocess.run([r'F:\SteamLibrary\steamapps\common\Aseprite\Aseprite.exe','-b',str(fx_path),'--sheet-columns','8','--sheet',str(native)],check=True,capture_output=True)
        native_sheet=Image.open(native).convert('RGBA')
        native_effects=[native_sheet.crop((i%8*128,i//8*128,(i%8+1)*128,(i//8+1)*128)) for i in range(len(effects))]
    for tag in ['transmit','transmit_ii']:
        start=len(fxframes)
        for key in [0,0,1,2,3,4,5,5]:
            original_layers=effects[fstart+key]
            layers=[Image.new('RGBA',(96,80)) for _ in original_layers]
            final=native_effects[fstart+key].crop((16,16,112,96))
            for y in range(80):
                for x in range(96):
                    r,g,b,a=final.getpixel((x,y))
                    if not a:continue
                    owner=max(i for i,cell in enumerate(original_layers) if cell.getpixel((x+16,y+16))[3])
                    layers[owner].putpixel((x,y),(min(255,round(r*3.2)),min(255,round(g*1.25)),round(b*.60),a))
            fxframes.append(layers)
        tags.append((tag,start,len(fxframes)-1));times.extend([22,23,45,45,45,45,22,23])
    write_ase(SOURCE/'chain_impact_fx.aseprite',fxframes,fm['layers'],tags,times,(48,48),
              note='Restored historical warm local contact clusters, eight held keys/six original poses; placed only on actual paid recipient snapshots',palette=P)
    historical=dict(json.loads((ROOT/'assets/powers/manifest.json').read_text())['effects'])
    historical['texture']='res://assets/powers/effects.png'
    historical['source']='assets/source-art/power_fx_002b.aseprite'
    design={'family':'chain_impact','grammar':{
        'silhouette':'Three recognizable spinning tops in the restored triangular collision relay',
        'motion':'First contact expands locally; actual receivers react sequentially',
        'location':'Paid collision/elimination source and snapshotted real recipients',
        'persistence':'Finite 0.38s event; at most three native cels, no persistent player aura',
        'palette':'Accepted warm orange/gold collision clusters and steel tops',
        'feature':'Historical triangular top story plus causal source-to-recipient contact reactions'},
        'event_tags':{'chain_impact':'transmit'},'active_tags':{},
        'historical_fx':historical,'static_frames':{'chain_impact':8,'chain_impact_ii':8},
        'notes':'Restores bdcc24e card layers and independent icon Rank I exactly; six poses and total duration preserved through paired holds. Rank II develops the final contact without changing composition. Original native128 pressure source plus at most two real recipient contact cels retain the current three-cel draw bound. Receiver metadata and physics are untouched.'}
    (OUT/'chain_impact_design.json').write_text(json.dumps(design,indent=2)+'\n')
    print('Chain restored: accepted card/icon pixels and rhythm; historical source burst, real recipient contact keys.')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--replace-authored',action='store_true');args=parser.parse_args()
    if not args.replace_authored:raise SystemExit('Explicit --replace-authored required; normal exports preserve edited masters.')
    restore_chain()
