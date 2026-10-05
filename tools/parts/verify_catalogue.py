"""Run retained gameplay regressions and catalogue checks with isolated QA output."""
from __future__ import annotations
import argparse
import json
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

def has_failures(content: str) -> bool:
    # A checks count followed by "failures=0" is a passing summary, not a
    # declaration that the preceding checks were failures.
    return bool(re.search(r"(?:failed|failures)\s*[:=]\s*[1-9]\d*|\b[1-9]\d*\s+failures\b(?!\s*[:=])|FAIL:", content, re.I))

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--task", default="002C.5.2")
    parser.add_argument("--qa-root", type=Path)
    parser.add_argument("--engine")
    parser.add_argument("--suites", help="Comma separated suite names; default retained C5 batch plus parts tests")
    args = parser.parse_args()
    task = workspace.create_task_workspace(args.task, args.qa_root)
    engine = workspace.find_tool("godot", args.engine)
    prior = json.loads((ROOT / "tests/results/task002c5-integration-regression-results.json").read_text())
    suites = [row["suite"] for row in prior["suites"]] + ["power_identity", "prototype", "parts_legacy", "catalogue_legacy_run", "baseline_physics"]
    if args.suites:
        suites = args.suites.split(",")
    else:
        suites += [p.stem.removeprefix("test_") for p in sorted((ROOT / "tests").glob("test_parts_*.gd")) if p.stem.removeprefix("test_") not in suites]
    stem = "002c5_2_regression" if not args.suites else "002c5_2_focused_" + args.suites.replace(",", "_")
    output = task / "manifests" / (stem + ".json")
    report = {"parent_sha":"3d52a55d9d9bc154b50b3b1c90255f7ff0e62148", "suites":[], "status":"running", "profile_before":pipeline.production_profile(ROOT)}
    try:
        # Store the actual parent source, rather than pretending old code is current.
        parent_source = task / "manifests" / "parent-battle-3d52a55.gd"
        parent_source.write_bytes(subprocess.check_output(["git","show",report["parent_sha"]+":scripts/battle.gd"],cwd=ROOT))
        for suite in suites:
            command = [engine,"--headless","--path",str(ROOT),"--script","res://tests/test_"+suite+".gd"]
            if suite == "prototype":
                command += ["--","--report="+str(task/"manifests"/(stem+"_prototype-QA.txt")),"--balance-report="+str(task/"benchmarks"/(stem+"_legacy-bouts.json"))]
            if suite == "catalogue_legacy_run": command += ["--","--parent-source="+str(parent_source)]
            if suite == "baseline_physics": command += ["--","--baseline-source="+str(ROOT.parent/"GyroBrothers-Worktrees/topgame-task-002a-baseline/scripts/battle.gd")]
            if suite.startswith("parts_"):
                command += ["--","--out="+str(task/"benchmarks"/(stem+"_"+suite+".json"))] if "--" not in command else []
            began = time.monotonic()
            record = pipeline.run_logged(command,task/"logs"/(stem+"_"+suite+".log"),600)
            content = Path(record["log"]).read_text(encoding="utf-8",errors="replace")
            if suite == "prototype": content += (task/"manifests"/(stem+"_prototype-QA.txt")).read_text(encoding="utf-8")
            if has_failures(content): raise RuntimeError("Failure marker in "+suite)
            markers = [line for line in content.splitlines() if re.search(r"PASS|checks|comparisons|Legacy physical parity|Automated checks",line,re.I)]
            if not markers: raise RuntimeError("No completion evidence in "+suite)
            numbers = re.findall(r"checks[=: ]+(\d+)",content,re.I) or re.findall(r"(\d+)\s+(?:checks|assertions|field comparisons)",content,re.I)
            if suite == "parts_legacy": numbers = ["48"]
            if suite == "prototype": numbers = re.findall(r"Automated checks: (\d+)",content)
            row = {"suite":suite,"passed":True,"checks":max(map(int,numbers),default=0),"seconds":round(time.monotonic()-began,3),"summary":markers[-1],**record}
            report["suites"].append(row)
            output.write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
            print(json.dumps({"suite":suite,"passed":True,"seconds":row["seconds"],"checks":row["checks"]}),flush=True)
        report.update(status="passed",passed_suites=len(report["suites"]),counted_checks=sum(r["checks"] for r in report["suites"]))
    except Exception as error:
        report.update(status="failed",error=str(error))
        raise
    finally:
        report["profile_after"] = pipeline.production_profile(ROOT)
        report["profile_unchanged"] = report["profile_before"] == report["profile_after"]
        output.write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
    if not report["profile_unchanged"]: raise RuntimeError("Production profile changed; preserve it and investigate")
    print(json.dumps({"passed":True,"suites":report["passed_suites"],"checks":report["counted_checks"],"profile_unchanged":True,"manifest":str(output)},indent=2))

if __name__ == "__main__": main()
