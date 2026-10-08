"""Paired natural Run ledger observations; no production economy overrides."""
from __future__ import annotations
import argparse, json, statistics, sys
from pathlib import Path
from datetime import datetime, timezone
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tools/build'))
sys.path.insert(0, str(ROOT/'tools/workspace'))
import windows_checkpoint as pipeline
import workspace

def source(project):
    paths = [project/'project.godot', project/'main.tscn']
    for folder in ['scripts','assets']:
        paths += [p for p in sorted((project/folder).rglob('*')) if p.is_file()]
    return {p.relative_to(project).as_posix():pipeline.sha256(p) for p in paths}

def profile():
    folder=Path(pipeline.production_profile(ROOT)['directory'])
    paths=[folder/name for name in ['collection.json','collection.json.bak','prototype.cfg']]
    paths += [p for p in sorted((folder/'collection-backups').rglob('*')) if p.is_file()]
    return {p.relative_to(folder).as_posix():pipeline.sha256(p) for p in paths if p.is_file()}

def observe(args):
    qa=workspace.create_task_workspace(args.task)
    project=args.project.resolve()
    stem='003a1_rpm_economy_'+args.label+'_'+datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f')
    out=qa/'manifests'/f'{stem}.json'
    proof=out.with_name(out.stem+'_provenance.json')
    driver=ROOT/'tests/observe_rpm_economy_003a1.gd'
    before=source(project)
    guard={'project':str(project),'label':args.label,'source_before':before,'player_before':profile(),'driver_sha256':pipeline.sha256(driver)}
    pipeline.write_json(proof,guard)
    engine=workspace.find_tool('godot',args.engine)
    log=qa/'logs'/f'{stem}.log'
    command=[engine,'--headless','--path',str(project),'--log-file',str(qa/'logs'/f'{stem}_engine.log'),'--script',str(driver),'--','--report='+str(out),'--collection-prefix='+str(qa/'temp'/stem),'--horizon='+str(args.horizon)]
    if args.case: command.append('--case='+args.case)
    process=pipeline.run_logged(command,log,1500)
    guard.update(process=process,source_after=source(project),player_after=profile(),report=str(out),report_sha256=pipeline.sha256(out))
    guard.update(source_unchanged=guard['source_before']==guard['source_after'],player_unchanged=guard['player_before']==guard['player_after'],driver_unchanged=guard['driver_sha256']==pipeline.sha256(driver))
    pipeline.write_json(proof,guard)
    assert all(guard[key] for key in ['source_unchanged','player_unchanged','driver_unchanged'])
    data=json.loads(out.read_text())
    for row in data['runs']:
        assert row['ledger_closure_error']<1e-6
    print(json.dumps({'report':str(out),'provenance':str(proof),'runs':len(data['runs']),'source_unchanged':True,'player_unchanged':True},indent=2),flush=True)

def compare(args):
    qa=workspace.create_task_workspace(args.task)
    old=json.loads(args.before.read_text())
    new=json.loads(args.after.read_text())
    old['input_policy']=old['input_policy'].replace('10 Hz','5 Hz')
    assert old['seeds']==new['seeds'] and old['horizon']==new['horizon']
    proofs=[json.loads(p.with_name(p.stem+'_provenance.json').read_text()) for p in [args.before,args.after]]
    assert proofs[0]['driver_sha256']==proofs[1]['driver_sha256']
    assert all(p[k] for p in proofs for k in ['source_unchanged','player_unchanged','driver_unchanged'])
    by_id={(r['id'],r['seed']):r for r in new['runs']}
    loss_sources=['passive','movement','steering','braking','burst','collisions','walls','wobble','powers','redline']
    gain_sources=['combat_reclamation','elimination','elite','boss','clutch','slipstream','redline_motion','redline_contact','runaway','dead_centre','impact_sink','second_wind','pickups']
    for dataset in [old,new]:
        for run in dataset['runs']:
            for key in loss_sources:run['loss_by_source'].setdefault(key,0.0)
            for key in gain_sources:run['recovery_by_source'].setdefault(key,0.0)
            run['absolute_rpm']={key:run[key]*9000 for key in ['starting_rpm','final_rpm','minimum_rpm']}
            run['input_profile']={'style':run['context']['style'],'sample_rate_hz':5,'controlled_seconds':run['controlled_seconds'],'braking_seconds':run['braking_seconds'],'venting_seconds':run['venting_seconds'],'burst_requests':run['burst_requests'],'accepted_bursts':run['loss_by_source']['burst']/.013}
    pairs=[]
    for row in old['runs']:
        now=by_id[(row['id'],row['seed'])]
        assert row['context']==now['context']
        end=min(row['survival_seconds'],now['survival_seconds'])
        samples=[]
        for run in [row,now]:
            points=[p for p in run['trace'] if p['time']<=end]
            last=points[-1]
            losses=sum(last['losses'].values()); gains=sum(last['gains'].values())
            samples.append({'time':last['time'],'rpm':last['rpm'],'total_loss':losses,'total_recovered':gains,'recovery_to_loss_ratio':gains/max(1e-9,losses),'loss_by_source':last['losses'],'recovery_by_source':last['gains']})
        pairs.append({'id':row['id'],'seed':row['seed'],'context':row['context'],'before':row,'after':now,'shared_lifetime':end,'shared_trace_window':samples})
    summaries={}
    for context in old['runs']:
        case=context['id']
        if case in summaries:continue
        selection=[p for p in pairs if p['id']==case]
        sums={}
        for label in ['before','after']:
            runs=[p[label] for p in selection]
            sums[label]={key:statistics.mean(r[key] for r in runs) for key in ['survival_seconds','final_rpm','minimum_rpm','total_loss','total_recovered','seconds_above_90','seconds_above_75','seconds_below_50','seconds_below_25','meaningful_contacts']}
            sums[label]['outcomes']={kind:sum(r['outcome']==kind for r in runs) for kind in sorted({r['outcome'] for r in runs})}
            sums[label]['loss_by_source_mean']={key:statistics.mean(r['loss_by_source'].get(key,0) for r in runs) for key in sorted({k for r in runs for k in r['loss_by_source']})}
            sums[label]['recovery_by_source_mean']={key:statistics.mean(r['recovery_by_source'].get(key,0) for r in runs) for key in sorted({k for r in runs for k in r['recovery_by_source']})}
        summaries[case]=sums
    result={'schema':'003a1-rpm-economy-comparison-v1','scope':old['scope'],'input_policy':old['input_policy'],'source_metadata_correction':'Original observation prose says 10 Hz; actual tick%12 at 60 Hz is 5 Hz. The input code and driver bytes used in both observations were identical.','units':'Reserve values/losses/gains are fractions of 9000 RPM; each Run includes absolute_rpm. Seconds are actual simulation elapsed.','pickup_rpm_note':'Grounded pickups award rerolls only and generate zero RPM. Explicit zero source fields distinguish no observed recovery from missing accounting.','horizon':old['horizon'],'seeds':old['seeds'],'before_report':str(args.before),'after_report':str(args.after),'before_provenance':str(args.before.with_name(args.before.stem+'_provenance.json')),'after_provenance':str(args.after.with_name(args.after.stem+'_provenance.json')),'same_driver':True,'profile_unchanged':True,'max_ledger_closure_error':max(p[phase]['ledger_closure_error'] for p in pairs for phase in ['before','after']),'censoring_note':'Horizon is a lower bound on survival. Deaths diverge; paired shared-window source ledgers are included to avoid comparing unequal lifetimes as rates. Changed RPM affects natural AI outcomes, XP and offered drafts; all ordinary draft history is retained.','summary':summaries,'pairs':pairs}
    out=qa/'003a1_rpm_economy_comparison.json'
    assert not out.exists(),'Preserve previous comparison'
    pipeline.write_json(out,result)
    pipeline.write_json(qa/'manifests'/out.name,result)
    print(json.dumps({'report':str(out),'summary':summaries},indent=2),flush=True)

def main():
    parser=argparse.ArgumentParser()
    sub=parser.add_subparsers(dest='mode',required=True)
    for name in ['observe','compare']:
        p=sub.add_parser(name);p.add_argument('--task',default='003A.1')
        if name=='observe':
            p.add_argument('--project',type=Path,required=True);p.add_argument('--label',required=True);p.add_argument('--engine');p.add_argument('--horizon',type=float,default=600);p.add_argument('--case')
        else:
            p.add_argument('--before',type=Path,required=True);p.add_argument('--after',type=Path,required=True)
    args=parser.parse_args()
    (observe if args.mode=='observe' else compare)(args)
if __name__=='__main__':main()
