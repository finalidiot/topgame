"""Narrow native Breakneck correction; unrelated redline tags stay byte exact."""
from __future__ import annotations
import argparse, hashlib, json, struct, subprocess, sys
from pathlib import Path
import zlib
from PIL import Image, ImageDraw
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
sys.path.insert(0, str(ROOT / 'tools/art'))
from build_power_art import read_ase
from final_acceptance_cards import split, join
from export_power_identity import export_family, main as export_main
SOURCE = ROOT / 'assets/source-art/power_identity_002c5/redline_cards.aseprite'
EXPECTED = '72f8ec978af6db0b21e66bac67cc2bc4b7256caa95a727bd28bbd93ff7d760fe'
PATH = [(20,36),(20,36),(20,37),(20,37),(22,35),(31,30),(43,24),(44,24),(41,26),(35,30),(28,34),(21,38)]

def cel_image(payload):
    assert struct.unpack_from('<HhhBHh', payload)[1:5] == (0,0,255,2)
    assert struct.unpack_from('<HH', payload,16) == (64,64)
    return Image.frombytes('RGBA',(64,64),zlib.decompress(payload[20:]))

def correction(data):
    header, frames = split(data)
    templates = {}
    for key in range(12):
        for kind, payload in frames[key][1]:
            if kind == 0x2005:
                layer = struct.unpack_from('<H',payload)[0]
                if layer in [1,2]: templates[key,layer] = cel_image(payload)
    for key in range(12):
        x,y = PATH[key]
        chunks = frames[36+key][1]
        for i,(kind,payload) in enumerate(chunks):
            if kind != 0x2005: continue
            layer = struct.unpack_from('<H',payload)[0]
            if layer == 0: continue
            out = Image.new('RGBA',(64,64))
            if layer in [1,2]:
                # Copy the accepted single native Redline machine, never an
                # interpolated redraw. The former second chassis is removed.
                out.paste(templates[key,layer],(x-38,y-31))
            elif layer == 3:
                draw = ImageDraw.Draw(out)
                length = [4,5,6,7,12,24,30,25,17,10,5,3][key]
                alpha = [85,100,115,135,185,235,250,220,160,115,70,40][key]
                # Two coherent tails lie strictly behind the machine's rear.
                # Their integer charge vector matches the moving top.
                for bank in [-1,1]:
                    end = (x-15,y+7+bank*4)
                    start = (max(2,end[0]-length),end[1]+round(length*.5))
                    fade = alpha / 255.0
                    ink = tuple(round(a+(b-a)*fade) for a,b in zip((43,59,70),(237,101,76)))+(255,)
                    draw.line([start,end],fill=ink,width=1)
                    if key in [5,6,7]:
                        middle = (round((start[0]+end[0])*.5),round((start[1]+end[1])*.5))
                        draw.line([middle,end],fill=(243,195,106,255),width=2)
            elif layer == 4:
                if key in [6,7]:
                    draw = ImageDraw.Draw(out)
                    ink = (243,195,106,255) if key == 6 else (173,146,98,255)
                    # One keyed impact fan at the front edge: one huge strike.
                    origin = (55,20)
                    for end in [(60,13),(62,19),(61,25)]:
                        draw.line([origin,end],fill=ink,width=1)
                    draw.line([(52,22),origin,(59,17)],fill=(227,232,220,255),width=2)
            chunks[i] = (kind,payload[:20]+zlib.compress(out.tobytes(),9))
    return join(header,frames)

def author(proof_path):
    assert not proof_path.exists(),'Preserve earlier evidence'
    before = SOURCE.read_bytes(); assert hashlib.sha256(before).hexdigest()==EXPECTED,'Expected accepted untouched master'
    _, old = split(before); _, old_meta = read_ase(SOURCE)
    after = correction(before); _, new = split(after)
    for index,((_,a),(_,b)) in enumerate(zip(old,new)):
        for (kind,payload),(new_kind,new_payload) in zip(a,b):
            assert kind==new_kind
            allowed = index>=36 and kind==0x2005 and struct.unpack_from('<H',payload)[0] in [1,2,3,4]
            assert allowed or payload==new_payload,('Unrelated native bytes changed',index,kind)
    SOURCE.write_bytes(after); _, meta=read_ase(SOURCE)
    for key in ['cell','pivot','tags','durations_ms','layers']:assert old_meta[key]==meta[key],key
    proof_path.parent.mkdir(parents=True,exist_ok=True)
    proof_path.write_text(json.dumps({'source':str(SOURCE),'before_sha256':EXPECTED,'after_sha256':hashlib.sha256(after).hexdigest(),'only_breakneck_body_action_highlights_changed':True,'all_other_native_chunks_unchanged':True,'topology_preserved':True,'path':PATH,'story':'One accepted native top, two charge-aligned tapering streaks, one contact fan; no static opponent.'},indent=2)+'\n')

def main():
    p=argparse.ArgumentParser();p.add_argument('--author',action='store_true');p.add_argument('--proof',type=Path);p.add_argument('--aseprite',default=r'F:\SteamLibrary\steamapps\common\Aseprite\Aseprite.exe');p.add_argument('--qa-image',type=Path);args=p.parse_args()
    if args.author:
        assert args.proof;author(args.proof)
    # Existing authoritative exporter verifies every native cel and writes
    # complete family/aggregate metadata, leaving icons/FX pixels unchanged.
    sys.argv=['export_power_identity.py','--family','redline','--aseprite',args.aseprite]
    export_main()
    if args.qa_image:
        assert not args.qa_image.exists(),'Preserve earlier review image'
        sheet=Image.open(ROOT/'assets/powers/identity/redline_cards.png').convert('RGBA')
        row=sheet.crop((0,192,768,256));row.save(args.qa_image)
    print('BREAKNECK_CARD_NATIVE_PARITY_PASS')
if __name__=='__main__':main()
