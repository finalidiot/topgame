"""Freeze, import and film native new-power review with explicit source/player guards."""
from pathlib import Path
import argparse, json, shutil, sys
from datetime import datetime, timezone
ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT/'tools/build'), str(ROOT/'tools/workspace'), str(ROOT/'tools/presentation')]
import windows_checkpoint as pipeline
import workspace
from upgrade_sustain_003a1 import source, player

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--label',default='01');parser.add_argument('--publication',default='003a2_new_base_powers_review');args=parser.parse_args()
    assert args.label.isalnum()
    assert args.publication.replace('_','').isalnum()
    qa=workspace.create_task_workspace('003A.2')
    stem='003a2_base_power_review_'+args.label+'_'+datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')
    stage=qa/'temp'/stem;record_path=qa/'manifests'/(stem+'.json')
    assert not stage.exists() and not record_path.exists()
    before=source(ROOT); protected=player(); stage.mkdir()
    for name in ['scripts','assets']:shutil.copytree(ROOT/name,stage/name)
    for name in ['project.godot','main.tscn']:shutil.copy2(ROOT/name,stage/name)
    (stage/'tests').mkdir()
    driver=ROOT/'tests/capture_base_powers_003a2.gd';shutil.copy2(driver,stage/'tests'/driver.name)
    if driver.with_suffix('.gd.uid').exists():shutil.copy2(driver.with_suffix('.gd.uid'),stage/'tests'/driver.with_suffix('.gd.uid').name)
    assert source(stage)==before
    # MovieWriter initializes its extent before SceneTree._initialize. Change
    # only these QA window overrides, keeping canonical source bytes intact.
    project=stage/'project.godot';canonical_project=project.read_bytes();movie_project=canonical_project
    overrides={b'window/size/window_width_override=960':b'window/size/window_width_override=800',b'window/size/window_height_override=600':b'window/size/window_height_override=512'}
    for old,new in overrides.items():
        assert movie_project.count(old)==1
        movie_project=movie_project.replace(old,new)
    project.write_bytes(movie_project)
    engine=workspace.find_tool('godot');ffmpeg=workspace.find_tool('ffmpeg')
    raw=qa/'temp'/(stem+'.avi');runtime=qa/'manifests'/(stem+'_runtime.json');images=qa/'images'/stem
    target=qa/'video'/(args.publication+'.mp4')
    assert not target.exists(), 'Preserve existing media; use a fresh publication name for a new candidate'
    executed=source(stage)
    record={'schema':'003a2-base-power-review-provenance-v1','status':'running','source_before':before,'executed_source_before':executed,'stage':str(stage),'player_before':protected,'driver_sha256':pipeline.sha256(driver),'engine':engine,'movie_window_overrides':{old.decode():new.decode() for old,new in overrides.items()}}
    pipeline.write_json(record_path,record)
    try:
        record['import']=pipeline.import_source([engine,'--headless','--editor','--path',str(stage),'--import'],qa/'logs'/(stem+'_import'))
        assert source(stage)==executed, 'Import changed runtime input bytes'
        record['native']=pipeline.run_logged([engine,'--path',str(stage),'--fixed-fps','60','--disable-vsync','--resolution','800x512','--position','-2000,-2000','--write-movie',str(raw),'--script','res://tests/'+driver.name,'--','--report='+str(runtime),'--images='+str(images)],qa/'logs'/(stem+'_native.log'),1200)
        data=json.loads(runtime.read_text(encoding='utf-8'));assert not data['failures'] and data['movie_frames']>0 and not data['collection_accessed']
        record['encode']=pipeline.run_logged([ffmpeg,'-hide_banner','-y','-i',str(raw),'-vf','scale=1600:1024:flags=neighbor','-c:v','libx264','-preset','fast','-crf','19','-c:a','aac','-b:a','160k','-movflags','+faststart',str(target)],qa/'logs'/(stem+'_encode.log'),600)
        record.update(status='passed',runtime={'path':str(runtime),'sha256':pipeline.sha256(runtime)},media={'path':str(target),'sha256':pipeline.sha256(target),'bytes':target.stat().st_size},images=str(images),movie_frames=data['movie_frames'],cases=len(data['cases']),prismatic_states=next(r['states_seen'] for r in data['cases'] if r['configuration']['id']=='prismatic_changes'))
    except Exception as error:
        record.update(status='failed',error=repr(error));raise
    finally:
        record.update(source_after=source(ROOT),executed_source_after=source(stage),player_after=player())
        record['executed_source_unchanged']=record['executed_source_after']==executed
        record['canonical_source_unchanged']=record['source_after']==before
        record['player_unchanged']=record['player_after']==protected
        record['driver_unchanged']=pipeline.sha256(driver)==record['driver_sha256']
        pipeline.write_json(record_path,record)
        print(json.dumps({'receipt':str(record_path),'status':record['status'],'media':record.get('media'),'player_unchanged':record['player_unchanged'],'canonical_source_unchanged':record['canonical_source_unchanged']},indent=2),flush=True)
    assert record['executed_source_unchanged'] and record['player_unchanged'] and record['driver_unchanged']

if __name__=='__main__':main()
