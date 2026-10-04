"""Export edited Aseprite masters without changing source cels. No author switch.
Normal RGBA layers supported; verify native Aseprite export with --aseprite.
"""
import argparse,json,math,subprocess,tempfile
from pathlib import Path
from PIL import Image,ImageChops
from build_power_art import read_ase
ROOT=Path(__file__).resolve().parents[1]
def main():
    p=argparse.ArgumentParser();p.add_argument('--aseprite');args=p.parse_args()
    result={'version':1,'projection':'fixed isometric 2:1; no sprite rotation','filter':'nearest'}
    for family in ['redline','dead_centre','afterimage','combat']:
        source=ROOT/'assets/source-art'/f'{family}_fx_002c4.aseprite'
        frames,meta=read_ase(source);w,h=meta['cell'];columns=6
        sheet=Image.new('RGBA',(w*columns,h*math.ceil(len(frames)/columns)))
        for i,im in enumerate(frames):sheet.alpha_composite(im,(i%columns*w,i//columns*h))
        out=ROOT/'assets/powers'/f'signature_{family}.png';sheet.save(out)
        assert meta['pivot']==[48,48] and len(meta['layers'])==4
        assert all(40<=t<=160 for t in meta['durations_ms'])
        assert all(v['to']-v['from']==5 for v in meta['tags'].values())
        if args.aseprite:
            with tempfile.TemporaryDirectory() as temp:
                native=Path(temp)/'native.png'
                subprocess.run([args.aseprite,'-b',str(source),'--sheet-columns','6','--sheet',str(native)],check=True)
                assert ImageChops.difference(sheet,Image.open(native).convert('RGBA')).getbbox() is None, family
        meta.update(columns=columns,frame_count=len(frames),texture=out.name,source=str(source.relative_to(ROOT)).replace('\\','/'))
        result[family]=meta
        print(f'{family}: {len(frames)} frames / {len(meta["tags"])} tags; source/export verified')
    (ROOT/'assets/powers/signature_manifest.json').write_text(json.dumps(result,indent=2)+'\n')
if __name__=='__main__':main()
