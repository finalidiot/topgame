"""Compose native-size authored art and explicitly posed arena QA captures."""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[1]
NAMES = {'impact_wake':'Impact Wake', 'redline':'Redline', 'iron_comet':'Iron Comet',
         'dead_centre':'Dead Centre', 'afterimage':'Afterimage', 'chain_impact':'Chain Impact',
         'clutch':'Clutch', 'high_gear':'High Gear', 'orbit_drive':'Orbit Drive',
         'crash_guard':'Crash Guard', 'momentum_bank':'Momentum Bank',
         'predator_line':'Predator Line', 'crosscut':'Crosscut'}
BRANCHES = {'redline':['runaway','breakneck'], 'dead_centre':['bulwark','counterweight'],
            'afterimage':['ghost_circuit','slipstream'], 'high_gear':['terminal_velocity','flow_state']}
FONT = ImageFont.truetype('C:/Windows/Fonts/consola.ttf', 12)
BIG = ImageFont.truetype('C:/Windows/Fonts/consolab.ttf', 17)
BG = '#111b24'

def texture(path):
    return Image.open(ROOT / path.removeprefix('res://')).convert('RGBA')

def art_cels(meta, art_id, root=ROOT):
    art = meta['art'][art_id]
    frame, row = art['card_static_frame'], art['card_row']
    card = Image.open(root/art['card_texture'].removeprefix('res://')).convert('RGBA').crop((frame*64,row*64,(frame+1)*64,(row+1)*64))
    icon = Image.open(root/art['icon'].removeprefix('res://')).convert('RGBA').crop((art['icon_frame']*16,0,(art['icon_frame']+1)*16,16))
    return card, icon

def paste_alpha(canvas, image, at):
    canvas.paste(image, at, image)

def actual_crop(motion,selection,at):
    from compose_identity_motion import image_at
    run=json.loads((motion/(selection+'.json')).read_text())['runs'][0]
    sample=min(run['rows'],key=lambda r:abs(r['time']-(run['actual_start']+at)))
    px,py=sample['position'];cx=round(320+px-py);cy=round(153+(px+py)*.5)
    cx=max(96,min(544,cx));cy=max(56,min(304,cy))
    native=image_at(motion/(selection+'.avi'),at).resize((640,360),Image.Resampling.NEAREST)
    return native.crop((cx-96,cy-56,cx+96,cy+56)),{'selection':selection,'source':str(motion/(selection+'.avi')),
        'actual_time':run['actual_start']+at,'rank':run['preset']['rank'],'seed':run['preset']['seed'],
        'pixel_operation':'Native integer2x capture restored to logical640x360 by nearest; crop192x112. No visual state edits.'}

def matrix(meta, captures, out, motion=None):
    canvas = Image.new('RGB',(974,2750), BG)
    d = ImageDraw.Draw(canvas)
    d.text((14,12),'002C.5 / FULL POWER IDENTITY REVIEW',font=BIG,fill='#e4ebd6')
    d.text((14,39),'Native 64px cards / independent 16px icons / native 192x112 arena crops',font=FONT,fill='#bbc8cf')
    d.text((14,58),'Combat: real input-only Rank II cores / Rank III mutations. Rank I cards compare art.' if motion else
           'Arena states are explicitly posed visual QA; motion/procs are reviewed separately.',font=FONT,fill='#bbc8cf')
    review={r['selection']:r['review_at'] for r in json.loads((out/'motion-review-index.json').read_text())} if motion else {}
    records=[]
    for row, family in enumerate(NAMES):
        y = 93 + row*203
        d.rectangle((8,y,965,y+197),outline='#344958')
        d.text((16,y+14),NAMES[family].replace(' ','\n'),font=BIG,fill='#e4ebd6')
        states = [family, family+'_ii'] + BRANCHES.get(family,[])
        for col, art_id in enumerate(states):
            x = 146 + col*204
            card, icon = art_cels(meta, art_id)
            paste_alpha(canvas,card,(x,y+7)); paste_alpha(canvas,icon,(x+75,y+15))
            label = ['RANK I','RANK II'][col] if col < 2 else art_id.replace('_',' ').upper()
            # Long mutation names use two plain lines without changing art scale.
            words = label.split(' ')
            if len(label)>15: label = '\n'.join([' '.join(words[:1]),' '.join(words[1:])])
            d.text((x+73,y+36),label,font=FONT,fill='#d4b886')
            if motion:
                selection=family if col<2 else art_id
                at=max(.05,float(review[selection])-.1) if col==0 else min(5.8,float(review[selection])+.1)
                if selection=='momentum_bank' and col==0:at=1.02  # Actual earned low-charge hold, before real release.
                if selection=='iron_comet' and col==1:at=1.37  # Actual rival strike, alongside the earlier wall-charge crop.
                if selection=='bulwark':at=.55  # Actual accepted incoming impact, not an earlier anchor tick.
                if selection=='counterweight':at=.683  # Actual release after stored contact force.
                image,record=actual_crop(motion,selection,at);record['card_state']=art_id;records.append(record)
            else:image = Image.open(captures / (art_id+'_gameplay.png')).convert('RGB')
            assert image.size == (192,112)
            canvas.paste(image,(x,y+78))
    canvas.save(out / '002c5_power_visual_matrix.png')
    ImageOps.grayscale(canvas).convert('RGB').save(out / '002c5_power_visual_matrix_grayscale.png')
    if motion:(out/'matrix-gameplay-provenance.json').write_text(json.dumps(records,indent=2)+'\n')

def before_after(meta, before, captures, out):
    old = json.loads((before/'snapshot/assets/powers/roster_manifest.json').read_text())
    old_cards = Image.open(before/'snapshot/assets/powers/roster_cards.png').convert('RGBA')
    old_icons = Image.open(before/'snapshot/assets/powers/roster_icons.png').convert('RGBA')
    canvas = Image.new('RGB',(680,530),BG); d = ImageDraw.Draw(canvas)
    d.text((12,12),'BEFORE / AFTER — RANK II',font=BIG,fill='#e4ebd6')
    d.text((12,38),'Card/icon art at 2x nearest. After arena crops at native scale.',font=FONT,fill='#bbc8cf')
    d.text((171,62),'BEFORE d882923',font=FONT,fill='#bbc8cf')
    d.text((341,62),'AFTER / NATIVE SOURCES',font=FONT,fill='#d4b886')
    for row,family in enumerate(['momentum_bank','predator_line','iron_comet']):
        art_id = family+'_ii'; y=88+row*145
        d.text((12,y+22),NAMES[family].replace(' ','\n'),font=BIG,fill='#e4ebd6')
        span=old['cards']['tags'][art_id]; old_row=int(span['from'])//6
        card=old_cards.crop((3*64,old_row*64,4*64,(old_row+1)*64))
        ix=int(old['icons']['tags'][art_id]['from']); icon=old_icons.crop((ix*16,0,(ix+1)*16,16))
        paste_alpha(canvas,card.resize((128,128),Image.Resampling.NEAREST),(169,y))
        paste_alpha(canvas,icon.resize((32,32),Image.Resampling.NEAREST),(303,y+12))
        card,icon=art_cels(meta,art_id)
        paste_alpha(canvas,card.resize((128,128),Image.Resampling.NEAREST),(343,y))
        paste_alpha(canvas,icon.resize((32,32),Image.Resampling.NEAREST),(480,y+5))
        runtime=Image.open(captures/(art_id+'_gameplay.png')).convert('RGB')
        canvas.paste(runtime,(480,y+37))
    canvas.save(out/'002c5_power_before_after.png')
    ImageOps.grayscale(canvas).convert('RGB').save(out/'002c5_power_before_after_grayscale.png')

def main():
    p=argparse.ArgumentParser();p.add_argument('--captures',type=Path,required=True)
    p.add_argument('--before',type=Path,required=True);p.add_argument('--out',type=Path,required=True)
    p.add_argument('--correction-v2',action='store_true');p.add_argument('--motion',type=Path)
    args=p.parse_args();args.out.mkdir(parents=True,exist_ok=True)
    meta=json.loads((ROOT/'assets/powers/identity_manifest.json').read_text())
    assert len(meta['families'])==13 and len(meta['art'])==34
    matrix(meta,args.captures,args.out,args.motion)
    if args.correction_v2:focused_correction(meta,args.before,args.captures,args.out,args.motion)
    else:before_after(meta,args.before,args.captures,args.out)
    print('Native review matrices composed: 13 families, 34 states; no art resampling in matrix.')

def focused_correction(meta,before,captures,out,motion=None):
    rejected_root=before/'snapshot'
    old=json.loads((rejected_root/'assets/powers/identity_manifest.json').read_text())
    families=['chain_impact','clutch','high_gear','orbit_drive','crash_guard','momentum_bank','predator_line','iron_comet','crosscut','dead_centre']
    canvas=Image.new('RGB',(1060,67+len(families)*168+21),BG);d=ImageDraw.Draw(canvas)
    d.text((14,10),'002C.5 / HUMAN CORRECTION / BEFORE d0d37e5 → CORRECTED',font=BIG,fill='#e4ebd6')
    d.text((14,36),'Card64px/icon16px actual scale. Combat192x112: real Rank II inputs.' if motion else
           'Every card64px / icon16px at actual scale. Corrected arena crops192x112 native. No art enlargement.',font=FONT,fill='#bbc8cf')
    review={r['selection']:r['review_at'] for r in json.loads((out/'motion-review-index.json').read_text())} if motion else {}
    for row,family in enumerate(families):
        y=67+row*168;d.text((10,y+20),NAMES[family].replace(' ','\n'),font=BIG,fill='#e4ebd6')
        for col,art_id in enumerate([family,family+'_ii']):
            x=153+col*445
            d.text((x,y),['RANK I','RANK II'][col]+' / BEFORE → AFTER',font=FONT,fill='#d4b886')
            card,icon=art_cels(old,art_id,rejected_root)
            paste_alpha(canvas,card,(x,y+23));paste_alpha(canvas,icon,(x+70,y+32))
            card,icon=art_cels(meta,art_id)
            paste_alpha(canvas,card,(x+102,y+23));paste_alpha(canvas,icon,(x+172,y+32))
            if motion:
                at=1.02 if family=='momentum_bank' and col==0 else min(5.8,float(review[family])+.1)
                arena,_=actual_crop(motion,family,at)
            else:arena=Image.open(captures/(art_id+'_gameplay.png')).convert('RGB')
            assert arena.size==(192,112)
            canvas.paste(arena,(x+213,y+23))
        d.line((8,y+158,1051,y+158),fill='#344958')
    canvas.save(out/'002c5_power_before_after_v2.png')
    ImageOps.grayscale(canvas).convert('RGB').save(out/'002c5_power_before_after_v2_grayscale.png')

if __name__=='__main__': main()
