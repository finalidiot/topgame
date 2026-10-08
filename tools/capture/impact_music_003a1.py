"""Actual native 60FPS collision and synchronized audio review; isolated source."""
from __future__ import annotations
import argparse, json, sys, wave, math
from pathlib import Path
from datetime import datetime, timezone
ROOT=Path(__file__).resolve().parents[2]
for folder in ['tools/build','tools/workspace','tools/presentation','tools/capture']:
    sys.path.insert(0,str(ROOT/folder))
import windows_checkpoint as pipeline
import workspace
from rpm_economy_study_003a1 import source, profile
from presentation_showcase import movie_metadata
from combat_art003a1 import frozen_project

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--mode',choices=['impacts','music'],required=True);p.add_argument('--diagnostic',action='store_true');p.add_argument('--provisional',action='store_true');p.add_argument('--engine');p.add_argument('--ffmpeg');args=p.parse_args()
    qa=workspace.create_task_workspace('003A.1');base='003a1_combat_impact_rework' if args.mode=='impacts' else '003a1_music_variety'
    stem=base+'_'+datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f');report=qa/'manifests'/f'{stem}.json';raw=qa/'temp'/f'{stem}.avi';frames=qa/'frames'/stem;video=qa/'video'/f'{stem if args.provisional else base}.mp4'
    assert args.diagnostic or not video.exists(),'Preserve prior review footage'
    player=profile();stage,original,frozen=frozen_project(qa,stem);driver=stage/'tests/capture_impact_music_003a1.gd';driver_sha=pipeline.sha256(driver)
    command=[workspace.find_tool('godot',args.engine),'--path',str(stage),'--script','res://tests/capture_impact_music_003a1.gd','--log-file',str(qa/'logs'/f'{stem}_engine.log')]
    command+=['--headless'] if args.diagnostic else ['--resolution','640x400','--fixed-fps','60','--disable-vsync','--write-movie',str(raw),'--audio-driver','Dummy']
    command+=['--','--mode='+args.mode,'--manifest='+str(report),'--frames='+str(frames)]
    if args.diagnostic:command+=['--diagnostic']
    process=pipeline.run_logged(command,qa/'logs'/f'{stem}.log',1200)
    data=json.loads(report.read_text());assert not data['failures'],data['failures'];assert not data['main_created'] and not data['collection_opened']
    assert source(stage)==frozen and pipeline.sha256(driver)==driver_sha
    current_profile=profile();profile_equal=current_profile==player
    data.update(frozen_source=frozen,original_production_source=original,source_unchanged=True,driver_sha256=driver_sha,player_before=player,player_after=current_profile,player_and_backups_unchanged=profile_equal,capture_process=process,source_git_sha=pipeline.git(ROOT,'rev-parse','HEAD'),human_status='PENDING HUMAN REVIEW',frozen_project=str(stage))
    pipeline.write_json(report,data)
    assert profile_equal,'Preserved raw evidence; external player change requires an honest new guard boundary'
    if not args.diagnostic:
        ffmpeg=workspace.find_tool('ffmpeg',args.ffmpeg);info=movie_metadata(ffmpeg,raw);assert '640x400' in info['metadata'];wave_path=raw.with_suffix('.wav')
        if info['has_audio']:
            wave_path=raw.with_name(raw.stem+'_native_mix.wav')
            assert not wave_path.exists()
            data['native_pcm_extraction']=pipeline.run_logged([ffmpeg,'-v','error','-i',str(raw),'-vn','-c:a','pcm_s16le',str(wave_path)],qa/'logs'/f'{stem}_pcm.log',180)
        command=[ffmpeg,'-v','error','-i',str(raw)]
        if not info['has_audio']:command+=['-i',str(wave_path)]
        command+=['-map','0:v:0','-map','0:a:0' if info['has_audio'] else '1:a:0','-vf','scale=1280:800:flags=neighbor','-c:v','libx264','-crf','18','-preset','fast','-c:a','aac','-b:a','192k','-pix_fmt','yuv420p','-movflags','+faststart',str(video)]
        encode=pipeline.run_logged(command,qa/'logs'/f'{stem}_encode.log',600);decode=pipeline.run_logged([ffmpeg,'-v','error','-i',str(video),'-f','null','-'],qa/'logs'/f'{stem}_decode.log',180)
        metadata=movie_metadata(ffmpeg,video);assert metadata['has_audio'] and abs(metadata['duration_seconds']-data['movie_frames']/60)<.3
        import numpy as np
        with wave.open(str(wave_path),'rb') as wav:
            assert wav.getsampwidth()==2
            samples=np.frombuffer(wav.readframes(wav.getnframes()),dtype='<i2').astype(np.float64)/32768.0
        peak=float(abs(samples).max());rms=float(np.sqrt(np.mean(samples*samples)));assert .001<peak<.99 and not np.any(abs(samples)>=1.0)
        data.update(video=str(video),video_sha256=pipeline.sha256(video),raw_sha256=pipeline.sha256(raw),raw_audio_sha256=pipeline.sha256(wave_path),encoder=encode,decoder=decode,movie_metadata=metadata,native_mix={'peak':peak,'peak_dbfs':20*math.log10(peak),'rms_dbfs':20*math.log10(rms),'clipped_samples':int(np.sum(abs(samples)>=1.0))},editorial='Native640x360 plus external40px caption, integer2x nearest. Full-speed60FPS; actual native Godot mixed audio. Labels explicitly distinguish fixtures from natural Run studies.')
        pipeline.write_json(report,data)
    print(json.dumps({'passed':True,'manifest':str(report),'video':data.get('video'),'seconds':data['movie_frames']/60,'player_and_backups_unchanged':profile_equal,'mix':data.get('native_mix')},indent=2))
if __name__=='__main__':main()
