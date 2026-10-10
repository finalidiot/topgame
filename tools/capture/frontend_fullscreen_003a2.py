"""Guarded actual desktop front-end matrix and variable-client native showcase."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[2]
for family in ('tools/build','tools/workspace','tools/presentation'): sys.path.insert(0,str(ROOT/family))
import windows_checkpoint as pipeline
import workspace
from upgrade_sustain_003a1 import source
spec=importlib.util.spec_from_file_location('profile_guard',ROOT/'tools/capture/android_fullscreen_003a2.py')
profile_guard=importlib.util.module_from_spec(spec);spec.loader.exec_module(profile_guard)
DRIVER=ROOT/'tests/test_frontend_fullscreen_003a2.gd'
REQUIRED={'title','hub','options','workshop','shop','starter','modes','help','save_tools','reset_confirm',
          'packet_purchase','packet_open','packet_result','packet_odds','packet_salvage','result',
          'battle','pause','ability_draft','mutation_draft','acquisition','level_up'}
CASES={'800x480','1280x720','1920x1080','2560x1440'}
def read(p):return json.loads(Path(p).read_text(encoding='utf-8'))
def pointer(p):
    p=Path(p).resolve();return {'path':str(p),'bytes':p.stat().st_size,'sha256':pipeline.sha256(p)}
def harness():
    paths=[DRIVER,Path(__file__),ROOT/'tools/capture/android_fullscreen_003a2.py',ROOT/'tools/build/windows_checkpoint.py',ROOT/'tools/workspace/workspace.py',ROOT/'tools/presentation/upgrade_sustain_003a1.py']
    if DRIVER.with_suffix('.gd.uid').exists():paths.append(DRIVER.with_suffix('.gd.uid'))
    return {str(p):pipeline.sha256(p) for p in paths}
def freeze(stage):
    stage.mkdir()
    for name in ('project.godot','main.tscn'):shutil.copy2(ROOT/name,stage/name)
    for name in ('scripts','assets','.godot'):shutil.copytree(ROOT/name,stage/name)
    (stage/'tests').mkdir();shutil.copy2(DRIVER,stage/'tests'/DRIVER.name)
    if DRIVER.with_suffix('.gd.uid').exists():shutil.copy2(DRIVER.with_suffix('.gd.uid'),stage/'tests'/DRIVER.with_suffix('.gd.uid').name)
    assert source(stage)==source(ROOT)
def validate(data,mode):
    assert data['schema']=='frontend-fullscreen-003a2-v1' and data['checks']>0 and data['failures']==[]
    assert not data['physical_phone_acceptance'] and not data['physical_controller_acceptance']
    if mode!='showcase':
        assert {row['case'] for row in data['observations']}==CASES
        for case in CASES:
            assert REQUIRED<={row['screen_label'] for row in data['observations'] if row['case']==case}
        assert any(row.get('push_input_in_local_coords') is False for row in data['inputs'])
    else:
        assert len(data['film'])>300 and data['phases']
        assert any(row['mode']==2 for row in data['phases'])
        assert any(row['label']=='RESUME / AUTHORED RE-ENTRY READY GO' and row['screen']=='battle' for row in data['phases'])
        assert any(row['type']=='native_OS_API_restore' and row['actual_paused'] and row['actors_unchanged'] and not row['forced_size_assignment'] and row['restored_client']==row['before_maximize_client'] for row in data['inputs'])
        assert data['phases'][-1]['mode']==0
    if mode!='headless':
        assert data['native']
        for row in data['images']:
            assert pipeline.sha256(Path(row['path']))==row['sha256']
            with Image.open(row['path']) as image:assert list(image.size)==row['pixels']
        for row in data['observations']:
            if 'controls_paint_order' in row:
                assert len(row['controls_rendered_pixels'])==2
                assert all(len(proof['distinct_colours'])>1 and pipeline.sha256(Path(proof['source_image']))==proof['sha256'] for proof in row['controls_rendered_pixels'])

def compose_matrix(data,target):
    font=ImageFont.truetype(r'C:\Windows\Fonts\consola.ttf',19)
    title=ImageFont.truetype(r'C:\Windows\Fonts\consolab.ttf',27)
    cases=['800x480','1280x720','1920x1080','2560x1440'];screens=['title','hub','options','workshop','shop','starter']
    canvas=Image.new('RGB',(3376,3312),'#101a20');draw=ImageDraw.Draw(canvas)
    draw.text((20,10),'003A.2 / RESPONSIVE FULL-CLIENT FRONT END',font=title,fill='#edf0e7')
    draw.text((20,47),'Actual Windows render pixels. Synthetic GUI input; no new human hardware acceptance.',font=font,fill='#b3cdd0')
    lookup={(row['case'],row['screen']):row for row in data['images']}
    for column,case in enumerate(cases):
        x=20+column*840
        for index,screen in enumerate(screens):
            y=92+index*532
            draw.text((x,y),case+' / '+screen.upper(),font=font,fill='#87cad7')
            image=Image.open(lookup[(case,screen)]['path']).convert('RGB')
            image=image.resize((800,round(image.height*800/image.width)),Image.Resampling.NEAREST)
            canvas.paste(image,(x,y+28))
    canvas.save(target,optimize=True)

def compose_classes(data,target):
    lookup={(r['case'],r['screen']):r for r in data['images']}
    canvas=Image.new('RGB',(2448,560),'#101a20');draw=ImageDraw.Draw(canvas)
    font=ImageFont.truetype(r'C:\Windows\Fonts\consolab.ttf',23)
    for column,(screen,label) in enumerate([('options','FRONT END / FULL CLIENT'),('battle','COMBAT / ACCEPTED ARENA'),('pause','COMBAT MODAL / LIVE ARENA')]):
        image=Image.open(lookup[('1920x1080',screen)]['path']).convert('RGB')
        image=image.resize((800,round(image.height*800/image.width)),Image.Resampling.NEAREST)
        left=16+column*816;draw.text((left,14),label,font=font,fill='#d7e8e1');canvas.paste(image,(left,52))
    canvas.save(target,optimize=True)

def compose_before_after(data,before,target):
    baseline=read(before)['rows']
    pairs=[(next(r for r in baseline if r['label']=='windowed_1920x1080_options'),next(r for r in data['images'] if r['case']=='1920x1080' and r['screen']=='options'),'DECLARED1920x1080 WINDOWED CLIENT'),
           (next(r for r in baseline if r['label']=='native_maximized_options'),next(r for r in data['images'] if r['case']=='1920x1080' and r['screen']=='options_native_maximized'),'ACTUAL NATIVE MAXIMIZED CLIENT')]
    rows=[]
    for old,new,label in pairs:
        assert pipeline.sha256(Path(old['image']))==old['sha256']
        a=Image.open(old['image']).convert('RGB');b=Image.open(new['path']).convert('RGB')
        assert a.size==b.size, 'Before/after must compare identical actual client dimensions'
        rows.append((a,b,label))
    canvas=Image.new('RGB',(3870,sum(a.height+72 for a,_,_ in rows)),'#101a20');draw=ImageDraw.Draw(canvas)
    font=ImageFont.truetype(r'C:\Windows\Fonts\consolab.ttf',25)
    top=0
    for a,b,label in rows:
        draw.text((10,top+10),'BEFORE ed1b73f / '+label,font=font,fill='#ebc0a5')
        draw.text((1940,top+10),'AFTER / SAMECLIENT / RESPONSIVE OPTIONS',font=font,fill='#9cdbcc')
        canvas.paste(a,(10,top+52));canvas.paste(b,(1940,top+52));top+=a.height+72
    canvas.save(target,optimize=True)

def encode_showcase(data,qa,stem,ffmpeg):
    # Real clients vary; an external fixed video canvas displays each entire
    # viewport with aspect preserved. Native OS mode/client are labelled.
    staged=qa/'temp'/(stem+'_film_composition');staged.mkdir()
    font=ImageFont.truetype(r'C:\Windows\Fonts\consola.ttf',22)
    for index,row in enumerate(data['film']):
        assert pipeline.sha256(Path(row['path']))==row['sha256']
        image=Image.open(row['path']).convert('RGB')
        scale=min(1920/image.width,1080/image.height)
        image=image.resize((round(image.width*scale),round(image.height*scale)),Image.Resampling.NEAREST)
        canvas=Image.new('RGB',(1920,1128),'#101a20');canvas.paste(image,((1920-image.width)//2,(1080-image.height)//2))
        mode='MAXIMIZED' if row['window_mode']==2 else 'WINDOWED'
        caption=f"ACTUAL CLIENT {row['client'][0]}x{row['client'][1]} / {mode} / {row['phase']} / SYNTHETIC GUI + OS API"
        ImageDraw.Draw(canvas).text((12,1091),caption,font=font,fill='#dbe6de')
        canvas.save(staged/f'{index:05d}.png',compress_level=1)
    target=qa/'temp'/(stem+'_validated_showcase.mp4');assert not target.exists()
    command=[ffmpeg,'-v','error','-framerate','30','-i',str(staged/'%05d.png'),'-an','-c:v','libx264','-crf','18','-preset','fast','-pix_fmt','yuv420p','-movflags','+faststart',str(target)]
    encode=pipeline.run_logged(command,qa/'logs'/(stem+'_encode.log'),900)
    decode=pipeline.run_logged([ffmpeg,'-v','error','-i',str(target),'-f','null','-'],qa/'logs'/(stem+'_decode.log'),240)
    return {'video':pointer(target),'encoder':encode,'decoder':decode,'external_composition':str(staged),'fps':30,'capture_cadence':'One actual root image per two fixed60 GUI frames; whole variable client uniformly fitted to fixed external1920x1080 area plus48px caption. Not MovieMaker, gameplay performance or human OS caption-button acceptance.'}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode',choices=('headless','native','showcase'),required=True)
    parser.add_argument('--label',default='final')
    parser.add_argument('--engine',default=r'E:\Desktop\Godot_v4.7.2-stable_win64_console.exe')
    parser.add_argument('--ffmpeg')
    parser.add_argument('--before',type=Path,default=ROOT.parent/'GyroBrothers-QA/003A.2/manifests/003a2_frontend_before_options_20261010_114901_045290.json')
    args=parser.parse_args();assert args.label.replace('_','').replace('-','').isalnum()
    qa=workspace.create_task_workspace('003A.2');os.environ['TOPGAME_QA_ROOT']=str(qa.parent)
    stamp=datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f');stem='003a2_frontend_'+args.mode+'_'+args.label+'_'+stamp
    stage=qa/'temp'/(stem+'_source');runtime=qa/'manifests'/(stem+'_runtime.json');manifest=qa/'manifests'/(stem+'.json')
    original=source(ROOT);profiles=profile_guard.player();drivers=harness()
    record={'status':'preparing','created_utc':datetime.now(timezone.utc).isoformat(),'mode':args.mode,'git_sha':pipeline.git(ROOT,'rev-parse','HEAD'),'source_before':original,'player_before':profiles,'harness':drivers,'scope':'Actual production Main/Menus desktop viewport renders with declared isolated UI fixtures; no physical controller/phone acceptance. OS API native maximize/restore actuation is labelled.'}
    pipeline.write_json(manifest,record)
    try:
        if args.mode=='native':
            reserved=[qa/'images'/name for name in ('003a2_frontend_fullscreen_matrix.png','003a2_presentation_classes.png','003a2_options_human_repro_before_after.png')]
            reserved += [qa/'manifests/003a2_frontend_layout_matrix.json',qa/'003a2_frontend_layout_matrix.json']
            assert not any(p.exists() for p in reserved),'All selected primary images and JSON mirrors must be absent before capture'
        if args.mode=='showcase':assert not (qa/'video/003a2_frontend_responsive_showcase.mp4').exists()
        freeze(stage);frozen=source(stage)
        command=[args.engine,'--path',str(stage),'--script','res://tests/'+DRIVER.name,'--fixed-fps','60','--disable-vsync','--audio-driver','Dummy','--log-file',str(qa/'logs'/(stem+'_engine.log'))]
        if args.mode=='headless':command+=['--headless']
        command+=['--','--report='+str(runtime),'--profile-prefix='+str(qa/'temp'/(stem+'_collection'))]
        if args.mode!='headless':command+=['--native','--frames='+str(qa/'frames'/stem)]
        if args.mode=='showcase':command+=['--showcase']
        if args.mode=='showcase':command+=['--run-seed=421717']
        record.update(status='running',source_root=str(stage));pipeline.write_json(manifest,record)
        record['process']=pipeline.run_logged(command,qa/'logs'/(stem+'.log'),900)
        data=read(runtime);validate(data,args.mode)
        record.update(source_unchanged=original==source(ROOT),frozen_source_unchanged=frozen==source(stage),harness_unchanged=drivers==harness(),player_after=profile_guard.player(),player_unchanged=profiles==profile_guard.player(),runtime=pointer(runtime),checks=data['checks'])
        assert all(record[k] for k in ('source_unchanged','frozen_source_unchanged','harness_unchanged','player_unchanged'))
        if args.mode=='native':
            targets={name:qa/'images'/name for name in ('003a2_frontend_fullscreen_matrix.png','003a2_presentation_classes.png','003a2_options_human_repro_before_after.png')}
            assert not any(p.exists() for p in targets.values())
            staged=qa/'temp'/(stem+'_composites');staged.mkdir()
            compose_matrix(data,staged/'003a2_frontend_fullscreen_matrix.png');compose_classes(data,staged/'003a2_presentation_classes.png');compose_before_after(data,args.before,staged/'003a2_options_human_repro_before_after.png')
            record['before_options']=pointer(args.before)
        if args.mode=='showcase':record.update(encode_showcase(data,qa,stem,workspace.find_tool('ffmpeg',args.ffmpeg)))
        record.update(source_unchanged=original==source(ROOT),frozen_source_unchanged=frozen==source(stage),harness_unchanged=drivers==harness(),player_after=profile_guard.player(),player_unchanged=profiles==profile_guard.player())
        assert all(record[k] for k in ('source_unchanged','frozen_source_unchanged','harness_unchanged','player_unchanged'))
        if args.mode=='native':
            for name,target in targets.items():shutil.copy2(staged/name,target)
            record['images']={name:pointer(p) for name,p in targets.items()}
        if args.mode=='showcase':
            target=qa/'video/003a2_frontend_responsive_showcase.mp4';assert not target.exists()
            shutil.copy2(Path(record['video']['path']),target);record['video']=pointer(target)
        record['status']='passed';pipeline.write_json(manifest,record)
        if args.mode=='native':
            target=qa/'manifests/003a2_frontend_layout_matrix.json';mirror=qa/'003a2_frontend_layout_matrix.json'
            assert not target.exists() and not mirror.exists()
            summary={'schema':'003a2-frontend-layout-matrix-v1','status':'passed','checks':data['checks'],'provenance':pointer(manifest),'runtime':pointer(runtime),'cases':data['observations'],'input_traces':data['inputs'],'artifacts':record['images'],'physical_controller_acceptance':False,'physical_phone_acceptance':False,'scope':record['scope']}
            pipeline.write_json(target,summary);mirror.write_bytes(target.read_bytes())
        print(json.dumps({'status':'passed','manifest':pointer(manifest),'checks':data['checks'],'images':record.get('images'),'video':record.get('video'),'protected_player_files':len(profiles['files'])},indent=2),flush=True)
    except Exception as exc:
        record.update(status='rejected_attempt',error=str(exc),source_unchanged=original==source(ROOT),harness_unchanged=drivers==harness(),player_after=profile_guard.player(),player_unchanged=profiles==profile_guard.player())
        if isinstance(exc,pipeline.ProcessValidationError):record['failed_process']=exc.record
        if runtime.exists():record['runtime']=pointer(runtime)
        if stage.exists():record['partial_stage']=str(stage)
        pipeline.write_json(manifest,record);raise

if __name__=='__main__':main()
