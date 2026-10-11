"""Discover real Bastion events, replay literal inputs, and film guarded excerpts."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import shutil
import sys
import wave
from array import array

ROOT = Path(__file__).resolve().parents[2]
for family in ('tools/build','tools/workspace','tools/presentation'):
    sys.path.insert(0,str(ROOT/family))
import windows_checkpoint as pipeline
import workspace
from upgrade_sustain_003a1 import source
spec=importlib.util.spec_from_file_location('bastion_profile_guard',ROOT/'tools/capture/android_fullscreen_003a2.py')
profiles=importlib.util.module_from_spec(spec);spec.loader.exec_module(profiles)
DRIVER=ROOT/'tests/capture_bastion_feel_003a2.gd'

def read(path): return json.loads(Path(path).read_text(encoding='utf-8'))
def pointer(path):
    path=Path(path).resolve()
    return {'path':str(path),'bytes':path.stat().st_size,'sha256':pipeline.sha256(path)}
def harness():
    files=[DRIVER,Path(__file__),ROOT/'tools/build/windows_checkpoint.py',ROOT/'tools/workspace/workspace.py',
           ROOT/'tools/presentation/upgrade_sustain_003a1.py',ROOT/'tools/capture/android_fullscreen_003a2.py']
    if DRIVER.with_suffix('.gd.uid').exists():files.append(DRIVER.with_suffix('.gd.uid'))
    return {str(path):pipeline.sha256(path) for path in files}
def create_stage(original,stage,native):
    stage.mkdir()
    for name in ('project.godot','main.tscn'):shutil.copy2(original/name,stage/name)
    for name in ('scripts','assets'):shutil.copytree(original/name,stage/name)
    (stage/'tests').mkdir();shutil.copy2(DRIVER,stage/'tests'/DRIVER.name)
    if DRIVER.with_suffix('.gd.uid').exists():shutil.copy2(DRIVER.with_suffix('.gd.uid'),stage/'tests'/DRIVER.with_suffix('.gd.uid').name)
    assert source(stage)==source(original)
    display=None
    if native:
        project=stage/'project.godot';old=project.read_bytes();new=old
        replacements={b'window/size/window_width_override=960':b'window/size/window_width_override=800',
                      b'window/size/window_height_override=600':b'window/size/window_height_override=480'}
        for before,after in replacements.items():
            assert new.count(before)==1,'Only the explicitly known movie display override is permitted'
            new=new.replace(before,after)
        project.write_bytes(new)
        display={'canonical_sha256':__import__('hashlib').sha256(old).hexdigest(),'movie_sha256':pipeline.sha256(project),
                 'only_changes':{before.decode():after.decode() for before,after in replacements.items()},
                 'scope':'QA MovieWriter window override only. Battle SubViewport remains640x360; all physics/scripts/assets are byte-identical.'}
    return display
def tape_plan(data,path):
    assert data['mode']=='discover'
    plan={'schema':'003a2-bastion-feel-plan-v1','discovery':pointer(path),
          'cases':[{'configuration':row['configuration'],'inputs':row['inputs'],'input_sha256':row['input_sha256']} for row in data['cases']],
          'sections':[],'scope':'Literal normalized per-tick inputs recorded from observed-only baseline policy. No runtime state/effect injection.'}
    return plan
def coverage(data):
    result=[]
    for case in data['cases']:
        events={}
        for event in case['events']:events[event['kind']]=events.get(event['kind'],0)+1
        delivered={}
        for event in case['delivered_counters']:
            if sum(float(component)**2 for component in event['actual_delta'])>1e-8:
                kind=event['cause']['kind'];delivered[kind]=delivered.get(kind,0)+1
        player=case['end'];contacts=case['contacts']
        meaningful=[event for event in contacts if event['severity']>=.75]
        result.append({'case':case['configuration'],'ticks':case['ticks'],'seconds':player['time'],'status':case['status'],'result':case['result'],
                       'full_top_contacts':len(contacts),'hard_contacts':len(meaningful),'max_severity':max((row['severity'] for row in contacts),default=0),
                       'semantic_events':events,'actually_delivered_counters':delivered,
                       'peak_stress':max((row['anchor_stress'] for row in case['trace']),default=0),'final_rpm':player['rpm'],
                       'peak_radius':max((row['radius'] for row in case['trace']),default=0),'input_sha256':case['input_sha256']})
    return result
def validate(data,plan=None,reference=None):
    assert data['schema']=='003a2-bastion-feel-capture-v1' and data['failures']==[]
    assert data['main_created'] is False and data['collection_accessed'] is False and data['permanent_rewards_settled'] is False
    assert data['native_view']==[800,480] and data['combat_view']==[640,360]
    if data['mode']=='native':
        assert len(data['sections'])==len(plan['sections'])>0
        assert data['movie_frames']==sum(s['to_tick']-s['from_tick']+1 for s in plan['sections'])
    for case in data['cases']:
        assert case['ticks']==len(case['inputs']) and case['ticks']>0
        assert all(float(row['rpm'])>=0 and row['radius']>=0 for row in case['trace'])
        assert all(row[0]**2+row[1]**2<=1.00002 for row in case['inputs'])
        if plan:
            original=next(row for row in plan['cases'] if row['configuration']['id']==case['configuration']['id'])
            assert case['inputs']==original['inputs'][:case['ticks']],'Every common-lifetime tick must consume the literal tape'
        if reference:
            original=next(row for row in reference['cases'] if row['configuration']['id']==case['configuration']['id'])
            assert case['trace']==original['trace'][:len(case['trace'])],'Same-source native/headless simulation replay must remain exact'
            assert case['contacts']==[row for row in original['contacts'] if row['time']<=case['end']['time']+1e-7]
            assert case['delivered_counters']==[row for row in original['delivered_counters'] if row['time']<=case['end']['time']+1e-7]

def media_info(path,ffmpeg):
    import subprocess
    result=subprocess.run([str(Path(ffmpeg).with_name('ffprobe.exe')),'-v','error','-show_streams','-show_format','-of','json',str(path)],capture_output=True,text=True,check=True)
    return json.loads(result.stdout)

def pcm_info(path):
    with wave.open(str(path),'rb') as audio:
        assert audio.getsampwidth()==2,'MovieWriter PCM must retain its expected signed16-bit samples'
        samples=array('h',audio.readframes(audio.getnframes()))
        return {'channels':audio.getnchannels(),'rate':audio.getframerate(),'frames':audio.getnframes(),
                'peak':max((abs(value) for value in samples),default=0)/32768,
                'saturated_samples':sum(abs(value)>=32767 for value in samples),'nonzero_samples':sum(value!=0 for value in samples)}

def caption_filter(data,label):
    def escaped(value): return value.replace('\\','\\\\').replace(':','\\:').replace("'","\\'").replace('%','\\%')
    filters=['pad=800:512:0:0:color=0x0b1019']
    for section in data['sections']:
        text=escaped(label+' / '+section['title'])
        filters.append("drawtext=fontfile='C\\:/Windows/Fonts/consola.ttf':text='"+text+"':fontsize=14:fontcolor=white:x=8:y=488:enable='between(n,"+str(section['movie_from'])+','+str(section['movie_to'])+")'")
    return ','.join(filters)+',scale=1600:1024:flags=neighbor'

def publish(args):
    qa=workspace.create_task_workspace('003A.2')
    targets=[qa/'video/003a2_bastion_active_defence_showcase.mp4',qa/'video/003a2_bastion_before_after.mp4']
    assert all(not path.exists() for path in targets),'Both selected names must be unused before any publication'
    receipt_paths=[args.before_native,args.after_native,args.showcase_native]
    records=[read(path) for path in receipt_paths]
    for record in records:
        assert record['status']=='passed' and record['mode']=='native'
        assert all(record[key] for key in ('executed_source_unchanged','frozen_source_unchanged','harness_unchanged','player_unchanged'))
        for key in ('runtime','raw_movie','raw_audio','video_candidate','plan','reference'):
            entry=record[key];assert pointer(entry['path'])==entry,'Every selected native receipt input/output remains exact'
    before,after,showcase=records
    assert before['plan']['sha256']==after['plan']['sha256'],'Matched movie uses one literal control plan'
    assert after['executed_source_before']==showcase['executed_source_before']==source(ROOT)
    changed=sorted(key for key in before['executed_source_before'] if before['executed_source_before'][key]!=after['executed_source_before'][key])
    assert changed==['scripts/sound.gd','scripts/starters.gd'],'Only the declared handling/copy and Sound routing source may differ'
    raw=[read(record['runtime']['path']) for record in records]
    assert raw[0]['movie_frames']==raw[1]['movie_frames']
    stamp=datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f');stem='003a2_bastion_feel_publication_'+stamp
    ledger=qa/'manifests'/(stem+'.json');stage=qa/'temp'/(stem+'_before_after.mp4')
    ffmpeg=workspace.find_tool('ffmpeg',args.ffmpeg);guard=harness();player=profiles.player();runtime_source=source(ROOT)
    record={'schema':'003a2-bastion-feel-publication-v1','status':'validating','mode':'native',
            'native_receipts':[pointer(path) for path in receipt_paths],'source_changes':changed,
            'scope':'Actual canonical Battle runtime. Showcase uses disclosed current observed inputs except the labelled recorded-input rearm chapter. Matched comparison consumes identical per-case initial fixtures/seeds/normalized controls. Full literal outcomes, including natural later ringouts, remain preserved; footage is not balance/FPS/hardware acceptance.',
            'audio_scope':'Real MovieWriter AudioServer WAV. Comparison audio is AFTER only. Normal Sound/Music/grind runtime is connected. Omitted solver prefixes suppress semantic sound requests; film audio resumes at rendered excerpts and music uses the film clock. No offline PCM reconstruction.',
            'omission_scope':'All omitted initial/countdown and inter-chapter prefixes are genuinely solved. Chapters start only at declared recorded ticks; no actor/resource/effect/outcome adjustment.',
            'before_audio_requests':raw[0]['cases'],'after_audio_requests':raw[1]['cases'],
            'phone_acceptance':False,'controller_hardware_acceptance':False,'player_before':player}
    # Compact actual sound evidence rather than repeating the physical state graph.
    for key in ('before_audio_requests','after_audio_requests'):
        record[key]=[{'case':row['configuration']['id'],'requests':row['native_audio_requests']} for row in record[key]]
    pipeline.write_json(ledger,record)
    try:
        record['comparison_encoder']=pipeline.run_logged([ffmpeg,'-v','error','-i',before['video_candidate']['path'],'-i',after['video_candidate']['path'],
            '-filter_complex','[0:v][1:v]hstack=inputs=2,setsar=1[v]','-map','[v]','-map','1:a:0',
            '-c:v','libx264','-crf','18','-preset','fast','-pix_fmt','yuv420p','-c:a','copy','-movflags','+faststart',str(stage)],qa/'logs'/(stem+'_encode.log'),600)
        record['comparison_decoder']=pipeline.run_logged([ffmpeg,'-v','error','-i',str(stage),'-f','null','-'],qa/'logs'/(stem+'_decode.log'),180)
        info=media_info(stage,ffmpeg);video=next(row for row in info['streams'] if row['codec_type']=='video')
        assert (video['width'],video['height'])==(3200,1024)
        assert all(not path.exists() for path in targets)
        assert runtime_source==source(ROOT) and player==profiles.player() and guard==harness()
        candidates=[Path(showcase['video_candidate']['path']),stage]
        for candidate,target in zip(candidates,targets):
            shutil.copy2(candidate,target);assert pipeline.sha256(candidate)==pipeline.sha256(target)
        record.update(status='passed',videos=[pointer(path) for path in targets],comparison_media=info,
                      source_root=str(ROOT),source_before=runtime_source,frozen_source_unchanged=runtime_source==source(ROOT),
                      harness_unchanged=guard==harness(),player_unchanged=player==profiles.player())
        pipeline.write_json(ledger,record)
        print(json.dumps({'status':'passed','receipt':pointer(ledger),'videos':record['videos']},indent=2),flush=True)
    except Exception as exc:
        record.update(status='rejected_attempt',error=str(exc));pipeline.write_json(ledger,record);raise

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode',choices=('discover','replay','native','publish'),required=True)
    parser.add_argument('--source-root',type=Path,required=True)
    parser.add_argument('--source-ledger',type=Path)
    parser.add_argument('--label',required=True)
    parser.add_argument('--plan',type=Path)
    parser.add_argument('--reference',type=Path)
    parser.add_argument('--engine',default=r'E:\Desktop\Godot_v4.7.2-stable_win64_console.exe')
    parser.add_argument('--ffmpeg')
    parser.add_argument('--before-native',type=Path)
    parser.add_argument('--after-native',type=Path)
    parser.add_argument('--showcase-native',type=Path)
    args=parser.parse_args();assert args.label.replace('_','').replace('-','').isalnum()
    if args.mode=='publish':
        assert args.before_native and args.after_native and args.showcase_native
        publish(args);return
    assert args.mode=='discover' or (args.plan and args.plan.is_file())
    qa=workspace.create_task_workspace('003A.2');__import__('os').environ['TOPGAME_QA_ROOT']=str(qa.parent)
    stamp=datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f');stem='003a2_bastion_feel_'+args.mode+'_'+args.label+'_'+stamp
    original=args.source_root.resolve();stage=qa/'temp'/(stem+'_source');raw=qa/'manifests'/(stem+'_runtime.json');receipt=qa/'manifests'/(stem+'.json')
    original_hashes=source(original);canonical_before=source(ROOT);guard=harness();player=profiles.player()
    plan=read(args.plan) if args.plan else None
    record={'schema':'003a2-bastion-feel-provenance-v1','status':'preparing','mode':args.mode,'source_label':args.label,
            'executed_original':str(original),'executed_source_before':original_hashes,'canonical_before':canonical_before,
            'harness':guard,'player_before':player,'physical_phone_acceptance':False,'physical_controller_acceptance':False,
            'scope':'Actual Battle/Run AI/Director, real countdown and literal per-tick input replay. No Main/collection settlement; all initial invested fixtures disclosed. Canonical may legitimately evolve during baseline discovery; only the executed immutable source and harness define its source guard.'}
    if args.source_ledger:record['upstream_source_ledger']=pointer(args.source_ledger)
    if args.plan:record['plan']=pointer(args.plan)
    if args.reference:record['reference']=pointer(args.reference)
    pipeline.write_json(receipt,record)
    try:
        display=create_stage(original,stage,args.mode=='native');frozen=source(stage)
        record.update(source_root=str(stage),display_only_project_adjustment=display)
        import_logs=qa/'logs'/(stem+'_import');import_logs.mkdir()
        record['import']=pipeline.import_source([args.engine,'--headless','--editor','--path',str(stage),'--import'],import_logs,600)
        assert frozen==source(stage),'Cold import must not alter production source/assets'
        command=[args.engine,'--path',str(stage),'--script','res://tests/'+DRIVER.name,'--audio-driver','Dummy','--log-file',str(qa/'logs'/(stem+'_engine.log'))]
        if args.mode=='native':command+=['--resolution','800x480','--fixed-fps','60','--disable-vsync','--write-movie',str(qa/'temp'/(stem+'.avi'))]
        else:command+=['--headless']
        command+=['--','--mode='+args.mode,'--report='+str(raw),'--source-label='+args.label]
        if args.plan:command+=['--plan='+str(args.plan.resolve())]
        if args.mode=='native':command+=['--frames='+str(qa/'frames'/stem)]
        record.update(status='running');pipeline.write_json(receipt,record)
        record['process']=pipeline.run_logged(command,qa/'logs'/(stem+'.log'),1800)
        data=read(raw);validate(data,plan,read(args.reference) if args.reference else None)
        if args.mode=='discover':
            target=qa/'manifests'/(stem+'_input_plan.json');pipeline.write_json(target,tape_plan(data,raw));record['input_plan']=pointer(target)
        record.update(runtime=pointer(raw),checks=data['checks'],coverage=coverage(data),
                      executed_source_unchanged=original_hashes==source(original),frozen_source_unchanged=frozen==source(stage),
                      harness_unchanged=guard==harness(),player_after=profiles.player(),player_unchanged=player==profiles.player(),
                      canonical_after=source(ROOT),canonical_unchanged=canonical_before==source(ROOT))
        assert all(record[key] for key in ('executed_source_unchanged','frozen_source_unchanged','harness_unchanged','player_unchanged'))
        if args.mode=='native':
            raw_video=qa/'temp'/(stem+'.avi');record['raw_movie']=pointer(raw_video)
            ffmpeg=workspace.find_tool('ffmpeg',args.ffmpeg)
            # AVI MovieWriter embeds its real AudioServer PCM; extract without
            # decoding/reconstruction so the WAV preserves the same sample bytes.
            wave=raw_video.with_suffix('.wav')
            assert not wave.exists()
            record['audio_extraction']=pipeline.run_logged([ffmpeg,'-v','error','-i',str(raw_video),'-map','0:a:0','-c:a','copy',str(wave)],qa/'logs'/(stem+'_audio_extract.log'),180)
            record['raw_audio']=pointer(wave)
            record['raw_media']=media_info(raw_video,ffmpeg);record['pcm']=pcm_info(wave)
            actual_audio=next(row for row in record['raw_media']['streams'] if row['codec_type']=='audio')
            assert actual_audio['codec_name']=='pcm_s16le' and int(actual_audio['sample_rate'])==48000 and actual_audio['channels']==2
            actual_video=next(row for row in record['raw_media']['streams'] if row['codec_type']=='video')
            assert (actual_video['width'],actual_video['height'])==(800,480)
            record['additional_writer_startup_tail_frames']=int(actual_video['nb_frames'])-data['movie_frames']
            assert 0<=record['additional_writer_startup_tail_frames']<=6
            assert record['pcm']['nonzero_samples']>0
            target=qa/'temp'/(stem+'_validated.mp4')
            record['encoder']=pipeline.run_logged([ffmpeg,'-v','error','-i',str(raw_video),'-i',str(wave),'-map','0:v:0','-map','1:a:0',
                '-vf',caption_filter(data,args.label),'-c:v','libx264','-crf','18','-preset','fast','-pix_fmt','yuv420p','-c:a','aac','-b:a','192k','-movflags','+faststart',str(target)],qa/'logs'/(stem+'_encode.log'),600)
            record['decoder']=pipeline.run_logged([ffmpeg,'-v','error','-i',str(target),'-f','null','-'],qa/'logs'/(stem+'_decode.log'),180)
            record['video_candidate']=pointer(target)
            record['audio_scope']='Actual Godot MovieWriter AudioServer WAV from event-synchronized normal Sound/Music runtime. Dummy output keeps capture quiet; no offline invented sound reconstruction or phone/hardware claim.'
        record['status']='passed';pipeline.write_json(receipt,record)
        print(json.dumps({'status':'passed','receipt':pointer(receipt),'runtime':record['runtime'],'input_plan':record.get('input_plan'),'coverage':record['coverage'],'video_candidate':record.get('video_candidate')},indent=2),flush=True)
    except Exception as exc:
        record.update(status='rejected_attempt',error=str(exc),executed_source_unchanged=original_hashes==source(original),
                      harness_unchanged=guard==harness(),player_after=profiles.player(),player_unchanged=player==profiles.player())
        if isinstance(exc,pipeline.ProcessValidationError):record['failed_process']=exc.record
        if raw.exists():record['partial_runtime']=pointer(raw)
        pipeline.write_json(receipt,record);raise

if __name__=='__main__':main()
