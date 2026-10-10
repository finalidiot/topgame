"""Freeze and record paid actual Ghost hijacks/earned Predator motion at60FPS.

Native renderer comparison explicitly uses held state and never claims physics.
All prior outputs are preserved; no Main or real player profile is opened.
"""
from __future__ import annotations
import argparse,json,re,sys
from datetime import datetime,timezone
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[2]
for folder in ['tools/build','tools/workspace','tools/presentation','tools/capture']:
    sys.path.insert(0,str(ROOT/folder))
import windows_checkpoint as pipeline
import workspace
from rpm_economy_study_003a1 import source,profile
from presentation_showcase import movie_metadata
from combat_art003a1 import frozen_project

def capture(args):
    qa=workspace.create_task_workspace('003A.1')
    base='003a1_ghost_circuit_hijack' if args.mode=='ghost' else '003a1_predator_pursuit_readability'
    if args.version:
        assert re.fullmatch(r'v[2-9][0-9]*',args.version),'Explicit fresh version required'
        base+='_'+args.version
    stem=base+'_'+datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f')
    report=qa/'manifests'/f'{stem}.json';primary=qa/f'{base}.json'
    frames=qa/'frames'/stem;raw=qa/'temp'/f'{stem}.avi';video=qa/'video'/f'{stem if args.provisional else base}.mp4'
    assert args.diagnostic or not video.exists(),'Preserve existing primary movie'
    assert args.diagnostic or args.provisional or not primary.exists(),'Preserve existing primaryJSON'
    player=profile();stage,original,frozen=frozen_project(qa,stem)
    driver=stage/'tests/capture_ghost_hijack_003a1.gd';driver_hash=pipeline.sha256(driver)
    dependency_names=['tests/capture_ghost_hijack_003a1.gd','tests/ghost_physics_fixture_003a1.gd','tests/capture_enemy_intelligence_003a1.gd','tests/capture_impact_music_003a1.gd']
    dependencies={name:pipeline.sha256(stage/name) for name in dependency_names}
    assert dependencies=={name:pipeline.sha256(ROOT/name) for name in dependency_names}
    command=[workspace.find_tool('godot',args.engine),'--path',str(stage),'--script','res://tests/capture_ghost_hijack_003a1.gd','--log-file',str(qa/'logs'/f'{stem}_engine.log')]
    command+=['--headless'] if args.diagnostic else ['--resolution','640x400','--fixed-fps','60','--disable-vsync','--write-movie',str(raw),'--audio-driver','Dummy']
    command+=['--','--mode='+args.mode,'--manifest='+str(report),'--frames='+str(frames)]
    if args.diagnostic:command+=['--diagnostic']
    process=pipeline.run_logged(command,qa/'logs'/f'{stem}.log',1200)
    data=json.loads(report.read_text());assert data['failures']==[],data['failures']
    assert data['movie_frames']==(2400 if args.mode=='ghost' else 1200)+(0 if args.diagnostic else 36)
    assert len(data['scenes'])==(4 if args.mode=='ghost' else 2)
    assert not data['main_created'] and not data['collection_opened']
    assert source(stage)==frozen and pipeline.sha256(driver)==driver_hash
    assert dependencies=={name:pipeline.sha256(stage/name) for name in dependency_names}
    current=source(ROOT);assert profile()==player,'Player/backup guard changed'
    if not args.provisional:
        assert current==original,'Production changed during capture; retain frozen attempt'
        assert dependencies=={name:pipeline.sha256(ROOT/name) for name in dependency_names},'Fixture changed during capture'
    data.update(capture_process=process,frozen_project=str(stage),original_production_source=original,frozen_source=frozen,frozen_source_unchanged=True,production_source_unchanged=current==original,driver_sha256=driver_hash,fixture_dependency_sha256=dependencies,player_before=player,player_after=profile(),player_and_backups_unchanged=True,source_git_sha=pipeline.git(ROOT,'rev-parse','HEAD'),human_status='PENDING HUMAN REVIEW')
    if not args.diagnostic:
        ffmpeg=workspace.find_tool('ffmpeg',args.ffmpeg);info=movie_metadata(ffmpeg,raw);assert '640x400' in info['metadata']
        command=[ffmpeg,'-v','error','-i',str(raw)]
        if not info['has_audio']:command+=['-i',str(raw.with_suffix('.wav'))]
        command+=['-map','0:v:0','-map','0:a:0' if info['has_audio'] else '1:a:0','-vf','scale=1280:800:flags=neighbor','-c:v','libx264','-crf','18','-preset','fast','-c:a','aac','-b:a','192k','-pix_fmt','yuv420p','-movflags','+faststart',str(video)]
        encode=pipeline.run_logged(command,qa/'logs'/f'{stem}_encode.log',600)
        decode=pipeline.run_logged([ffmpeg,'-v','error','-i',str(video),'-f','null','-'],qa/'logs'/f'{stem}_decode.log',180)
        metadata=movie_metadata(ffmpeg,video);assert metadata['has_audio'] and abs(metadata['duration_seconds']-data['movie_frames']/60)<.3
        for item in data['features'].values():
            png=pipeline.png_record(Path(item['path']));assert (png['width'],png['height'])==(640,400)
        data.update(video=str(video),video_sha256=pipeline.sha256(video),raw_sha256=pipeline.sha256(raw),encoder=encode,decoder=decode,movie_metadata=metadata,editorial='Uncut fixed60Hz actual solver within each disclosed initial-condition scenario. Native640×360 gameplay plus40px caption strip, integer2× nearest display, synchronized actual Godot audio. No slow motion or cinematic actor hold. Controlled geometry evidence, not natural Run balance.')
    assert profile()==player and source(stage)==frozen
    if not args.provisional:
        assert source(ROOT)==original,'Production changed before evidence finalization'
        assert dependencies=={name:pipeline.sha256(ROOT/name) for name in dependency_names}
    pipeline.write_json(report,data)
    if not args.diagnostic and not args.provisional:pipeline.write_json(primary,data)
    print(json.dumps({'passed':True,'manifest':str(report),'primary':str(primary) if primary.exists() else None,'video':data.get('video'),'seconds':data['movie_frames']/60,'source_unchanged':current==original},indent=2))

def renderer_pair(args):
    qa=workspace.create_task_workspace('003A.1');stem='003a1_predator_renderer_pair_'+datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f')
    player=profile();original=source(ROOT);results=[]
    prior=qa/'temp/003a1_predator_trail_before_20261009_power_identity.gd'
    assert prior.is_file()
    for label in ['before','after']:
        stage,initial,frozen=frozen_project(qa,stem+'_'+label);assert initial==original
        if label=='before':
            (stage/'scripts/power_identity.gd').write_bytes(prior.read_bytes());changed=source(stage)
            assert {k:v for k,v in changed.items() if k!='scripts/power_identity.gd'}=={k:v for k,v in frozen.items() if k!='scripts/power_identity.gd'}
            frozen=changed
        frames=qa/'frames'/f'{stem}_{label}';report=qa/'manifests'/f'{stem}_{label}.json'
        command=[workspace.find_tool('godot',args.engine),'--path',str(stage),'--script','res://tests/capture_predator_renderer_pair_003a1.gd','--resolution','640x400','--fixed-fps','60','--disable-vsync','--audio-driver','Dummy','--','--mode=powers','--manifest='+str(report),'--frames='+str(frames)]
        process=pipeline.run_logged(command,qa/'logs'/f'{stem}_{label}.log',180)
        data=json.loads(report.read_text());assert data['failures']==[] and data['scenes'][0]['held_state_fixture']
        assert source(stage)==frozen and source(ROOT)==original and profile()==player
        item=Path(data['features']['predator_flow_turn']['path']);results.append({'label':label,'frame':str(item),'frame_sha256':pipeline.sha256(item),'frozen_source':frozen,'process':process,'manifest':str(report)})
    output=qa/'images/003a1_predator_pursuit_before_after.png';assert not output.exists()
    canvas=Image.new('RGB',(1280,856),(17,23,27));draw=ImageDraw.Draw(canvas);font=ImageFont.truetype('C:/Windows/Fonts/consola.ttf',16)
    for index,item in enumerate(results):
        image=Image.open(item['frame']).convert('RGB');assert image.size==(640,360)
        canvas.paste(image,(index*640,36));draw.text((index*640+12,10),item['label'].upper()+' / identical held renderer fixture',fill=(229,189,117),font=font)
        #2× nearest crop of the owner/motion region gives readable native detail.
        draw.text((index*640+32,405),'4x nearest detail / unchanged native art',fill=(189,204,204),font=font)
        crop=image.crop((246,118,390,222));canvas.paste(crop.resize((576,416),Image.Resampling.NEAREST),(index*640+32,432))
    canvas.save(output)
    proof={'passed':True,'image':str(output),'image_sha256':pipeline.sha256(output),'pairs':results,'comparison':'Identical held visual states; before snapshot replaces ONLY power_identity.gd with preserved exact before bytes. Native gameplay figures are not physics/balance evidence. Current actual contact-earned normal/RF video is separate. Top full native screenshots and4× nearest owner-region detail.','source_before':original,'source_after':source(ROOT),'source_unchanged':True,'player_and_backups_unchanged':True,'art_assets_unchanged':True}
    pipeline.write_json(qa/'manifests'/f'{stem}.json',proof);print(json.dumps({'passed':True,'image':str(output),'manifest':str(qa/'manifests'/f'{stem}.json')},indent=2))

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--mode',choices=['ghost','predator','predator-compare'],required=True);p.add_argument('--diagnostic',action='store_true');p.add_argument('--provisional',action='store_true');p.add_argument('--version',default='',help='Fresh v2-or-later evidence identity; prior files are never replaced');p.add_argument('--engine');p.add_argument('--ffmpeg');args=p.parse_args()
    renderer_pair(args) if args.mode=='predator-compare' else capture(args)
if __name__=='__main__':main()
