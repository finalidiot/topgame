"""Verify historical Chain pixels/timing and native source restoration."""
import argparse, hashlib, json, subprocess, tempfile
from pathlib import Path
from PIL import Image
from build_power_art import read_ase
ROOT=Path(__file__).resolve().parents[1]
ASE=r'F:\SteamLibrary\steamapps\common\Aseprite\Aseprite.exe'
def native_frames(path,columns):
    frames,meta=read_ase(path)
    with tempfile.TemporaryDirectory() as temp:
        file=Path(temp)/'sheet.png'
        subprocess.run([ASE,'-b',str(path),'--sheet-columns',str(columns),'--sheet',str(file)],capture_output=True,check=True)
        sheet=Image.open(file).convert('RGBA');w,h=meta['cell']
        return [sheet.crop((i%columns*w,i//columns*h,(i%columns+1)*w,(i//columns+1)*h)) for i in range(len(frames))],meta
def visible_equal(a,b):
    aa,bb=a.tobytes(),b.tobytes()
    return all(aa[i:i+4]==bb[i:i+4] for i in range(0,len(aa),4) if aa[i+3] or bb[i+3])
def main():
    p=argparse.ArgumentParser();p.add_argument('--out',type=Path,required=True);args=p.parse_args()
    oldcards,oldmeta=native_frames(ROOT/'assets/source-art/power_cards_002b1.aseprite',6)
    cards,cm=native_frames(ROOT/'assets/source-art/power_identity_002c5/chain_impact_cards.aseprite',12)
    oldicons,oi=native_frames(ROOT/'assets/source-art/power_icons_002b.aseprite',6)
    icons,im=native_frames(ROOT/'assets/source-art/power_identity_002c5/chain_impact_icons.aseprite',2)
    start=int(oldmeta['tags']['chain_impact']['from'])
    assert all(visible_equal(cards[i],oldcards[start+i//2]) for i in range(12))
    assert all(sum(cm['durations_ms'][i*2:i*2+2])==oldmeta['durations_ms'][start+i] for i in range(6))
    assert visible_equal(icons[0],oldicons[oi['tags']['chain_impact']['from']])
    preserved=[]
    for path in ['assets/source-art/power_cards_002b1.aseprite','assets/source-art/power_icons_002b.aseprite','assets/source-art/power_fx_002b.aseprite']:
        old=subprocess.check_output(['git','show','bdcc24e:'+path],cwd=ROOT)
        assert old==(ROOT/path).read_bytes()
        preserved.append({'path':path,'sha256':hashlib.sha256(old).hexdigest()})
    result={'status':'pass','historical_commit':subprocess.check_output(['git','rev-parse','bdcc24e'],cwd=ROOT,text=True).strip(),
        'card_rank_i_visible_native_pixels_exact':True,'icon_rank_i_visible_native_pixels_exact':True,
        'original_six_poses_preserved_as_paired_holds':True,'original_each_pose_and_total_duration_preserved':True,
        'historical_master_bytes_unchanged':preserved,
        'rank_ii_choice':'Same accepted triangular three-top composition, additional physical final receiver follow-through',
        'runtime_choice':'Original native128 warm pressure burst at paid source; warm local historical contact clusters on at most two actual recipients, three-cel ceiling'}
    args.out.parent.mkdir(parents=True,exist_ok=True);args.out.write_text(json.dumps(result,indent=2))
    print(json.dumps(result,indent=2))
if __name__=='__main__':main()
