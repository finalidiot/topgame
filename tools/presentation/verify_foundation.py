"""Run current presentation/combat contracts with preserved external evidence.

Uses isolated save fixtures and refuses existing reports/logs. Archived exact
pre-feedback trajectories are not current acceptance contracts; accepted drift,
RPM recovery and gravity behavior are exercised by their current focused tests.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/workspace"))
import workspace
sys.path.insert(0, str(ROOT / "tools/build"))
import windows_checkpoint as pipeline
sys.path.insert(0, str(ROOT / "tools/parts"))
from verify_feedback import run_suite, source_fingerprint

ADDED = ["power_identity", "parts_catalogue", "parts_collection", "parts_package",
         "feedback_drift", "feedback_anchor_contacts", "power_feedback",
         "feedback_rerolls", "feedback_effects", "feedback_live_pickup",
         "feedback_parts_retention", "beast_manifestations", "music",
         "save_tools", "presentation_flow", "presentation_retention", "frontend"]


def asset_fingerprint() -> dict:
    files = {p.relative_to(ROOT).as_posix(): pipeline.sha256(p)
             for p in sorted((ROOT / "assets").rglob("*"))
             if p.is_file() and not p.name.endswith(".tmp")}
    return {"sha256": hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest(), "files": files}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--task", default="002C.6")
    parser.add_argument("--qa-root", type=Path)
    parser.add_argument("--engine")
    parser.add_argument("--stem", default="002c6_regression")
    parser.add_argument("--suites", help="Optional comma-separated current suite names")
    parser.add_argument("--timeout", type=int, default=600)
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z0-9_-]+", args.stem): parser.error("Use a clear artifact identity")
    qa = workspace.qa_root(args.qa_root).resolve()
    profile = pipeline.production_profile(ROOT)
    if profile.get("directory"):
        user = Path(profile["directory"]).resolve()
        if qa == user or qa.is_relative_to(user): raise ValueError("QA root must not be inside the player profile")
    task = workspace.create_task_workspace(args.task, qa)
    target = task / "manifests" / (args.stem + ".json")
    if target.exists(): raise RuntimeError("Preserved report already exists; choose another --stem")
    prior = json.loads((ROOT / "tests/results/task002c5-integration-regression-results.json").read_text())
    suites = list(dict.fromkeys(args.suites.split(",") if args.suites else
                              [r["suite"] for r in prior["suites"]] + ADDED))
    excluded = {"baseline_physics", "parts_legacy", "catalogue_legacy_run"}
    for name in suites:
        if name in excluded: raise ValueError("Archived pre-feedback trajectory contract: " + name)
        if not re.fullmatch(r"[a-z0-9_]+", name) or not (ROOT / "tests" / ("test_" + name + ".gd")).is_file():
            raise ValueError("Unknown suite: " + name)
        if (task / "logs" / (args.stem + "_" + name + ".log")).exists():
            raise RuntimeError("Preserved log already exists; choose another --stem")
        if (task / "manifests" / (args.stem + "_" + name + ".json")).exists():
            raise RuntimeError("Preserved suite report already exists; choose another --stem")
    if (task / "benchmarks" / (args.stem + "_parts.json")).exists():
        raise RuntimeError("Preserved benchmark already exists; choose another --stem")
    engine = workspace.find_tool("godot", args.engine)
    evidence = {"status":"running", "branch":pipeline.git(ROOT, "branch", "--show-current"),
                "head":pipeline.git(ROOT, "rev-parse", "HEAD"), "suites":[],
                "source_before":source_fingerprint(), "assets_before":asset_fingerprint(),
                "profile_before":pipeline.production_profile(ROOT),
                "historical_contracts_excluded":sorted(excluded),
                "exclusion_reason":"Accepted C5.2 feedback changed drift/power/RPM trajectories; current behavior and exact accepted-main retention are tested instead."}
    def save(): target.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    previous_qa = os.environ.get("TOPGAME_QA_ROOT")
    os.environ["TOPGAME_QA_ROOT"] = str(qa)
    try:
        for name in suites:
            command = [engine, "--headless", "--path", str(ROOT), "--script", "res://tests/test_" + name + ".gd"]
            if name == "parts_catalogue":
                command += ["--", "--out=" + str(task / "benchmarks" / (args.stem + "_parts.json"))]
            elif name in ["feedback_drift", "feedback_anchor_contacts", "power_feedback", "feedback_parts_retention", "save_tools", "presentation_flow", "presentation_retention", "music", "frontend"]:
                command += ["--", "--report=" + str(task / "manifests" / (args.stem + "_" + name + ".json"))]
            row = run_suite(command, task / "logs" / (args.stem + "_" + name + ".log"), name, args.timeout)
            evidence["suites"].append(row)
            save()
            print(json.dumps({k:row[k] for k in ["suite", "status", "seconds", "checks"]}), flush=True)
            if pipeline.production_profile(ROOT) != evidence["profile_before"]:
                raise RuntimeError("Player profile changed; stop and investigate")
        evidence["failed_suites"] = [r["suite"] for r in evidence["suites"] if not r["passed"]]
        evidence["passed_suites"] = sum(r["passed"] for r in evidence["suites"])
        evidence["checks"] = sum(r["checks"] for r in evidence["suites"] if r["passed"])
        evidence["status"] = "failed" if evidence["failed_suites"] else "passed"
    except Exception as error:
        evidence.update(status="failed", error=str(error))
        raise
    finally:
        if previous_qa is None: os.environ.pop("TOPGAME_QA_ROOT", None)
        else: os.environ["TOPGAME_QA_ROOT"] = previous_qa
        evidence["source_after"] = source_fingerprint()
        evidence["assets_after"] = asset_fingerprint()
        evidence["profile_after"] = pipeline.production_profile(ROOT)
        evidence["source_unchanged"] = evidence["source_before"] == evidence["source_after"]
        evidence["assets_unchanged"] = evidence["assets_before"] == evidence["assets_after"]
        evidence["profile_unchanged"] = evidence["profile_before"] == evidence["profile_after"]
        if not all(evidence[k] for k in ["source_unchanged", "assets_unchanged", "profile_unchanged"]): evidence["status"] = "failed"
        save()
    print(json.dumps({"status":evidence["status"], "suites":evidence["passed_suites"], "checks":evidence["checks"], "failed":evidence["failed_suites"], "manifest":str(target)}, indent=2))
    return 0 if evidence["status"] == "passed" else 1


if __name__ == "__main__": raise SystemExit(main())
