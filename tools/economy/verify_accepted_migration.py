"""Generate a save with the real accepted parent API, then verify migration.

Only the legacy global class declaration is removed in memory. Exact Git source,
old-generated save bytes, backup archive, engine log and player profile hashes
remain in external QA. The test never opens the real player collection.
"""
from __future__ import annotations

import argparse
from datetime import datetime,timezone
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT / "tools/workspace"))
import workspace
sys.path.insert(0,str(ROOT / "tools/build"))
import windows_checkpoint as pipeline


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--task",default="003A")
    parser.add_argument("--stem",default="003a_accepted_parent_migration")
    parser.add_argument("--parent",default="b7812e17ddce6166258eca7285a0a38e8cae37fc")
    parser.add_argument("--qa-root",type=Path)
    parser.add_argument("--engine")
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9a-f]{40}",args.parent): parser.error("Provide an exact accepted Git commit SHA")
    if not re.fullmatch(r"[a-z0-9_-]+",args.stem): parser.error("Provide a clear evidence stem")
    if pipeline.git(ROOT,"rev-parse",args.parent) != args.parent: raise RuntimeError("Accepted parent does not resolve exactly")
    task = workspace.create_task_workspace(args.task,workspace.qa_root(args.qa_root))
    source = task / "temp" / (args.stem + "_CollectionSave.gd")
    collection = task / "temp" / (args.stem + "_collection.json")
    engine_report = task / "manifests" / (args.stem + "_engine.json")
    manifest = task / "manifests" / (args.stem + ".json")
    log = task / "logs" / (args.stem + ".log")
    for path in (source,collection,engine_report,manifest,log):
        if path.exists(): raise FileExistsError("Preserved migration evidence exists: " + str(path))
    previous = pipeline.production_profile(ROOT)
    if previous.get("directory"):
        user = Path(previous["directory"]).resolve()
        if task.resolve() == user or task.resolve().is_relative_to(user): raise ValueError("QA must be outside the player profile")
    original = subprocess.run(["git","show",args.parent + ":scripts/collection_save.gd"],cwd=ROOT,
                              check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE).stdout
    source.write_bytes(original)
    command = [workspace.find_tool("godot",args.engine),"--headless","--path",str(ROOT),
               "--script","res://tests/test_accepted_save_migration.gd","--",
               "--old-source=" + str(source),"--collection=" + str(collection),
               "--report=" + str(engine_report),"--parent=" + args.parent]
    executed = subprocess.run(command,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,
                              text=True,encoding="utf-8",errors="replace",timeout=120)
    log.write_text(executed.stdout,encoding="utf-8")
    result = json.loads(engine_report.read_text(encoding="utf-8")) if engine_report.exists() else {}
    after = pipeline.production_profile(ROOT)
    passed = executed.returncode == 0 and result.get("status") == "passed" and "SCRIPT ERROR:" not in executed.stdout and after == previous
    evidence = {"task":args.task,"status":"passed" if passed else "failed","accepted_parent_sha":args.parent,
                "actual_accepted_source_sha256":workspace.sha256(source),"engine_report":str(engine_report),
                "log":str(log),"returncode":executed.returncode,"checks":result.get("checks",0),
                "profile_before":previous,"profile_after":after,"profile_unchanged":previous == after,
                "created_utc":datetime.now(timezone.utc).isoformat()}
    manifest.write_text(json.dumps(evidence,indent=2)+"\n",encoding="utf-8")
    print(executed.stdout,end="")
    print(json.dumps({"status":evidence["status"],"checks":evidence["checks"],"manifest":str(manifest),"profile_unchanged":previous == after},indent=2))
    return 0 if passed else 1


if __name__ == "__main__": raise SystemExit(main())
