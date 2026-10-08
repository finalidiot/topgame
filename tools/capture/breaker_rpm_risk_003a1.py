"""Render normal-Main Breaker opening/risk footage from a frozen exact source."""
from __future__ import annotations
import argparse, json, shutil, sys
from pathlib import Path
from datetime import datetime, timezone
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/build'))
sys.path.insert(0,str(ROOT/'tools/workspace'))
sys.path.insert(0,str(ROOT/'tools/presentation'))
sys.path.insert(0,str(ROOT/'tools/capture'))
import windows_checkpoint as pipeline
import workspace
from rpm_economy_study_003a1 import source, profile
from presentation_showcase import movie_metadata

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--base-snapshot',type=Path,required=True);parser.add_argument('--diagnostic',action='store_true');parser.add_argument('--engine');parser.add_argument('--ffmpeg')
    args=parser.parse_args();qa=workspace.create_task_workspace('003A.1')
    stem='003a1_breaker_rpm_risk_'+datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f')
    video=qa/'video/003a1_breaker_rpm_risk.mp4';report=qa/'manifests'/f'{stem}.json'
    assert args.diagnostic or not video.exists(),'Preserve existing final evidence'
    before=source(ROOT);player=profile()
    stage=qa/'temp'/f'{stem}_source';shutil.copytree(args.base_snapshot,stage)
    for directory in ['scripts','assets','.godot']:
        shutil.copytree(ROOT/directory,stage/directory,dirs_exist_ok=True)
    driver=ROOT/'tests/capture_breaker_rpm_risk_003a1.gd'
    shutil.copy2(driver,stage/'tests'/driver.name)
    assert source(stage)==before
    original=(stage/'project.godot').read_bytes()
    adjusted=original.replace(b'window/size/window_width_override=1280',b'window/size/window_width_override=640').replace(b'window/size/window_height_override=720',b'window/size/window_height_override=360')
    assert adjusted!=original
    (stage/'project.godot').write_bytes(adjusted)
    stage_source=source(stage)
    assert {k:v for k,v in stage_source.items() if k!='project.godot'}=={k:v for k,v in before.items() if k!='project.godot'}
    raw=qa/'temp'/f'{stem}.avi';frames=qa/'frames'/stem
    command=[workspace.find_tool('godot',args.engine),'--path',str(stage),'--script','res://tests/capture_breaker_rpm_risk_003a1.gd','--log-file',str(qa/'logs'/f'{stem}_engine.log')]
    if args.diagnostic:command+=['--headless']
    else:command+=['--resolution','640x360','--fixed-fps','60','--disable-vsync','--write-movie',str(raw),'--audio-driver','Dummy']
    command+=['--','--manifest='+str(report),'--collection-prefix='+str(qa/'temp'/f'{stem}_collection'),'--frames='+str(frames)]
    if args.diagnostic:command+=['--diagnostic']
    process=pipeline.run_logged(command,qa/'logs'/f'{stem}.log',1500)
    data=json.loads(report.read_text())
    assert data['movie_frames']>1200 and len(data['cases'])==2
    economy=data['cases'][0]['economy']
    assert economy['losses']['burst']>.05 and economy['total_recovered']>.02
    assert any(c['natural_end'] and c['result']['reason']=='ring_out' for c in data['cases'])
    assert len(data['contacts'])>0 and data['mapped_events']>=4*(data['movie_frames']-180)
    assert source(stage)==stage_source and source(ROOT)==before and profile()==player
    data.update(source_before=before,source_unchanged=True,stage_source=stage_source,display_only_variance='QA snapshot overrides initial Windows window from 1280x720 to native640x360 before Movie Maker initialization; logical gameplay canvas/settings/physics unchanged.',player_before=player,player_unchanged=True,driver_sha256=pipeline.sha256(driver),capture_process=process,source_git_sha=pipeline.git(ROOT,'rev-parse','HEAD'),scope_limits='Synthetic mapped controls demonstrate actual production input/physics; not physical controller or phone acceptance.')
    if not args.diagnostic:
        ffmpeg=workspace.find_tool('ffmpeg',args.ffmpeg);raw_info=movie_metadata(ffmpeg,raw)
        assert '640x360' in raw_info['metadata'],'The recorded source must be native gameplay scale'
        command=[ffmpeg,'-v','error','-i',str(raw)]
        if not raw_info['has_audio']:command+=['-i',str(raw.with_suffix('.wav'))]
        command+=['-map','0:v:0','-map','0:a:0' if raw_info['has_audio'] else '1:a:0','-vf','scale=1280:720:flags=neighbor','-c:v','libx264','-crf','18','-preset','fast','-c:a','aac','-b:a','160k','-pix_fmt','yuv420p','-movflags','+faststart',str(video)]
        data['encoder']=pipeline.run_logged(command,qa/'logs'/f'{stem}_encode.log',600)
        data['decoder']=pipeline.run_logged([ffmpeg,'-v','error','-i',str(video),'-f','null','-'],qa/'logs'/f'{stem}_decode.log',180)
        info=movie_metadata(ffmpeg,video);assert info['has_audio'] and abs(info['duration_seconds']-data['nominal_seconds'])<.3
        data.update(video=str(video),video_sha256=pipeline.sha256(video),movie_metadata=info)
    pipeline.write_json(report,data)
    print(json.dumps({'manifest':str(report),'video':data.get('video'),'seconds':data['nominal_seconds'],'source_unchanged':True,'player_unchanged':True},indent=2),flush=True)
if __name__=='__main__':main()
