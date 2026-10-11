"""Guarded canonical Bastion handling/active-defence observations, never tuning production."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import statistics
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "tools/build"), str(ROOT / "tools/presentation"), str(ROOT / "tools/workspace")]
import windows_checkpoint as pipeline
from upgrade_sustain_003a1 import source, player
import workspace

DRIVER = ROOT / "tests/observe_bastion_feel_003a2.gd"
PACKAGES = {
    "naked": ({}, {}),
    "dead_centre_i": ({"dead_centre": 1}, {}),
    "dead_centre_ii": ({"dead_centre": 2}, {}),
    "bulwark": ({"dead_centre": 3}, {"dead_centre": "bulwark"}),
    "counterweight": ({"dead_centre": 3}, {"dead_centre": "counterweight"}),
    "sink": ({"impact_sink": 2}, {}),
    "crash_guard": ({"crash_guard": 2}, {}),
    "anchor_exchange": ({"anchor_exchange": 2}, {}),
    "gyro_lock": ({"gyro_lock": 2}, {}),
    "comet": ({"iron_comet": 2}, {}),
    "bank": ({"momentum_bank": 2}, {}),
    "chain": ({"chain_impact": 2}, {}),
    "high_gear": ({"high_gear": 2}, {}),
    "mixed_attack": ({"iron_comet": 2, "momentum_bank": 2, "chain_impact": 2, "high_gear": 2}, {}),
    "defence_stack": ({"dead_centre": 3, "impact_sink": 2, "crash_guard": 2, "anchor_exchange": 2,
                       "gyro_lock": 2, "momentum_bank": 2, "clutch": 2}, {"dead_centre": "bulwark"}),
    "mixed_defence": ({"dead_centre": 2, "impact_sink": 2, "crash_guard": 2, "iron_comet": 2,
                       "momentum_bank": 2, "chain_impact": 2, "high_gear": 2}, {}),
}
LITERAL = {"response", "cruise", "cruise_uncapped", "turn", "release", "edge", "edge_stop", "shared_course", "zero_input", "centre_hold"}
POLICIES = LITERAL | {"minimal", "active_defence", "brace_counter", "pursuit", "aggressive", "edge_recovery"}
SHORT_HORIZONS = {"response": 6.0, "cruise": 12.0, "cruise_uncapped": 12.0, "turn": 6.0, "release": 8.0, "edge": 6.0, "edge_stop": 6.0}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def changes(before: dict, after: dict) -> dict:
    return {k: {"before": before.get(k), "after": after.get(k)}
            for k in sorted(before.keys() | after.keys()) if before.get(k) != after.get(k)}


def declared_cases(args) -> list[dict]:
    cases = []
    packages = args.packages or (["naked"] if args.phase == "response" else list(PACKAGES))
    policies = args.policies or (["response", "cruise"] if args.phase == "response"
                                else ["release", "edge"] if args.phase == "range"
                                else ["shared_course", "active_defence"])
    assert set(packages) <= PACKAGES.keys() and set(policies) <= POLICIES
    profiles = [("bastion", a) for a in args.accelerations]
    if args.phase == "response": profiles += [("breaker", 0.0), ("vane", 0.0)]
    for starter, acceleration in profiles:
        for package in packages:
            ranks, mutations = PACKAGES[package]
            for seed in args.seeds:
                for policy in policies:
                    horizon = SHORT_HORIZONS.get(policy, args.horizon)
                    cases.append({"case_id": f"{starter}/{package}/{policy}/{seed}/{acceleration:.3f}",
                                  "starter": starter, "package": package, "policy": policy, "ranks": ranks,
                                  "mutations": mutations, "acceleration": acceleration, "seed": seed,
                                  "lane": "natural" if args.phase == "combat" else "solo",
                                  "horizon": horizon, "investments": min(21, max(1, sum(ranks.values()) + 1)),
                                  "input_kind": "literal_fixed_step_calls" if policy in LITERAL else "sampled_public_state_policy",
                                  "label": args.label})
    assert len(cases) <= args.case_limit, f"Declared {len(cases)} cases exceeds explicit {args.case_limit} limit"
    assert len({c["case_id"] for c in cases}) == len(cases)
    return cases


def observe(args) -> None:
    qa = workspace.create_task_workspace("003A.2")
    original = args.project.resolve()
    assert original.is_dir() and (original / "project.godot").is_file()
    assert original != ROOT, "Execute a copied frozen stage, never the user's current checkout"
    stem = "003a2_bastion_feel_" + args.label + "_" + datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
    stage = qa / "temp" / (stem + "_source")
    raw = qa / "manifests" / (stem + "_runtime.json")
    request = qa / "temp" / (stem + "_request.json")
    receipt = qa / "manifests" / (stem + ".json")
    log = qa / "logs" / (stem + ".log")
    profile = qa / "temp" / (stem + "_profile")
    assert not any(p.exists() for p in [stage, raw, request, receipt, log])
    input_source = source(original)
    canonical_before = source(ROOT)
    protected_player = player()
    harness = {str(p): digest(p) for p in [DRIVER, Path(__file__), ROOT / "tools/build/windows_checkpoint.py",
                                        ROOT / "tools/presentation/upgrade_sustain_003a1.py", ROOT / "tools/workspace/workspace.py", DRIVER.with_suffix(".gd.uid")] if p.is_file()}
    cases = declared_cases(args)
    record = {"schema": "003a2-bastion-feel-guard-v1", "status": "preparing", "phase": args.phase,
              "label": args.label, "input_stage": str(original), "input_source_before": input_source,
              "canonical_before_unexecuted": canonical_before, "player_before": protected_player,
              "harness_before": harness, "cases": cases,
              "scope": "Each batch cold-copies the frozen input stage, then adds only the exact new observer. Acceleration experiments are disclosed per-entity initialization overrides. Canonical-root presentation/audio changes are unexecuted and recorded separately. No native engine/player window, natural acquisition, survival optimization, permanent reward or physical-feel acceptance claim."}
    write(receipt, record)
    shutil.copytree(original, stage, ignore=shutil.ignore_patterns(".godot", ".git", "builds"))
    (stage / "tests").mkdir(exist_ok=True)
    shutil.copy2(DRIVER, stage / "tests" / DRIVER.name)
    if DRIVER.with_suffix(".gd.uid").is_file(): shutil.copy2(DRIVER.with_suffix(".gd.uid"), stage / "tests" / (DRIVER.name + ".uid"))
    write(request, {"cases": cases})
    engine = workspace.find_tool("godot", args.engine)
    try:
        record["import"] = pipeline.import_source([engine, "--headless", "--editor", "--path", str(stage), "--import"],
                                                   qa / "temp" / (stem + "_import"))
        executed_before = source(stage)
        assert executed_before == input_source, "Cold import changed protected runtime input bytes"
        record.update(status="running", executed_source_before=executed_before,
                      executed_driver_sha256=digest(stage / "tests" / DRIVER.name),
                      executed_uid_sha256=digest(stage / "tests" / (DRIVER.name + ".uid")) if (stage / "tests" / (DRIVER.name + ".uid")).is_file() else None,
                      request_sha256=digest(request))
        write(receipt, record)
        os.environ["TOPGAME_QA_ROOT"] = str(qa.parent)
        command = [engine, "--headless", "--path", str(stage), "--script", "res://tests/" + DRIVER.name,
                   "--", "--report=" + str(raw), "--request=" + str(request), "--profile-prefix=" + str(profile)]
        start = time.monotonic()
        try:
            process = pipeline.run_logged(command, log, args.timeout)
            record["process"] = process
        except pipeline.ProcessValidationError as error:
            record["process"] = error.record
            raise
        record["wall_seconds"] = round(time.monotonic() - start, 3)
        data = json.loads(raw.read_text(encoding="utf-8"))
        assert len(data["samples"]) == len(cases) and not data["failures"]
        assert all(r["finite"] and r["ledger_closure_error"] < 1e-6 for r in data["samples"])
        record.update(status="passed", checks=data["checks"], runtime={"path": str(raw), "sha256": digest(raw)},
                      isolated_profiles={key: {**value, "sha256": digest(Path(value["path"]))} for key, value in data["profiles"].items()})
    except Exception as error:
        record.update(status="failed", error=f"{type(error).__name__}: {error}")
        raise
    finally:
        record["executed_harness_after"]={p.relative_to(stage).as_posix():digest(p) for p in [stage / "tests" / DRIVER.name,stage / "tests" / (DRIVER.name+".uid")] if p.is_file()}
        record["executed_driver_unchanged"]=record.get("executed_driver_sha256")==record["executed_harness_after"].get("tests/"+DRIVER.name) and record.get("executed_uid_sha256")==record["executed_harness_after"].get("tests/"+DRIVER.name+".uid")
        record.update(input_source_after=source(original), canonical_after_unexecuted=source(ROOT), player_after=player(),
                      harness_after={p: digest(Path(p)) for p in harness}, executed_source_after=source(stage))
        record["input_stage_unchanged"] = record["input_source_before"] == record["input_source_after"]
        record["executed_source_unchanged"] = record.get("executed_source_before") == record["executed_source_after"]
        record["harness_unchanged"] = record["harness_before"] == record["harness_after"]
        record["player_unchanged"] = record["player_before"] == record["player_after"]
        record["canonical_root_unexecuted_deltas"] = changes(record["canonical_before_unexecuted"], record["canonical_after_unexecuted"])
        record["scope_note"] = "Canonical root delta is disclosed, not an executed-stage equivalence assertion. Only immutable/copied executed stage and exact harness qualify these physics observations."
        if not all(record[k] for k in ["input_stage_unchanged", "executed_source_unchanged", "harness_unchanged", "player_unchanged", "executed_driver_unchanged"]): record["status"] = "failed"
        write(receipt, record)
        print(json.dumps({k: record.get(k) for k in ["status", "phase", "checks", "wall_seconds", "input_stage_unchanged", "executed_source_unchanged", "harness_unchanged", "player_unchanged"]} |
                         {"receipt": str(receipt), "sha256": digest(receipt), "raw": str(raw), "cases": len(cases)}, indent=2), flush=True)
    if record["status"] != "passed": raise SystemExit(1)


def comparison(args) -> None:
    destination = args.out.resolve()
    qa = workspace.create_task_workspace("003A.2")
    assert destination.is_relative_to(qa.resolve()) and not destination.exists(), "Fresh external output required; archive prior versions explicitly"
    rows, refs = [], []
    for path in args.receipts:
        proof = json.loads(path.read_text(encoding="utf-8"))
        assert proof["status"] == "passed" and all(proof[k] for k in ["input_stage_unchanged", "executed_source_unchanged", "harness_unchanged", "player_unchanged"])
        raw = Path(proof["runtime"]["path"])
        assert digest(raw) == proof["runtime"]["sha256"]
        data = json.loads(raw.read_text(encoding="utf-8"))
        for row in data["samples"]:
            copied={**row,"receipt":str(path),"raw_report":str(raw)}
            if "idle_seconds" not in copied and abs(copied["input_seconds"]-copied["seconds"])<1e-7:
                copied["idle_seconds"]=0.0
                copied["idle_scope"]="Derived from the exact advancing-tick steering integral: input_seconds equals observed seconds within1e-7; no advancing tick lacks requested steering. Impact holds add no time. Other rows lacking this equality keep idle unmeasured."
            rows.append(copied)
        refs.append({"path": str(path), "sha256": digest(path), "runtime": proof["runtime"], "label": proof["label"],
                     "phase": proof["phase"], "executed_source": proof["executed_source_before"],
                     "unexecuted_canonical_deltas": proof["canonical_root_unexecuted_deltas"]})
    groups = {}
    for row in rows:
        key = tuple(row[k] for k in ["label", "starter", "package", "policy", "lane", "horizon"])
        groups.setdefault(key, {}).setdefault(row["actual_handling"]["acceleration"], []).append(row)
    summaries = []
    metrics = ["final_rpm", "mean_speed", "peak_speed", "mean_heading_error_radians", "centre_fraction",
               "active_input_fraction", "input_changes", "brake_seconds", "idle_seconds", "active_control_seconds", "actual_player_burst_activations", "contacts_count", "heavy_count", "mean_wobble",
               "mean_anchor_stress", "first_response_5", "first_response_50", "turn_to_up_seconds", "release_response_35",
               "edge_centre_seconds", "steady_cruising_speed", "configured_speed_cap_full_reserve", "unbraked_turn_to_up_seconds"]
    for key, variants in groups.items():
        for acceleration, observations in variants.items():
            summaries.append({**dict(zip(["label", "starter", "package", "policy", "lane", "horizon"], key)), "acceleration": acceleration,
                              "cases": len(observations), "seeds": [r["seed"] for r in observations],
                              "natural_terminations": sum(r["ended_naturally"] for r in observations),
                              "right_censored": sum(r["right_censored"] for r in observations),
                              "observed_duration_seconds": {"min":min(r["seconds"] for r in observations),"max":max(r["seconds"] for r in observations)},
                              "uncensored_terminal_durations": [r["seconds"] for r in observations if r["ended_naturally"]],
                              "terminal_outcomes": [{"seed":r["seed"],"outcome":r["player_outcome"],"reason":r["reason"],"observed_seconds":r["seconds"],"right_censored":r["right_censored"]} for r in observations],
                              "player_ringouts": sum(r["player_outcome"] == "ring_out" for r in observations),
                              "metrics": {m: {"mean": statistics.mean(values), "min": min(values), "max": max(values)}
                                          for m in metrics if m!="final_rpm" and (values := [float(r[m]) for r in observations if r.get(m) is not None])},
                              "unreached_response_gates": {m: sum(r.get(m) is None for r in observations)
                                                          for m in ["first_response_5", "first_response_50", "turn_to_up_seconds", "release_response_35", "edge_centre_seconds"]}})
    pairs, replays = [], []
    for index, a in enumerate(rows):
        for b in rows[index + 1:]:
            if any(a[k] != b[k] for k in ["starter", "package", "policy", "lane", "seed", "horizon"]): continue
            if a["actual_handling"] == b["actual_handling"]:
                if a["receipt"] != b["receipt"]:
                    keys = ["contacts", "full_impacts", "economy", "power_procs", "defence_procs", "roster_procs", "director_history", "final_power_state", "player_outcome"]
                    actor_keys=["simulation_time","fixed_step_calls","rpm","wobble","position","velocity","speed","radius","powers","census","mode"]
                    trace_equal=[{k:t[k] for k in actor_keys} for t in a["trace"]]==[{k:t[k] for k in actor_keys} for t in b["trace"]]
                    encoding_same=a.get("input_hash_encoding")==b.get("input_hash_encoding")
                    replays.append({"case_a": a["case_id"], "case_b": b["case_id"], "label_a": a["label"], "label_b": b["label"],
                                    "same_handling": True,"compared_fields": keys,"trace_actor_fields":actor_keys,
                                    "recorded_actual_replay_exact":trace_equal and all(a[k] == b[k] for k in keys),
                                    "input_hash_encoding_same":encoding_same,
                                    "compatible_input_hash_equal":a["input_sha256"]==b["input_sha256"] if encoding_same else None,
                                    "scope":"Exact recorded actor samples/contacts/ledger/power/outcome fields, not unrecorded per-tick actor equality. Extra v3 telemetry fields are omitted; different input hash encodings are not compared."})
                continue
            common = min(a["fixed_step_calls"], b["fixed_step_calls"])
            ap = {r["ticks"]: r["sha256"] for r in a["input_prefix_hashes"]}
            bp = {r["ticks"]: r["sha256"] for r in b["input_prefix_hashes"]}
            stamps = set(ap) & set(bp)
            common_living = min(a["seconds"], b["seconds"])
            matched = []
            for at in a["trace"]:
                bt = next((t for t in b["trace"] if abs(t["simulation_time"]-at["simulation_time"])<1e-7),None)
                if bt and at["simulation_time"]<=common_living+1e-7:
                    matched.append({"simulation_time":at["simulation_time"],"a_rpm":at["rpm"],"b_rpm":bt["rpm"],"rpm_delta_b_minus_a":bt["rpm"]-at["rpm"],
                                    "a_economy":at.get("economy"),"b_economy":bt.get("economy"),"a_powers":at["powers"],"b_powers":bt["powers"]})
            matched_end=matched[-1] if matched else None
            unequal_censor=a["right_censored"]!=b["right_censored"] or abs(a["seconds"]-b["seconds"])>1e-6
            pairs.append({"case_a": a["case_id"], "case_b": b["case_id"], "seed": a["seed"], "package": a["package"],
                          "policy": a["policy"], "input_kind": a["input_kind"], "common_fixed_step_calls": common,
                          "shared_prefix_hashes_exact": all(ap[t] == bp[t] for t in stamps if t <= common),
                          "whole_realized_input_exact": a["input_sha256"] == b["input_sha256"],
                          "same_duration": abs(a["seconds"] - b["seconds"]) < 1e-6,
                          "label_a":a["label"],"label_b":b["label"],
                          "natural_outcomes":{"a":{"seconds":a["seconds"],"outcome":a["player_outcome"],"right_censored":a["right_censored"]},"b":{"seconds":b["seconds"],"outcome":b["player_outcome"],"right_censored":b["right_censored"]}},
                          "common_living_seconds":common_living,"last_exact_shared_actor_sample":matched_end,
                          "matched_sample_count":len(matched),"matched_ledger_available":bool(matched_end and matched_end["a_economy"] is not None and matched_end["b_economy"] is not None),
                          "final_rpm_delta_is_equal_duration":not unequal_censor,
                          "input_hash_scope_a":a.get("input_hash_encoding","Six-decimal command text + flags; quantized evidence"),"input_hash_scope_b":b.get("input_hash_encoding","Six-decimal command text + flags; quantized evidence"),
                          "a_acceleration": a["actual_handling"]["acceleration"], "b_acceleration": b["actual_handling"]["acceleration"],
                          "deltas_b_minus_a": {m: b[m] - a[m] for m in metrics if a.get(m) is not None and b.get(m) is not None}})
    contexts=[]
    for path in args.context_receipts:
        proof=json.loads(path.read_text(encoding="utf-8"))
        assert proof["status"]=="passed" and all(proof[k] for k in ["executed_source_unchanged","frozen_source_unchanged","harness_unchanged","player_unchanged"])
        raw=Path(proof["runtime"]["path"]);assert digest(raw)==proof["runtime"]["sha256"]
        data=json.loads(raw.read_text(encoding="utf-8"));assert not data["failures"] and not data["main_created"] and not data["collection_accessed"] and not data["permanent_rewards_settled"]
        observed=[]
        for c in data["cases"]:
            if c["configuration"]["loadout"]!="naked":continue
            end=c["end"]; contacts=c["contacts"]
            observed.append({"configuration":c["configuration"],"handling":c["handling"],"initial_positions":c["initial_positions"],
                             "input_sha256":c["input_sha256"],"realized_input_records":len(c["inputs"]),"fixed_step_calls":c["ticks"],
                             "terminal_status":c["status"],"right_censored":c["status"]=="battle","result":c["result"],"observed_seconds":end["time"],
                             "final_rpm":end["rpm"],"final_actor":{k:end[k] for k in ["position","velocity","speed","radius","wobble"]},
                             "final_economy":end["economy"],"contacts_count":len(contacts),"hard_contacts":sum(e["severity"]>=.75 for e in contacts),
                             "contact_profile":contacts})
        assert {c["configuration"]["starter"] for c in observed}=={"bastion","breaker","vane"}
        contexts.append({"receipt":{"path":str(path),"sha256":digest(path)},"runtime":proof["runtime"],"executed_source":proof["executed_source_before"],
                         "checks_separate_not_counted_in_this_study":proof["checks"],"rows":observed,
                         "scope":"Separate actual default Run/countdown naked starter context at one seed421717 and16s horizon with observed reposition/edge corrections. Realized inputs differ by starter. Three censored descriptive observations, not a causal matched-input starter comparison or ring-out rate."})
    result = {"schema": "003a2-bastion-feel-comparison-v3", "scope": "All supplied guarded observations, with literal input equality and adaptive policy differences reported separately. Acceleration is an initialization-only experiment; speed cap, mass, RPM economy, opponents and physical power implementations are unchanged within a source stage. Observed steady cruise may differ at the same cap because propulsion balances drag. Short or right-censored observations cannot establish anti-AFK or survival superiority. No optimal-survival tuning claim.",
              "evidence": refs,"separately_scoped_natural_starter_context":contexts, "cases": len(rows), "groups": summaries, "pairs": pairs, "same_handling_source_replays": replays, "samples": rows,
              "limitations": ["Solo fixtures have no opponent/admissions and cannot establish combat balance.",
                              "The natural adaptive Director may admit different enemies/times after changed movement or clears; same seed is not identical pressure exposure.",
                              "A fixed policy is a disclosed controller, not a skilled human or a universal build recommendation.",
                              "Declared Director investment count follows each owned-rank package; within-package handling pairs hold it exact, but cross-package combat differences include different pressure budgets.",
                              "Declared initial powers measure response after investment, not natural acquisition rates or economy.",
                              "Observation horizons and natural death are reported, including unreached gates and every unfavourable delta. Censored durations are not averaged as deaths; final RPM under unequal durations is not a balance comparison.",
                              "Shared living comparisons use exact recorded simulation timestamps, never interpolation. Earlier response/activity reports lack per-trace RPM source ledgers; those pairs explicitly report matched_ledger_available=false.",
                              "input_seconds is steering-only; true idle requires no steering, Brake or Burst request. Earlier rows with steering-seconds equal elapsed within1e-7 have zero input-idle by the nonnegative advancing-tick integral; other missing idle fields remain unmeasured.",
                              "Window-free headless QA measures simulation, not perceived thumb/controller/audio feel or native performance."]}
    write(destination, result)
    print(json.dumps({"path": str(destination), "sha256": digest(destination), "cases": len(rows), "groups": len(summaries), "pairs": len(pairs)}), flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    run = commands.add_parser("observe")
    run.add_argument("--project", type=Path, required=True)
    run.add_argument("--phase", choices=["response", "range", "combat"], required=True)
    run.add_argument("--label", required=True)
    run.add_argument("--engine", default=None)
    run.add_argument("--seeds", type=int, nargs="+", default=[421, 7341, 2026])
    run.add_argument("--accelerations", type=float, nargs="+", default=[.72, .82, .85, .88])
    run.add_argument("--packages", nargs="+")
    run.add_argument("--policies", nargs="+")
    run.add_argument("--horizon", type=float, default=45)
    run.add_argument("--timeout", type=int, default=1800)
    run.add_argument("--case-limit", type=int, default=240)
    run.set_defaults(action=observe)
    compare = commands.add_parser("compare")
    compare.add_argument("--receipts", type=Path, nargs="+", required=True)
    compare.add_argument("--context-receipts",type=Path,nargs="*",default=[])
    compare.add_argument("--out", type=Path, required=True)
    compare.set_defaults(action=comparison)
    args = parser.parse_args()
    if args.command == "observe":
        assert args.label.replace("_", "").replace("-", "").isalnum()
        assert 1 <= args.horizon <= 600 and len(args.seeds) == len(set(args.seeds))
        assert all(a == 0 or .60 <= a <= 1.5 for a in args.accelerations)
    args.action(args)


if __name__ == "__main__": main()
