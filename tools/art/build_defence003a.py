"""Author or export the three final003A active defence families.

Normal invocation exports saved artist-editable sources through Aseprite and
checks visible cel parity. --author is an explicit reconstruction of only these
new masters. Accepted machine pixels are composited without scaling/repainting.
"""
import argparse
import hashlib
import json
import math
import subprocess
import sys
import tempfile
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from build_power_art import read_ase, write_ase

SOURCE = ROOT / 'assets/source-art/defence003a'
OUT = ROOT / 'assets/powers/defence003a'
FAMILIES = {
    'gyro_lock': ['gyro_lock', 'gyro_lock_ii', 'keel', 'flywheel'],
    'impact_sink': ['impact_sink', 'impact_sink_ii', 'shock_bleed', 'return_spring'],
    'anchor_exchange': ['anchor_exchange', 'anchor_exchange_ii', 'deep_footing', 'slip_anchor'],
}
EVENTS = {
    'gyro_lock_set': {'family': 'gyro_lock', 'tag': 'engage'},
    'gyro_lock_break': {'family': 'gyro_lock', 'tag': 'release'},
    'sink_store': {'family': 'impact_sink', 'tag': 'engage'},
    'sink_vent': {'family': 'impact_sink', 'tag': 'vent'},
    'sink_return': {'family': 'impact_sink', 'tag': 'return'},
    'exchange_set': {'family': 'anchor_exchange', 'tag': 'engage'},
    'exchange_release': {'family': 'anchor_exchange', 'tag': 'release'},
}
COLORS = {'ink': '#111b24', 'dark': '#253944', 'steel': '#617880', 'silver': '#afc4c5',
          'paper': '#e7e5ca', 'gold': '#f0c572', 'brass': '#b88e50', 'hot': '#f29558',
          'red': '#bd5b3c', 'sea': '#2f6969', 'mint': '#80b7a5', 'ice': '#c5e7d6'}
BLADES, BLADE_META = read_ase(ROOT / 'assets/source-art/starter_blade_accents_002b1.aseprite')
PARTS = {name: Image.open(ROOT / f'assets/top/parts/{folder}/{name}.png').convert('RGBA')
         for name, folder in [('mid', 'ratchets'), ('needle', 'bits'), ('flat', 'bits')]}

def color(c, a=255): return (*bytes.fromhex(COLORS.get(c, c).lstrip('#')), a)
def blank(size): return Image.new('RGBA', size)
def line(im, points, c, width=1, alpha=255):
    ImageDraw.Draw(im).line([(round(x), round(y)) for x, y in points], fill=color(c, alpha), width=width)
def poly(im, points, c, alpha=255):
    ImageDraw.Draw(im).polygon([(round(x), round(y)) for x, y in points], fill=color(c, alpha))
def dot(im, x, y, c): ImageDraw.Draw(im).point((round(x), round(y)), fill=color(c))
def oval(im, box, c, width=1): ImageDraw.Draw(im).ellipse(tuple(round(x) for x in box), outline=color(c), width=width)

def top(im, kind, x, y, pose):
    offset = (round(x - 24), round(y - 26))
    im.alpha_composite(PARTS['needle' if kind == 'bastion' else 'flat'], offset)
    im.alpha_composite(PARTS['mid'], offset)
    im.alpha_composite(BLADES[BLADE_META['tags'][kind]['from'] + pose % 8], offset)

def floor_arc(im, cx, cy, r, start, extent, c, width=1):
    points = [(cx + math.cos(start + extent * k / 9) * r,
               cy + math.sin(start + extent * k / 9) * r * .5) for k in range(10)]
    line(im, points, c, width)

def gyro_fixture(im, cx, cy, strength, developed=False):
    # Three physical curved skids, never a perfect UI circle or card bed.
    for a in [.15, 2.25, 4.3]:
        floor_arc(im[0], cx, cy, 15, a, .8, 'dark', 2)
        if strength >= .2:
            floor_arc(im[1], cx, cy, 14, a, .3 + strength * .45, 'steel', 2)
            end = a + .3 + strength * .45
            dot(im[2], cx + math.cos(end) * 14, cy + math.sin(end) * 7, 'ice')
    if developed:
        line(im[1], [(cx-4, cy+8), (cx-1, cy+10), (cx+4, cy+8)], 'silver')

def sink_fixture(im, cx, cy, strength, developed=False):
    # Mechanical accordion dampers physically cradle the bit contact.
    count = max(1, math.ceil(strength * 4))
    for sign in [-1, 1]:
        x = cx + sign * 13
        poly(im[0], [(x-4, cy+2), (x, cy), (x+4, cy+2), (x, cy+5)], 'dark')
        for k in range(count):
            y = cy - k * 3
            line(im[1], [(x-3,y+2), (x,y), (x+3,y+2)], 'brass', 2)
            line(im[2], [(x-2,y+2), (x,y+1)], 'gold' if strength > .65 else 'silver')
        if developed: dot(im[2], x, cy-count*3, 'hot')

def brace_fixture(im, cx, cy, strength, developed=False):
    for dx, dy in [(-15,-4), (15,-4), (-15,6), (15,6)]:
        x,y=cx+dx,cy+dy
        poly(im[0], [(x-4,y),(x,y-2),(x+4,y),(x,y+3)], 'dark')
        if strength >= .20:
            line(im[1], [(cx + dx*.35, cy + dy*.4), (x, y)], 'steel', 2)
            line(im[1], [(x-3,y),(x,y-1),(x+3,y)], 'silver', 2)
            if developed: line(im[2], [(x-2,y+2),(x+2,y+2)], 'gold', 2)
        if strength > .70: dot(im[2], x, y-1, 'paper')

def fixture(family, layers, x, y, strength, developed=False):
    {'gyro_lock': gyro_fixture, 'impact_sink': sink_fixture, 'anchor_exchange': brace_fixture}[family](layers,x,y,strength,developed)

def card(family, variant, key):
    layers = [blank((64,64)) for _ in range(5)]
    developed = variant != family
    phases = [0,.15,.35,.55,.75,1,1,.80,.60,.40,.15,0]
    strength = phases[key]
    x,y=29,32
    if family == 'gyro_lock':
        x = [24,25,26,27,28,29,30,31,32,33,34,35][key]
        y = [34,34,33,33,32,32,31,31,30,30,29,29][key]
        for a,b in [((6,53),(16,48)),((19,47),(28,42)),((31,42),(41,40))]: line(layers[0],[a,b],'dark',2)
        if variant == 'flywheel': floor_arc(layers[0],30,46,24,2.7,2.2,'steel')
        fixture(family,layers[:3],x,y+15,strength,developed)
        if variant == 'keel': brace_fixture(layers[:3],x,y+16,strength,True)
    elif family == 'impact_sink':
        fixture(family,layers[:3],x,y+15,strength,developed)
        rival_x = [54,52,49,46,44,46,49,51,53,54,55,56][key]
        rival_y = [15,17,19,22,24,21,18,16,14,13,12,12][key]
        top(layers[2],'breaker',rival_x,rival_y,key)
        if key in [3,4,5]: line(layers[4],[(37,33),(40,29),(43,29)],'gold',2)
        if key in [7,8,9] and variant != 'return_spring':
            for offset in [-11,11]: line(layers[4],[(x+offset,y+9),(x+offset+1,y+3),(x+offset-1,y-1)],'mint')
        if variant == 'return_spring' and key in [7,8,9]:
            floor_arc(layers[4],x,y+14,16+(key-7)*5,3.4,1.1,'gold',2)
            floor_arc(layers[4],x,y+14,16+(key-7)*5,.3,1.1,'silver',2)
    else:
        if variant == 'slip_anchor' and key >= 7: x += (key-6)*2; y -= key-6
        fixture(family,layers[:3],29,48,strength,developed)
        if variant == 'deep_footing' and strength > .5:
            line(layers[1],[(12,57),(18,58),(24,56)],'brass',2)
            line(layers[1],[(40,56),(46,58),(52,57)],'brass',2)
        if key in [4,5,6]:
            top(layers[2],'breaker',52+(key-4)*2,20-(key-4)*2,key)
            line(layers[4],[(40,32),(43,28),(47,27)],'gold',2)
    # A sparse real floor shadow; never an opaque inner square.
    ImageDraw.Draw(layers[0]).ellipse((x-10,y+14,x+11,y+18),fill=color('dark',125))
    top(layers[3],'bastion',x,y,key)
    return layers

def icon(family, variant):
    layers=[blank((16,16)) for _ in range(3)]
    developed=variant != family
    if family == 'gyro_lock':
        for start in [.1,2.2,4.3]: floor_arc(layers[0],8,9,6,start,1.3,'steel',2)
        poly(layers[1],[(5,6),(8,4),(11,6),(11,9),(8,11),(5,9)],'sea')
        line(layers[2],[(6,6),(8,5),(10,6)],'ice')
        if variant == 'keel': line(layers[2],[(4,13),(8,15),(12,13)],'gold',2)
        if variant == 'flywheel': line(layers[2],[(11,1),(14,4),(12,6)],'mint',2)
    elif family == 'impact_sink':
        for x in [3,12]:
            for y in [4,7,10]: line(layers[0],[(x-2,y+1),(x,y-1),(x+2,y+1)],'brass',2)
        line(layers[1],[(5,11),(8,13),(11,11)],'silver',2)
        if variant == 'shock_bleed': line(layers[2],[(7,2),(8,5),(7,8)],'mint',2)
        elif variant == 'return_spring': line(layers[2],[(7,6),(8,3),(9,6)],'hot',2)
        else: dot(layers[2],8,6,'gold')
    else:
        for x,y in [(3,5),(12,5),(3,12),(12,12)]: poly(layers[0],[(x-2,y),(x,y-1),(x+2,y),(x,y+2)],'steel')
        line(layers[1],[(4,6),(8,8),(11,6)],'silver',2)
        line(layers[1],[(4,11),(8,8),(11,11)],'silver',2)
        if variant == 'slip_anchor': line(layers[2],[(10,1),(14,3),(12,5)],'mint',2)
        elif variant == 'deep_footing': line(layers[2],[(5,14),(10,14)],'gold',2)
        else: dot(layers[2],8,8,'gold')
    if developed: dot(layers[2],14,14,'paper')
    return layers

def fx(family, tag, key):
    layers=[blank((96,80)) for _ in range(4)]
    active=tag in ['lock','stored','brace']
    strength=key/7 if active or tag == 'engage' else (7-key)/7
    fixture(family,layers[:3],48,48,strength,True)
    if tag in ['vent','return']:
        if tag == 'vent':
            for x in [33,63]: line(layers[3],[(x,47-key),(x+1,42-key),(x-1,38-key)],'mint',max(1,2-key//4))
        else:
            radius=12+key*4
            for start in [.3,2.4,4.5]: floor_arc(layers[3],48,48,radius,start,.8,'gold',2)
    elif tag == 'release' and key >= 3:
        # Release retracts the exact fixture towards its real contact pivot.
        for x in [35,61]: line(layers[3],[(x,53),(x+(1 if x<48 else -1)*3,51)],'steel')

    if not active and key == 7: return [blank((96,80)) for _ in range(4)]
    return layers

def author():
    SOURCE.mkdir(parents=True,exist_ok=True)
    for family,variants in FAMILIES.items():
        cards=[]; tags=[]
        for variant in variants:
            first=len(cards)
            cards.extend(card(family,variant,k) for k in range(12))
            tags.append((variant,first,len(cards)-1))
        write_ase(SOURCE/f'{family}_cards.aseprite',cards,
                  ['01 real floor tracks','02 physical fittings','03 incoming machine','04 accepted native defender','05 contact and release'],
                  tags,[80,80,80,60,60,80,110,80,80,80,100,130]*4,(32,32),
                  'Final003A: distinct active defence; exact accepted top parts; transparent card field')
        write_ase(SOURCE/f'{family}_icons.aseprite',[icon(family,v) for v in variants],
                  ['01 independent silhouette','02 mechanism','03 branch identity'],[(v,i,i) for i,v in enumerate(variants)],
                  [100]*4,(8,8),'Final003A: independently authored sixteen pixel HUD icons')
        names={'gyro_lock':['lock','engage','release'],'impact_sink':['stored','engage','vent','return'],
               'anchor_exchange':['brace','engage','release']}[family]
        frames=[]; tags=[]
        for tag in names:
            first=len(frames);frames.extend(fx(family,tag,k) for k in range(8));tags.append((tag,first,len(frames)-1))
        write_ase(SOURCE/f'{family}_fx.aseprite',frames,
                  ['01 floor contact','02 mechanism and skids','03 charge fittings','04 finite release'],tags,
                  [45,45,45,45,55,65,75,90]*len(names),(48,48),
                  'Final003A: fixed-isometric contact pivot; eight discrete keyed poses; no runtime texture generation')

def export(aseprite,check=False):
    OUT.mkdir(parents=True,exist_ok=True)
    manifest={'version':1,'filter':'nearest','families':{},'art':{},'events':EVENTS,
              'scope':'Native artist-editable active defence; no accepted family changes'}
    for family,variants in FAMILIES.items():
        info={}
        for group,cell,pivot,columns,count in [('cards',(64,64),(32,32),12,12),('icons',(16,16),(8,8),4,1),('fx',(96,80),(48,48),8,8)]:
            source=SOURCE/f'{family}_{group}.aseprite'; frames,meta=read_ase(source)
            assert tuple(meta['cell'])==cell and tuple(meta['pivot'])==pivot
            assert len(meta['layers']) >= 3 and len(set(meta['layers']))==len(meta['layers'])
            assert all(v['to']-v['from']+1==count for v in meta['tags'].values())
            with tempfile.TemporaryDirectory() as temp:
                native=Path(temp)/'native.png'
                subprocess.run([str(aseprite),'-b',str(source),'--sheet-columns',str(columns),'--sheet',str(native)],check=True,capture_output=True)
                sheet=Image.open(native).convert('RGBA')
                assert sheet.size==(cell[0]*columns,cell[1]*math.ceil(len(frames)/columns))
                for index,frame in enumerate(frames):
                    actual=sheet.crop((index%columns*cell[0],index//columns*cell[1],index%columns*cell[0]+cell[0],index//columns*cell[1]+cell[1]))
                    a,b=frame.tobytes(),actual.tobytes()
                    assert all(a[k:k+4]==b[k:k+4] for k in range(0,len(a),4) if a[k+3] or b[k+3]),(family,group,index,'native parity')
                destination=OUT/f'{family}_{group}.png'
                if check:
                    old=Image.open(destination).convert('RGBA')
                    assert old.tobytes()==sheet.tobytes(),(family,group,'runtime pixels stale')
                else: destination.write_bytes(native.read_bytes())
            meta.update(columns=columns,frame_count=len(frames),source=str(source.relative_to(ROOT)).replace('\\','/'),
                        texture='res://'+str(destination.relative_to(ROOT)).replace('\\','/'),
                        source_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
            info[group]=meta
        manifest['families'][family]=info
        for variant in variants:
            span=info['cards']['tags'][variant]
            manifest['art'][variant]={'family':family,'art_id':variant,'source_tag':variant,
                'icon':info['icons']['texture'],'icon_frame':info['icons']['tags'][variant]['from'],
                'card_texture':info['cards']['texture'],'card_row':span['from']//12,'card_cell':64,
                'card_frames':12,'card_static_frame':5,'card_durations_ms':info['cards']['durations_ms'][span['from']:span['to']+1]}
        print(f'{family}: saved source parity; {len(variants)} independent card/icon states, {len(info["fx"]["tags"])} keyed FX states')
    path=OUT/'manifest.json'
    if check: assert json.loads(path.read_text(encoding='utf-8'))==manifest,'manifest stale'
    else: path.write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--author',action='store_true')
    parser.add_argument('--check',action='store_true')
    parser.add_argument('--aseprite',type=Path,default=Path(r'F:\SteamLibrary\steamapps\common\Aseprite\Aseprite.exe'))
    args=parser.parse_args()
    if args.author: author()
    export(args.aseprite,args.check)

if __name__=='__main__': main()
