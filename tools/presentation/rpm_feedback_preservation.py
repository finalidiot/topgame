"""Verify this pass against its immutable start, including all player backups."""
from __future__ import annotations
import argparse, hashlib, json, re, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/build'))
sys.path.insert(0,str(ROOT/'tools/workspace'))
sys.path.insert(0,str(ROOT/'tools/presentation'))
import windows_checkpoint as pipeline
import workspace
from rpm_economy_study_003a1 import source, profile

def methods(path):
    text=path.read_text(encoding='utf-8')
    starts=list(re.finditer(r'^func ([A-Za-z_][A-Za-z_0-9]*)\(',text,re.M))
    result={}
    for i,m in enumerate(starts):
        lines=text[m.start():starts[i+1].start() if i+1<len(starts) else len(text)].splitlines()
        # A new top-level doc comment belongs to the following method, not
        # to the physical function above it. Indented body comments stay exact.
        while lines and (not lines[-1].strip() or lines[-1].startswith('#')):lines.pop()
        result[m.group(1)]='\n'.join(lines)
    return result

def verify(start_path,out):
    assert not out.exists(),'Keep prior evidence'
    start=json.loads(start_path.read_text())
    before=Path(start['before_project']);player=profile()
    old={k:v for k,v in start['player_files_before'].items() if k in ['collection.json','collection.json.bak','prototype.cfg'] or k.startswith('collection-backups/')}
    assert player==old,'Current player collection/preferences/recovery backups changed'
    old_assets={r['path']:r['sha256'] for r in start['snapshot']['inputs'] if r['path'].startswith('assets/')}
    assert all(pipeline.sha256(ROOT/name)==digest for name,digest in old_assets.items()),'An accepted existing asset changed'
    old_results=start['existing_validation']
    assert all(pipeline.sha256(ROOT/'tests/results'/name)==digest for name,digest in old_results.items()),'Historical compact evidence changed'
    music={p.relative_to(ROOT/'assets/audio/music').as_posix():pipeline.sha256(p) for p in sorted((ROOT/'assets/audio/music').rglob('*')) if p.is_file()}
    assert music==start['music_before'],'Accepted music changed'
    physical_paths=['scripts/starters.gd','scripts/parts.gd','scripts/part_physics.gd','scripts/threat_director.gd','scripts/enemy_roles.gd','scripts/enemy_builds.gd','scripts/roster_runtime.gd','scripts/defence_runtime.gd','scripts/beast_manifestations.gd','scripts/front_end.gd','scripts/packet_economy.gd','scripts/parts_collection.gd']
    physical_paths=[name for name in physical_paths if (before/name).is_file()]
    preserved={name:pipeline.sha256(ROOT/name)==pipeline.sha256(before/name) for name in physical_paths}
    assert all(preserved.values()),'Accepted controller/physics/AI/catalogue/beast/packet core changed'
    old_battle=methods(before/'scripts/battle.gd');new_battle=methods(ROOT/'scripts/battle.gd')
    expected_changes={'_resolve_pair_records','_resolve_small_pair','_draw'}
    changed={name for name in old_battle if old_battle[name]!=new_battle.get(name)}
    assert changed==expected_changes,changed
    for name in ['_attempt_burst','_update_fighter','_resolve_boundary','_ai_direction','_ai_should_brake']:
        if name in old_battle:assert old_battle[name]==new_battle[name],name
    qa=workspace.create_task_workspace('003A.1')
    comparison=json.loads((qa/'003a1_rpm_economy_comparison.json').read_text())
    observation_proof=json.loads(Path(comparison['after_provenance']).read_text())
    trial=Path(observation_proof['project'])
    observed=source(trial);current=source(ROOT)
    source_delta=[name for name in observed if observed[name]!=current.get(name)]
    allowed={'scripts/battle.gd','scripts/top_status_bars.gd','scripts/parts_package_probe.gd','assets/audio/pickup_collect.wav.import'}
    assert set(source_delta)<=allowed,source_delta
    trial_battle=methods(trial/'scripts/battle.gd')
    assert all(new_battle[name]==value for name,value in trial_battle.items() if name!='_draw'),'Observed physical solver differs from final source'
    required=['video/003a1_breaker_rpm_risk.mp4','video/003a1_dead_center_rpm_pressure.mp4','video/003a1_pickup_feel.mp4','images/003a1_combat_hud_matrix.png','003a1_rpm_economy_comparison.json','003a1_anchor_rearm_timing.json']
    media={name:{'path':str(qa/name),'sha256':pipeline.sha256(qa/name),'bytes':(qa/name).stat().st_size} for name in required}
    for name in ['003a1_rpm_economy_comparison.json','003a1_anchor_rearm_timing.json']:
        assert pipeline.sha256(qa/name)==pipeline.sha256(qa/'manifests'/name),'Canonical/requested evidence differs'
    record={'schema':'003a1-rpm-feedback-preservation-v1','start_record':str(start_path),'verified_starting_sha':start['sha'],'player_files_before':old,'player_files_after':player,'player_collection_preferences_and_all_backups_byte_identical':True,'player_files':len(player),'recovery_backup_files':sum(name.startswith('collection-backups/') for name in player),'accepted_assets_byte_identical':len(old_assets),'accepted_music_byte_identical':True,'historical_compact_evidence_unchanged':len(old_results),'preserved_core':preserved,'changed_battle_methods':sorted(changed),'new_battle_presentation_getter':sorted(set(new_battle)-set(old_battle)),'burst_movement_boundary_ai_methods_byte_identical':True,'final_vs_observed_source_delta':source_delta,'observation_runtime_variance_note':'Post-study changes are imported WAV format metadata, read-only packaged asset inspection, and visual bar attachment to the unchanged canonical shake. All observed Battle methods except drawing and every resource/physics/power/input/economy implementation are identical.','observed_battle_physics_methods_identical':True,'final_media':media,'human_acceptance':'Pending review; no current APK device acceptance.'}
    pipeline.write_json(out,record)
    print(json.dumps({'report':str(out),'player_files':len(player),'accepted_assets':len(old_assets),'source_delta':source_delta,'passed':True},indent=2),flush=True)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--start',type=Path,required=True);parser.add_argument('--out',type=Path,required=True)
    args=parser.parse_args();verify(args.start,args.out)
if __name__=='__main__':main()
