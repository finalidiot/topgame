"""Offline deterministic Ghost Circuit before/after geometry observations."""
from __future__ import annotations
import argparse,json,sys,shutil
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/build'));sys.path.insert(0,str(ROOT/'tools/workspace'));sys.path.insert(0,str(ROOT/'tools/presentation'))
import windows_checkpoint as pipeline
import workspace
from rpm_economy_study_003a1 import source,profile

def observe_main():
    p=argparse.ArgumentParser();p.add_argument('--project',type=Path,required=True);p.add_argument('--label',required=True);p.add_argument('--engine');p.add_argument('--horizon',type=float,default=60);p.add_argument('--case-set',choices=['standard','manual'],default='standard');a=p.parse_args()
    qa=workspace.create_task_workspace('003A.1');stamp=datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f');stem='003a1_ghost_accessibility_'+a.label+'_'+stamp
    project=a.project.resolve(); out=qa/'manifests'/f'{stem}.json'; proof=out.with_name(out.stem+'_provenance.json')
    for driver in ['observe_ghost_accessibility_003a1.gd','ghost_circuit_diagnostics_003a1.gd']:
        if project!=ROOT:shutil.copy2(ROOT/'tests'/driver,project/'tests'/driver)
    before=source(project);player=profile();observer={name:pipeline.sha256(project/'tests'/name) for name in ['observe_ghost_accessibility_003a1.gd','ghost_circuit_diagnostics_003a1.gd']}
    guard={'project':str(project),'label':a.label,'source_before':before,'player_before':player,'observer':observer};pipeline.write_json(proof,guard)
    log=qa/'logs'/f'{stem}.log'
    process=pipeline.run_logged([workspace.find_tool('godot',a.engine),'--headless','--path',str(project),'--script','res://tests/observe_ghost_accessibility_003a1.gd','--','--report='+str(out),'--horizon='+str(a.horizon),'--case-set='+a.case_set],log,1800)
    guard.update(source_after=source(project),player_after=profile(),process=process,report=str(out),report_sha256=pipeline.sha256(out));guard.update(source_unchanged=guard['source_before']==guard['source_after'],player_unchanged=guard['player_before']==guard['player_after']);pipeline.write_json(proof,guard)
    assert guard['source_unchanged'] and guard['player_unchanged']
    data=json.loads(out.read_text(encoding='utf-8'));assert len(data['runs'])==(6 if a.case_set=='manual' else 24)
    print(json.dumps({'report':str(out),'proof':str(proof),'summary':[{'id':r['configuration']['id'],'seed':r['seed'],'seconds':r['survival'],'paid_attempts':r['paid_attempts'],'closures':r['closed_count'],'max_speed':r['max_speed'],'reasons':r['reasons']} for r in data['runs']]},indent=2),flush=True)
def compare_main():
    p=argparse.ArgumentParser();p.add_argument('--before',type=Path,required=True);p.add_argument('--after',type=Path,required=True);p.add_argument('--before-manual',type=Path,required=True);p.add_argument('--after-manual',type=Path,required=True);p.add_argument('--human-save-boundary',action='store_true');a=p.parse_args(sys.argv[2:])
    qa=workspace.create_task_workspace('003A.1'); targets=[qa/'003a1_ghost_circuit_accessibility.json',qa/'manifests/003a1_ghost_circuit_accessibility.json']
    assert not any(t.exists() for t in targets),'Preserve prior evidence'
    groups=[]; pairs=[]; evidence=[]
    for label,old_path,new_path in [('feedback_routes',a.before,a.after),('unassisted_manual_input',a.before_manual,a.after_manual)]:
        old=json.loads(old_path.read_text(encoding='utf-8')); new=json.loads(new_path.read_text(encoding='utf-8'))
        op=json.loads(old_path.with_name(old_path.stem+'_provenance.json').read_text(encoding='utf-8')); np=json.loads(new_path.with_name(new_path.stem+'_provenance.json').read_text(encoding='utf-8'))
        assert op['source_unchanged'] and np['source_unchanged'] and np['player_unchanged']
        assert op['player_unchanged'] or (label=='feedback_routes' and a.human_save_boundary)
        assert op['observer']['observe_ghost_accessibility_003a1.gd']==np['observer']['observe_ghost_accessibility_003a1.gd']
        if label=='unassisted_manual_input': assert op['observer']==np['observer'] and op['player_unchanged']
        assert old['horizon']==new['horizon'] and old['seeds']==new['seeds']
        changes=[k for k in op['source_before'] if op['source_before'][k]!=np['source_before'].get(k)]
        assert changes==['scripts/power_runtime.gd']
        indexed={(r['configuration']['id'],r['seed']):r for r in new['runs']}
        for row in old['runs']:
            after=indexed[(row['configuration']['id'],row['seed'])]; assert row['configuration']==after['configuration']
            def summary(r):
                eligible=len(r['candidates']); successful=r['closed_count']; misses=sum(not v['actual_closure'] for v in r['candidates'])
                first=r['closures'][0]['time'] if r['closures'] else None
                return {'actual_seconds':r['survival'],'outcome':r['outcome'],'final_rpm':r['rpm'],'paid_trace_emissions':r['trace_emissions'],'total_paid_emission_frames':r['paid_attempts'],'eligible_meaningful_paid_closure_opportunities':eligible,'successful_circuits':successful,'eligible_gap_misses':misses,'eligible_opportunity_failure_rate':misses/eligible if eligible else None,'first_actual_closure_time':first,'nonqualification_reasons_by_simulation_frame':r['reasons'],'actual_closures':r['closures']}
            pairs.append({'group':label,'configuration':row['configuration'],'seed':row['seed'],'before':summary(row),'after':summary(after)})
        evidence.append({'group':label,'before':str(old_path),'before_sha256':pipeline.sha256(old_path),'after':str(new_path),'after_sha256':pipeline.sha256(new_path),'before_provenance':str(old_path.with_name(old_path.stem+'_provenance.json')),'after_provenance':str(new_path.with_name(new_path.stem+'_provenance.json')),'runtime_changes':changes,'driver_identical':True,'diagnostic_reader_identical':op['observer']['ghost_circuit_diagnostics_003a1.gd']==np['observer']['ghost_circuit_diagnostics_003a1.gd'],'diagnostic_reader_difference_scope':'The original baseline has no named Ghost constants, so old fallback values are exact. The after reader explicitly reads inherited constants to report the fixed56 threshold; geometry/control analysis otherwise unchanged. Manual comparison uses byte-identical updated observers.' if label=='feedback_routes' else 'Byte-identical observers.','before_player_unchanged':op['player_unchanged'],'after_player_unchanged':np['player_unchanged'],'human_save_boundary':'Human explicitly confirmed playing/saving during original before study. Newer collection/backup were preserved; observer creates Battle only and never Main, Collection or preferences. This stage does not claim whole-stage profile byte equality.' if not op['player_unchanged'] else None})
    import statistics
    cases=[]
    for case in sorted({r['configuration']['id'] for r in pairs}):
        selected=[r for r in pairs if r['configuration']['id']==case]
        cases.append({'id':case,'configuration':selected[0]['configuration'],'before_closures':[r['before']['successful_circuits'] for r in selected],'after_closures':[r['after']['successful_circuits'] for r in selected],'before_eligible_gap_misses':sum(r['before']['eligible_gap_misses'] for r in selected),'after_eligible_gap_misses':sum(r['after']['eligible_gap_misses'] for r in selected),'first_closure_before':[r['before']['first_actual_closure_time'] for r in selected],'first_closure_after':[r['after']['first_actual_closure_time'] for r in selected]})
    missed={label:sum(r[label]['eligible_gap_misses'] for r in pairs) for label in ['before','after']}
    closures={label:sum(r[label]['successful_circuits'] for r in pairs) for label in ['before','after']}
    before_gaps=[v['candidate']['gap'] for path in [a.before,a.before_manual] for r in json.loads(path.read_text(encoding='utf-8'))['runs'] for v in r['candidates'] if not v['actual_closure']]
    quantiles=statistics.quantiles(before_gaps,n=100,method='inclusive')
    natural_examples=[]
    after_manual=json.loads(a.after_manual.read_text(encoding='utf-8'))
    for row in after_manual['runs']:
        if row['configuration']['id']!='vane_manual_imperfect':continue
        natural_examples.append({'id':row['configuration']['id'],'seed':row['seed'],'starting_loadout_fixture':{'starter':'vane','afterimage_rank':3,'mutation':'ghost_circuit','high_gear_rank':1},'controls':'5Hz sampled direct stick rotation1.45rad/s +sin(time*3.4)*.22radian error; no position/velocity correction, Burst or Brake.','actual_closures':row['closures'][:3],'real_path_samples':row['route_samples'][:15],'source_evidence':str(a.after_manual),'scope':'Actual production fixed solver/AI/Director paid traces; initial owned powers are declared fixture, no live positions/traces/reserve/outcomes injected.'})
    data={'schema':'003a1-ghost-circuit-accessibility-v1','verified_starting_sha':'6a852cf0bedef0a9c8d4b0d7e76a2ee626b7f4e1','production_tuning':{'closure_world_units_before':38.0,'closure_world_units_after':56.0,'speed':112.0,'continuity':26.0,'emit_gap':6.0,'preview':70.0,'minimum_age':.85,'minimum_perimeter':180.0,'minimum_area':1300.0,'minimum_extent':32.0,'maximum_gap_perimeter_ratio':.22,'cooldown_seconds':3.5},'selection_reason':'Before eligible failed paid loops repeatedly miss at38–55.4world units. Fixed56 enlarges only their closure window; larger gaps still need movement. No speed/trace/area/perimeter/continuity/cooldown changes and no runtime percentile analysis.','before_failed_eligible_gap_distribution':{'n':len(before_gaps),'min':min(before_gaps),'median':statistics.median(before_gaps),'q75':quantiles[74],'q90':quantiles[89],'max':max(before_gaps)},'study':{'before_runs':len(pairs),'after_runs':len(pairs),'seconds_per_run':45,'seeds':[421,7341,2026],'starting_loadout_fixture':True,'actual_solver_ai_director':True,'player_save_opened_by_observer':False,'source_changes':['scripts/power_runtime.gd'],'force_equations_changed':False,'trace_costs_changed':False},'total_actual_closures':closures,'eligible_paid_gap_misses':missed,'eligible_gap_miss_reduction':1-missed['after']/missed['before'],'cases':cases,'paired_runs':pairs,'natural_examples':natural_examples,'evidence':evidence,'limits':['Feedback-circle guidance already reliably closes before; it is not proof every human succeeds.','Custom oval first closure improves15.4→15.1s, while total8→7 due earlier physical pulse changing later contact trajectories; counts do not improve uniformly.','Square changes interrupt paid connected path and remain0; slow/tiny/idle/straight do not become automatic.','Eligible opportunities exclude cooldown, missing geometry and unpaid frames. Total trace emissions are not individual attempted loops.','Initial Ghost/High Gear investment is a declared fixture; this is natural movement/physics evidence, not naturally earned power acquisition or human phone/controller acceptance.'],'human_acceptance':'Pending human review of forgiving closure and new physical circuit renderer.'}
    blob=json.dumps(data,indent=2)+'\n'
    for target in targets:target.write_text(blob,encoding='utf-8')
    print(json.dumps({'json':str(targets[0]),'manifest_copy':str(targets[1]),'sha256':pipeline.sha256(targets[0]),'closures':closures,'gap_misses':missed,'cases':len(cases)},indent=2))
if __name__=='__main__':
    if len(sys.argv)>1 and sys.argv[1]=='compare':compare_main()
    else:observe_main()
