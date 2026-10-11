"""Isolated paired ecology workload, real pilots, native replay and retirement proof.

New initial legal III ownership is the intentional AFTER workload expansion.
BEFORE uses its legal II equivalents; this is not equal-combat-outcome evidence.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import math
from pathlib import Path
import shutil
import statistics
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[2]
for family in ("tools/build", "tools/workspace", "tools/presentation"):
    sys.path.insert(0, str(ROOT / family))
import windows_checkpoint as pipeline
import workspace
from rpm_economy_study_003a1 import source

BASELINE = "b476c6d9240a2c9f03942cda70d43576cc3903da"
DRIVER = "observe_ecology_performance_003a2.gd"


def now():
    return datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def pointer(path):
    path = Path(path).resolve()
    return {"path": str(path), "bytes": path.stat().st_size, "sha256": pipeline.sha256(path)}


def protected(original):
    result = {}
    for name in original:
        path = Path(name)
        assert path.is_file(), "Missing protected file: " + name
        result[name] = {"size": path.stat().st_size, "sha256": pipeline.sha256(path)}
    return result


def guard(qa):
    baseline = read(qa / "manifests/003a2_scope_baseline.json")
    assert baseline["starting_main"] == BASELINE
    result = {kind: protected(baseline[kind]) for kind in ("player", "assets", "music")}
    assert all(result[kind] == baseline[kind] for kind in result), "Protected baseline changed; preserve and investigate"
    return result


def import_preserving_bytes(engine, project, log_prefix):
    originals = {p: p.read_bytes() for p in (project / "assets").rglob("*.import")}
    process = pipeline.import_source([engine, "--headless", "--path", str(project), "--editor", "--import"], log_prefix, 900)
    normalisations = {}
    for path, original in originals.items():
        if path.read_bytes() == original:
            continue
        assert path.read_bytes().replace(b"\r\n", b"\n") == original.replace(b"\r\n", b"\n"), "Importer changed metadata semantics"
        normalisations[path.relative_to(project).as_posix()] = {"imported_sha256": pipeline.sha256(path), "difference": "CRLF/LF only"}
        path.write_bytes(original)
        normalisations[path.relative_to(project).as_posix()]["restored_sha256"] = pipeline.sha256(path)
    return {**process, "import_metadata_newline_normalisations": normalisations}


def extract_runtime(archive, stage):
    with zipfile.ZipFile(archive) as handle:
        for item in handle.infolist():
            relative = Path(item.filename)
            assert not relative.is_absolute() and ".." not in relative.parts
            if relative.parts[0] not in ("scripts", "assets", "project.godot", "main.tscn"):
                continue
            target = (stage / relative).resolve()
            assert target.is_relative_to(stage.resolve())
            if item.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(handle.read(item))


def driver_hash(project):
    return pipeline.sha256(project / "tests" / DRIVER)


def freeze(args, qa):
    stem = "003a2_ecology_performance_frozen_" + now()
    manifest = qa / "manifests" / (stem + ".json")
    current, harness, protected_before = source(ROOT), driver_hash(ROOT), guard(qa)
    archive = qa / "temp" / (stem + "_baseline.zip")
    subprocess.run(["git", "archive", "--format=zip", "--output", str(archive), BASELINE], cwd=ROOT, check=True)
    record = {"status": "preparing", "created_utc": datetime.now(timezone.utc).isoformat(), "baseline_sha": BASELINE,
              "working_head": pipeline.git(ROOT, "rev-parse", "HEAD"), "baseline_archive": pointer(archive),
              "original_production": current, "driver_sha256": harness, "wrapper": pointer(__file__), "stages": {},
              "protected_start": {kind: len(files) for kind, files in protected_before.items()},
              "scope": "Immutable accepted-main git archive and coherent current runtime. Same observer in isolated projects. Legal initial ownership changes II to III; initial physical fixtures stay matched. No canonical editor import, save mutation or accepted asset rewrite."}
    pipeline.write_json(manifest, record)
    engine = workspace.find_tool("godot", args.engine)
    try:
        for label in ("before", "after"):
            stage = qa / "temp" / (stem + "_" + label)
            assert not stage.exists()
            stage.mkdir()
            if label == "before":
                extract_runtime(archive, stage)
            else:
                for name in ("project.godot", "main.tscn"):
                    shutil.copy2(ROOT / name, stage / name)
                for family in ("scripts", "assets"):
                    shutil.copytree(ROOT / family, stage / family)
                assert source(stage) == current
            (stage / "tests").mkdir()
            shutil.copy2(ROOT / "tests" / DRIVER, stage / "tests" / DRIVER)
            expected = source(stage)
            item = {"project": str(stage), "before_import_production_hashes": expected, "driver_sha256": driver_hash(stage)}
            record["stages"][label] = item
            pipeline.write_json(manifest, record)
            print("COLD_IMPORT " + label, flush=True)
            item["import"] = import_preserving_bytes(engine, stage, qa / "logs" / (stem + "_" + label + "_import"))
            imported = source(stage)
            added = {key: value for key, value in imported.items() if key not in expected}
            assert all(key.startswith("scripts/") and key.endswith(".uid") for key in added), "Unexpected importer mutation"
            assert {key: imported[key] for key in expected} == expected
            assert driver_hash(stage) == harness
            item.update(production_hashes=imported, cold_import_added_uid_metadata=added)
            pipeline.write_json(manifest, record)
        assert source(ROOT) == current and driver_hash(ROOT) == harness and guard(qa) == protected_before
        record.update(status="passed", canonical_runtime_unchanged=True, protected_player_assets_music_unchanged=True)
    except Exception as exc:
        record.update(status="failed", error=str(exc))
        pipeline.write_json(manifest, record)
        raise
    pipeline.write_json(manifest, record)
    print(json.dumps({"frozen": pointer(manifest)}, indent=2), flush=True)
    return manifest


def stats(values):
    if not values:
        return {"samples": 0}
    values = sorted(values)
    assert all(math.isfinite(value) and value >= 0 for value in values)
    return {"samples": len(values), "median_ms": statistics.median(values), "p95_ms": values[math.ceil(len(values) * .95) - 1],
            "max_ms": values[-1], "mean_ms": statistics.mean(values)}


def summary(cases):
    result = {}
    for count in (3, 4, 5, 6):
        selected = [case for case in cases if case["full_enemies_fixture"] == count]
        assert len(selected) == 3
        metrics = {key: stats([value for case in selected for value in case["samples_ms"][key]]) for key in selected[0]["samples_ms"]}
        peaks = {key: max(case["peaks"].get(key, 0) for case in selected) for key in {key for case in selected for key in case["peaks"]}}
        sums = {key: sum(case[key] for case in selected) for key in ("frames", "advancing_frames", "impact_hold_frames", "requested_density_frames", "requested_density_advancing_frames", "density_with_multiple_routes_frames",
                "multiple_paid_route_frames", "multiple_ecology_owner_frames", "committed_owner_frames", "loaded_owner_frames", "buckled_owner_frames")}
        coverage = {}
        for case in selected:
            for key, value in case["final_ecology"].items():
                coverage[key] = coverage.get(key, 0) + value
        result[str(count + 1)] = {"cases": len(selected), "full_enemies": count, "total_full_tops": count + 1, "additional_stress": count == 6, "measurements": metrics, "peaks": peaks,
                              "frame_counts": sums, "actual_ecology_events": coverage, "clocks_synchronized": all(case["clocks_synchronized"] for case in selected)}
    return result


def validate(raw, rendered, ticks):
    assert not raw["failures"] and raw["checks"] > 0
    assert len(raw["cases"]) == 12 and raw["seeds"] == [421, 7341, 2026] and raw["ticks_per_case"] == ticks
    assert raw["rendered"] == rendered and not raw["main_created"] and not raw["collection_opened"]
    assert [(c["seed"], c["full_enemies_fixture"]) for c in raw["cases"]] == [(seed, count) for seed in raw["seeds"] for count in (3, 4, 5, 6)]
    for case in raw["cases"]:
        assert case["clocks_synchronized"] and case["requested_density_advancing_frames"] >= 120
        assert case["peaks"]["powered_enemies"] == case["full_enemies_fixture"]
        assert case["frames"] == case["advancing_frames"] + case["impact_hold_frames"]
        assert len(case["samples_ms"]["physics"]) == max(0, case["frames"] - 60)
        assert case["physics_ms"]["samples"] > 0
        if rendered:
            assert case["frame_wall_ms"]["samples"] > 0 and case["draw_submission_ms"]["samples"] > 0


def physical_initial(case):
    return [{key: value for key, value in f.items() if key not in ("powers", "ranks", "mutations", "published_power_state")} for f in case["initial"]]


def replay_fields(case):
    fields = ("seed", "full_enemies_fixture", "initial_clock_fixture", "initial", "final", "frames", "advancing_frames", "impact_hold_frames",
              "requested_density_frames", "requested_density_advancing_frames", "density_with_multiple_routes_frames", "multiple_paid_route_frames", "multiple_ecology_owner_frames", "committed_owner_frames", "loaded_owner_frames",
              "buckled_owner_frames", "status", "final_powers", "final_roster", "final_ecology")
    result = {key: case[key] for key in fields}
    result["trace"] = [{key: row[key] for key in ("tick", "elapsed", "control", "physical", "powers", "roster", "ecology")} for row in case["trace"]]
    return result


def run_stage(args, qa, boundary, label, stem, rendered, cleanup=False):
    item = boundary["stages"][label]
    project = Path(item["project"])
    assert source(project) == item["production_hashes"] and driver_hash(project) == item["driver_sha256"]
    report = qa / "benchmarks" / (stem + "_" + label + ".json")
    log = qa / "logs" / (stem + "_" + label + ".log")
    command = [workspace.find_tool("godot", args.engine), "--path", str(project), "--script", "res://tests/" + DRIVER, "--audio-driver", "Dummy"]
    command += ["--resolution", "640x360", "--disable-vsync"] if rendered else ["--headless"]
    command += ["--", "--report=" + str(report), "--label=" + label, "--ticks=" + str(args.ticks)]
    if rendered:
        command.append("--rendered")
    if cleanup:
        command.append("--cleanup-only")
    process = None
    try:
        process = pipeline.run_logged(command, log, 900)
        data = read(report)
        if cleanup:
            assert not data["failures"] and data["cleanup"]["admissions"] == 64
            assert len(data["cleanup"]["rows"]) == 64 and all(row["outcome"] == "ring_out" for row in data["cleanup"]["rows"])
        else:
            validate(data, rendered, args.ticks)
        assert source(project) == item["production_hashes"] and driver_hash(project) == item["driver_sha256"]
        return {"report": pointer(report), "process": process, "data": data}
    finally:
        if report.exists():
            pipeline.write_json(qa / "manifests" / (stem + "_" + label + "_attempt.json"),
                                {"report": pointer(report), "log": pointer(log) if log.exists() else None, "process": process,
                                 "source_unchanged": source(project) == item["production_hashes"], "driver_unchanged": driver_hash(project) == item["driver_sha256"]})


def measure(args, qa, manifest):
    boundary = read(manifest)
    assert boundary["status"] == "passed" and boundary["baseline_sha"] == BASELINE
    protected_before, canonical_before, harness_before = guard(qa), source(ROOT), driver_hash(ROOT)
    assert canonical_before == boundary["original_production"] and harness_before == boundary["driver_sha256"], "Frozen current source/observer changed"
    rendered = args.mode == "native"
    suffix = "_" + args.revision if args.revision else ""
    kind = "retirement" if args.cleanup else args.mode
    stem = "003a2_ecology_performance_" + kind + suffix + "_" + now()
    output = qa / "benchmarks" / ("003a2_ecology_performance_" + kind + suffix + ".json")
    canonical = qa / "manifests" / output.name
    assert not output.exists() and not canonical.exists(), "Preserve earlier evidence; use a new revision"
    results = {}
    try:
        for label in ("before", "after"):
            print("MEASURE " + kind + " " + label, flush=True)
            results[label] = run_stage(args, qa, boundary, label, stem, rendered, args.cleanup)
        assert guard(qa) == protected_before and source(ROOT) == canonical_before and driver_hash(ROOT) == harness_before
        replay = None
        if not args.cleanup:
            for before, after in zip(results["before"]["data"]["cases"], results["after"]["data"]["cases"]):
                assert (before["seed"], before["full_enemies_fixture"], before["initial_clock_fixture"], physical_initial(before)) == (after["seed"], after["full_enemies_fixture"], after["initial_clock_fixture"], physical_initial(after)), "Physical fixture changed"
            if rendered:
                simulation = qa / "benchmarks" / ("003a2_ecology_performance_simulation" + suffix + ".json")
                previous = read(simulation)
                assert previous["frozen_boundary"]["sha256"] == pipeline.sha256(manifest)
                for label in ("before", "after"):
                    old_pointer = previous["observations"][label]["report"]
                    assert pipeline.sha256(Path(old_pointer["path"])) == old_pointer["sha256"]
                    old = read(old_pointer["path"])
                    assert [replay_fields(case) for case in old["cases"]] == [replay_fields(case) for case in results[label]["data"]["cases"]], "Native/headless physical/control replay differs: " + label
                replay = {"simulation_report": pointer(simulation), "cases": 24, "physical_controls_epochs_positions_velocities_RPM_outcomes_counters_exact": True,
                          "excluded": "Renderer resource/static-memory counters, draw calls and timings differ by design."}
        record = {"status": "passed", "created_utc": datetime.now(timezone.utc).isoformat(), "mode": kind, "frozen_boundary": pointer(manifest),
                  "baseline_sha": BASELINE, "observer_sha256": harness_before, "wrapper": pointer(__file__), "scope": results["after"]["data"]["scope"],
                  "observations": {label: {key: value for key, value in item.items() if key != "data"} for label, item in results.items()},
                  "checks": {label: item["data"]["checks"] for label, item in results.items()}, "protected_counts": {kind: len(files) for kind, files in protected_before.items()},
                  "protected_player_assets_music_unchanged": True, "canonical_and_staged_runtime_unchanged": True,
                  "native_headless_replay": replay, "matched_initial_physics": not args.cleanup,
                  "intentional_workload_delta": "Accepted baseline selected families are legal II equivalents; AFTER has III branches. Other powers, physical initial builds/poses/velocities and role pilots are matched. Combat outcomes may differ.",
                  "limitations": "Short disclosed load fixtures; extra Director admissions suspended, existing outcomes/retirement natural. Serialized host measurements, no other scheduled QA contention; other host activity remains possible. CPU draw is submission only, frame wall includes harness/read-only monitors. Godot static memory is not RSS or leak proof. No guaranteed FPS, physical Android or human controller claims."}
        if args.cleanup:
            record["retirement"] = {label: item["data"]["cleanup"] for label, item in results.items()}
        else:
            record["summary"] = {label: summary(item["data"]["cases"]) for label, item in results.items()}
        pipeline.write_json(output, record)
        pipeline.write_json(canonical, record)
        assert output.read_bytes() == canonical.read_bytes()
        print(json.dumps({"passed": True, "report": pointer(output), "checks": record["checks"], "summary": record.get("summary")}, indent=2), flush=True)
    except Exception as exc:
        pipeline.write_json(qa / "manifests" / (stem + "_failed.json"), {"status": "failed", "error": str(exc), "frozen_boundary": pointer(manifest),
                            "attempts": {label: {key: value for key, value in item.items() if key != "data"} for label, item in results.items()},
                            "protected_unchanged": guard(qa) == protected_before, "canonical_runtime_unchanged": source(ROOT) == canonical_before})
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--freeze", action="store_true")
    parser.add_argument("--stages", type=Path)
    parser.add_argument("--mode", choices=("simulation", "native"))
    parser.add_argument("--cleanup", action="store_true", help="Separate untimed real ring-out/retirement contract")
    parser.add_argument("--ticks", type=int, default=720)
    parser.add_argument("--revision", default="")
    parser.add_argument("--engine")
    parser.add_argument("--qa-root", type=Path)
    args = parser.parse_args()
    assert not args.revision or all(character.isalnum() or character == "_" for character in args.revision)
    assert 180 <= args.ticks <= 1800 and (args.freeze or args.stages)
    assert not args.cleanup or args.mode != "native", "Cleanup contract is untimed/headless"
    qa = workspace.create_task_workspace("003A.2", args.qa_root)
    manifest = freeze(args, qa) if args.freeze else args.stages.resolve()
    if args.mode or args.cleanup:
        measure(args, qa, manifest)


if __name__ == "__main__":
    main()
