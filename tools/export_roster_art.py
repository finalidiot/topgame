"""Export edited native 002C.5 sources; never reconstruct or overwrite masters."""
import argparse, json, math, subprocess, tempfile
from pathlib import Path
from PIL import Image
from build_power_art import read_ase

ROOT = Path(__file__).resolve().parents[1]
def main():
    p = argparse.ArgumentParser(); p.add_argument('--aseprite'); args = p.parse_args()
    result = {'version': 1, 'projection': 'fixed isometric2:1; upright cels', 'filter': 'nearest'}
    for group, columns, pivot, layers in [('effects', 6, [48,48], 4), ('cards', 6, [32,32], 5), ('icons', 16, [8,8], 2)]:
        name = 'fx' if group == 'effects' else group
        source = ROOT / 'assets/source-art' / f'roster_{name}_002c5.aseprite'
        frames, meta = read_ase(source); w,h = meta['cell']
        if group == 'icons': columns = len(frames)
        sheet = Image.new('RGBA', (w*columns, h*math.ceil(len(frames)/columns)))
        for i, im in enumerate(frames): sheet.alpha_composite(im, (i%columns*w, i//columns*h))
        out = ROOT/'assets/powers'/f'roster_{group}.png'; sheet.save(out)
        assert meta['pivot'] == pivot and len(meta['layers']) == layers
        assert all(int(v['to'])-int(v['from']) == (0 if group == 'icons' else 5) for v in meta['tags'].values())
        if args.aseprite:
            with tempfile.TemporaryDirectory() as temp:
                native = Path(temp)/'native.png'
                subprocess.run([args.aseprite, '-b', str(source), '--sheet-columns', str(columns), '--sheet', str(native)], check=True)
                exported = Image.open(native).convert('RGBA')
                assert sheet.size == exported.size and sheet.tobytes() == exported.tobytes(), group
        meta.update(columns=columns, frame_count=len(frames), texture=out.name, source=str(source.relative_to(ROOT)).replace('\\','/'))
        result[group] = meta
        print(f'{group}: {len(frames)} frames, {len(meta["tags"])} tags; native source/export verified')
    (ROOT/'assets/powers/roster_manifest.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
if __name__ == '__main__': main()
