"""Eight new mutation illustrations, authored as editable native pixel cels.

--author constructs only absent 003A.2 masters. Normal export reads the saved
artist-owned masters through actual Aseprite; it never reconstructs artwork.
Accepted sources are read-only composition references. No gameplay code runs.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys
import uuid
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from build_power_art import read_ase, write_ase

SOURCE = ROOT / 'assets/source-art/ecology003a2'
OUT = ROOT / 'assets/powers/ecology003a2'
FAMILIES = {
    'iron_comet': ['wallbreaker', 'ricochet_engine'],
    'orbit_drive': ['centrifuge', 'perpetual_orbit'],
    'momentum_bank': ['flywheel_release', 'countersteer'],
    'crash_guard': ['reactive_plating', 'sacrificial_damper'],
}
NAMES = {'wallbreaker': 'Wallbreaker', 'ricochet_engine': 'Ricochet Engine',
         'centrifuge': 'Centrifuge', 'perpetual_orbit': 'Perpetual Orbit',
         'flywheel_release': 'Flywheel Release', 'countersteer': 'Countersteer',
         'reactive_plating': 'Reactive Plating', 'sacrificial_damper': 'Sacrificial Damper'}
TIMES = {'wallbreaker': [190, 130, 70, 55, 100, 210],
         'ricochet_engine': [120, 75, 100, 70, 100, 180],
         'centrifuge': [150, 110, 80, 70, 120, 185],
         'perpetual_orbit': [120, 120, 120, 120, 120, 160],
         'flywheel_release': [150, 170, 220, 55, 90, 195],
         'countersteer': [150, 150, 160, 85, 115, 185],
         'reactive_plating': [170, 100, 180, 100, 90, 180],
         'sacrificial_damper': [160, 100, 80, 180, 160, 200]}
STATIC = {'wallbreaker': 3, 'ricochet_engine': 3, 'centrifuge': 3,
          'perpetual_orbit': 4, 'flywheel_release': 3, 'countersteer': 3,
          'reactive_plating': 3, 'sacrificial_damper': 3}
STORIES = {
    'wallbreaker': 'One hard wall rebound commits the intact top to one rival; a single contact and recoil finish the line.',
    'ricochet_engine': 'Two separated real wall faces and successive oblique rebound lanes; no continuous rail or stronger single strike.',
    'centrifuge': 'A carved tangential contact pushes the rival out of the curve; a finite spent skid replaces a damage aura.',
    'perpetual_orbit': 'One intact top maintains an open smooth travel curve; continuity and recovery replace an attack composition.',
    'flywheel_release': 'The broad top brakes into a compact heel skid, holds, then releases forward on a committed line.',
    'countersteer': 'The same broad top banks braking motion, then redirects across its incoming line into a lateral exit.',
    'reactive_plating': 'A genuine incoming top displaces the defender; a later separate aimed contact releases its stored counterforce.',
    'sacrificial_damper': 'One huge incoming hit buckles the defender into a longer skid and sparse spent rim fragments; recovery remains visible.',
}
PAL = {'ink': '#111b24', 'floor': '#1b2d39', 'dark': '#253944',
       'steel': '#617880', 'silver': '#afc4c5', 'paper': '#e7e5ca',
       'white': '#fff3d1', 'brass': '#b88e50', 'gold': '#f0c572',
       'red': '#bd5b3c', 'hot': '#f29558', 'sea': '#2f6969',
       'mint': '#80b7a5', 'ice': '#c5e7d6', 'blue': '#37627b'}
CARD_LAYERS = ['01 sparse arena floor', '02 paid physical travel and shadows',
               '03 accepted rival native body', '04 accepted owner native body',
               '05 contact and finite follow-through']
ICON_LAYERS = ['01 independently authored miniature tops', '02 branch travel and contact']
REFERENCES = ['assets/source-art/starter_blade_accents_002b1.aseprite',
              'assets/top/parts/ratchets/mid.png', 'assets/top/parts/bits/flat.png',
              'assets/top/parts/bits/needle.png']
_blades = None
_blade_meta = None
_parts = None

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def rgba(c): return (*bytes.fromhex(PAL.get(c, c).lstrip('#')), 255)
def blank(size): return Image.new('RGBA', size)
def line(im, points, c, width=1):
    ImageDraw.Draw(im).line([(round(x), round(y)) for x, y in points], fill=rgba(c), width=width)
def poly(im, points, c):
    ImageDraw.Draw(im).polygon([(round(x), round(y)) for x, y in points], fill=rgba(c))
def dot(im, x, y, c): ImageDraw.Draw(im).point((round(x), round(y)), fill=rgba(c))
def arc(im, cx, cy, rx, start, extent, c, width=1):
    line(im, [(cx+math.cos(start+extent*k/12)*rx, cy+math.sin(start+extent*k/12)*rx*.5) for k in range(13)], c, width)
def references():
    global _blades, _blade_meta, _parts
    if _blades is None:
        _blades, _blade_meta = read_ase(ROOT / REFERENCES[0])
        _parts = {name: Image.open(ROOT / path).convert('RGBA') for name, path in
                  [('ratchet', REFERENCES[1]), ('flat', REFERENCES[2]), ('needle', REFERENCES[3])]}
    return _blades, _blade_meta, _parts
def top(im, kind, x, y, key):
    blades, meta, parts = references()
    offset = (round(x-24), round(y-26))
    im.alpha_composite(parts['needle' if kind == 'bastion' else 'flat'], offset)
    im.alpha_composite(parts['ratchet'], offset)
    im.alpha_composite(blades[meta['tags'][kind]['from']+[0, 1, 3, 4, 6, 7][key]], offset)
def shadow(im, x, y, r=12):
    ImageDraw.Draw(im).ellipse((x-r, y+13, x+r, y+17), fill=rgba('floor'))
def contact(im, x, y, strong=False):
    line(im, [(x-4,y+2),(x,y),(x+3,y-3)], 'gold', 2)
    dot(im, x, y-1, 'white')
    if strong:
        line(im, [(x-2,y-4),(x,y-2)], 'paper')
        line(im, [(x+4,y+3),(x+7,y+4)], 'silver')
def wall(im, side):
    if side == 'left':
        poly(im, [(1,13),(6,10),(9,13),(9,42),(6,47),(1,44)], 'dark')
        line(im, [(7,13),(7,42)], 'silver', 2)
        line(im, [(2,15),(2,42)], 'steel')
    else:
        poly(im, [(49,2),(54,1),(60,4),(60,22),(56,26),(50,22)], 'dark')
        line(im, [(52,4),(52,22)], 'silver', 2)
        line(im, [(57,5),(57,21)], 'steel')

def card(branch, k):
    im = [blank((64,64)) for _ in CARD_LAYERS]
    own = rival = None
    # Every sibling has its own staged positions and floor/contact composition.
    if branch == 'wallbreaker':
        wall(im[0], 'left')
        own = [(21,34),(20,35),(28,29),(39,24),(39,27),(31,33)][k]
        rival = [(52,18),(52,18),(52,18),(53,18),(58,14),(59,15)][k]
        if k < 2: contact(im[4], 9, 27)
        if k in (2,3,4):
            line(im[1], [(11,48),(19,43),(29,36)], 'brass', 2)
            line(im[1], [(12,53),(23,46),(32,39)], 'silver')
        if k in (3,4): contact(im[4], 47, 23, True)
        if k == 5: line(im[1], [(30,49),(36,46),(43,43)], 'steel', 2)
    elif branch == 'ricochet_engine':
        wall(im[0], 'left'); wall(im[0], 'right')
        own = [(23,36),(20,36),(31,27),(42,18),(32,35),(44,39)][k]
        if k >= 1: line(im[1], [(9,47),(18,42),(27,35)], 'brass')
        if k >= 2: line(im[1], [(29,31),(39,25),(48,20)], 'silver')
        if k >= 4:
            line(im[1], [(46,31),(39,38),(30,42)], 'gold')
            line(im[1], [(31,47),(39,49),(48,46)], 'steel')
        if k in (1,3): contact(im[4], 9 if k == 1 else 51, 26 if k == 1 else 17)
    elif branch == 'centrifuge':
        own = [(27,31),(31,27),(36,28),(37,33),(31,36),(27,32)][k]
        rival = [(52,19),(51,20),(48,24),(54,26),(60,24),(61,23)][k]
        arc(im[1], 29, 47, 22, 2.5, 1.25+k*.18, 'sea', 2)
        if k >= 2: arc(im[1], 29, 47, 18, 3.2, .85, 'mint')
        if k in (2,3): contact(im[4], 44, 31)
        if k >= 3:
            line(im[1], [(47,41),(54,43),(61,41)], 'steel', 2)
            line(im[4], [(52,36),(56,37)], 'ice')
    elif branch == 'perpetual_orbit':
        own = [(17,36),(22,29),(33,23),(43,27),(41,36),(29,40)][k]
        points = [(7,54),(9,46),(16,39),(27,34),(40,36),(49,44),(43,52),(31,57),(19,56)]
        line(im[1], points[:min(9,4+k)], 'sea', 2)
        line(im[1], [(x,y+2) for x,y in points[:min(8,3+k)]], 'steel')
        # Short separate heel marks retain an open curve rather than a HUD ring.
        for x,y in [(12,47),(28,36),(47,44)]: line(im[4], [(x,y),(x+2,y-1)], 'mint')
    elif branch == 'flywheel_release':
        own = [(38,24),(32,30),(28,34),(37,27),(46,21),(43,24)][k]
        line(im[1], [(7,54),(15,49),(23,43)], 'dark', 2)
        if k in (1,2):
            line(im[1], [(10,50),(18,51),(27,48),(33,44)], 'gold', 2)
            line(im[1], [(12,56),(22,55),(30,51)], 'brass', 2)
        if k in (3,4):
            line(im[1], [(6,57),(19,49),(32,40),(40,32)], 'gold', 2)
            line(im[1], [(9,61),(23,53),(35,45)], 'silver')
        if k == 5: line(im[1], [(20,46),(29,40),(36,34)], 'steel')
    elif branch == 'countersteer':
        own = [(24,22),(25,29),(29,35),(38,35),(44,29),(38,28)][k]
        line(im[1], [(7,18),(14,24),(20,31),(25,39)], 'steel', 2)
        if k in (1,2):
            line(im[1], [(13,43),(20,47),(29,47)], 'brass', 2)
            line(im[1], [(17,50),(24,52),(32,49)], 'gold')
        if k >= 3:
            line(im[1], [(26,49),(34,53),(46,52),(57,46)], 'gold', 2)
            line(im[1], [(31,57),(42,58),(53,53)], 'silver')
        if k == 3: line(im[4], [(31,42),(35,43),(39,41)], 'paper', 2)
    elif branch == 'reactive_plating':
        own = [(25,35),(25,35),(23,37),(31,32),(36,28),(31,31)][k]
        rival = [(52,17),(47,21),(43,25),(45,23),(54,15),(57,14)][k]
        line(im[1], [(14,54),(22,54),(28,51)], 'steel', 2)
        if k in (1,2):
            line(im[4], [(35,28),(37,30),(37,33),(35,35)], 'silver', 2)
            contact(im[4], 39, 28)
        if k >= 3: line(im[1], [(24,51),(32,44),(40,37)], 'brass', 2)
        if k in (3,4): contact(im[4], 43, 24, True)
    else:
        assert branch == 'sacrificial_damper'
        own = [(29,26),(27,29),(23,34),(18,39),(19,37),(23,33)][k]
        rival = [(48,16),(44,21),(39,27),(38,29),(43,24),(48,19)][k]
        if k >= 2:
            line(im[1], [(31,43),(26,48),(19,53),(9,56)], 'steel', 2)
            line(im[1], [(28,50),(20,58),(8,61)], 'brass')
        if k in (1,2): contact(im[4], 36, 29, True)
        if k in (2,3,4):
            for x,y in [(29-k,46),(36-k,42),(41-k,37)]:
                line(im[4], [(x,y),(x+2,y+1)], 'silver')
            line(im[4], [(10,54),(13,53)], 'gold')
        if k == 5: line(im[1], [(16,52),(22,48),(28,44)], 'dark')
    if rival is not None:
        shadow(im[1], *rival, 10); top(im[2], 'breaker', *rival, k)
    shadow(im[1], *own)
    top(im[3], 'bastion', *own, k)
    return im

def tiny_top(im, x, y, red=False):
    poly(im, [(x-4,y),(x-2,y-2),(x+3,y-2),(x+5,y),(x+3,y+3),(x-3,y+3)], 'dark')
    line(im, [(x-3,y),(x,y-1),(x+3,y)], 'silver')
    line(im, [(x-2,y+2),(x+2,y+2)], 'red' if red else 'blue', 2)
    dot(im, x, y, 'hot' if red else 'ice'); line(im, [(x,y+3),(x,y+5)], 'steel')
def icon(branch):
    im = [blank((16,16)) for _ in ICON_LAYERS]
    if branch == 'wallbreaker':
        line(im[1], [(1,2),(1,12)], 'silver', 2); tiny_top(im[0], 9, 7)
        line(im[1], [(3,12),(6,10),(8,9)], 'gold', 2)
    elif branch == 'ricochet_engine':
        line(im[1], [(1,5),(1,13)], 'silver'); line(im[1], [(14,1),(14,7)], 'silver')
        tiny_top(im[0], 8, 5); line(im[1], [(2,13),(8,10),(13,7),(10,14)], 'brass')
    elif branch == 'centrifuge':
        tiny_top(im[0], 6, 8); tiny_top(im[0], 12, 2, True)
        line(im[1], [(1,14),(5,15),(10,13)], 'mint'); line(im[1], [(12,9),(15,11)], 'gold')
    elif branch == 'perpetual_orbit':
        tiny_top(im[0], 8, 5); line(im[1], [(2,7),(1,11),(4,14),(10,15),(14,12),(14,8)], 'mint')
    elif branch == 'flywheel_release':
        tiny_top(im[0], 10, 4); line(im[1], [(1,14),(5,11),(9,8)], 'gold', 2)
        line(im[1], [(4,15),(8,12)], 'silver')
    elif branch == 'countersteer':
        tiny_top(im[0], 9, 6); line(im[1], [(1,2),(2,8),(5,12),(10,14),(15,11)], 'gold', 2)
    elif branch == 'reactive_plating':
        tiny_top(im[0], 5, 9); tiny_top(im[0], 12, 2, True)
        line(im[1], [(8,8),(10,6),(12,7)], 'paper'); line(im[1], [(3,15),(7,13)], 'brass')
    else:
        tiny_top(im[0], 4, 10); tiny_top(im[0], 11, 4, True)
        line(im[1], [(1,15),(4,14)], 'steel'); dot(im[1], 9, 12, 'silver'); dot(im[1], 13, 10, 'gold')
    return im

def author(source_dir=SOURCE):
    targets = [source_dir / f'{family}_{group}.aseprite' for family in FAMILIES for group in ('cards','icons')]
    if any(p.exists() for p in targets): raise ValueError('Refusing to reconstruct an existing artist-owned master')
    source_dir.mkdir(parents=True, exist_ok=True)
    for family, branches in FAMILIES.items():
        cards = [card(branch, key) for branch in branches for key in range(6)]
        write_ase(source_dir / f'{family}_cards.aseprite', cards, CARD_LAYERS,
                  [(branch,index*6,index*6+5) for index,branch in enumerate(branches)],
                  [value for branch in branches for value in TIMES[branch]], (32,32),
                  note='003A.2 / six distinct physical-story poses per mutation / intact accepted native top parts / transparent background / no gadgets / saved layers are editing authority', palette=PAL)
        write_ase(source_dir / f'{family}_icons.aseprite', [icon(branch) for branch in branches], ICON_LAYERS,
                  [(branch,index,index) for index,branch in enumerate(branches)], [160,160], (8,8),
                  note='003A.2 / independently authored 16px physical top and travel silhouettes / never resized cards', palette=PAL)

def visible_equal(a, b):
    aa, bb = a.tobytes(), b.tobytes()
    return all(aa[k:k+4] == bb[k:k+4] for k in range(0,len(aa),4) if aa[k+3] or bb[k+3])

def export(aseprite, qa_dir, check=False, source_dir=SOURCE, out_dir=OUT):
    qa_dir.mkdir(parents=True, exist_ok=False)
    reference_before = {name:sha(ROOT/name) for name in REFERENCES}
    manifest = {'version':1,'task':'003A.2','filter':'nearest','native_pixels':True,
                'scope':'Eight new Rank III mutation illustrations; accepted art and gameplay remain unchanged.',
                'families':{},'art':{},'references':reference_before}
    if not check: out_dir.mkdir(parents=True, exist_ok=True)
    for family, branches in FAMILIES.items():
        groups = {}
        for group, size, pivot, columns, count in [('cards',(64,64),(32,32),6,6),('icons',(16,16),(8,8),2,1)]:
            source_path=source_dir/f'{family}_{group}.aseprite'; frames, meta=read_ase(source_path)
            assert tuple(meta['cell'])==size and tuple(meta['pivot'])==pivot
            assert meta['layers']==(CARD_LAYERS if group=='cards' else ICON_LAYERS)
            assert list(meta['tags'])==branches and len(frames)==2*count
            assert all(span['to']-span['from']+1==count for span in meta['tags'].values())
            if group=='cards':
                for branch in branches:
                    span=meta['tags'][branch]
                    assert len({hashlib.sha256(f.tobytes()).hexdigest() for f in frames[span['from']:span['to']+1]})==6
            png=qa_dir/f'{family}_{group}_native.png'; data=qa_dir/f'{family}_{group}_native.json'
            command=[str(aseprite),'--batch',str(source_path),'--list-layers','--list-tags','--list-slices',
                     '--sheet-columns',str(columns),'--sheet',str(png),'--format','json-array','--data',str(data)]
            result=subprocess.run(command,capture_output=True,text=True,check=True)
            (qa_dir/f'{family}_{group}.log').write_text(result.stdout+result.stderr,encoding='utf-8')
            native=Image.open(png).convert('RGBA'); assert native.size==(columns*size[0],math.ceil(len(frames)/columns)*size[1])
            for index,frame in enumerate(frames):
                cel=native.crop((index%columns*size[0],index//columns*size[1],(index%columns+1)*size[0],(index//columns+1)*size[1]))
                assert visible_equal(frame,cel),(family,group,index,'native RGBA parity')
            actual=json.loads(data.read_text(encoding='utf-8'))
            assert [frame['duration'] for frame in actual['frames']]==meta['durations_ms']
            assert [layer['name'] for layer in actual['meta']['layers']]==meta['layers']
            assert {tag['name']:{'from':tag['from'],'to':tag['to']} for tag in actual['meta']['frameTags']}==meta['tags']
            assert actual['meta']['slices'][0]['keys'][0]['pivot']==dict(zip(('x','y'),pivot))
            target=out_dir/f'{family}_{group}.png'
            if check: assert Image.open(target).convert('RGBA').tobytes()==native.tobytes()
            else: native.save(target,optimize=True)
            # Catalogue metadata always uses canonical resource paths; alternate
            # directories only support external isolated exporter regression.
            meta.update(columns=columns,frame_count=len(frames),source=f'assets/source-art/ecology003a2/{source_path.name}',
                        texture=f'res://assets/powers/ecology003a2/{target.name}',source_sha256=sha(source_path),
                        texture_sha256=sha(target),native_runtime_rgba_exact=True)
            groups[group]=meta
        manifest['families'][family]={'cards':groups['cards'],'icons':groups['icons'],
                                     'stories':{branch:STORIES[branch] for branch in branches}}
        for branch in branches:
            span=groups['cards']['tags'][branch]
            manifest['art'][branch]={'family':family,'art_id':branch,'source_tag':branch,
                'icon':groups['icons']['texture'],'icon_frame':groups['icons']['tags'][branch]['from'],
                'card_texture':groups['cards']['texture'],'card_row':span['from']//6,'card_cell':64,
                'card_frames':6,'card_static_frame':STATIC[branch],
                'card_durations_ms':groups['cards']['durations_ms'][span['from']:span['to']+1]}
    assert reference_before=={name:sha(ROOT/name) for name in REFERENCES}
    path=out_dir/'manifest.json'
    if check: assert json.loads(path.read_text(encoding='utf-8'))==manifest
    else: path.write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    report={'created_utc':datetime.now(timezone.utc).isoformat(),'masters':8,'cards':8,'card_frames':48,'icons':8,
            'editable_layers_tags_pivots_durations_verified':True,'actual_aseprite_runtime_rgba_parity':True,
            'accepted_reference_bytes_unchanged':True,'manifest_sha256':sha(path),'native_evidence':str(qa_dir)}
    (qa_dir/'export_validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    return report

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--author',action='store_true');parser.add_argument('--check',action='store_true')
    parser.add_argument('--aseprite',type=Path,default=Path(r'F:\SteamLibrary\steamapps\common\Aseprite\Aseprite.exe'))
    parser.add_argument('--qa-dir',type=Path)
    args=parser.parse_args()
    if args.author and args.check:parser.error('--author and --check are distinct workflows')
    if args.author:author()
    qa=args.qa_dir or ROOT.parent/'GyroBrothers-QA/003A.2/temp'/('ecology-art-'+uuid.uuid4().hex)
    print(json.dumps(export(args.aseprite,qa,args.check),indent=2))
if __name__=='__main__':main()
