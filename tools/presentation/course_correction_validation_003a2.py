"""Run current contracts in a frozen external stage; preserve every failed attempt."""
from pathlib import Path
from datetime import datetime, timezone
import argparse, json, os, re, shutil, subprocess, sys, time
ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'tools/build'),str(ROOT/'tools/workspace'),str(ROOT/'tools/presentation')]
import windows_checkpoint as pipeline
import workspace
from upgrade_sustain_003a1 import source, player

RECENT=['pickup_positions_003a1','shop_ux_003a1','shop_focus_cost_003a1','combat_audio_mix_003a1','native_window_layout_003a1','enemy_intelligence_003a1','enemy_power_packages_003a1','enemy_burst_sampling_003a1','ability_card_hierarchy_003a1','deep_run_density_003a1','window_client_fill_003a1','level_up_back_003a1','ghost_circuit_hijack_003a1','ghost_physics_003a1','orbit_full_carve_003a1','chain_hard_hits_003a1','predator_pursuit_visual_003a1','mutation_acquisition_003a2','mutation_physics_003a2','mutation_solver_contract_003a2','ecology_neutral_hosts_003a2','frontend_layout_003a2','frontend_pages_003a2','frontend_packet_touch_003a2','frontend_interactions_003a2','frontend_classes_003a2','mobile_menu_hud_safe_003a2','touch_fullscreen_projection_003a2','touch_fullscreen_003a2','android_fullscreen_layout_003a2','mobile_canvas_policy_003a2','mobile_choice_contact_003a2','levelup_fullclient_003a2','bastion_feel_003a2','base_powers_003a2','course_correction_ui_003a2','controller_rumble_003a2']

RECENT += ['prismatic_hud_003a2']

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--only',nargs='*');parser.add_argument('--mode',choices=['headless','python'],default='headless');parser.add_argument('--python-executable',default=sys.executable,help='Interpreter with the selected Python test dependencies');args=parser.parse_args()
    qa=workspace.create_task_workspace('003A.2');os.environ['TOPGAME_QA_ROOT']=str(qa.parent)
    stem='003a2_course_regression_'+args.mode+'_'+datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f')
    receipt=qa/'manifests'/(stem+'.json');stage=qa/'temp'/stem
    before=source(ROOT);protected=player();stage.mkdir()
    for name in ['scripts','assets','tests']:shutil.copytree(ROOT/name,stage/name)
    for name in ['project.godot','main.tscn']:shutil.copy2(ROOT/name,stage/name)
    assert source(stage)==before
    if args.mode=='headless':
        previous=json.loads((ROOT/'tests/results/003a1_combat_acceptance_validation.json').read_text(encoding='utf-8'))
        names=list(dict.fromkeys([r['name'] for r in previous['headless']['suites']]+RECENT))
        names=args.only or names
        assert all((stage/'tests'/('test_'+name+'.gd')).exists() for name in names), 'Every selected test must exist'
    else:names=args.only or ['build','workspace','parts','presentation','android','audio','art']
    harness_paths=[p for p in (stage/'tests').rglob('*') if p.is_file()] if args.mode=='headless' else [p for category in names for p in (ROOT/'tools'/category).rglob('*.py')]
    harness={str(p):pipeline.sha256(p) for p in harness_paths}
    record={'schema':'003a2-course-correction-regression-v1','status':'running','mode':args.mode,'stage':str(stage),'source_before':before,'player_before':protected,'harness_before':harness,'suites':[],'scope':'Actual current contracts; frozen source and explicit isolated QA profiles. Seeded/state fixtures remain scoped by their own drivers. Failed attempts are preserved; no hardware or human enjoyment claim.'}
    pipeline.write_json(receipt,record)
    try:
        engine=workspace.find_tool('godot')
        if args.mode=='headless':record['import']=pipeline.import_source([engine,'--headless','--editor','--path',str(stage),'--import'],qa/'logs'/(stem+'_import'))
        assert source(stage)==before
        for name in names:
            report=qa/'manifests'/(stem+'_'+name+'.json');profile=qa/'temp'/(stem+'_'+name+'_profile');log=qa/'logs'/(stem+'_'+name+'.log')
            if args.mode=='python':command=[args.python_executable,'-m','unittest','discover','-s',str(ROOT/'tools'/name),'-p','test_*.py','-v']
            else:
                command=[engine,'--headless']
                if name in ['input_acceptance_003a1','overdrive_lifecycle_003a1','shop_ux_003a1','level_up_back_003a1']:command+=['--fixed-fps','60','--disable-vsync']
                command+=['--path',str(stage),'--script','res://tests/test_'+name+'.gd','--','--report='+str(report)]
                if name not in ['parts_package','packet_package','parts_collection']:command+=['--qa-task=003A.2']
                if name=='controller_rumble_003a2':command+=['--out='+str(report)]
                if name in ['input_acceptance_003a1','overdrive_lifecycle_003a1','level_up_back_003a1']:command+=['--profiles='+str(profile)]
                if name=='level_up_back_003a1':command+=['--kind=flow']
                if name in ['mobile_shell_layout_003a1','touch_fullscreen_projection_003a2','frontend_classes_003a2']:command+=['--profile='+str(profile)+'.json']
                if name in ['frontend_interactions_003a2','android_fullscreen_layout_003a2','mobile_choice_contact_003a2','levelup_fullclient_003a2','controller_rumble_003a2','course_correction_ui_003a2']:command+=['--profile-prefix='+str(profile)]
                if name=='shop_ux_003a1':command+=['--mode=all','--diagnostic','--profile='+str(profile)+'.json']
                if name=='baseline_physics':command+=['--baseline-source='+str(ROOT.parent/'GyroBrothers-Worktrees/topgame-task-002a-baseline/scripts/battle.gd')]
            start=time.monotonic();code=None;timed_out=False
            with log.open('wb') as stream:
                try:code=subprocess.run(command,cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT,timeout=900).returncode
                except subprocess.TimeoutExpired:timed_out=True
            content=log.read_text(encoding='utf-8',errors='replace')
            counts=re.findall(r'checks[=: ]+(\d+)',content,re.I) or re.findall(r'(\d+)\s+(?:checks|assertions|field comparisons)',content,re.I)
            if args.mode=='python':counts=re.findall(r'Ran (\d+) tests?',content)
            checks=max(map(int,counts),default=0)
            summary=[line for line in content.splitlines() if re.search(r'PASS|checks|assertions|field comparisons|Ran \d+',line,re.I)]
            data=json.loads(report.read_text(encoding='utf-8')) if report.exists() else {}
            if isinstance(data.get('checks'),int):checks=max(checks,data['checks'])
            passed=code==0 and not pipeline.ERRORS.search(content) and not data.get('failures') and (checks>0 or bool(re.search(r'\b[A-Z0-9_]+_PASS\b',content)))
            row={'name':name,'passed':passed,'checks':checks,'exit_code':code,'timed_out':timed_out,'seconds':round(time.monotonic()-start,3),'command':command,'summary':summary[-1] if summary else '', 'log':str(log),'log_sha256':pipeline.sha256(log),'report':str(report) if report.exists() else None}
            record['suites'].append(row);pipeline.write_json(receipt,record);print(json.dumps({k:row[k] for k in ['name','passed','checks','seconds']}),flush=True)
        record['status']='passed' if all(r['passed'] for r in record['suites']) else 'failed'
    except Exception as error:record.update(status='failed',error=repr(error));raise
    finally:
        record.update(executed_source_after=source(stage),canonical_source_after=source(ROOT),player_after=player(),harness_after={str(p):pipeline.sha256(p) for p in harness_paths})
        record['source_unchanged']=record['executed_source_after']==before
        record['canonical_source_unchanged']=record['canonical_source_after']==before
        record['player_unchanged']=record['player_after']==protected
        record['harness_unchanged']=record['harness_before']==record['harness_after']
        record['failed_suites']=[r['name'] for r in record['suites'] if not r['passed']]
        record['checks']=sum(r['checks'] for r in record['suites'] if r['passed'])
        if not all(record[k] for k in ['source_unchanged','player_unchanged','harness_unchanged']):record['status']='failed'
        pipeline.write_json(receipt,record);print(json.dumps({k:record[k] for k in ['status','failed_suites','checks','source_unchanged','player_unchanged','harness_unchanged']}|{'receipt':str(receipt)},indent=2),flush=True)
    raise SystemExit(0 if record['status']=='passed' else 1)

if __name__=='__main__':main()
