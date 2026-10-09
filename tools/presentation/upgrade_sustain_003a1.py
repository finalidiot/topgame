"""Measure fixed legal investment curves in real Run physics and compare stages."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
import re
from pathlib import Path
import statistics
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/build"))
sys.path.insert(0, str(ROOT / "tools/workspace"))
import windows_checkpoint as pipeline
import workspace
DRIVER = ROOT / "tests/observe_upgrade_sustain_003a1.gd"

def source(project: Path) -> dict:
    files = [project / "project.godot", project / "main.tscn"]
    for directory in ("scripts", "assets"):
        files += [p for p in (project / directory).rglob("*") if p.is_file()]
    return {p.relative_to(project).as_posix(): pipeline.sha256(p) for p in sorted(files)}

def player() -> dict:
    inventory = pipeline.production_profile(ROOT)
    directory = Path(inventory["directory"])
    inventory["recovery_backups"] = {str(p.relative_to(directory)): pipeline.sha256(p) for p in sorted((directory / "collection-backups").rglob("*")) if p.is_file()}
    return inventory

def observe(args) -> None:
    qa = workspace.create_task_workspace("003A.1")
    name = "003a1_upgrade_sustain_" + args.label + "_" + args.case + "_" + datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
    output, provenance = qa / "manifests" / (name + ".json"), qa / "manifests" / (name + "_provenance.json")
    guard = {"project":str(args.project.resolve()),"label":args.label,"case":args.case,"source_before":source(args.project),"player_before":player(),"driver_sha256":pipeline.sha256(DRIVER)}
    pipeline.write_json(provenance, guard)
    command = [workspace.find_tool("godot", args.engine), "--headless", "--path", str(args.project), "--script", str(DRIVER), "--", "--report=" + str(output), "--case=" + args.case, "--horizon=" + str(args.horizon)]
    process = pipeline.run_logged(command, qa / "logs" / (name + ".log"), 2400)
    guard.update(process=process, source_after=source(args.project), player_after=player(), report=str(output), report_sha256=pipeline.sha256(output))
    guard.update(source_unchanged=guard["source_before"] == guard["source_after"], player_unchanged=guard["player_before"] == guard["player_after"], driver_unchanged=guard["driver_sha256"] == pipeline.sha256(DRIVER))
    pipeline.write_json(provenance, guard)
    assert all(guard[k] for k in ("source_unchanged", "player_unchanged", "driver_unchanged"))
    data = json.loads(output.read_text(encoding="utf-8"))
    validate(data)
    print(json.dumps({"passed":True,"report":str(output),"provenance":str(provenance),"runs":len(data["runs"])}, indent=2), flush=True)

def validate(data: dict) -> None:
    expected = {(n, seed, policy) for n in (0,3,6,12) for seed in (421,7341,2026) for policy in (["active", "active_then_hands_off"] if n == 12 else ["active"])}
    styles = {row["style"] for row in data["runs"]}
    for style in styles:
        actual = {(row["investments"], row["seed"], row["policy"]) for row in data["runs"] if row["style"] == style}
        assert actual == expected
    for row in data["runs"]:
        assert row["ledger_closure_error"] < 1e-6
        assert row["initial_ranks"] == row["final_ranks"] and sum(row["initial_ranks"].values()) == row["investments"]
        assert row["total_loss"] > 0 and abs(row["total_loss"] - sum(row["loss_by_source"].values())) < 1e-8
        assert abs(row["total_gain"] - sum(row["gain_by_source"].values())) < 1e-8
        assert abs(row["starting_rpm"] - row["total_loss"] + row["total_gain"] - row["final_rpm"]) < 1e-6
        assert row["survival_seconds"] <= data["horizon"] + .1
        assert row["seconds_above_90"] <= row["survival_seconds"] + .1

def load_reports(paths: list[Path], profile_boundary: dict | None = None) -> tuple[list[dict], list[dict]]:
    records, guards = [], []
    for path in paths:
        data = json.loads(path.read_text(encoding="utf-8"))
        guard = json.loads(path.with_name(path.stem + "_provenance.json").read_text(encoding="utf-8"))
        validate(data)
        assert pipeline.sha256(path) == guard["report_sha256"]
        assert guard["source_unchanged"] and guard["driver_unchanged"]
        if not guard["player_unchanged"]:
            # Keep the original failed guard visible. Only an explicitly
            # supplied human-confirmed boundary tied to these exact bytes can
            # distinguish unrelated play from a study that wrote player data.
            assert profile_boundary is not None and profile_boundary.get("human_confirmed_play_or_save") is True
            resolved = profile_boundary["affected_provenance"].get(str(path.with_name(path.stem + "_provenance.json")))
            assert resolved is not None and resolved["provenance_sha256"] == pipeline.sha256(path.with_name(path.stem + "_provenance.json"))
            assert resolved["player_before"] == guard["player_before"] and resolved["player_after"] == guard["player_after"]
        records.extend(data["runs"])
        guards.append(guard)
    assert len(records) == 45
    assert {row["style"] for row in records} == {"aggressive", "defensive", "mixed"}
    return records, guards

def summarize(records: list[dict]) -> dict:
    result = {}
    for style in ("aggressive", "defensive", "mixed"):
        levels = {}
        for investments in (0,3,6,12):
            sample = [r for r in records if r["style"] == style and r["investments"] == investments and r["policy"] == "active"]
            levels[str(investments)] = {key:statistics.mean(r[key] for r in sample) for key in ("survival_seconds", "final_rpm", "minimum_rpm", "total_loss", "total_gain", "net_change", "seconds_above_90", "gain_loss_ratio")}
            levels[str(investments)]["censored_count"] = sum(r["censored"] for r in sample)
            levels[str(investments)]["outcomes"] = {reason:sum(r["reason"] == reason for r in sample) for reason in sorted({r["reason"] for r in sample})}
            levels[str(investments)]["loss_by_source_mean"] = {key:statistics.mean(r["loss_by_source"].get(key,0) for r in sample) for key in sorted({k for r in sample for k in r["loss_by_source"]})}
            levels[str(investments)]["gain_by_source_mean"] = {key:statistics.mean(r["gain_by_source"].get(key,0) for r in sample) for key in sorted({k for r in sample for k in r["gain_by_source"]})}
        result[style] = levels
    return result

def compare(args) -> None:
    boundary = json.loads(args.profile_boundary_report.read_text(encoding="utf-8")) if args.profile_boundary_report else None
    before, before_guards = load_reports(args.before,boundary)
    after, after_guards = load_reports(args.after)
    assert {g["driver_sha256"] for g in before_guards + after_guards} == {pipeline.sha256(DRIVER)}
    key = lambda r:(r["style"],r["investments"],r["seed"],r["policy"])
    newer = {key(r):r for r in after}
    pairs = []
    for old in before:
        new = newer[key(old)]
        assert old["initial_assembly"] == new["initial_assembly"] and old["initial_ranks"] == new["initial_ranks"] and old["initial_mutations"] == new["initial_mutations"]
        shared = min(old["survival_seconds"],new["survival_seconds"])
        shared_samples = []
        for row in (old,new):
            trace = [p for p in row["trace"] if p["time"] <= shared + 1e-6]
            point = trace[-1]
            shared_samples.append(point)
        pairs.append({"key":key(old),"before":old,"after":new,"shared_lifetime":shared,"shared_trace_window":shared_samples})
    qa = workspace.create_task_workspace("003A.1")
    output_stem = getattr(args, "output_stem", "003a1_upgrade_sustain_curve")
    assert re.fullmatch(r"[a-z0-9_-]+", output_stem)
    output = qa / (output_stem + ".json")
    assert not output.exists() and not (qa / "manifests" / output.name).exists()
    result = {"schema":"003a1-upgrade-sustain-curve-v1","scope":"Paired deterministic fixed investment curves in real Run physics/AI/Director; declared legal invested loadouts and pressure investment context, sampled controls only. No spawned QA enemies, reserve changes, outcomes, positioning or clock jumps.",
              "units":"Reserve/loss/gain fractions of9000 RPM; seconds are actual production elapsed excluding ordinary countdown/impact holds", "censoring":"Horizon runs are lower bounds on survival. Terminal means mix natural deaths and censored horizons; shared trace windows retain like-for-like evidence.",
              "fixed_investment_boundary":"Ranks are fixed for the study so0/3/6/12 mean the actual declared budget throughout. Natural XP is not turned into additional powers; this isolates combinations rather than claiming a natural draft history.",
              "before_reports":[str(p) for p in args.before],"after_reports":[str(p) for p in args.after],"before_provenance":before_guards,"after_provenance":after_guards,
              "player_unchanged":all(g["player_unchanged"] for g in before_guards + after_guards),"human_profile_activity_boundary":boundary,"source_unchanged":True,"driver_sha256":pipeline.sha256(DRIVER),"runs_per_stage":45,"seeds":[421,7341,2026],"investment_levels":[0,3,6,12],
              "summary":{"before":summarize(before),"after":summarize(after)},"pairs":pairs,"max_ledger_closure_error":max(r[phase]["ledger_closure_error"] for r in pairs for phase in ("before","after")),"human_acceptance":"Pending; automated sampled bots identify source budgets, not human enjoyment or maximal feasible sustain."}
    pipeline.write_json(output, result)
    pipeline.write_json(qa / "manifests" / output.name, result)
    print(json.dumps({"passed":True,"report":str(output),"summary":result["summary"]}, indent=2))

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="mode",required=True)
    observe_parser = sub.add_parser("observe")
    observe_parser.add_argument("--project",type=Path,required=True)
    observe_parser.add_argument("--label",required=True)
    observe_parser.add_argument("--case",choices=("aggressive","defensive","mixed"),required=True)
    observe_parser.add_argument("--engine")
    observe_parser.add_argument("--horizon",type=float,default=480)
    compare_parser = sub.add_parser("compare")
    compare_parser.add_argument("--before",nargs=3,type=Path,required=True)
    compare_parser.add_argument("--after",nargs=3,type=Path,required=True)
    compare_parser.add_argument("--profile-boundary-report",type=Path,help="Explicit human-confirmed save boundary; original failed profile guards stay false")
    compare_parser.add_argument("--output-stem",default="003a1_upgrade_sustain_curve",help="Fresh evidence name; existing comparisons are never overwritten")
    args = parser.parse_args()
    (observe if args.mode == "observe" else compare)(args)

if __name__ == "__main__": main()
