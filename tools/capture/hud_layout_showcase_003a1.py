"""Render canonical native combat with its actual external margin HUD."""
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
    parser=argparse.ArgumentParser(); parser.add_argument('--base-snapshot',type=Path,required=True); parser.add_argument('--engine'); parser.add_argument('--ffmpeg');parser.add_argument('--label',default='final');parser.add_argument('--video-name',default='003a1_hud_layout_showcase')
    args=parser.parse_args(); qa=workspace.create_task_workspace('003A.1')
    stem='003a1_hud_layout_showcase_'+args.label+'_'+datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f')
    video=qa/'video'/f'{args.video_name}.mp4'; report=qa/'manifests'/f'{stem}.json'
    assert not video.exists(),'Preserve existing final evidence; use a separate video-name for another reviewed version'
    before=source(ROOT); player=profile()
    stage=qa/'temp'/f'{stem}_source'; shutil.copytree(args.base_snapshot,stage)
    for directory in ['scripts','assets','.godot']:
        shutil.copytree(ROOT/directory,stage/directory,dirs_exist_ok=True)
    for name in ['project.godot','main.tscn']:shutil.copy2(ROOT/name,stage/name)
    driver=ROOT/'tests/capture_hud_layout_showcase_003a1.gd';shutil.copy2(driver,stage/'tests'/driver.name)
    assert source(stage)==before
    original=(stage/'project.godot').read_bytes()
    adjusted=original.replace(b'window/size/viewport_height=480',b'window/size/viewport_height=520').replace(b'window/size/window_width_override=960',b'window/size/window_width_override=800').replace(b'window/size/window_height_override=600',b'window/size/window_height_override=520')
    assert adjusted!=original
    (stage/'project.godot').write_bytes(adjusted)
    stage_source=source(stage)
    assert {k:v for k,v in stage_source.items() if k!='project.godot'}=={k:v for k,v in before.items() if k!='project.godot'}
    raw=qa/'temp'/f'{stem}.avi';frames=qa/'frames'/stem
    command=[workspace.find_tool('godot',args.engine),'--path',str(stage),'--script','res://tests/capture_hud_layout_showcase_003a1.gd','--log-file',str(qa/'logs'/f'{stem}_engine.log'),'--resolution','800x520','--fixed-fps','60','--disable-vsync','--write-movie',str(raw),'--audio-driver','Dummy','--','--manifest='+str(report),'--profile='+str(qa/'temp'/f'{stem}_collection.json'),'--frames='+str(frames)]
    process=pipeline.run_logged(command,qa/'logs'/f'{stem}.log',900)
    data=json.loads(report.read_text(encoding='utf-8'))
    assert not data['failures'],data['failures']
    assert data['movie_frames']==1980 and len(data['features'])==7
    assert {'windows_single_meter','windows_four_meters','overdrive_on','overdrive_off','boss_rival_world_bars','android_layout_four_meters','options'}==set(data['features'])
    assert source(stage)==stage_source and profile()==player
    current=source(ROOT)
    differences={k:{'recorded':before.get(k),'current':current.get(k)} for k in sorted(set(before)|set(current)) if before.get(k)!=current.get(k)}
    data.update(recorded_source=before,frozen_stage_source=stage_source,frozen_source_unchanged=True,root_source_changed_during_recording=differences,source_isolation='All runtime/scripts/assets are frozen before capture. Concurrent root work is recorded separately; a later source is not falsely claimed as this capture.',display_only_variance='QA snapshot adds40pixels below unchanged800x480 product canvas for review caption and forces native800x520 initialwindow; Battle640x360 is byte-identical.',player_before=player,player_after=profile(),player_unchanged=True,driver_sha256=pipeline.sha256(driver),capture_process=process,source_git_sha=pipeline.git(ROOT,'rev-parse','HEAD'),raw_movie=str(raw),raw_sha256=pipeline.sha256(raw))
    ffmpeg=workspace.find_tool('ffmpeg',args.ffmpeg);raw_info=movie_metadata(ffmpeg,raw)
    assert '800x520' in raw_info['metadata']
    command=[ffmpeg,'-v','error','-i',str(raw)]
    if not raw_info['has_audio']:command+=['-i',str(raw.with_suffix('.wav'))]
    command+=['-map','0:v:0','-map','0:a:0' if raw_info['has_audio'] else '1:a:0','-vf','scale=1600:1040:flags=neighbor','-c:v','libx264','-crf','18','-preset','fast','-c:a','aac','-b:a','160k','-pix_fmt','yuv420p','-movflags','+faststart',str(video)]
    data['encoder']=pipeline.run_logged(command,qa/'logs'/f'{stem}_encode.log',600)
    data['decoder']=pipeline.run_logged([ffmpeg,'-v','error','-i',str(video),'-f','null','-'],qa/'logs'/f'{stem}_decode.log',180)
    info=movie_metadata(ffmpeg,video);assert info['has_audio'] and abs(info['duration_seconds']-data['nominal_seconds'])<.5
    data.update(video=str(video),video_sha256=pipeline.sha256(video),movie_metadata=info)
    pipeline.write_json(report,data)
    print(json.dumps({'manifest':str(report),'video':str(video),'seconds':data['nominal_seconds'],'frozen_source_unchanged':True,'player_unchanged':True,'concurrent_root_differences':list(differences)},indent=2),flush=True)
if __name__=='__main__': main()
