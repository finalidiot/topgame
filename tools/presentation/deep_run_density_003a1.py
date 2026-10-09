"""Compare real seeded Director policy on explicit independent census fixtures."""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/workspace"))
sys.path.insert(0, str(ROOT / "tools/build"))
import workspace
import windows_checkpoint as pipeline

DRIVER = "observe_deep_run_density_003a1.gd"
MODEL = "director_density_model_003a1.gd"
BASELINE = "68669556b253a67212e32c0cbf18d56f0df43f6f"


def fingerprints(stage: Path) -> dict:
    return {p.relative_to(stage).as_posix(): pipeline.sha256(p)
            for family in ("scripts", "tests") for p in sorted((stage / family).glob("*.gd"))}


def player() -> dict:
    value = pipeline.production_profile(ROOT)
    directory = Path(value["directory"])
    value["backups"] = {str(p.relative_to(directory)): pipeline.sha256(p)
                        for p in sorted((directory / "collection-backups").rglob("*")) if p.is_file()}
    return value


def summary(cases: list[dict]) -> dict:
    result = {}
    for policy in ("quick", "durable"):
        selected = [case for case in cases if case["policy"] == policy]
        ranges = {}
        for index, name in enumerate(("0–5 minutes", "5–10 minutes", "10–15 minutes", "15+ minutes")):
            bins = [case["ranges"][index] for case in selected]
            samples = sum(row["samples"] for row in bins)
            rows = [row for case in selected for row in case["trace"] if min(3, int(row["time"] / 300)) == index]
            intervals = [interval for row in bins for interval in row["admission_intervals"]]
            ranges[name] = {
                "average_active_full": sum(row["active_full_sum"] for row in bins) / samples,
                "peak_active_full": max(row["peak_active_full"] for row in bins),
                "average_fixture_swarm_bodies": sum(row["active_swarm_bodies"] for row in rows) / len(rows),
                "peak_fixture_swarm_bodies": max(row["peak_active_small"] for row in bins),
                "average_active_total_bodies": sum(row["active_total_bodies"] for row in rows) / len(rows),
                "peak_active_total_bodies": max(row["peak_total_bodies"] for row in bins),
                "peak_elites": max(row["peak_elites"] for row in bins),
                "peak_bosses": max(row["peak_bosses"] for row in bins),
                "director_tiers": sorted(set(t for row in bins for t in row["tiers"])),
                "full_top_caps": sorted(set(n for row in bins for n in row["full_caps"])),
                "pressure_budget_min": min(row["budget_min"] for row in bins),
                "pressure_budget_max": max(row["budget_max"] for row in bins),
                "admissions": sum(row["admissions"] for row in bins),
                "mean_admission_interval": sum(intervals) / len(intervals) if intervals else None,
            }
        result[policy] = ranges
    return result


def validate(data: dict, label: str) -> None:
    assert data["label"] == label and len(data["cases"]) == 12
    for case in data["cases"]:
        assert not case["violations"], case["violations"][:2]
        assert case["bounded_state"]["history"] <= 128 and case["bounded_state"]["recent"] <= 6
        assert case["bounded_state"]["active"] <= 6
        assert case["first_five"] is None or case["first_five"] >= 640
        assert case["first_six"] is None or case["first_six"] >= 880
        if label == "after":
            for event in case["admissions"]:
                if event["time"] < 640:
                    assert event["census_before"]["full"] + (event["kind"] != "swarm") <= 4
                if event["time"] >= 640:
                    if event["kind"] == "swarm":
                        assert event["census_before"]["full"] < 4 and event["census_before"]["bosses"] == 0
                    if event["kind"] == "boss":
                        assert event["census_before"]["full"] <= 3 and event["census_before"]["bosses"] == 0
                    if event["census_before"]["full"] >= 4:
                        assert not event["census_before"]["swarm"] and event["census_before"]["bosses"] == 0
    if label == "after":
        assert any(case["first_five"] is not None for case in data["cases"])
        assert any(case["first_six"] is not None for case in data["cases"])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine")
    parser.add_argument("--qa-root", type=Path, help="Base QA root containing task directories")
    args = parser.parse_args()
    qa = workspace.create_task_workspace("003A.1", args.qa_root)
    name = "003a1_deep_density_" + datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
    before_player = player()
    stages = {}
    for label in ("before", "after"):
        stage = qa / "temp" / (name + "_" + label)
        assert not stage.exists()
        (stage / "scripts").mkdir(parents=True)
        (stage / "tests").mkdir()
        (stage / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Isolated Director Policy QA"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding="utf-8")
        for script in ("threat_director.gd", "seed_utils.gd"):
            if label == "before":
                result = subprocess.run(["git", "-C", str(ROOT), "show", BASELINE + ":scripts/" + script], capture_output=True, check=True)
                (stage / "scripts" / script).write_bytes(result.stdout)
            else:
                shutil.copy2(ROOT / "scripts" / script, stage / "scripts" / script)
        for script in (DRIVER, MODEL):
            shutil.copy2(ROOT / "tests" / script, stage / "tests" / script)
        stages[label] = {"stage": stage, "fingerprints": fingerprints(stage),
                         "report": qa / "manifests" / (name + "_" + label + ".json"),
                         "log": qa / "logs" / (name + "_" + label + ".log")}
    assert pipeline.sha256(stages["before"]["stage"] / "tests" / DRIVER) == pipeline.sha256(stages["after"]["stage"] / "tests" / DRIVER)
    engine = workspace.find_tool("godot", args.engine)
    def run(label: str) -> tuple[str, dict]:
        stage = stages[label]
        command = [engine, "--headless", "--path", str(stage["stage"]), "--script", "res://tests/" + DRIVER,
                   "--", "--label=" + label, "--report=" + str(stage["report"])]
        process = pipeline.run_logged(command, stage["log"], 120)
        data = json.loads(stage["report"].read_text(encoding="utf-8"))
        validate(data, label)
        assert fingerprints(stage["stage"]) == stage["fingerprints"]
        return label, {"data": data, "process": process, "report": str(stage["report"]),
                       "report_sha256": pipeline.sha256(stage["report"]), "frozen_source": str(stage["stage"]),
                       "source_sha256": stage["fingerprints"]}
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = dict(pool.map(run, ("before", "after")))
    assert player() == before_player
    early_pairs = []
    for old, new in zip(results["before"]["data"]["cases"], results["after"]["data"]["cases"]):
        extract = lambda case: [{key: event[key] for key in ("time", "ready_at", "expires", "kind", "key", "cost", "small_cap")}
                                for event in case["admissions"] if event["time"] < 280]
        assert extract(old) == extract(new), "Unexpected early/mid policy change"
        early_pairs.append({"seed": old["seed"], "policy": old["policy"], "admissions_before_280_exact_equal": True})
    output = qa / "003a1_deep_run_density.json"
    assert not output.exists() and not (qa / "manifests" / output.name).exists()
    record = {"created_utc": datetime.now(timezone.utc).isoformat(), "baseline_sha": BASELINE,
              "scope": results["after"]["data"]["scope"], "human_acceptance": "Pending; policy-fixture density is not natural survival or human difficulty acceptance.",
              "clock": "Real Director policy inputs0..1200sec,0.25sec steps; lifetime census is an explicit independent fixture.",
              "thresholds": {"ordinary_full_caps": [1,2,3,3,4], "five_seconds": 640, "five_tier": 7, "six_seconds": 880, "six_tier": 9},
              "ordinary_changes": {"before_280": "Exact paired admissions unchanged", "late_swarm_peak": [10,9], "late_total_target": [16,15], "late_base_cadence_multiplier": 1.06, "base_budget": "16 unchanged"},
              "grandfather_rule": "New admission targets may be lower than an earlier live reservation. Old waves/bosses finish without despawn; hard existing small/boss ceilings remain10/2. No fifth/sixth admission beneath a live reserved swarm. Deep new boss requires no live swarm, no existing boss and at most3 other full tops; boss-active support target is4 total full.",
              "early_mid_pairs": early_pairs, "player_unchanged": True, "source_unchanged": True,
              "summary": {label: summary(result["data"]["cases"]) for label, result in results.items()},
              "sources": {label: {key: value for key, value in result.items() if key != "data"} for label, result in results.items()},
              "cases": {label: result["data"]["cases"] for label, result in results.items()}}
    pipeline.write_json(output, record)
    pipeline.write_json(qa / "manifests" / output.name, record)
    print(json.dumps({"passed": True, "report": str(output), "sha256": pipeline.sha256(output),
                      "cases_per_source": 12, "early_mid_exact_pairs": len(early_pairs), "summary": record["summary"]}, indent=2))


if __name__ == "__main__":
    main()
