"""Compare actual eight-scene physics across explicit production boundaries."""
from __future__ import annotations
import argparse,json,sys
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
for folder in ['tools/build','tools/workspace']:sys.path.insert(0,str(ROOT/folder))
import windows_checkpoint as pipeline
import workspace

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--before',type=Path,required=True);p.add_argument('--after',type=Path,required=True);args=p.parse_args()
    before=json.loads(args.before.read_text());after=json.loads(args.after.read_text())
    assert not before['failures'] and not after['failures']
    assert len(before['scenes'])==len(after['scenes'])==8
    assert before['fixture_dependency_sha256']==after['fixture_dependency_sha256'],'Exact common capture driver/fixture required'
    domains=['initial','control_history','contacts','peak_orbit','peak_bank','flow_frames','existing_power_counters','final','clock_failures']
    results=[]
    for old,new in zip(before['scenes'],after['scenes']):
        assert old['id']==new['id']
        equality={key:old[key]==new[key] for key in domains}
        assert all(equality.values()),(old['id'],equality)
        results.append({'scene':old['id'],'exact_domains':equality})
    # Native audio/draw metadata is intentionally outside this comparison.
    assert before['actor_samples']==after['actor_samples'],'Every sampled actor/control/clock/paid event/economy state must match'
    old_source=before['frozen_source'];new_source=after['frozen_source']
    changed={key:{'before':old_source.get(key),'after':new_source.get(key)} for key in sorted(set(old_source)|set(new_source)) if old_source.get(key)!=new_source.get(key)}
    assert changed and set(changed)=={'scripts/ecology_runtime.gd'},'Only declared minimal-host compatibility production boundary is allowed'
    report={'schema':'003a2-ecology-neutral-boundary-actual-replay-v1','before_report':str(args.before),'after_report':str(args.after),'before_report_sha256':pipeline.sha256(args.before),'after_report_sha256':pipeline.sha256(args.after),'actual_source_changed':changed,'common_fixture_sha256':before['fixture_dependency_sha256'],'scenes':results,'actor_samples':len(before['actor_samples']),'sampled_actual_physics_exact':True,'all_controls_contacts_events_clocks_ledgers_exact':True,'scope':'Exact common initial fixtures and observed controls through4800 actual fixed physics ticks. Every sampled actor pose/velocity/RPM/wobble/outcome, complete paid event/economy state and eight final states match across the declared pure catalogue/minimal-host compatibility correction. Source bytes differ honestly. This is selected fixture physics equality; no byte-identical movie or universal state-space claim.'}
    qa=workspace.create_task_workspace('003A.2');out=qa/'manifests'/('003a2_ecology_actual_boundary_equality_'+datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f')+'.json')
    pipeline.write_json(out,report);print(json.dumps({'passed':True,'manifest':str(out),'samples':report['actor_samples'],'source_changed':list(changed)},indent=2))
if __name__=='__main__':main()
