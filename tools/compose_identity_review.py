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

def art_cels(meta, art_id):
    art = meta['art'][art_id]
    frame, row = art['card_static_frame'], art['card_row']
    card = texture(art['card_texture']).crop((frame*64,row*64,(frame+1)*64,(row+1)*64))
    icon = texture(art['icon']).crop((art['icon_frame']*16,0,(art['icon_frame']+1)*16,16))
    return card, icon

def paste_alpha(canvas, image, at):
    canvas.paste(image, at, image)

def matrix(meta, captures, out):
    canvas = Image.new('RGB',(974,2750), BG)
    d = ImageDraw.Draw(canvas)
    d.text((14,12),'002C.5 / FULL POWER IDENTITY REVIEW',font=BIG,fill='#e4ebd6')
    d.text((14,39),'Native 64px cards / independent 16px icons / native 192x112 arena crops',font=FONT,fill='#bbc8cf')
    d.text((14,58),'Arena states are explicitly posed visual QA; motion/procs are reviewed separately.',font=FONT,fill='#bbc8cf')
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
            image = Image.open(captures / (art_id+'_gameplay.png')).convert('RGB')
            assert image.size == (192,112)
            canvas.paste(image,(x,y+78))
    canvas.save(out / '002c5_power_visual_matrix.png')
    ImageOps.grayscale(canvas).convert('RGB').save(out / '002c5_power_visual_matrix_grayscale.png')

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
    args=p.parse_args();args.out.mkdir(parents=True,exist_ok=True)
    meta=json.loads((ROOT/'assets/powers/identity_manifest.json').read_text())
    assert len(meta['families'])==13 and len(meta['art'])==34
    matrix(meta,args.captures,args.out);before_after(meta,args.before,args.captures,args.out)
    print('Native review matrices composed: 13 families, 34 states; no art resampling in matrix.')

if __name__=='__main__': main()
