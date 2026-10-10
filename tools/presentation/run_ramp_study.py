"""Guard natural earned Run observations; compare censored timing and early pressure."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import statistics
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/workspace'))
sys.path.insert(0, str(ROOT / 'tools/build'))
import workspace
import windows_checkpoint as pipeline

def source(project):
    paths = [project / 'project.godot']
    for folder in ['scripts', 'assets']:
        paths += [p for p in sorted((project / folder).rglob('*')) if p.is_file()]
    return {p.relative_to(project).as_posix(): pipeline.sha256(p) for p in paths}

def observe(args, task):
    project = args.project.resolve()
    stem = '003a1_natural_ramp_' + args.label + '_' + datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f')
    report = task / 'manifests' / (stem + '.json')
    provenance = task / 'manifests' / (stem + '_provenance.json')
    collection = task / 'temp' / stem
    driver = ROOT / 'tests/observe_run_ramp.gd'
    before = source(project)
    profile = pipeline.production_profile(ROOT)
    guard = {'project': str(project), 'label': args.label, 'source_before': before, 'driver_sha256': pipeline.sha256(driver), 'profile_before': profile, 'scope': 'External identical observation driver preloads res:// production code from the selected project. Source remains unchanged; isolated collections only.'}
    assert not report.exists() and not provenance.exists()
    provenance.write_text(json.dumps(guard, indent=2) + '\n')
    command = [workspace.find_tool('godot', args.engine), '--headless', '--path', str(project), '--script', str(driver), '--', '--report=' + str(report), '--collection-prefix=' + str(collection), '--horizon=' + str(args.horizon)]
    if args.case: command.append('--case=' + args.case)
    if args.seed is not None: command.append('--seed=' + str(args.seed))
    process = pipeline.run_logged(command, task / 'logs' / (stem + '.log'), 1200)
    after = source(project)
    profile_after = pipeline.production_profile(ROOT)
    guard.update(process=process, source_after=after, source_unchanged=before == after, profile_after=profile_after, profile_unchanged=profile == profile_after, driver_unchanged=guard['driver_sha256'] == pipeline.sha256(driver), report=str(report), report_sha256=pipeline.sha256(report))
    provenance.write_text(json.dumps(guard, indent=2) + '\n')
    assert all(guard[key] for key in ['source_unchanged', 'profile_unchanged', 'driver_unchanged']), 'Observation guard failed'
    data = json.loads(report.read_text())
    print(json.dumps({'report': str(report), 'provenance': str(provenance), 'runs': len(data['runs']), 'source_unchanged': True, 'profile_unchanged': True}, indent=2), flush=True)
    return report

def common_window(row, end):
    trace = [point for point in row['trace'] if point['time'] <= end]
    return {key: statistics.mean(float(point[key]) for point in trace) if trace else None for key in ['pressure', 'full', 'small', 'level', 'investments']}

def compare(args, task):
    before = json.loads(args.before.read_text())
    after = json.loads(args.after.read_text())
    by_id = {(r['id'], r['seed']): r for r in after['runs']}
    pairs = []
    keys = ['first_contact', 'first_meaningful_contact', 'first_commit', 'first_specialist', 'first_swarm', 'first_elite', 'first_boss', 'first_overlap', 'average_pressure', 'average_full', 'average_small', 'longest_empty_gap', 'longest_low_pressure_gap', 'longest_contact_gap', 'commits_per_minute', 'elapsed', 'level', 'draft_count', 'threats_cleared']
    for row in before['runs']:
        current = by_id[(row['id'], row['seed'])]
        assert row['context'] == current['context'], 'Starting assembly and sampled control style must match'
        shared = min(row['elapsed'], current['elapsed'])
        pairs.append({'id': row['id'], 'seed': row['seed'], 'build': row['context']['build'], 'policy': row['context']['style'], 'before': {key: row[key] for key in keys}, 'after': {key: current[key] for key in keys}, 'before_censored_at_horizon': not row['ended_naturally'], 'after_censored_at_horizon': not current['ended_naturally'], 'before_reason': row['reason'], 'after_reason': current['reason'], 'shared_lifetime_seconds': shared, 'common_early_window_seconds': min(170.0, shared), 'before_common_early': common_window(row, min(170.0, shared)), 'after_common_early': common_window(current, min(170.0, shared)), 'before_drafts': row['drafts'], 'after_drafts': current['drafts']})
    summary = {}
    for key in keys:
        old = [p['before'][key] for p in pairs if p['before'][key] >= 0]
        new = [p['after'][key] for p in pairs if p['after'][key] >= 0]
        summary[key] = {'before_mean_observed': statistics.mean(old) if old else None, 'after_mean_observed': statistics.mean(new) if new else None, 'before_observed_n': len(old), 'after_observed_n': len(new)}
        matched = [p for p in pairs if p['before'][key] >= 0 and p['after'][key] >= 0]
        summary[key].update(both_observed_n=len(matched), before_mean_when_both_observed=statistics.mean(p['before'][key] for p in matched) if matched else None, after_mean_when_both_observed=statistics.mean(p['after'][key] for p in matched) if matched else None)
    before_proof = json.loads(args.before.with_name(args.before.stem + '_provenance.json').read_text())
    after_proof = json.loads(args.after.with_name(args.after.stem + '_provenance.json').read_text())
    assert before_proof['driver_sha256'] == after_proof['driver_sha256'], 'Identical external driver required'
    assert before_proof['source_unchanged']
    assert all(proof[key] for proof in [before_proof, after_proof] for key in ['profile_unchanged', 'driver_unchanged'])
    variance = None
    if not after_proof['source_unchanged']:
        assert args.ui_variance_proof, 'A source variance needs an explicit preserved narrow proof'
        variance = json.loads(args.ui_variance_proof.read_text())
        changed = [key for key in after_proof['source_before'] if after_proof['source_before'][key] != after_proof['source_after'].get(key)]
        assert changed == ['scripts/main.gd'], changed
        assert variance['before_main_sha256'] == after_proof['source_before']['scripts/main.gd']
        assert variance['after_main_sha256'] == after_proof['source_after']['scripts/main.gd']
        assert variance['only_unhandled_input_changed'] and variance['physical_and_draft_methods_identical']
    old_project, new_project = Path(before_proof['project']), Path(after_proof['project'])
    def tuning(project):
        text = (project / 'scripts/threat_director.gd').read_text()
        start = text.index('const TUNING: Dictionary = ') + len('const TUNING: Dictionary = ')
        return json.loads(text[start:text.index('\n}', start) + 2])
    old_tuning, new_tuning = tuning(old_project), tuning(new_project)
    timing_keys = {'tier_seconds', 'breath_min', 'breath_max', 'drain_max'}
    old_stats = {k: v for k, v in old_tuning.items() if k not in timing_keys}
    new_stats = {k: v for k, v in new_tuning.items() if k not in timing_keys}
    old_roles = (old_project / 'scripts/enemy_roles.gd').read_text()
    new_roles = (new_project / 'scripts/enemy_roles.gd').read_text()
    normalized_roles = re.sub(r'^const COMMIT_(?:START|MATURITY)_SECONDS: float = [0-9.]+\n', '', new_roles, flags=re.M)
    normalized_roles = normalized_roles.replace('COMMIT_START_SECONDS', '35.0').replace('COMMIT_MATURITY_SECONDS', '325.0')
    old_director = (old_project / 'scripts/threat_director.gd').read_text()
    new_director = (new_project / 'scripts/threat_director.gd').read_text()
    seed_line = 'rng.seed = Seeds.derive(seed_value,"threat_director/v1")'
    invariants = {'all_non_timing_director_tuning_identical': old_stats == new_stats, 'non_timing_tuning': old_stats, 'enemy_roles_only_commit_start_constants_changed': normalized_roles == old_roles, 'enemy_builds_elite_boss_mass_speed_damage_profiles_unchanged': normalized_roles == old_roles, 'director_rng_seed_derivation_unchanged': seed_line in old_director and seed_line in new_director, 'same_external_observer_driver': True, 'before_source_unchanged': before_proof['source_unchanged'], 'after_source_unchanged': after_proof['source_unchanged'], 'profile_driver_and_allowed_source_variance_guards_passed': True, 'no_opening_swarm_before_28_seconds': all(r['first_swarm'] < 0 or r['first_swarm'] >= 28.0 for r in after['runs'])}
    assert all(invariants[key] for key in ['all_non_timing_director_tuning_identical', 'enemy_roles_only_commit_start_constants_changed', 'director_rng_seed_derivation_unchanged', 'no_opening_swarm_before_28_seconds'])
    result = {'schema': '003a1-run-ramp-comparison-v1', 'scope': 'Natural actual Main XP and legal seeded offers, every production combat tick and Director admission. Starting assemblies and deterministic sampled controls are labelled policies. Different natural outcomes censor timings; -1 means not observed, never zero or infinite. Averages of observed event times are descriptive, not uncensored timing estimates. Full candidate includes other hotfix changes; common early windows limit survival-length confounding.', 'before_report': str(args.before), 'after_report': str(args.after), 'before_sha256': pipeline.sha256(args.before), 'after_sha256': pipeline.sha256(args.after), 'horizon_seconds': before['horizon'], 'pairs': pairs, 'summary': summary, 'invariants': invariants, 'before_timing': {k:v for k,v in old_tuning.items() if k in timing_keys}, 'after_timing': {k:v for k,v in new_tuning.items() if k in timing_keys}, 'natural_investment': 'All draft rows include the actual earned XP total, seeded legal offer, chosen power/branch and owned ranks. No injected powers or XP.', 'build_labels': {'bastion':'Stock Bastion', 'breaker':'Stock Breaker', 'vane':'Declared Balance / Mid / Needle custom assembly with Vane handling; not stock Vane', 'custom_defence':'Declared Hammerfall / Ballast / Tripod custom defensive assembly'}, 'limitations': ['Bots are sampled input policies, not human feel.', 'Mature invested AFK comparison is a separate fixture and is not replaced by these opening-to-loss observations.', 'Earlier available threats need budget and a safe port, so eligibility is not a guaranteed admission time.']}
    output = args.output or task / 'manifests/003a1_run_ramp_comparison.json'
    if variance:
        result['source_variance'] = {'proof': str(args.ui_variance_proof), 'proof_sha256': pipeline.sha256(args.ui_variance_proof), 'details': variance, 'observed_main_sha256': after_proof['source_before']['scripts/main.gd'], 'final_ui_main_sha256': after_proof['source_after']['scripts/main.gd'], 'reason': 'During observation, only Main._unhandled_input was corrected for Nintendo Back/Burst routing. This driver calls Main._action for normal drafts and Battle.test_step for sampled controls, and never emits controller/key UI events. Physics, Director, drafts and every other Main method are verified identical. Original raw source-change failure is retained; no claim of whole-source byte equality is made.'}
    assert not output.exists(), 'Preserve prior comparison'
    output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'comparison': str(output), 'pairs': len(pairs), 'summary': summary}, indent=2), flush=True)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, default=ROOT)
    parser.add_argument('--label', default='candidate')
    parser.add_argument('--engine')
    parser.add_argument('--horizon', type=float, default=600.0)
    parser.add_argument('--case')
    parser.add_argument('--seed', type=int)
    parser.add_argument('--before', type=Path)
    parser.add_argument('--after', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--ui-variance-proof', type=Path)
    args = parser.parse_args()
    task = workspace.create_task_workspace('003A.1')
    if args.before and args.after: compare(args, task)
    else: observe(args, task)

if __name__ == '__main__': main()
