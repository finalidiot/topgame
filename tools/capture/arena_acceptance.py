"""Record native grounded-pickup / arena-stage 003A human review.

Battle-only, isolated from Main and saves. Movies and full telemetry remain
external. Pickups are real earned drops; clock-offset arena stages are labelled
visual fixtures and cannot be cited as survival/Director acceptance.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json, re, subprocess, sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/workspace'))
sys.path.insert(0,str(ROOT/'tools/build'))
import workspace
import windows_checkpoint as pipeline

def dependencies():
    paths={'tools/capture/arena_acceptance.py','project.godot'}
    pending=['tests/capture_arena_acceptance.gd']
    while pending:
        relative=pending.pop()
        if relative in paths:continue
        paths.add(relative)
        for resource in re.findall(r'["\']res://([^"\']+)["\']',(ROOT/relative).read_text(encoding='utf-8')):
            target=ROOT/resource
            if '%' in resource:
                target=ROOT/resource.split('%',1)[0]
                if not target.is_dir():target=target.parent
            if target.is_file():
                if target.suffix=='.gd':pending.append(resource)
                else:paths.add(resource)
            elif target.is_dir():
                paths.update(p.relative_to(ROOT).as_posix() for p in target.rglob('*') if p.is_file() and p.suffix in {'.png','.json','.import'})
    # Data-driven atlas paths are not GDScript literals. Native source retained.
    for family in ['assets/arena','assets/top','assets/powers','assets/source-art/arena_escalation003a','assets/source-art/feedback_002c5_2']:
        paths.update(p.relative_to(ROOT).as_posix() for p in (ROOT/family).rglob('*') if p.is_file())
    return sorted(paths)

def validate(data,mode,rendered):
    assert data['failures']==[],data['failures']
    assert data['mode']==mode and data['native_view']==[640,360]
    assert not data['collection_opened'] and not data['main_created']
    if mode=='pickups':
        s=data['scenario'];assert s['collected']>=1 and s['expired']>=1 and s['hits']>0
        assert len(s['actual_spawn_clear_summaries'])>=2
        rows=data['rows']
        assert any(row['pickup']['active'] for row in rows)
        assert any(any(item['warning'] for item in row['pickup']['active']) for row in rows)
        assert any(row['pickup']['expired']>0 for row in rows)
        assert all(row['pickup']['draw_before_rigs'] and row['pickup']['lifetime']==16 and row['pickup']['collect_radius']==18 for row in rows)
        assert max(len(row['pickup']['active']) for row in rows)<=2
        assert any(row['phase']=='leave_centre' and sum(v*v for v in row['position'])>45**2 for row in rows)
        assert any(row['phase']=='hold_centre' and sum(v*v for v in row['position'])<40**2 for row in rows)
        required=['floor_before_collection','collected','expiry_warning','expired_floor']
    else:
        scenes=data['scenario']['scenes']
        assert [scene['stage'] for scene in scenes]==['EARLY','MID','LATE','EXTREME','EXTREME / REDUCED FLASHING','EXTREME / MOBILE QUALITY']
        assert data['scenario']['clock_fixture_explicit'] and not data['scenario']['balance_claim']
        assert data['movie_frames']==2880
        for scene in scenes:
            assert scene['live_combat_frames']>=300 and scene['hits']>0,scene
            assert scene['peak_arena_draws']<=(14 if scene['quality']<.75 else 17)
        required=['early','mid','late','extreme','extreme_reduced_flashing','extreme_mobile_quality']
    if rendered:
        for name in required:
            assert name in data['feature_frames'],name
            image=pipeline.png_record(Path(data['feature_frames'][name]['path']))
            assert image['width']==640 and image['height']==360

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--mode',choices=['pickups','arena'],required=True);p.add_argument('--diagnostic',action='store_true');p.add_argument('--qa-root',type=Path);p.add_argument('--engine');p.add_argument('--ffmpeg');a=p.parse_args()
    qa=workspace.create_task_workspace('003A',a.qa_root)
    base='003a_grounded_pickups' if a.mode=='pickups' else '003a_arena_escalation'
    stem=base+'_'+datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f')
    manifest=qa/'manifests'/f'{stem}.json';raw=qa/'temp'/f'{stem}.avi';video=qa/'video'/f'{base}.mp4';frames=qa/'frames'/stem
    assert not manifest.exists() and not raw.exists()
    if not a.diagnostic:assert not video.exists(),'Preserve previous review media'
    paths=dependencies();before={path:pipeline.sha256(ROOT/path) for path in paths}
    profile=pipeline.production_profile(ROOT)
    command=[workspace.find_tool('godot',a.engine),'--path',str(ROOT),'--script','res://tests/capture_arena_acceptance.gd']
    if a.diagnostic:command+=['--headless']
    else:command+=['--fixed-fps','60','--disable-vsync','--write-movie',str(raw),'--audio-driver','Dummy']
    command+=['--','--mode='+a.mode,'--manifest='+str(manifest)]
    command+=['--diagnostic'] if a.diagnostic else ['--frames='+str(frames)]
    process=pipeline.run_logged(command,qa/'logs'/f'{stem}.log',600)
    data=json.loads(manifest.read_text(encoding='utf-8'));validate(data,a.mode,not a.diagnostic)
    after={path:pipeline.sha256(ROOT/path) for path in paths}
    assert before==after,'Battle/capture dependencies changed during observation'
    assert pipeline.production_profile(ROOT)==profile,'Read-only Battle capture changed human profile'
    data.update(capture_process=process,source_sha256=before,source_unchanged=True,source_git_sha=pipeline.git(ROOT,'rev-parse','HEAD'),profile_before=profile,profile_after=pipeline.production_profile(ROOT),profile_unchanged=True,human_status='PENDING HUMAN REVIEW',source_scope='Actual transitive Battle/capture GDScript and all native arena/top/power render assets; no Main/Menus/preferences/music dependencies.')
    if not a.diagnostic:
        ffmpeg=workspace.find_tool('ffmpeg',a.ffmpeg)
        encoder=pipeline.run_logged([ffmpeg,'-v','error','-i',str(raw),'-an','-vf','scale=1280:720:flags=neighbor','-c:v','libx264','-crf','18','-preset','fast','-pix_fmt','yuv420p','-movflags','+faststart',str(video)],qa/'logs'/f'{stem}_encode.log',300)
        decoder=pipeline.run_logged([ffmpeg,'-v','error','-i',str(video),'-f','null','-'],qa/'logs'/f'{stem}_decode.log',120)
        metadata=subprocess.run([ffmpeg,'-hide_banner','-i',str(video)],capture_output=True,text=True).stderr
        match=re.search(r'Duration: (\d+):(\d+):(\d+(?:\.\d+)?)',metadata);assert match
        seconds=int(match[1])*3600+int(match[2])*60+float(match[3]);assert abs(seconds-data['movie_frames']/60)<.25
        assert video.stat().st_size>100000
        data.update(video=str(video),video_sha256=pipeline.sha256(video),raw_movie=str(raw),raw_sha256=pipeline.sha256(raw),actual_duration_seconds=seconds,encoder=encoder,decoder=decoder,movie_metadata=metadata,editorial='Native640x360 observation, integer2x nearest export. Only unrendered warmup gaps are omitted from pickup chronology; actual controls/positions/clock/receipts remain in telemetry. Arena stages are labelled clock-offset fixtures; no natural survival claims.')
    manifest.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'passed':True,'mode':a.mode,'manifest':str(manifest),'video':data.get('video'),'seconds':data.get('actual_duration_seconds'),'scenario':data['scenario'],'profile_unchanged':True},indent=2))

if __name__=='__main__':main()
