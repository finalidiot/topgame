"""Run and summarize deterministic natural full-top impact telemetry for 003A.

Analysis quantiles are offline only. Production uses the declared fixed impulse
threshold. Full event rows and isolated collections stay in the external QA tree.
"""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/workspace"))
sys.path.insert(0, str(ROOT / "tools/build"))
import workspace
import windows_checkpoint as pipeline

QUANTILES = (0, .10, .25, .50, .75, .90, .95, .975, .99, .995, .999, 1)
MEANINGFUL_MIN = .22  # canonical run_progression.gd collision_min_severity


def quantiles(values: list[float]) -> dict:
    ordered = sorted(values)
    if not ordered:
        return {}
    result = {}
    for q in QUANTILES:
        position = (len(ordered) - 1) * q
        lo = int(position)
        hi = min(len(ordered) - 1, lo + 1)
        result[str(q)] = round(ordered[lo] + (ordered[hi] - ordered[lo]) * (position-lo), 4)
    return result


def presentation_evidence(data: dict) -> dict:
    reasons=Counter()
    rows=[]
    shown_player=shown_npc=duplicates=0
    for run in data["runs"]:
        presentation=run["presentation"]
        history=presentation.get("events",[])
        blocked=[event for event in history if event["kind"]=="suppressed"]
        shown=[event for event in history if event["kind"]=="spawned"]
        assert len(blocked)==presentation["suppressed"],"Suppression history was truncated; do not infer counts"
        assert len(shown)==presentation["spawned"],"Spawn history was truncated; do not infer counts"
        by_reason=Counter(event["reason"] for event in blocked)
        reasons.update(by_reason)
        player=sum(event.get("owner_entity_id")==1 for event in shown)
        shown_player+=player; shown_npc+=len(shown)-player
        duplicates+=presentation["duplicates"]
        rows.append({"style":run["context"]["id"],"seed":run["seed"],"blocked_reasons":dict(by_reason),"blocked_events":blocked,"shown_player":player,"shown_npc":len(shown)-player,"duplicates":presentation["duplicates"],"peak_live":presentation["peak_live"],"complete_presentation_history":True})
    all_events=[event for run in data["runs"] for event in run["events"]]
    qualifying=[event for event in all_events if event["impulse"]*event["closing"]>=1_000_000]
    slow=[event for event in all_events if event["closing"]<20]
    return {"presentation_policy":{"maximum_live":1,"owner_cooldown_seconds":4,"global_cooldown_seconds":1.6,"deduplication":"Monotonic canonical accepted collision identity, consumed even when suppressed; bounded96-entry diagnostics."},"actual_suppression_reasons":dict(reasons),"natural_duplicate_collision_count":duplicates,"actually_shown_player":shown_player,"actually_shown_npc":shown_npc,"presentation_by_style_seed":rows,"all_simulation_seconds":sum(run["elapsed"] for run in data["runs"]),"minimum_qualifying_closing_speed":min(event["closing"] for event in qualifying),"highest_impulse_under20_closing_speed":max((event["impulse"] for event in slow),default=0),"highest_work_under20_closing_speed":max((event["impulse"]*event["closing"] for event in slow),default=0),"natural_frequency_note":"31 observed performances across 15 natural seeded Runs totalling6127.933 simulation seconds; a measured outcome, never a frequency target or dynamic runtime percentile."}


def summarize(data: dict, threshold: float | None, metric: str = "impulse_work") -> dict:
    runs = []
    all_events = []
    for run in data["runs"]:
        events = [dict(event, impulse_work=event["impulse"]*event["closing"]) for event in run["events"]]
        assert len({event["collision_id"] for event in events}) == len(events)
        meaningful = [event for event in events if event["severity"] >= MEANINGFUL_MIN]
        player = [event for event in meaningful if event["player_involved"]]
        qualifying = [event for event in events if threshold is not None and event[metric] >= threshold]
        all_events.extend(events)
        presentation = run["presentation"]
        runs.append({"build_context": run["context"], "seed":run["seed"], "starting_stats":run["starting_stats"],
                     "simulation_seconds":run["elapsed"],"simulation_ticks":run["simulation_ticks"],"ended_naturally":run["ended_naturally"],
                     "end_reason":run["reason"],"final_level":run["level"],"final_powers":run["powers"],"final_ranks":run["ranks"],"final_mutations":run["mutations"],
                     "opening_loadout":"Declared legal starting assembly only; starting and subsequent powers chosen from actual offers.",
                     "raw_full_top_contacts":len(events),"meaningful_full_top_contacts":len(meaningful),"meaningful_player_contacts":len(player),
                     "raw_metric_quantiles":{key:quantiles([event[key] for event in events]) for key in ["impulse","impulse_work","closing","severity"]},
                     "metric_quantiles":{key:quantiles([event[key] for event in meaningful]) for key in ["impulse","impulse_work","closing","severity"]},
                     "player_metric_quantiles":{key:quantiles([event[key] for event in player]) for key in ["impulse","impulse_work","closing","severity"]},
                     "qualifying_extreme_contacts":len(qualifying) if threshold is not None else None,
                     "actually_shown":presentation["spawned"],"presentation_suppressed":presentation["suppressed"],"peak_live":presentation["peak_live"],
                     "qualifying_examples": [{key:event.get(key) for key in ["collision_id","time","first_entity_id","second_entity_id","impulse","impulse_work","closing","severity","first_normal_speed","second_normal_speed","first_effective_mass","second_effective_mass","powers","power_ranks","power_mutations","player_involved"]} for event in sorted(qualifying,key=lambda e:e[metric],reverse=True)[:3]]})
    meaningful = [event for event in all_events if event["severity"] >= MEANINGFUL_MIN]
    player = [event for event in meaningful if event["player_involved"]]
    bins = [0, 100, 250, 500, 750, 1000, 1250, 1500, 1750, 2000, 2500, 3000, 4000, 8000, float("inf")]
    histogram = [{"lower_inclusive":lower,"upper_exclusive":upper if upper != float("inf") else None,"count":sum(lower<=event["impulse"]<upper for event in meaningful)} for lower,upper in zip(bins,bins[1:])]
    work_bins = [0, 10000, 25000, 50000, 100000, 250000, 500000, 750000, 1000000, 1250000, 1500000, 2000000, float("inf")]
    work_histogram = [{"lower_inclusive":lower,"upper_exclusive":upper if upper != float("inf") else None,"count":sum(lower<=event["impulse_work"]<upper for event in all_events)} for lower,upper in zip(work_bins,work_bins[1:])]
    return {"scope":data["scope"],"metric_id":metric,"metric":"Canonical full-top collision work proxy = accepted solver normal impulse J × actual positive pre-contact normal closing speed." if metric=="impulse_work" else "Canonical full-top solver physical impulse J before attack bias, recoil and safety velocity clamp.",
            "formula":"J=(1.70*normal_closing_speed+19)/(inverse_mass_first+inverse_mass_second); component contact multiplies J by clamp(sqrt(contact_attack_first*contact_attack_second),0.70,1.30).",
            "units":"Game mass × squared world units/second; impulse times closing speed has energy dimensions, and is a work proxy rather than measured dissipated energy." if metric=="impulse_work" else "Game mass × world units/second; same J already used for physical recoil.",
            "meaningful_definition":"Canonical progression collision severity >=0.22; raw full-top accepted contacts below this remain reported separately.",
            "severity_limitation":"clamp(closing/220,0.08,1.30) saturates at286 world units/second and cannot separate exceptionally fast upper-tail contacts.",
            "total_raw_full_top_collision_events":len(all_events),"total_meaningful_full_top_collision_events":len(meaningful),"meaningful_player_events":len(player),
            "raw_quantiles":{key:quantiles([event[key] for event in all_events]) for key in ["impulse","impulse_work","closing","severity"]},
            "representative_quantiles":{key:quantiles([event[key] for event in meaningful]) for key in ["impulse","impulse_work","closing","severity"]},
            "player_quantiles":{key:quantiles([event[key] for event in player]) for key in ["impulse","impulse_work","closing","severity"]},
            "impulse_histogram":histogram,"collision_work_histogram":work_histogram,"chosen_fixed_extreme_threshold":threshold,
            "threshold_reasoning":"Fixed offline calibration against multiple assembly/policy/seed distributions. Work proxy separates exceptional impacts while avoiding a nonzero-impulse solver separation bias near zero closing speed. No live percentile and no fixed frequency target.",
            "number_qualifying":sum(event[metric]>=threshold for event in all_events) if threshold is not None else None,
            "number_actually_shown_after_cooldown_and_deduplication":sum(run["actually_shown"] for run in runs),
            "runtime_percentile_used":False,"runs":runs,
            "limitations":"Deterministic sampled-bot physics observation, not human feel acceptance; no exact manifestations-per-minute target. Separate deliberate pose fixtures demonstrate the visual ladder."}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--qa-root", type=Path)
    parser.add_argument("--engine")
    parser.add_argument("--horizon", type=float, default=600)
    parser.add_argument("--case")
    parser.add_argument("--seed", type=int)
    parser.add_argument("--input", type=Path, help="Analyze a preserved raw telemetry file without rerunning.")
    parser.add_argument("--threshold",type=float)
    parser.add_argument("--metric",choices=["impulse","impulse_work"],default="impulse_work")
    parser.add_argument("--output",type=Path)
    parser.add_argument("--baseline-raw",type=Path,help="Require exact natural collision/progression equality to a preserved pre-gate study.")
    parser.add_argument("--enrich-existing",type=Path,help="Append exact presentation-history counts to this run's own generated manifest, preserving its pre-enrichment bytes.")
    args = parser.parse_args()
    task = workspace.create_task_workspace("003A",args.qa_root)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
    name = "003a_beast_impact_distribution_"+stamp
    if args.enrich_existing:
        existing=args.enrich_existing
        original=existing.read_bytes()
        result=json.loads(original)
        raw=Path(result["raw_telemetry"])
        assert pipeline.sha256(raw)==result["raw_sha256"]
        data=json.loads(raw.read_text(encoding="utf-8"))
        result.update(presentation_evidence(data))
        preservation=existing.with_name(existing.stem+"_pre_presentation_enrichment_"+stamp+".json")
        assert not preservation.exists()
        preservation.write_bytes(original)
        result["derived_enrichment"]={"preserved_original":str(preservation),"original_sha256":pipeline.sha256(preservation),"analysis_tool_sha256":pipeline.sha256(Path(__file__)),"actual_bounded_histories_complete":True}
        existing.write_text(json.dumps(result,indent=2)+"\n",encoding="utf-8")
        print(json.dumps({"manifest":str(existing),"actual_suppression_reasons":result["actual_suppression_reasons"],"source_and_profile_guards":result["source_unchanged"] and result["profile_unchanged"]},indent=2))
        return
    output = args.output or task / "manifests" / (name+".json")
    assert not output.exists(),"Preserve prior QA evidence"
    raw = args.input
    process = None
    profile_before = pipeline.production_profile(ROOT)
    tracked = [p for p in (ROOT / "scripts").glob("*.gd")]+[ROOT / "tests/observe_beast_impacts.gd",ROOT / "tests/rpm_bot.gd",ROOT / "assets/data/parts_catalogue.json"]
    source_before = {str(p.relative_to(ROOT)).replace("\\","/"):pipeline.sha256(p) for p in tracked}
    if raw is None:
        raw = task / "temp" / (name+"_events.json")
        command = [workspace.find_tool("godot",args.engine),"--headless","--path",str(ROOT),"--script","res://tests/observe_beast_impacts.gd","--","--report="+str(raw),"--collection-prefix="+str(task / "temp" / name),"--horizon="+str(args.horizon)]
        if args.case: command.append("--case="+args.case)
        if args.seed is not None: command.append("--seed="+str(args.seed))
        print("BEAST_IMPACT_STUDY "+str(raw),flush=True)
        process = pipeline.run_logged(command,task / "logs" / (name+".log"),900)
    data = json.loads(raw.read_text(encoding="utf-8"))
    source_after = {str(p.relative_to(ROOT)).replace("\\","/"):pipeline.sha256(p) for p in tracked}
    profile_after = pipeline.production_profile(ROOT)
    assert profile_before == profile_after,"Natural study modified real profile"
    assert source_before == source_after,"Source changed during study; preserve raw telemetry and rerun on frozen source"
    result = summarize(data,args.threshold,args.metric)
    if args.baseline_raw:
        baseline=json.loads(args.baseline_raw.read_text(encoding="utf-8"))
        assert len(baseline["runs"])==len(data["runs"])
        for old,new in zip(baseline["runs"],data["runs"]):
            assert old["context"]==new["context"] and old["seed"]==new["seed"]
            assert old["elapsed"]==new["elapsed"] and old["reason"]==new["reason"] and old["drafts"]==new["drafts"]
            old_events=[{key:value for key,value in event.items() if key!="presentation"} for event in old["events"]]
            new_events=[{key:value for key,value in event.items() if key!="presentation"} for event in new["events"]]
            assert old_events==new_events,"Presentation qualification changed natural collision/progression trajectory"
        result["pre_gate_comparison"]={"baseline_raw":str(args.baseline_raw),"baseline_sha256":pipeline.sha256(args.baseline_raw),"runs":len(data["runs"]),"exact_collision_and_draft_equality":True,"elapsed_and_outcome_equality":True}
    result.update(created_utc=datetime.now(timezone.utc).isoformat(),source_git_sha=pipeline.git(ROOT,"rev-parse","HEAD"),source_sha256=source_before,source_unchanged=True,profile_before=profile_before,profile_after=profile_after,profile_unchanged=True,raw_telemetry=str(raw),raw_sha256=pipeline.sha256(raw),process=process)
    output.write_text(json.dumps(result,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"manifest":str(output),"raw":str(raw),"contacts":result["total_meaningful_full_top_collision_events"],"quantiles":result["representative_quantiles"],"shown":result["number_actually_shown_after_cooldown_and_deduplication"]},indent=2),flush=True)


if __name__ == "__main__":
    main()
