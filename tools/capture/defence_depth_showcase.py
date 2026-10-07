"""Record the final003A defence families through actual mapped pad events."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import sys
import wave
from array import array
import math

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/build'))
sys.path.insert(0, str(ROOT / 'tools/workspace'))
sys.path.insert(0, str(ROOT / 'tools/capture'))
import windows_checkpoint as pipeline
import workspace
import progression_showcase as capture

def dependencies() -> list[Path]:
    # Freeze the actual standalone Battle dependency graph. Unrelated menu and
    # Android navigation work may continue without falsifying this capture.
    pending=[ROOT/'tests/capture_defence_depth.gd',ROOT/'tests/measured_presentation_battle.gd']
    found=set()
    while pending:
        path=pending.pop()
        if path in found: continue
        found.add(path)
        for name in re.findall(r'res://([^"\s]+\.gd)',path.read_text(encoding='utf-8')):
            child=ROOT/name
            if child.exists(): pending.append(child)
    found.update(p for p in (ROOT/'assets').rglob('*') if p.is_file() and p.suffix in ['.png','.json','.aseprite','.wav','.fnt'])
    found.update([ROOT/'project.godot',Path(__file__).resolve()])
    return sorted(found)

def validate(data: dict) -> None:
    assert data['passed'] and not data['failures'] and len(data['cases'])==9
    assert data['controller_events']>18000
    for case in data['cases']:
        family=case['case']['family']
        assert not case['result'],'A show must not hide or override a real defeat'
        assert case['seconds'] >= 11.5
        assert case['maxima']['fx'] <= 32
        assert case['simulation_ms']['samples'] >= 700
        if family=='gyro_lock': assert case['maxima']['gyro']>=.65
        elif family=='impact_sink': assert case['maxima']['sink']>=15 and case['tool_state']['vents']>=1
        elif family=='anchor_exchange': assert case['maxima']['brace']>=.95 and case['tool_state']['rpm_spent']>0
        if case['case']['branch']=='slip_anchor': assert case['maxima']['carry']>.2

def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--diagnostic',action='store_true')
    parser.add_argument('--engine')
    parser.add_argument('--ffmpeg')
    parser.add_argument('--encode-manifest',type=Path)
    args=parser.parse_args()
    task=workspace.create_task_workspace('003A')
    name='003a_defence_power_'+datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f')
    output=args.encode_manifest or task/'manifests'/(name+'.json')
    raw=task/'temp'/(name+'.avi')
    target=task/'video/003a_defence_power_showcase.mp4'
    if not args.encode_manifest:
        files=dependencies()
        before={p.relative_to(ROOT).as_posix():pipeline.sha256(p) for p in files}
        profile=pipeline.production_profile(ROOT)
        (task/'manifests'/(name+'_inputs.json')).write_text(json.dumps({'source':before,'profile':profile},indent=2)+'\n')
        command=[workspace.find_tool('godot',args.engine),'--path',str(ROOT),'--script','res://tests/capture_defence_depth.gd','--fixed-fps','60','--disable-vsync']
        command+=['--headless'] if args.diagnostic else ['--write-movie',str(raw),'--audio-driver','Dummy']
        command+=['--','--manifest='+str(output)]
        command+=['--diagnostic'] if args.diagnostic else ['--frames='+str(task/'frames'/name)]
        process=pipeline.run_logged(command,task/'logs'/(name+'.log'),600)
        data=json.loads(output.read_text(encoding='utf-8'))
        validate(data)
        after={p.relative_to(ROOT).as_posix():pipeline.sha256(p) for p in files}
        assert before==after,'Actual capture dependencies must remain frozen'
        assert profile==pipeline.production_profile(ROOT),'Player profile changed'
        data.update(capture_process=process,source_sha256=after,source_unchanged=True,profile_before=profile,
                    profile_after=pipeline.production_profile(ROOT),profile_unchanged=True,
                    source_git_sha=pipeline.git(ROOT,'rev-parse','HEAD'),working_tree=pipeline.git(ROOT,'status','--porcelain'),
                    raw_movie=str(raw))
    else:
        data=json.loads(output.read_text(encoding='utf-8'))
        validate(data);raw=Path(data['raw_movie'])
    if not args.diagnostic:
        assert not target.exists(),'Preserve existing human evidence'
        ffmpeg=workspace.find_tool('ffmpeg',args.ffmpeg)
        metadata=capture.movie_metadata(ffmpeg,raw)
        sidecar=raw.with_suffix('.wav')
        command=[ffmpeg,'-v','error','-i',str(raw)]
        if not metadata['has_audio']:
            assert sidecar.exists(),'Actual captured SFX sidecar required'
            command+=['-i',str(sidecar)]
        command+=['-map','0:v:0','-map','0:a:0' if metadata['has_audio'] else '1:a:0',
                  '-vf','scale=1280:720:flags=neighbor','-c:v','libx264','-crf','18','-preset','fast',
                  '-pix_fmt','yuv420p','-c:a','aac','-b:a','160k','-ar','48000','-movflags','+faststart',str(target)]
        encoder=pipeline.run_logged(command,task/'logs'/(name+'_encode.log'),600)
        decoder=pipeline.run_logged([ffmpeg,'-v','error','-i',str(target),'-f','null','-'],task/'logs'/(name+'_decode.log'),180)
        final=capture.movie_metadata(ffmpeg,target)
        assert final['has_audio'] and 105<final['duration_seconds']<112
        pcm=task/'temp'/(name+'_actual_sfx.wav')
        pipeline.run_logged([ffmpeg,'-v','error','-i',str(target),'-map','0:a:0','-c:a','pcm_s16le',str(pcm)],task/'logs'/(name+'_audio.log'),180)
        with wave.open(str(pcm),'rb') as file:
            assert file.getnchannels()==2 and file.getframerate()==48000
            values=array('h',file.readframes(file.getnframes()))
        peak=max(abs(v) for v in values)/32768
        rms=math.sqrt(sum(v*v for v in values)/len(values))/32768
        assert .0001<rms and .001<peak<.99
        data.update(video=str(target),video_sha256=pipeline.sha256(target),seconds=final['duration_seconds'],
                    raw_sha256=pipeline.sha256(raw),raw_audio_sidecar=str(sidecar),audio_peak=peak,audio_rms=rms,
                    encoder=encoder,decoder=decoder,editorial='Full chronological nine cases; native640 enlarged integer2x nearest; actual mixed gameplay SFX; captions are explicit fixture/behaviour labels; no replaced game imagery or forced power effects.')
    output.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'passed':True,'manifest':str(output),'video':data.get('video'),'seconds':data.get('seconds')},indent=2))

if __name__=='__main__': main()
