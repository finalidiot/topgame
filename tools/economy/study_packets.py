"""Run production packet economy and save-transaction contracts in isolated QA.

All sampling happens in the real GDScript sampler. This wrapper preserves fresh
engine logs, source identity and exact production-profile fingerprints.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/workspace"))
import workspace
sys.path.insert(0, str(ROOT / "tools/build"))
import windows_checkpoint as pipeline


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--task", default="003A")
    parser.add_argument("--stem", default="003a_economy_verified")
    parser.add_argument("--cohort", type=int, default=3000)
    parser.add_argument("--qa-root", type=Path)
    parser.add_argument("--engine")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z0-9_-]+", args.stem): parser.error("Use a clear evidence stem")
    if not 100 <= args.cohort <= 10000: parser.error("Cohort must be 100..10000")
    task = workspace.create_task_workspace(args.task, workspace.qa_root(args.qa_root))
    engine = workspace.find_tool("godot", args.engine)
    manifest = task / "manifests" / (args.stem + ".json")
    if manifest.exists(): raise FileExistsError(manifest)
    files = [(name, task / "logs" / (args.stem + "_" + name + ".log"),
              task / "manifests" / (args.stem + "_" + name + ".json"))
             for name in ("packet_economy", "packet_transactions")]
    for _, log, report in files:
        if log.exists() or report.exists(): raise FileExistsError("Preserved evidence already exists")
    evidence = {"task": args.task, "branch": pipeline.git(ROOT, "branch", "--show-current"),
                "source_parent": pipeline.git(ROOT, "rev-parse", "HEAD"), "status": "running",
                "profile_before": pipeline.production_profile(ROOT), "suites": []}
    for name, log, report in files:
        command = [engine, "--headless", "--path", str(ROOT), "--script", "res://tests/test_" + name + ".gd",
                   "--", "--report=" + str(report)]
        if name == "packet_economy": command += ["--cohort=" + str(args.cohort)]
        result = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, encoding="utf-8", errors="replace", timeout=600)
        log.write_text(result.stdout, encoding="utf-8")
        data = json.loads(report.read_text(encoding="utf-8")) if report.exists() else {}
        passed = result.returncode == 0 and data.get("status") == "passed" and "SCRIPT ERROR:" not in result.stdout
        evidence["suites"].append({"suite":name, "passed":passed, "checks":data.get("checks",0),
                                  "returncode":result.returncode, "log":str(log), "report":str(report)})
        print(json.dumps(evidence["suites"][-1]), flush=True)
        if pipeline.production_profile(ROOT) != evidence["profile_before"]:
            raise RuntimeError("Production profile changed; stop and inspect")
    evidence["profile_after"] = pipeline.production_profile(ROOT)
    evidence["profile_unchanged"] = evidence["profile_before"] == evidence["profile_after"]
    evidence["status"] = "passed" if evidence["profile_unchanged"] and all(r["passed"] for r in evidence["suites"]) else "failed"
    evidence["checks"] = sum(r["checks"] for r in evidence["suites"])
    manifest.write_text(json.dumps(evidence,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"status":evidence["status"],"checks":evidence["checks"],"manifest":str(manifest)}),flush=True)
    return 0 if evidence["status"] == "passed" else 1


if __name__ == "__main__": raise SystemExit(main())
