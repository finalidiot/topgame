"""Verify an actual Windows package's isolated catalogue and all part textures.

Usage: python tools/parts/verify_packaged_catalogue.py --exe <candidate.exe>
       --qa-root <external GyroBrothers-QA>
Evidence and uniquely named fixtures remain outside the repository. No build
promotion, player-save reset, gameplay injection or existing-file overwrite.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import sys
import uuid

ROOT = Path(__file__).resolve().parents[2]
TASK = "002C.5.2"
sys.path.insert(0, str(ROOT / "tools" / "workspace"))
import workspace
sys.path.insert(0, str(ROOT / "tools" / "build"))
import windows_checkpoint as pipeline

def check_engine_log(path: Path) -> dict:
    if not path.is_file():
        raise RuntimeError(f"Actual engine log was not produced: {path}")
    content = path.read_text(encoding="utf-8", errors="replace")
    if pipeline.ERRORS.search(content):
        raise RuntimeError(f"Engine errors in actual package log: {path}")
    if "PACKAGED_PART_ASSETS_PASS textures=42" not in content:
        raise RuntimeError(f"The actual compiled package probe did not complete: {path}")
    return {"path": str(path), "sha256": workspace.sha256(path)}


def verify_collection(path: Path, expected: set[str]) -> dict:
    if not path.is_file():
        raise RuntimeError("The actual package did not create its isolated QA collection")
    saved = json.loads(path.read_text(encoding="utf-8"))
    owned = saved.get("owned_part_ids")
    if (saved.get("schema_version") != 1 or saved.get("starter_selected") != "breaker"
            or not isinstance(owned, list) or not all(isinstance(p, str) for p in owned)
            or len(owned) != len(expected) or set(owned) != expected):
        raise RuntimeError("Packaged QA collection does not own exactly the current 31 qualified part IDs")
    build = saved.get("equipped_build")
    if build != {"blade": "smash", "ratchet": "high", "bit": "flat"}:
        raise RuntimeError("The newly created QA collection changed its initial Breaker assembly")
    return {"path": str(path), "sha256": workspace.sha256(path), "owned_count": len(owned),
            "category_counts": {c: sum(p.startswith(c + ":") for p in owned)
                                for c in ("blade", "ratchet", "bit")},
            "owned_part_ids": sorted(owned), "equipped_build": build}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", type=Path, required=True, help="Explicit candidate or latest Windows executable")
    parser.add_argument("--qa-root", type=Path, help="External QA root; defaults to the workspace convention")
    args = parser.parse_args()
    exe = args.exe.expanduser().resolve(strict=True)
    if not exe.is_file() or exe.suffix.lower() != ".exe":
        parser.error("--exe must identify an existing Windows executable")
    qa_root = workspace.qa_root(args.qa_root)
    before = pipeline.production_profile(ROOT)
    if not before.get("available"):
        parser.error("The real player profile cannot be fingerprinted on this host; no package was launched")
    if before.get("available"):
        user_directory = Path(before["directory"]).resolve()
        if qa_root == user_directory or user_directory in qa_root.parents:
            parser.error("The external QA root must be outside the player's user-data directory")
    task = workspace.create_task_workspace(TASK, qa_root)
    run_id = uuid.uuid4().hex
    stem = "002c5_2_packaged_catalogue_" + run_id
    collection = task / "temp" / (stem + "_collection.json")
    asset_report = task / "manifests" / (stem + "_assets.json")
    manifest = task / "manifests" / (stem + ".json")
    if any(path.exists() for path in (collection, asset_report, manifest)):
        raise RuntimeError("Unique QA fixture unexpectedly already exists; no files were overwritten")
    source = ROOT / "assets/data/parts_catalogue.json"
    source_data = json.loads(source.read_text(encoding="utf-8"))
    catalogue = source_data["categories"]
    expected = {category + ":" + id for category, parts in catalogue.items() for id in parts}
    expected_textures = {str(part["visual"][field]) for category, parts in catalogue.items()
                         for part in parts.values() for field in (["sprite", "spin"] if category == "blade" else ["sprite"])}
    if len(expected) != 31 or len(expected_textures) != 42:
        raise RuntimeError("This task's package check requires the final 31-part / 42-texture catalogue")
    report = {"task": TASK, "run_id": run_id, "status": "running",
              "started_utc": datetime.now(timezone.utc).isoformat(), "exe": str(exe),
              "exe_sha256": workspace.sha256(exe), "source_catalogue_sha256": workspace.sha256(source),
              "profile_before": before, "child_environment": {"TOPGAME_QA_ROOT": str(qa_root)},
              "evidence_scope": "Actual packaged isolated ownership and compiled read-only catalogue/texture probe; no gameplay outcomes injected"}
    prior_qa_root = os.environ.get("TOPGAME_QA_ROOT")
    try:
        # run_logged launches hidden Windows children. Its inherited environment
        # is explicitly scoped here, then restored even if package validation fails.
        os.environ["TOPGAME_QA_ROOT"] = str(qa_root)
        engine_log = task / "logs" / (stem + "_engine.log")
        command = [str(exe), "--headless", "--quit-after", "120", "--log-file", str(engine_log),
                   "--", "--qa-catalogue", "--collection-path=" + str(collection),
                   "--qa-assets-report=" + str(asset_report)]
        report["collection_process"] = pipeline.run_logged(command, task / "logs" / (stem + "_process.log"), 180)
        report["collection_engine_log"] = check_engine_log(engine_log)
        report["collection"] = verify_collection(collection, expected)
        assets = json.loads(asset_report.read_text(encoding="utf-8"))
        rows = assets.get("textures", [])
        # Git's clean snapshot may normalise text newlines. Compare decoded
        # catalogue content, while retaining both raw file hashes as evidence.
        if (json.loads(assets.get("catalogue_json", "null")) != source_data
                or assets.get("failures") != [] or assets.get("read_only_asset_inspection") is not True
                or len(rows) != len(expected_textures)
                or {row["path"] for row in rows} != expected_textures
                or not all(row.get("valid") is True and row.get("visible_pixels") is True
                           and row.get("size") == ([384, 48] if row["path"].endswith("_spin.png") else [48, 48])
                           for row in rows)):
            raise RuntimeError("Actual package JSON or all 42 visible component textures differ from current source")
        report["assets"] = {"path": str(asset_report), "sha256": workspace.sha256(asset_report),
                            "textures_verified": len(rows), "catalogue_matches_source": True,
                            "packaged_catalogue_sha256": assets["catalogue_sha256"]}
        report["status"] = "passed"
    except Exception as error:
        report.update(status="failed", error=str(error))
        if isinstance(error, pipeline.ProcessValidationError): report["failed_process"] = error.record
        raise
    finally:
        if prior_qa_root is None: os.environ.pop("TOPGAME_QA_ROOT", None)
        else: os.environ["TOPGAME_QA_ROOT"] = prior_qa_root
        report["profile_after"] = pipeline.production_profile(ROOT)
        report["profile_unchanged"] = report["profile_before"] == report["profile_after"]
        if not report["profile_unchanged"]:
            report.update(status="failed", error="The real player profile changed; preserve it and investigate")
        report["finished_utc"] = datetime.now(timezone.utc).isoformat()
        manifest.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    if not report["profile_unchanged"]: raise RuntimeError(report["error"])
    print(json.dumps({"passed": True, "owned_parts": 31, "textures_verified": 42,
                      "profile_unchanged": True, "manifest": str(manifest)}, indent=2))


if __name__ == "__main__":
    main()
