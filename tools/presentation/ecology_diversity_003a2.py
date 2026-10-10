"""Matched legal availability model, exact common driver and declared gameplay."""
from __future__ import annotations
import argparse,hashlib,json,shutil,sys,zipfile
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
for folder in ['tools/build','tools/workspace','tools/presentation','tools/capture']:
    sys.path.insert(0,str(ROOT/folder))
import windows_checkpoint as pipeline
import workspace
from rpm_economy_study_003a1 import source,profile
from combat_art003a1 import frozen_project
BASELINE='b476c6d9240a2c9f03942cda70d43576cc3903da'
DRIVERS=['tests/observe_mutation_drafts_003a2.gd','tests/mutation_draft_policy_003a2.gd']

def run(args):
    qa=workspace.create_task_workspace('003A.2');stem='003a2_legal_diversity_'+datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f')
    player=profile();before_source=source(ROOT);hashes={name:pipeline.sha256(ROOT/name) for name in DRIVERS}
    engine=workspace.find_tool('godot',args.engine)
    baseline=qa/'temp'/f'{stem}_before';archive=qa/'temp'/f'{stem}_before.zip'
    pipeline.run_logged(['git','-C',str(ROOT),'archive','--format=zip','--output='+str(archive),BASELINE],qa/'logs'/f'{stem}_archive.log',180)
    baseline.mkdir()
    with zipfile.ZipFile(archive) as zipped:
        for member in zipped.infolist():
            target=(baseline/member.filename).resolve();assert target.is_relative_to(baseline.resolve()),'Archive target must stay in fresh QA stage'
        zipped.extractall(baseline)
    for name in DRIVERS:shutil.copy2(ROOT/name,baseline/name)
    old_source=source(baseline)
    imported=pipeline.import_source([engine,'--headless','--path',str(baseline),'--editor','--import'],qa/'logs'/f'{stem}_before_import',600)
    # Godot rewrites archived Windows sidecar newline bytes while building its
    # fresh cache. Prove identical decoded metadata before restoring the exact
    # accepted bytes; the imported resource/cache filenames and UIDs stay exact.
    rewrites={}
    with zipfile.ZipFile(archive) as zipped:
        for name,old_hash in old_source.items():
            path=baseline/name
            if pipeline.sha256(path)==old_hash:continue
            old=zipped.read(name);new=path.read_bytes()
            assert name.endswith('.import') and old.replace(b'\r\n',b'\n')==new.replace(b'\r\n',b'\n'),name+' changed beyond import newline normalization'
            rewrites[name]={'archive_sha256':old_hash,'imported_sha256':hashlib.sha256(new).hexdigest(),'normalized_content_equal':True}
            path.write_bytes(old)
    imported['verified_newline_only_sidecars_restored_exactly']=rewrites
    assert source(baseline)==old_source
    current,original,current_source=frozen_project(qa,stem+'_after');assert original==before_source
    phases=[]
    for label,stage,frozen in [('before',baseline,old_source),('after',current,current_source)]:
        report=qa/'manifests'/f'{stem}_{label}.json'
        command=[engine,'--headless','--path',str(stage),'--script','res://tests/observe_mutation_drafts_003a2.gd','--','--report='+str(report),'--label='+label,'--seeds='+str(args.seeds)]
        if label=='after':command+=['--require-new']
        process=pipeline.run_logged(command,qa/'logs'/f'{stem}_{label}.log',600)
        data=json.loads(report.read_text());assert data['failures']==[]
        assert source(stage)==frozen and hashes=={name:pipeline.sha256(stage/name) for name in DRIVERS}
        phases.append({'label':label,'report':str(report),'report_sha256':pipeline.sha256(report),'stage':str(stage),'source':frozen,'process':process,'summary':data})
    assert profile()==player and source(ROOT)==before_source and hashes=={name:pipeline.sha256(ROOT/name) for name in DRIVERS}
    out=qa/'manifests'/f'{stem}_comparison.json'
    result={'schema':'003a2-build-diversity-legal-model-v1','seeds':args.seeds,'baseline_commit':BASELINE,'same_driver_sha256':hashes,'phases':phases,'baseline_import':imported,'player_before':player,'player_after':profile(),'player_and_backups_unchanged':True,'current_production_source_unchanged':True,'source_git_sha':pipeline.git(ROOT,'rev-parse','HEAD'),'scope':'Five declared analytical preferences plus attributed elimination-XP fixture inputs. Real RunContext offers/claim tokens/eligibility/sibling closure/seven-family cap. Matched seeds and exact driver across accepted b476 and current catalogue. Availability/choices are not natural XP timing, player preference, win rates, live quotas or universal-pick balance. Gameplay initial-condition evidence is attached separately.'}
    pipeline.write_json(out,result);print(json.dumps({'passed':True,'comparison':str(out),'before':phases[0]['report'],'after':phases[1]['report']},indent=2),flush=True)

def assemble(args):
    qa=workspace.create_task_workspace('003A.2');study=json.loads(args.comparison.read_text());movie=json.loads(args.gameplay.read_text())
    assert len(study['phases'])==2 and not movie['failures'] and len(movie['scenes'])==8
    assert all(not p['summary']['failures'] for p in study['phases'])
    # Only the declared initial-window dimensions differ across the observers.
    study_source=study['phases'][1]['source'];movie_source=movie['frozen_source']
    assert {k:v for k,v in study_source.items() if k!='project.godot'}=={k:v for k,v in movie_source.items() if k!='project.godot'}
    result={**study,'legal_model_comparison':str(args.comparison),'legal_model_sha256':pipeline.sha256(args.comparison),'actual_gameplay_report':str(args.gameplay),'actual_gameplay_report_sha256':pipeline.sha256(args.gameplay),'runtime_scenes':movie['scenes'],'runtime_video':movie.get('video'),'runtime_video_sha256':movie.get('video_sha256'),'native_gameplay_scope':movie['authenticity'],'human_balance_status':'PENDING HUMAN PLAYTEST; fixture procs and legal availability do not establish a universal balance ranking.'}
    out=qa/'manifests/003a2_build_diversity_simulation.json';assert not out.exists(),'Preserve prior final study'
    pipeline.write_json(out,result);print(json.dumps({'passed':True,'required_report':str(out),'sha256':pipeline.sha256(out)},indent=2),flush=True)

def main():
    p=argparse.ArgumentParser(description=__doc__);sub=p.add_subparsers(dest='mode',required=True)
    observe=sub.add_parser('run');observe.add_argument('--seeds',type=int,default=256);observe.add_argument('--engine')
    finish=sub.add_parser('assemble');finish.add_argument('--comparison',type=Path,required=True);finish.add_argument('--gameplay',type=Path,required=True)
    args=p.parse_args();run(args) if args.mode=='run' else assemble(args)
if __name__=='__main__':main()
