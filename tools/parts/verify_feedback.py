"""Run human-feedback regressions without overwriting earlier checkpoint evidence."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "workspace"))
import workspace
sys.path.insert(0, str(ROOT / "tools" / "build"))
import windows_checkpoint as pipeline
from verify_catalogue import has_failures

HISTORICAL = {
    "baseline_physics": {
        "reason": "Task 001 exact player trajectories predate the requested lateral-friction drift correction.",
        "completion": r"Baseline differential:.*field comparisons.*[1-9]\d* failures",
    },
    "parts_legacy": {
        "reason": "The frozen C5.1 48-assembly fixture includes player-turn trajectories; these now intentionally retain lateral momentum.",
        "completion": r"Legacy physical parity: (?!48 /)\d+ / 48 exact; failures \[.+\]",
    },
}
SUPERSEDED_RUN = {
    "suite": "catalogue_legacy_run", "status": "superseded_not_run", "passed": False,
    "reason": "The archived C5.1 strict whole-dictionary/seeded-trajectory equivalence contract is superseded by explicitly requested drift, actual Redline recovery, Dead Centre recovery/gravity and persistent paid Afterimage routes. New drift presentation fields also alter whole-dictionary equality. This is not evidence of unchanged movement, powers, RPM or director trajectories.",
    "evidence": ["tests/test_catalogue_legacy_run.gd:state erases only earlier catalogue metadata", "tests/test_feedback_drift.gd compares actual current turns against the same solver with only the requested drift hook disabled", "tests/test_power_feedback.gd validates the requested current power behaviour"],
}


def source_fingerprint() -> dict:
    paths = list((ROOT / "scripts").glob("*.gd")) + list((ROOT / "assets/data").glob("*.json"))
    paths += [ROOT / "project.godot", ROOT / "main.tscn"]
    records = {p.relative_to(ROOT).as_posix(): pipeline.sha256(p) for p in sorted(paths) if p.is_file()}
    return {"sha256": hashlib.sha256(json.dumps(records, sort_keys=True).encode()).hexdigest(), "files": records}


def parse_checks(suite: str, content: str) -> int:
    if suite == "parts_legacy": return 48
    if suite == "prototype": numbers = re.findall(r"Automated checks: (\d+)", content)
    else: numbers = re.findall(r"checks[=: ]+(\d+)", content, re.I) or re.findall(r"(\d+)\s+(?:checks|assertions|field comparisons)", content, re.I) or re.findall(r"Ran (\d+) tests?", content)
    return max(map(int, numbers), default=0)


def historical_failure(suite: str, code: int, content: str) -> bool:
    policy = HISTORICAL.get(suite)
    if not policy or code != 1 or "SCRIPT ERROR" in content or not re.search(policy["completion"], content): return False
    if suite == "baseline_physics": return bool(re.search(r"FAIL .*movement tick .* (?:pos|vel) ", content)) and "ERROR:" not in content
    return "ERROR:" not in content


def run_suite(command: list[str], log: Path, suite: str, timeout: int) -> dict:
    began = time.monotonic()
    options = {}
    if os.name == "nt":
        startup = subprocess.STARTUPINFO(); startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW; startup.wShowWindow = subprocess.SW_HIDE
        options.update(startupinfo=startup, creationflags=subprocess.CREATE_NO_WINDOW)
    timed_out = False
    with log.open("wb") as stream:
        try: result = subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout, **options); code = result.returncode
        except subprocess.TimeoutExpired: code = None; timed_out = True
    content = log.read_text(encoding="utf-8", errors="replace")
    if suite == "prototype":
        extra = next((a.removeprefix("--report=") for a in command if a.startswith("--report=")), "")
        if extra and Path(extra).is_file(): content += Path(extra).read_text(encoding="utf-8", errors="replace")
    markers = [line for line in content.splitlines() if re.search(r"PASS|checks|comparisons|Legacy physical parity|Automated checks|Baseline differential", line, re.I)]
    if re.search(r"Ran \d+ tests?", content) and re.search(r"^OK$", content, re.M): markers.append("Python unittest: " + re.search(r"Ran \d+ tests?", content).group(0) + "; OK")
    passed = code == 0 and not timed_out and not pipeline.ERRORS.search(content) and not has_failures(content) and bool(markers)
    status = "passed" if passed else "superseded_historical_comparison" if historical_failure(suite, code, content) else "failed"
    row = {"suite":suite, "status":status, "passed":passed, "checks":parse_checks(suite, content), "seconds":round(time.monotonic()-began,3), "command":command, "exit_code":code, "timed_out":timed_out, "summary":markers[-1] if markers else None, "log":str(log), "log_sha256":pipeline.sha256(log)}
    if status == "superseded_historical_comparison": row["reason"] = HISTORICAL[suite]["reason"]
    if status != "passed": row["failure_examples"] = [line for line in content.splitlines() if re.search(r"FAIL|ERROR|parity|Baseline differential", line)][:10]
    return row


def combine_acceptance(initial_path: Path, supplement_paths: list[Path], output: Path) -> dict:
    """Retain failures, then prove their narrow presentation fix with final reruns."""
    initial = json.loads(initial_path.read_text())
    supplements = [json.loads(path.read_text()) for path in supplement_paths]
    if not supplements: raise RuntimeError("At least one stable final-source supplement is required")
    postfix = supplements[-1]
    for evidence in supplements:
        if evidence.get("failed_suites") or not evidence.get("profile_unchanged") or not evidence.get("production_source_unchanged_during_tests"):
            raise RuntimeError("Every supplement must pass on a stable production source/profile")
        if not evidence.get("status", "").startswith("passed_current_behaviour"):
            raise RuntimeError("Supplement has no passing current-contract status")
    current_source = source_fingerprint()
    if current_source != postfix["source_after"]: raise RuntimeError("Production source changed after final reruns")
    current_profile = pipeline.production_profile(ROOT)
    for evidence in [initial] + supplements:
        if evidence["profile_before"] != current_profile or evidence["profile_after"] != current_profile:
            raise RuntimeError("Player profile differs from the preserved regression evidence")
    before = initial["source_before"]["files"]
    after = postfix["source_after"]["files"]
    changed = [p for p in sorted(set(before) | set(after)) if before.get(p) != after.get(p)]
    if set(changed) - {"scripts/battle.gd", "scripts/parts_package_probe.gd"}: raise RuntimeError("Broad source edits require a new complete batch: " + str(changed))
    if "scripts/parts_package_probe.gd" in changed and not any(row["suite"] == "parts_package" and row["passed"] for row in postfix["suites"]):
        raise RuntimeError("Latest read-only package probe needs its own final-source package regression")
    final_rows = {row["suite"]: {**row, "validation_phase":"initial_before_presentation_postfix"} for row in initial["suites"] if row["status"] not in ["superseded_historical_comparison"]}
    for index,evidence in enumerate(supplements):
        for row in evidence["suites"]: final_rows[row["suite"]] = {**row, "validation_phase":"postfix_supplement_"+str(index+1)}
    residual = [name for name,row in final_rows.items() if not row["passed"] or row["status"] != "passed"]
    if residual: raise RuntimeError("Current-contract failures remain unresolved: " + str(residual))
    report = {
        "status":"passed_current_contracts_with_targeted_postfix_validation", "branch":pipeline.git(ROOT,"branch","--show-current"),
        "source_sha_at_testing":pipeline.git(ROOT,"rev-parse","HEAD"), "source":current_source,
        "initial_manifest":str(initial_path), "initial_manifest_sha256":pipeline.sha256(initial_path),
        "initial_status":initial["status"], "initial_failed_suites":initial["failed_suites"],
        "initial_failure_evidence_preserved":True, "postfix_manifests":[{"path":str(path),"sha256":pipeline.sha256(path)} for path in supplement_paths],
        "source_changes_during_initial_batch":changed,
        "postfix_scope":"Presentation only: paid Orbit Drive brake-turn tip sparks; emission cadence clock now advances equally with particles enabled/disabled. Additional read-only isolated QA probe inspects three feedback textures. Acceleration, friction, collision transfer, damage and power economy are unchanged by these post-batch changes.",
        "postfix_source_unchanged_during_tests":True, "postfix_suites":sum(e["passed_suites"] for e in supplements), "postfix_counted_checks":sum(e["counted_passed_checks"] for e in supplements),
        "passed_suites":len(final_rows), "counted_passed_checks":sum(row["checks"] for row in final_rows.values()), "current_suites":list(final_rows.values()),
        "superseded_historical_comparisons":[row for row in initial["suites"] if row["status"] == "superseded_historical_comparison"],
        "superseded_not_run":initial["superseded_contracts"], "historical_trajectory_equivalence":False,
        "retention_scope":"The new feedback_parts_retention suite checks unchanged legacy ratings, isolated full-contact response and wall response for48 assemblies while explicitly measuring their changed player movement.",
        "profile":current_profile, "profile_unchanged":True, "human_visual_and_handling_acceptance":"pending",
        "task_002c5_home_human_playtest":"pending", "remaining_failure_suites":[],
    }
    output.write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--qa-root", type=Path)
    parser.add_argument("--engine")
    parser.add_argument("--suites", help="Optional comma-separated focused suite names")
    parser.add_argument("--stem", default="002c5_2_feedback_regression", help="New evidence identity; existing report paths are refused")
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--combine", nargs="+", type=Path, metavar="MANIFEST", help="Initial evidence followed by stable final-source supplements")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z0-9_-]*feedback[a-z0-9_-]*", args.stem): parser.error("Use a clear feedback-prefixed evidence filename")
    task = workspace.create_task_workspace("002C.5.2", args.qa_root)
    output = task / "manifests" / (args.stem + ".json")
    if output.exists(): raise RuntimeError("Existing evidence is preserved; choose another --stem: " + str(output))
    if args.combine:
        report = combine_acceptance(args.combine[0], args.combine[1:], output)
        print(json.dumps({"status":report["status"],"passed_suites":report["passed_suites"],"checks":report["counted_passed_checks"],"profile_unchanged":True,"manifest":str(output)},indent=2))
        return 0
    engine = workspace.find_tool("godot", args.engine)
    prior = json.loads((ROOT / "tests/results/task002c5-integration-regression-results.json").read_text())
    suites = [row["suite"] for row in prior["suites"]] + ["power_identity", "prototype", "parts_legacy", "baseline_physics"]
    suites += [p.stem.removeprefix("test_") for p in sorted((ROOT / "tests").glob("test_parts_*.gd"))]
    suites += ["feedback_drift", "feedback_anchor_contacts", "power_feedback", "feedback_rerolls", "feedback_effects", "feedback_live_pickup", "feedback_parts_retention"]
    suites = list(dict.fromkeys(args.suites.split(",") if args.suites else suites))
    if "catalogue_legacy_run" in suites: raise RuntimeError("Archived exact whole-Run equivalence is superseded; do not falsely count it as passing")
    for suite in suites:
        if not re.fullmatch(r"[a-z0-9_]+", suite) or not (ROOT / "tests" / ("test_"+suite+".gd")).is_file(): raise RuntimeError("Unknown suite: "+suite)
        if (task / "logs" / (args.stem+"_"+suite+".log")).exists(): raise RuntimeError("Existing log is preserved; choose a new --stem")
    report = {"status":"running", "branch":pipeline.git(ROOT,"branch","--show-current"), "source_sha":pipeline.git(ROOT,"rev-parse","HEAD"), "working_tree_status":pipeline.git(ROOT,"status","--porcelain"), "source_before":source_fingerprint(), "profile_before":pipeline.production_profile(ROOT), "suites":[], "superseded_contracts":[SUPERSEDED_RUN] if not args.suites else [], "historical_comparisons_are_not_acceptance":True}
    try:
        for suite in suites:
            command = [engine,"--headless","--path",str(ROOT),"--script","res://tests/test_"+suite+".gd"]
            if suite == "prototype": command += ["--","--report="+str(task/"manifests"/(args.stem+"_prototype-QA.txt")),"--balance-report="+str(task/"benchmarks"/(args.stem+"_legacy-bouts.json"))]
            elif suite == "baseline_physics": command += ["--","--baseline-source="+str(ROOT.parent/"GyroBrothers-Worktrees/topgame-task-002a-baseline/scripts/battle.gd")]
            elif suite == "parts_catalogue": command += ["--","--out="+str(task/"benchmarks"/(args.stem+"_parts_catalogue.json"))]
            elif suite in ["feedback_drift","feedback_anchor_contacts","power_feedback","feedback_parts_retention"]: command += ["--","--report="+str(task/"manifests"/(args.stem+"_"+suite+".json"))]
            row = run_suite(command, task/"logs"/(args.stem+"_"+suite+".log"), suite, args.timeout)
            report["suites"].append(row)
            output.write_text(json.dumps(report, indent=2)+"\n", encoding="utf-8")
            print(json.dumps({k:row[k] for k in ["suite","status","seconds","checks"]}), flush=True)
            if pipeline.production_profile(ROOT) != report["profile_before"]: raise RuntimeError("Production profile changed; preserve it and investigate before continuing")
        report["failed_suites"] = [row["suite"] for row in report["suites"] if row["status"] == "failed"]
        report["passed_suites"] = sum(row["passed"] for row in report["suites"])
        report["counted_passed_checks"] = sum(row["checks"] for row in report["suites"] if row["passed"])
        report["superseded_comparisons"] = [row["suite"] for row in report["suites"] if row["status"] == "superseded_historical_comparison"]
        report["status"] = "failed" if report["failed_suites"] else "passed_current_behaviour_with_superseded_historical_comparisons" if report["superseded_comparisons"] else "passed_current_behaviour"
    except Exception as error: report.update(status="failed", error=str(error)); raise
    finally:
        report["source_after"] = source_fingerprint()
        report["production_source_unchanged_during_tests"] = report["source_before"] == report["source_after"]
        report["profile_after"] = pipeline.production_profile(ROOT)
        report["profile_unchanged"] = report["profile_before"] == report["profile_after"]
        if not report["profile_unchanged"] or not report["production_source_unchanged_during_tests"]: report["status"] = "failed"
        output.write_text(json.dumps(report, indent=2)+"\n", encoding="utf-8")
    print(json.dumps({"status":report["status"],"passed_suites":report["passed_suites"],"checks":report["counted_passed_checks"],"failed_suites":report["failed_suites"],"superseded_comparisons":report["superseded_comparisons"],"profile_unchanged":report["profile_unchanged"],"production_source_unchanged_during_tests":report["production_source_unchanged_during_tests"],"manifest":str(output)},indent=2), flush=True)
    return 1 if report["status"] == "failed" else 0


if __name__ == "__main__": raise SystemExit(main())
