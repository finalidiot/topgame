"""Export artist-owned per-family Aseprite masters, never reconstruct them.

Cards: native64px,12 authored keys/state. Icons: independent16px silhouette.
FX: fixed-isometric96x80,8 keys/state, contact pivot48,48. Native Aseprite
exports are checked byte-for-byte; manifest/catalogue timing comes from source.
"""
import argparse
import json
import subprocess
import tempfile
import uuid
from pathlib import Path
from PIL import Image
from build_power_art import read_ase

ROOT = Path(__file__).resolve().parents[1]
FAMILIES = ['impact_wake', 'redline', 'iron_comet', 'dead_centre', 'afterimage',
            'chain_impact', 'clutch', 'high_gear', 'orbit_drive', 'crash_guard',
            'momentum_bank', 'predator_line', 'crosscut']

def save_json(path, data):
    # Parallel artists export independent families; readers never see partial JSON.
    stage = path.with_name(path.name + '.' + uuid.uuid4().hex + '.tmp')
    stage.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
    stage.replace(path)

def export_family(family, aseprite):
    target = ROOT / 'assets/powers/identity'
    target.mkdir(parents=True, exist_ok=True)
    design_path = target / f'{family}_design.json'
    if not design_path.exists():
        return None
    design = json.loads(design_path.read_text(encoding='utf-8-sig'))
    result = {'family': family, 'grammar': design['grammar'], 'design': str(design_path.relative_to(ROOT)).replace('\\', '/')}
    for group, size, pivot, count in [('cards', (64,64), [32,32], 12), ('icons', (16,16), [8,8], 1), ('fx', (96,80), [48,48], 8)]:
        source = ROOT / 'assets/source-art/power_identity_002c5' / f'{family}_{group}.aseprite'
        if not source.exists():
            raise FileNotFoundError(source)
        frames, meta = read_ase(source)
        assert tuple(meta['cell']) == size and meta['pivot'] == pivot, (family, group, meta)
        assert len(meta['layers']) >= (2 if group == 'icons' else 4), (family, group, 'editable named layers')
        assert len(set(meta['layers'])) == len(meta['layers'])
        for tag, span in meta['tags'].items():
            assert span['to'] - span['from'] + 1 == count, (family, group, tag)
        columns = len(frames) if group == 'icons' else count
        with tempfile.TemporaryDirectory() as temp:
            native = Path(temp) / 'native.png'
            subprocess.run([aseprite, '-b', str(source), '--sheet-columns', str(columns), '--sheet', str(native)], check=True, capture_output=True)
            sheet = Image.open(native).convert('RGBA')
            assert sheet.size == (size[0]*columns, size[1]*((len(frames)+columns-1)//columns))
            for index, frame in enumerate(frames):
                actual = sheet.crop((index%columns*size[0],index//columns*size[1],index%columns*size[0]+size[0],index//columns*size[1]+size[1]))
                # RGB under alpha0 is immaterial; compare visible RGBA and alpha.
                source_pixels = frame.tobytes()
                native_pixels = actual.tobytes()
                assert all(source_pixels[p:p+4] == native_pixels[p:p+4]
                           for p in range(0,len(source_pixels),4)
                           if source_pixels[p+3] or native_pixels[p+3]), (family, group, index, 'native source parity')
            destination = target / f'{family}_{group}.png'
            native.replace(destination)
        meta.update(columns=columns, frame_count=len(frames), source=str(source.relative_to(ROOT)).replace('\\','/'), texture='res://' + str(destination.relative_to(ROOT)).replace('\\','/'))
        result[group] = meta
    result['event_tags'] = design.get('event_tags', {})
    result['active_tags'] = design.get('active_tags', {})
    result['notes'] = design.get('notes', '')
    if 'historical_fx' in design:
        result['historical_fx'] = design['historical_fx']
    result['art'] = {}
    for art_id, span in result['cards']['tags'].items():
        assert art_id in result['icons']['tags'], (family, art_id, 'independent HUD icon required')
        row = int(span['from']) // 12
        timings = result['cards']['durations_ms'][span['from']:span['to']+1]
        static = int(design.get('static_frames', {}).get(art_id, 5))
        assert 0 <= static < 12
        result['art'][art_id] = {'family':family, 'art_id':art_id, 'source_tag':art_id,
            'icon':result['icons']['texture'], 'icon_frame':int(result['icons']['tags'][art_id]['from']),
            'card_texture':result['cards']['texture'], 'card_row':row,'card_cell':64,
            'card_frames':12, 'card_static_frame':static, 'card_durations_ms':timings}
    save_json(target / f'{family}_manifest.json', result)
    print(f'{family}: native parity verified; {len(result["art"])} card/icon states, {len(result["fx"]["tags"])} FX tags')
    return result

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--aseprite', default=r'F:\SteamLibrary\steamapps\common\Aseprite\Aseprite.exe')
    parser.add_argument('--family', action='append')
    args = parser.parse_args()
    for family in args.family or FAMILIES:
        assert family in FAMILIES
        export_family(family, args.aseprite)
    families = {}
    art = {}
    for family in FAMILIES:
        path = ROOT / 'assets/powers/identity' / f'{family}_manifest.json'
        if path.exists():
            item = json.loads(path.read_text(encoding='utf-8'))
            families[family] = item
            art.update(item['art'])
    aggregate = {'version':1, 'filter':'nearest', 'scope':'artist-owned native per-family identity sources; no physics or RNG', 'families':families, 'art':art}
    save_json(ROOT / 'assets/powers/identity_manifest.json', aggregate)

if __name__ == '__main__':
    main()
