"""Source-guard a supplemental fixed-parameter threat-order comparison."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sources() -> dict[str, str]:
    paths = list((ROOT / "scripts").glob("*.gd"))
    paths += [ROOT / "tests" / name for name in (
        "observe_bastion_active_defence.gd", "observe_bastion_matched_pressure.gd",
        "observe_bastion_matched_pressure.gd.uid", "rpm_bot.gd")]
    paths += [ROOT / "assets/data/parts_catalogue.json", ROOT / "project.godot", Path(__file__)]
    return {path.relative_to(ROOT).as_posix(): digest(path) for path in sorted(paths)}


def fingerprint(value: object) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    qa = ROOT.parent / "GyroBrothers-QA" / "003A.1"
    target = args.out.resolve()
    if not target.is_relative_to(qa.resolve() / "manifests"):
        raise SystemExit("Use a fresh external003A.1/manifests output")
    log = qa / "logs" / (target.stem + ".log")
    proof_path = target.with_suffix(".provenance.json")
    summary_path = target.with_suffix(".summary.json")
    if any(path.exists() for path in (target, log, proof_path, summary_path)):
        raise SystemExit("Refusing to overwrite preserved supplemental artifacts")
    before, reference_hash = sources(), digest(args.reference)
    command = [str(args.godot), "--headless", "--path", str(ROOT), "--script",
               "res://tests/observe_bastion_matched_pressure.gd", "--",
               "--reference=" + str(args.reference.resolve()), "--report=" + str(target)]
    with log.open("w", encoding="utf-8") as stream:
        result = subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT)
    after = sources()
    errors = [line for line in log.read_text(encoding="utf-8").splitlines()
              if "SCRIPT ERROR:" in line or "ERROR:" in line or "were leaked" in line]
    proof = {"command": command, "exit_code": result.returncode, "source_before": before,
             "source_after": after, "source_unchanged": before == after,
             "reference_sha256": reference_hash, "reference_unchanged": reference_hash == digest(args.reference),
             "raw_sha256": digest(target) if target.exists() else None, "log": str(log), "engine_errors": errors}
    proof_path.write_text(json.dumps(proof, indent=2) + "\n", encoding="utf-8")
    if result.returncode or errors or before != after or not proof["reference_unchanged"]:
        raise SystemExit("Supplement failed; preserve raw log and provenance")
    data = json.loads(target.read_text(encoding="utf-8"))
    a, b = data["samples"]
    shared_end = min(a["run_seconds"], b["run_seconds"])
    details = {row["policy"]: row for row in data["replay_details"]}
    admitted = {policy: [event for event in details[policy]["admissions"]
                         if event["actual_admission_time"] <= shared_end + 1e-8]
                for policy in ("zero_input", "minimal_active")}
    fields = ("serial", "key", "kind", "role", "name", "cost", "tier_at_entry", "small_cap", "warning",
              "opponent_build", "actual_initial_mass", "actual_initial_handling", "entity_ids")
    exact_a = [{key: event[key] for key in fields} for event in admitted["zero_input"]]
    exact_b = [{key: event[key] for key in fields} for event in admitted["minimal_active"]]
    common = 0
    for left, right in zip(exact_a, exact_b):
        if left != right:
            break
        common += 1
    rows = []
    for row in (a, b):
        lost, gained = sum(row["mature_losses"].values()), sum(row["mature_gains"].values())
        rows.append({key: row[key] for key in ("policy", "run_seconds", "mature_seconds", "reason", "ended_naturally",
                    "final_rpm", "final_wobble", "mature_contacts", "mature_heavy_contacts", "centre_seconds",
                    "mean_effective_mass", "mean_wobble", "input_seconds", "brake_seconds", "control_modes",
                    "mature_losses", "mature_gains")})
        rows[-1].update(handoff_rpm=row["handoff"]["rpm"], handoff_fingerprint=fingerprint(row["handoff"]),
                        total_loss=lost, total_gain=gained,
                        ledger_closure_error=row["final_rpm"]-row["handoff"]["rpm"]-(gained-lost))
    cap_safe = True
    for detail in data["replay_details"]:
        for event in detail["offers"]:
            c, limit = event["census_before"], event["limits"]
            cap_safe &= c["pressure"] + event["cost"] <= limit["budget"] + 1e-6
            cap_safe &= c["total"] + (event["small_cap"] if event["kind"] == "swarm" else 1) <= limit["total"]
            if event["kind"] != "swarm":
                cap_safe &= c["full"] + 1 <= limit["full"]
            if event["kind"] in ("elite", "boss"):
                field = "elites" if event["kind"] == "elite" else "bosses"
                cap_safe &= c[field] + 1 <= limit[field]
    summary = {"schema": "003a1-fixed-order-supplement-analysis-v1", "scope": data["scope"],
               "raw_report": str(target), "raw_sha256": digest(target), "reference_sha256": reference_hash,
               "identical_full_handoff": rows[0]["handoff_fingerprint"] == rows[1]["handoff_fingerprint"],
               "shared_lifetime_end": shared_end, "shared_mature_seconds": shared_end-360,
               "nominal_event_count": len(data["nominal_schedule"]), "admitted_counts_over_shared_lifetime":
               {policy: len(events) for policy, events in admitted.items()}, "matched_exact_parameter_prefix_count": common,
               "identical_all_shared_admitted_parameters": exact_a == exact_b, "all_original_caps_and_budgets_respected": cap_safe,
               "admission_timing_equal": [event["actual_admission_time"] for event in admitted["zero_input"]] ==
                                        [event["actual_admission_time"] for event in admitted["minimal_active"]],
               "fixed_parameter_fields": list(fields), "admissions": admitted, "samples": rows,
               "limitations": data["limitations"]}
    summary_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    assert summary["identical_full_handoff"] and cap_safe
    assert all(abs(row["ledger_closure_error"]) < 1e-9 for row in rows)
    assert common > 0, "At least one admitted fixed-parameter enemy must be compared"
    print(json.dumps({"passed": True, "summary": str(summary_path), "shared_events": common,
                      "all_shared_parameters_identical": exact_a == exact_b,
                      "afk_rpm": a["final_rpm"], "active_rpm": b["final_rpm"]}, indent=2))


if __name__ == "__main__":
    main()
