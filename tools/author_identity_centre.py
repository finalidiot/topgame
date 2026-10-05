"""Centre correction: accepted native top anatomy, floor load and real contact.

Historical Centre cards/FX were inspected: their legs/cylinder cannot satisfy
the revised physical-event brief. This recipe copies accepted Bastion/Breaker
blade/ratchet/bit pixels, replacing the surrounding hardware with floor load.
Saved named-layer Aseprite masters remain the normal export authority.
"""
import argparse, json
from pathlib import Path
from PIL import Image, ImageDraw, ImageOps
from build_power_art import write_ase, read_ase
from author_identity_core import top, shadow, tiny_top, line, dot, card_layers, P, HEADINGS

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'assets/source-art/power_identity_002c5'
OUT=ROOT/'assets/powers/identity'
STATES=['dead_centre','dead_centre_ii','bulwark','counterweight']
NAMES=['Arena floor and contact bed','Physical bit pressure and displacement',
       'Accepted native top bodies','Accepted incoming rival','Floor bite and contact reaction']
POSE_MS=[220,160,280,110,170,260]

def pressure(im,x,y,stage,heavy=False):
    # Unequal cracked floor seams originate at the real bit. No hardware,
    # box, feet, circle or independently orbiting motif surrounds the top.
    line(im,[(x-6,y+2),(x-3,y+1),(x,y)],'steel')
    if stage>=2:
        line(im,[(x-2,y+2),(x+2,y+2)],'ink',2)
        line(im,[(x+2,y+2),(x+6,y+3),(x+9,y+2)],'silver')
    if stage>=4:
        line(im,[(x-2,y+3),(x-5,y+5),(x-10,y+6)],'dark',2)
        line(im,[(x-2,y+3),(x-5,y+5),(x-9,y+6)],'silver')
    if stage>=5:dot(im,x+3,y+5,'paper')
    if heavy and stage>=3:
        line(im,[(x+5,y+3),(x+8,y+5),(x+11,y+5)],'steel')
        dot(im,x+11,y+5,'silver');dot(im,x-7,y+4,'silver')

def card(state,p):
    im=card_layers();strong=state!='dead_centre'
    counter=state=='counterweight';bulwark=state=='bulwark'
    own=(23,29+[0,1,3,3,2,2][p]) if counter else (32,27+[0,1,3,3,2,2][p])
    if bulwark:own=(27,30+[0,1,2,2,2,2][p])
    x,y=own;contact=y+16
    line(im[0],[(6,46),(28,34),(57,47)],'floor')
    line(im[0],[(13,58),(33,47),(57,55)],'dark')
    shadow(im[1],x,y,15);pressure(im[1],x,contact,[1,3,7,7,6,5][p],strong)
    if p in [1,2]:
        for dx,dy in [(-9,1),(8,0),(4,6)]:dot(im[4],x+dx,contact+dy,'silver')
    top(im[2],'bastion',x,y,[0,1,2,3,5,7][p])
    if counter or bulwark:
        rival=([(56,18),(48,23),(42,27),(44,24),(51,18),(57,14)] if counter else
               [(55,18),(48,22),(44,25),(47,22),(52,17),(55,15)])[p]
        rx,ry=rival
        line(im[1],[(59,34),(51,33),(43,33)],'red')
        if p>=3:
            line(im[1],[(39,35),(47,29),(56,22)],'gold' if counter else 'steel')
            if counter:line(im[1],[(41,38),(49,31)],'brass')
        top(im[3],'breaker',rx,ry,[0,1,3,4,6,7][p])
        if p in [1,2,3]:
            cx,cy=(36,29) if counter else (39,29)
            line(im[4],[(cx-2,cy+2),(cx,cy),(cx+2,cy-2)],'paper',2)
            if p==2:dot(im[4],cx,cy,'white')
            if counter and p==3:
                line(im[4],[(cx+1,cy),(cx+5,cy-3)],'gold',2)
        if counter and p==2:
            # Load stays in the struck rotor and its bit, never a spring box.
            line(im[4],[(x+10,y+5),(x+12,y+3)],'gold',2)
    return im

def icon(state):
    ims=[Image.new('RGBA',(16,16)) for _ in range(2)]
    tiny_top(ims[0],7,6,5,'steel')
    line(ims[1],[(7,9),(7,12)],'silver')
    line(ims[1],[(3,14),(6,13),(8,13),(11,14)],'steel')
    if state=='dead_centre_ii':dot(ims[1],7,14,'paper');dot(ims[1],12,13,'silver')
    if state=='bulwark':line(ims[1],[(14,3),(12,5),(11,7)],'hot',2)
    if state=='counterweight':line(ims[1],[(11,11),(14,9)],'gold',2);dot(ims[1],14,8,'paper')
    return ims

TAGS=['ground_lock','ground_lock_ii','bulwark_lock','bulwark_impact','jaw_break',
      'counterweight_store','counterweight_release']+['counterweight_release_'+h for h in HEADINGS]

def fx(tag,k):
    ims=[Image.new('RGBA',(96,80)) for _ in NAMES]
    if tag.startswith('counterweight_release'):
        dx,dy=HEADINGS.get(tag.rsplit('_',1)[-1],HEADINGS['ne'])
        tx,ty=-dy,dx
        distance=[0,2,5,8,12,16,21,27][k]
        if k<7:
            for j in range(3 if k<4 else 2):
                x=48+dx*distance+tx*(j-1)*4;y=48+dy*distance+ty*(j-1)*4
                line(ims[4],[(x-dx*2,y-dy*2),(x+dx*2,y+dy*2)],'gold' if k<4 else 'brass')
        return ims
    if tag=='jaw_break':
        if k<6:
            for j,(dx,dy) in enumerate([(-1,.5),(1,.2),(.3,1)]):
                x=48+dx*(4+k*2);y=48+dy*(2+k)
                line(ims[4],[(x,y),(x+dx*2,y+dy)],'steel' if k<3 else 'dark')
        return ims
    strong=tag in ['ground_lock_ii','bulwark_lock','bulwark_impact']
    pressure(ims[1],48,48,k,strong)
    if tag=='bulwark_impact' and k<6:
        line(ims[4],[(42-k,47-k*.4),(40-k,45-k*.4)],'paper' if k<3 else 'steel')
        if k in [1,2]:dot(ims[4],44,46,'white')
    if tag=='counterweight_store' and k>0:
        line(ims[4],[(49,49),(51+k*.3,48),(53+k*.3,46)],'gold' if k>3 else 'brass')
        if k>=5:dot(ims[4],51,48,'paper')
    return ims

def author():
    frames=[];tags=[];times=[]
    for state in STATES:
        start=len(frames)
        for p,d in enumerate(POSE_MS):
            cells=card(state,p)
            for hold in [d//2,d-d//2]:frames.append([c.copy() for c in cells]);times.append(hold)
        tags.append((state,start,len(frames)-1))
    write_ase(SOURCE/'dead_centre_cards.aseprite',frames,NAMES,tags,times,(32,32),
              note='Human correction: six held physical top/load/contact poses; exact accepted native body pixels; no clamp or cylinder',palette=P)
    write_ase(SOURCE/'dead_centre_icons.aseprite',[icon(s) for s in STATES],
              ['Independent planted top silhouette','Bit contact and mutation response'],
              [(s,i,i) for i,s in enumerate(STATES)],[120]*4,(8,8),note='Native16px planted bit silhouette; never shrunk card',palette=P)
    frames=[];tags=[];times=[]
    for tag in TAGS:
        start=len(frames);frames.extend(fx(tag,k) for k in range(8));tags.append((tag,start,len(frames)-1))
        times.extend([130,90,70,70,80,90,110,140])
    write_ase(SOURCE/'dead_centre_fx.aseprite',frames,NAMES,tags,times,(48,48),
              note='Actual charge-stage bit/floor compression; finite contact and directed counterstroke; no hardware or runtime top substitution',palette=P)
    design={'family':'dead_centre','correction':'Human final review extended correction to clamp-like Centre',
      'grammar':{'silhouette':'Recognizable heavy spinning top pressing its bit into fractured arena floor',
                 'motion':'Settles under load; planted contact holds, Counterweight returns the accepted strike',
                 'location':'Actual bit and floor; finite accepted-contact and counterstroke direction',
                 'persistence':'Existing anchor and stored-force stages; bounded paid impact/release',
                 'palette':'Accepted Bastion steel, sparse floor silver and restrained amber counterstroke',
                 'feature':'Floor load and real rotor survival without clamp legs, platform or spring cylinder'},
      'event_tags':{'anchor':'ground_lock','anchor_ii':'ground_lock_ii','anchor_break':'jaw_break',
                    'bulwark_impact':'bulwark_impact','counterweight_store':'counterweight_store','counterweight_release':'counterweight_release'},
      'active_tags':{'anchor':'ground_lock','anchor_ii':'ground_lock_ii','bulwark':'bulwark_lock','counterweight':'counterweight_store'},
      'static_frames':{s:4 for s in STATES},
      'notes':['All historical Centre card/icon/FX sources inspected; older four legs and spring box were not restored.',
               'Card subject uses accepted native Bastion/Breaker blade, ratchet and bit without resampling.',
               'Six excellent top/load/contact poses held twice; saved editable masters are export authority.',
               'FX show uneven physical floor seams at the actual bit with charge-stage intensity; no platform.',
               'Bulwark remains planted after incoming contact; Counterweight returns actual accepted force.',
               'No mechanics, charge, RPM, positions, timers or target selection changed.']}
    (OUT/'dead_centre_design.json').write_text(json.dumps(design,indent=2)+'\n',encoding='utf-8')

def preview(out):
    out.mkdir(parents=True,exist_ok=True)
    sheet=Image.new('RGB',(800,360),'#17242d');d=ImageDraw.Draw(sheet)
    for row,s in enumerate(STATES):
        d.text((4,row*90+5),s,fill='white')
        for p in range(6):
            cell=Image.new('RGBA',(64,64))
            for layer in card(s,p):cell.alpha_composite(layer)
            sheet.paste(cell,(130+p*100,row*90+8),cell)
    sheet.save(out/'centre-native-card-keys.png');ImageOps.grayscale(sheet).save(out/'centre-native-card-keys-gray.png')
    sheet=Image.new('RGB',(1000,len(TAGS)*90),'#37434b');d=ImageDraw.Draw(sheet)
    for row,tag in enumerate(TAGS):
        d.text((4,row*90+8),tag,fill='white')
        for k in range(8):
            cell=Image.new('RGBA',(96,80))
            for layer in fx(tag,k):cell.alpha_composite(layer)
            top(cell,'bastion',48,32,k%8)
            sheet.paste(cell,(200+k*98,row*90+3),cell)
    sheet.save(out/'centre-native-fx-live-top.png');ImageOps.grayscale(sheet).save(out/'centre-native-fx-live-top-gray.png')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--replace-authored',action='store_true');p.add_argument('--review-dir',type=Path);args=p.parse_args()
    if not args.replace_authored:raise SystemExit('Explicit --replace-authored required; normal exports preserve saved artist masters.')
    author()
    if args.review_dir:preview(args.review_dir)
