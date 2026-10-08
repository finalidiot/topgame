"""Read-only preservation check against this pass's immutable starting record."""
from __future__ import annotations
import argparse,json,re,sys
from pathlib import Path
from datetime import datetime,timezone
ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'tools/build'),str(ROOT/'tools/presentation')]
import windows_checkpoint as pipeline
from rpm_economy_study_003a1 import profile,source

ART_CHANGED={
    *['assets/arena/'+name+'.png' for name in ['backdrop','structure','surface','markings','rear_rim','front_rim']],
    'assets/source-art/arena_foundry_eight.aseprite','assets/powers/identity_manifest.json',
    *['assets/'+folder+'/'+name+suffix for folder,suffixes in [('powers/identity',['_cards.png','_design.json','_manifest.json']),('source-art/power_identity_002c5',['_cards.aseprite'])] for name in ['redline','afterimage'] for suffix in suffixes]
}
def method(text,name):
    match=re.search(r'(?m)^func '+re.escape(name)+r'\(',text);assert match,name
    end=re.search(r'(?m)^func ',text[match.end():]);return text[match.start():match.end()+end.start() if end else len(text)].rstrip()
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--stem',required=True);args=parser.parse_args();assert re.fullmatch(r'[a-z0-9_-]+',args.stem)
    qa=ROOT.parent/'GyroBrothers-QA/003A.1';output=qa/'manifests'/f'{args.stem}.json';assert not output.exists()
    start=json.loads((qa/'manifests/003a1_combat_acceptance_start.json').read_text(encoding='utf-8'));baseline=Path(start['before_project'])
    def compare(base,folder):return {name:{'before':digest,'after':pipeline.sha256(folder/name) if (folder/name).is_file() else None} for name,digest in base.items() if not (folder/name).is_file() or pipeline.sha256(folder/name)!=digest}
    altered=compare(start['assets_before'],ROOT);unexpected=set(altered)-ART_CHANGED
    music_changes=compare(start['music_before'],ROOT);compact_changes=compare(start['existing_validation'],ROOT/'tests/results');qa_changes=compare(start['existing_qa_evidence'],qa)
    # These physical methods stay exact; collision's prefix through force,
    # damage, costs and power acceptance stays exact before presentation fields.
    old=(baseline/'scripts/battle.gd').read_text(encoding='utf-8');new=(ROOT/'scripts/battle.gd').read_text(encoding='utf-8')
    physical=['_update_ai','_ai_should_brake','_attempt_burst','_update_fighter','_drift_strength','_update_drift_tip','project','unproject_direction']
    unchanged={name:method(old,name)==method(new,name) for name in physical if re.search(r'(?m)^func '+name+r'\(',old)}
    prefix='# Presentation reads this accepted solver event;'
    unchanged['canonical_full_top_collision_force_loss_and_power_acceptance']=method(old,'_resolve_pair_records').split(prefix)[0]==method(new,'_resolve_pair_records').split(prefix)[0]
    locked_files=['assets/arena/manifest.json','assets/data/parts_catalogue.json','scripts/part_physics.gd','scripts/enemy_commitment.gd','scripts/threat_director.gd','scripts/beast_manifestations.gd']
    locked={name:pipeline.sha256(baseline/name)==pipeline.sha256(ROOT/name) for name in locked_files if (baseline/name).is_file()}
    now=profile();player_changes={name:{'before':digest,'current':now.get(name)} for name,digest in start['player_files_before'].items() if now.get(name)!=digest}
    boundary=qa/'manifests/003a1_upgrade_sustain_human_save_boundary.json'
    activity_path=qa/'manifests/003a1_combat_player_activity_boundary.json'
    activity=json.loads(activity_path.read_text(encoding='utf-8')) if activity_path.is_file() else {}
    failures=[]
    if unexpected:failures.append('Unrequested existing asset edits: '+str(sorted(unexpected)))
    if music_changes or compact_changes or qa_changes:failures.append('Locked music/historical evidence changed')
    if not all(unchanged.values()) or not all(locked.values()):failures.append('Core physical/preservation contract changed')
    if set(player_changes)-{'collection.json','collection.json.bak','prototype.cfg'}:failures.append('Recovery backups changed')
    if player_changes and not boundary.is_file():failures.append('Human save boundary evidence missing')
    if not activity.get('human_confirmed_play_or_save') or now!=activity.get('player_files_after_human'):failures.append('Current player data differs from the accepted24-file post-human boundary')
    if activity and pipeline.sha256(Path(activity['post_human_guard_report']))!=activity['post_human_guard_sha256']:failures.append('Post-human boundary proof changed')
    record={'schema':1,'task':'003A.1 final combat acceptance','status':'passed' if not failures else 'failed','created_utc':datetime.now(timezone.utc).isoformat(),'starting_sha':start['sha'],'current_head':pipeline.git(ROOT,'rev-parse','HEAD'),'runtime':source(ROOT),'existing_asset_count':len(start['assets_before']),'intentional_existing_art_changes':altered,'unexpected_existing_asset_changes':sorted(unexpected),'accepted_music_unchanged':not music_changes,'accepted_music_files':len(start['music_before']),'historical_compact_unchanged':not compact_changes,'historical_compact_files':len(start['existing_validation']),'historical_qa_unchanged':not qa_changes,'historical_qa_files':len(start['existing_qa_evidence']),'exact_physical_methods':unchanged,'locked_files':locked,'player_start_to_current_unchanged':not player_changes,'player_changes':player_changes,'player_file_count':len(now),'recovery_backups_start_to_current_unchanged':not set(player_changes)-{'collection.json','collection.json.bak','prototype.cfg'},'human_save_boundary':str(boundary) if player_changes else None,'player_policy':'User confirmed playing/saving during this pass. Collection/bak changed15:47UTC; preferences changed15:34UTC and still have historical fields without the new impact_numbers key, consistent with the prior human executable. Newer human build/settings/progress are preserved. This is not a false start-to-finish byte-identical claim; isolated stage/build guards fingerprint current data afresh. All21recovery-backupfiles stay exact against the original pass start.','failures':failures}
    record.update(post_human_activity_boundary=str(activity_path),post_human_player_and_backups_unchanged=now==activity.get('player_files_after_human'))
    pipeline.write_json(output,record);print(json.dumps({k:v for k,v in record.items() if k in ['status','failures','existing_asset_count','accepted_music_unchanged','historical_qa_unchanged','player_start_to_current_unchanged','player_file_count','post_human_player_and_backups_unchanged']},indent=2));assert not failures
if __name__=='__main__':main()
