"""Guarded actual-catalogue mutation card review; all output is external QA."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import sys
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'tools/build'),str(ROOT/'tools/presentation')]
import windows_checkpoint as pipeline
from upgrade_sustain_003a1 import source

def read_json(path): return json.loads(path.read_text(encoding='utf-8'))
def pointer(path): return {'path':str(path.resolve()),'sha256':pipeline.sha256(path)}
def protected(rows):
    return {name:{'size':Path(name).stat().st_size,'sha256':pipeline.sha256(Path(name))} for name in rows}
def matrix(runtime, target):
    # Four intact640x360 menu screenshots, each preserving both sibling cards
    # and the actual inspector. QA captions occupy new pixels outside the UI.
    canvas=Image.new('RGB',(1320,860),(14,22,29));draw=ImageDraw.Draw(canvas)
    font=ImageFont.truetype(r'C:\Windows\Fonts\consola.ttf',16)
    title=ImageFont.truetype(r'C:\Windows\Fonts\consolab.ttf',23)
    draw.text((14,10),'003A.2 / EIGHT MUTATIONS / ACTUAL CATALOGUE CARDS',font=title,fill='#e3e8dc')
    draw.text((14,39),'Declared sibling-choice fixtures. Native UI pixels; accepted artwork preserved.',font=font,fill='#afc4c5')
    for index,row in enumerate(runtime['images']):
        raw=Image.open(row['path']).convert('RGB');x,y,w,h=map(int,row['menu_rect'])
        assert (w,h)==(640,360) and x>=0 and y>=0 and x+w<=raw.width and y+h<=raw.height
        crop=raw.crop((x,y,x+w,y+h));left=12+(index%2)*656;top=64+(index//2)*400
        names=' / '.join(card['name'] for card in row['cards'])
        draw.text((left,top),names,font=font,fill='#d49bf1')
        canvas.paste(crop,(left,top+24))
    canvas.save(target,optimize=True)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine',default=r'E:\Desktop\Godot_v4.7.2-stable_win64_console.exe')
    parser.add_argument('--tests-only',action='store_true')
    args=parser.parse_args()
    qa=ROOT.parent/'GyroBrothers-QA/003A.2'
    baseline_path=qa/'manifests/003a2_scope_baseline.json';baseline=read_json(baseline_path)
    stamp=datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f');stem='003a2_mutation_art_'+stamp
    out=qa/'manifests'/f'{stem}.json';assert not out.exists()
    guards={kind:protected(baseline[kind]) for kind in ('player','assets','music')}
    assert all(guards[kind]==baseline[kind] for kind in guards)
    owned=[ROOT/'scripts/run_powers.gd',ROOT/'scripts/ecology_art.gd',ROOT/'tests/capture_ecology_art003a2.gd',
           ROOT/'tools/art/ecology_art003a2.py',ROOT/'tools/art/test_ecology_art003a2.py',Path(__file__)]
    owned += [p for directory in ('assets/source-art/ecology003a2','assets/powers/ecology003a2') for p in (ROOT/directory).rglob('*') if p.is_file()]
    own_before={str(p):pipeline.sha256(p) for p in owned}
    report={'status':'running','created_utc':datetime.now(timezone.utc).isoformat(),'baseline':pointer(baseline_path),
            'tests_only':args.tests_only,'owned_source_before':own_before,'accepted_assets':len(guards['assets']),
            'protected_player_files':len(guards['player']),'music_files':len(guards['music'])}
    pipeline.write_json(out,report)
    log=qa/'logs'/f'{stem}_python.log'
    record=pipeline.run_logged([sys.executable,'-B','-m','unittest','discover','-s',str(ROOT/'tools/art'),'-p','test_ecology_art003a2.py','-v'],log,120)
    text=log.read_text(encoding='utf-8');match=re.search(r'Ran (\d+) tests',text)
    assert match and int(match[1])==13 and re.search(r'^OK$',text,re.M)
    report['art_tests']={**record,'cases':13}
    if not args.tests_only:
        source_before=source(ROOT)
        frames=qa/'frames'/stem;runtime_path=qa/'manifests'/f'{stem}_native.json'
        native_log=qa/'logs'/f'{stem}_native.log'
        command=[args.engine,'--fixed-fps','60','--disable-vsync','--path',str(ROOT),'--script','res://tests/capture_ecology_art003a2.gd',
                 '--','--output-dir='+str(frames),'--report='+str(runtime_path)]
        process=pipeline.run_logged(command,native_log,120)
        runtime=read_json(runtime_path)
        assert runtime['checks']>0 and not runtime['failures'] and runtime['forms']==54 and len(runtime['images'])==4
        for row in runtime['images']:assert pipeline.sha256(Path(row['path']))==row['sha256']
        target=qa/'images/003a2_mutation_cards.png';assert not target.exists()
        matrix(runtime,target)
        source_after=source(ROOT);assert source_before==source_after
        report.update(native_process=process,native_report=pointer(runtime_path),native_checks=runtime['checks'],
                      matrix=pointer(target),runtime_source_unchanged=True,
                      source_before=source_before,source_after=source_after)
    guards_after={kind:protected(baseline[kind]) for kind in guards}
    report.update(owned_source_after={str(p):pipeline.sha256(p) for p in owned},
                  accepted_assets_player_music_unchanged=guards==guards_after,
                  owned_source_unchanged=own_before=={str(p):pipeline.sha256(p) for p in owned},
                  art_manifest=pointer(ROOT/'assets/powers/ecology003a2/manifest.json'),
                  scope='New mutation art only. Actual Aseprite parity, saved source editability and deterministic export. Native matrix uses actual catalogue and normal Menus with declared legal choice fixtures; no combat/acquisition or human hardware claim.')
    assert report['accepted_assets_player_music_unchanged'] and report['owned_source_unchanged']
    report['status']='passed';pipeline.write_json(out,report)
    print(json.dumps({'manifest':str(out),'sha256':pipeline.sha256(out),'cases':13,'native_checks':report.get('native_checks'),
                      'matrix':report.get('matrix'),'accepted_assets_player_music_unchanged':True},indent=2))
if __name__=='__main__':main()
