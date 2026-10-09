"""Freeze source and record actual production enemy pilots/powers at native60FPS.

Legal one-enemy scenarios are labelled fixtures, not natural Run balance claims.
Primary evidence is never replaced. Diagnostics retain their complete snapshots.
"""
from __future__ import annotations
import argparse,json,re,sys
from pathlib import Path
from datetime import datetime,timezone
ROOT=Path(__file__).resolve().parents[2]
for folder in ['tools/build','tools/workspace','tools/presentation','tools/capture']:
    sys.path.insert(0,str(ROOT/folder))
import windows_checkpoint as pipeline
import workspace
from rpm_economy_study_003a1 import source,profile
from presentation_showcase import movie_metadata
from combat_art003a1 import frozen_project

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--mode',choices=['intelligence','powers'],required=True)
    p.add_argument('--diagnostic',action='store_true');p.add_argument('--provisional',action='store_true')
    p.add_argument('--version',default='',help='Fresh evidence suffix, such asv2; existing versions are never replaced')
    p.add_argument('--engine');p.add_argument('--ffmpeg');args=p.parse_args()
    qa=workspace.create_task_workspace('003A.1')
    base='003a1_enemy_intelligence_showcase' if args.mode=='intelligence' else '003a1_enemy_power_showcase'
    if args.version:
        assert re.fullmatch(r'v[2-9][0-9]*',args.version),'Version must be an explicitv2-or-later evidence identity'
        base+='_'+args.version
    stem=base+'_'+datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f')
    report=qa/'manifests'/f'{stem}.json';frames=qa/'frames'/stem;raw=qa/'temp'/f'{stem}.avi'
    video=qa/'video'/f'{stem if args.provisional else base}.mp4'
    assert args.diagnostic or not video.exists(),'Preserve prior primary evidence'
    player=profile();stage,original,frozen=frozen_project(qa,stem)
    driver=stage/'tests/capture_enemy_intelligence_003a1.gd';driver_hash=pipeline.sha256(driver)
    command=[workspace.find_tool('godot',args.engine),'--path',str(stage),'--script','res://tests/capture_enemy_intelligence_003a1.gd','--log-file',str(qa/'logs'/f'{stem}_engine.log')]
    command+=['--headless'] if args.diagnostic else ['--resolution','640x400','--fixed-fps','60','--disable-vsync','--write-movie',str(raw),'--audio-driver','Dummy']
    command+=['--','--mode='+args.mode,'--manifest='+str(report),'--frames='+str(frames)]
    if args.diagnostic:command+=['--diagnostic']
    process=pipeline.run_logged(command,qa/'logs'/f'{stem}.log',1200)
    data=json.loads(report.read_text());assert data['failures']==[],data['failures']
    assert data['movie_frames']==(3480 if args.mode=='intelligence' else 2640)+(0 if args.diagnostic else 36)
    assert len(data['scenes'])==(8 if args.mode=='intelligence' else 4)
    assert not data['main_created'] and not data['collection_opened']
    assert source(stage)==frozen and pipeline.sha256(driver)==driver_hash
    current_profile=profile();assert current_profile==player,'Player/backup guard changed; retain raw evidence'
    current_source=source(ROOT)
    if not args.diagnostic and not args.provisional:assert current_source==original,'Production changed during final capture; retain raw evidence'
    data.update(capture_process=process,frozen_project=str(stage),original_production_source=original,frozen_source=frozen,frozen_source_unchanged=True,production_source_unchanged=current_source==original,driver_sha256=driver_hash,player_before=player,player_after=current_profile,player_and_backups_unchanged=True,source_git_sha=pipeline.git(ROOT,'rev-parse','HEAD'),human_status='PENDING HUMAN REVIEW')
    pipeline.write_json(report,data)
    if not args.diagnostic:
        ffmpeg=workspace.find_tool('ffmpeg',args.ffmpeg);info=movie_metadata(ffmpeg,raw);assert '640x400' in info['metadata']
        command=[ffmpeg,'-v','error','-i',str(raw)]
        if not info['has_audio']:command+=['-i',str(raw.with_suffix('.wav'))]
        command+=['-map','0:v:0','-map','0:a:0' if info['has_audio'] else '1:a:0','-vf','scale=1280:800:flags=neighbor','-c:v','libx264','-crf','18','-preset','fast','-c:a','aac','-b:a','192k','-pix_fmt','yuv420p','-movflags','+faststart',str(video)]
        encode=pipeline.run_logged(command,qa/'logs'/f'{stem}_encode.log',600)
        decode=pipeline.run_logged([ffmpeg,'-v','error','-i',str(video),'-f','null','-'],qa/'logs'/f'{stem}_decode.log',180)
        metadata=movie_metadata(ffmpeg,video)
        assert metadata['has_audio'] and abs(metadata['duration_seconds']-data['movie_frames']/60)<.3
        for item in data['features'].values():
            png=pipeline.png_record(Path(item['path']));assert png['width']==640 and png['height']==400
        data.update(video=str(video),video_sha256=pipeline.sha256(video),raw_sha256=pipeline.sha256(raw),encoder=encode,decoder=decode,movie_metadata=metadata,editorial='Uncut within each disclosed scenario. Actual synchronized Godot music/SFX;640x360 native gameplay plus40px external caption strip. Integer2x nearest display;60FPS real-time without slow motion. No Main/HUD or natural Run claim.')
        pipeline.write_json(report,data)
    print(json.dumps({'passed':True,'manifest':str(report),'video':data.get('video'),'seconds':data['movie_frames']/60,'source_unchanged':current_source==original,'player_and_backups_unchanged':True},indent=2))
if __name__=='__main__':main()
