"""Run/analyse disclosed mature-pressure observations without gameplay edits."""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import shutil
import zipfile
from pathlib import Path
from statistics import mean
from typing import Any

ROOT = Path(__file__).resolve().parents[2]


def canonical_hash(value: Any) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def source_hashes(root: Path = ROOT) -> dict[str, str]:
    paths = sorted((root / "scripts").glob("*.gd"))
    paths += [root / "tests" / "observe_bastion_active_defence.gd", root / "tests" / "rpm_bot.gd"]
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}


def trend(points: list[tuple[float, float]]) -> float | None:
    if len(points) < 2:
        return None
    tx, ry = mean(x for x, _ in points), mean(y for _, y in points)
    denominator = sum((x - tx) ** 2 for x, _ in points)
    return sum((x - tx) * (y - ry) for x, y in points) / denominator if denominator else None


def duration_above(points: list[tuple[float, float]], threshold: float) -> float:
    total = 0.0
    for (a, ra), (b, rb) in zip(points, points[1:]):
        if ra >= threshold and rb >= threshold:
            total += b - a
        elif (ra >= threshold) != (rb >= threshold) and ra != rb:
            crossing = a + (b - a) * (threshold - ra) / (rb - ra)
            total += crossing - a if ra >= threshold else b - crossing
    return total


def summarize(row: dict[str, Any], path: Path) -> dict[str, Any]:
    handoff = row.get("handoff", {})
    start = float(handoff.get("time", row["run_seconds"]))
    elapsed = float(row["mature_seconds"])
    points = [(float(t["time"]), float(t["rpm"])) for t in row["trace"] if t["time"] >= start]
    if handoff:
        points.insert(0, (start, float(handoff["rpm"])))
        points.append((float(row["run_seconds"]), float(row["final_rpm"])))
    losses, gains = row["mature_losses"], row["mature_gains"]
    total_lost, total_gained = sum(losses.values()), sum(gains.values())
    net = float(row["final_rpm"]) - float(handoff.get("rpm", row["final_rpm"]))
    full = [r for r in row["full_impacts"] if r["time"] >= start]
    final_window = [p for p in points if p[0] >= row["run_seconds"] - 120]
    return {
        "raw_report": str(path),
        **{k: row[k] for k in ("seed", "starter", "stage", "policy", "run_seconds", "mature_seconds", "mature_handoff_reached", "reason", "ended_naturally", "final_rpm", "final_wobble", "mature_contacts", "mature_heavy_contacts", "mean_radius", "peak_radius", "mean_wobble", "mean_effective_mass", "mean_incoming_rpm_scale", "input_seconds", "brake_seconds", "control_modes", "handling", "base_mass", "power_ranks", "mutations", "power_procs", "defence_procs", "roster_procs")},
        **{k: row[k] for k in ("stats", "physical", "initial_build", "mature_minimum_rpm", "mature_above_75_seconds", "mature_above_50_seconds") if k in row},
        "handoff_fingerprint": canonical_hash(handoff),
        "handoff_rpm": handoff.get("rpm"),
        "handoff_power_state": handoff.get("power_state"),
        "mature_minimum_sampled_rpm": min((rpm for _, rpm in points), default=None),
        "mature_losses": losses,
        "mature_gains": gains,
        "mature_total_lost": total_lost,
        "mature_total_gained": total_gained,
        "mature_net_reserve": net,
        "ledger_closure_error": net - (total_gained - total_lost),
        "net_reserve_per_minute": net / elapsed * 60 if elapsed else None,
        "last_120s_regression_per_minute": trend(final_window) * 60 if trend(final_window) is not None else None,
        "time_above_75_sample_interpolation_seconds": duration_above(points, .75),
        "time_above_50_sample_interpolation_seconds": duration_above(points, .5),
        "centre_occupancy_fraction": row["centre_seconds"] / elapsed if elapsed else None,
        "full_impacts": len(full),
        "mean_full_severity": mean(r["severity"] for r in full) if full else None,
        "mean_full_impulse": mean(r["impulse"] for r in full) if full else None,
        "maximum_full_impulse": max((r["impulse"] for r in full), default=None),
        "incoming_contacts_per_minute": row["mature_contacts"] / elapsed * 60 if elapsed else None,
        "incoming_full_contacts_per_minute": len(full) / elapsed * 60 if elapsed else None,
        "meaningful_heavy_contacts_per_minute": row["mature_heavy_contacts"] / elapsed * 60 if elapsed else None,
        "wobble_removed_in_player_updates": row["wobble_removed"],
        "director_decision_sequence": [{k: h[k] for k in ("serial", "key", "time", "tier", "investments")} for h in row["director_history"]],
    }


def analyse(paths: list[Path], destination: Path) -> dict[str, Any]:
    rows = []
    for path in paths:
        source = json.loads(path.read_text(encoding="utf-8"))
        for row in source["samples"]:
            summary = summarize(row, path)
            summary.update({"opening_mode": source.get("opening_mode", "natural_run_common_warmup"),
                            "opening_clock_seconds": source.get("opening_clock_seconds", 0),
                            "source_label": source.get("source_label", ""),
                            "warmup_seconds": source.get("warmup_seconds"),
                            "mature_horizon_seconds": source.get("mature_horizon_seconds")})
            rows.append(summary)
    pairs = []
    groups: dict[tuple[Any, ...], dict[str, dict[str, Any]]] = {}
    for row in rows:
        key = (row["raw_report"], row["starter"], row["stage"], row["seed"])
        groups.setdefault(key, {})[row["policy"]] = row
    for key, group in groups.items():
        if "zero_input" not in group or "minimal_active" not in group:
            continue
        a, b = group["zero_input"], group["minimal_active"]
        common_end = min(a["run_seconds"], b["run_seconds"])
        starts = [float(row["run_seconds"]) - float(row["mature_seconds"]) for row in (a, b)]
        common_start = max(starts)
        sequences = [[event for event in row["director_decision_sequence"] if common_start <= event["time"] <= common_end] for row in (a, b)]
        pairs.append({"raw_report": key[0], "starter": key[1], "stage": key[2], "seed": key[3],
                      "identical_handoff_fingerprint": a["handoff_fingerprint"] == b["handoff_fingerprint"],
                      "identical_whole_run_director_decisions": a["director_decision_sequence"] == b["director_decision_sequence"],
                      "shared_mature_lifetime_start": common_start, "shared_mature_lifetime_end": common_end,
                      "shared_mature_lifetime_seconds": max(0, common_end - common_start),
                      "identical_ordered_threat_keys_during_shared_lifetime": [event["key"] for event in sequences[0]] == [event["key"] for event in sequences[1]],
                      "identical_director_decisions_during_shared_lifetime": sequences[0] == sequences[1],
                      "shared_lifetime_director_choices_zero_input": sequences[0],
                      "shared_lifetime_director_choices_minimal_active": sequences[1],
                      "active_minus_afk_final_rpm": b["final_rpm"] - a["final_rpm"],
                      "active_minus_afk_mature_survival_seconds": b["mature_seconds"] - a["mature_seconds"]})
    report = {"schema": "003a1-offline-ledger-analysis-v1", "scope": "Offline summary of production-ledger observations; interpolation uses raw5-second reserve samples. Inputs naturally change clears/admission eligibility, so same seed/common handoff does not imply identical later enemy admission timing.", "samples": rows, "pairs": pairs}
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return report


def finalize(directory: Path) -> None:
    """Write the three review reports from preserved, complete source-guarded runs."""
    def seed_reports(prefix: str) -> list[Path]:
        return sorted(p for p in directory.glob(prefix + "*.json") if p.name[len(prefix):-5].isdigit())
    before_natural = seed_reports("003a1_before_natural_matrix_")
    after_natural = seed_reports("003a1_after_natural_matrix_")
    before_opening = seed_reports("003a1_before_mature_starter_custom_")
    after_opening = seed_reports("003a1_after_mature_starter_custom_")
    extra_pairs = [directory / f"003a1_{version}_{mode}_stock_moderate_421.json"
                   for version in ("before", "after") for mode in ("natural", "mature")]
    required = before_natural + after_natural + before_opening + after_opening + extra_pairs
    if any(len(group) != 3 for group in (before_natural, after_natural, before_opening, after_opening)):
        raise SystemExit("Three seed reports required for each main natural/opening matrix")
    if not all(path.exists() for path in required):
        raise SystemExit("Stock/moderate observations are incomplete")
    for path in required:
        proof_path = path.with_suffix(".provenance.json")
        if not proof_path.exists():
            raise SystemExit(f"Incomplete run/provenance: {path}")
        proof = json.loads(proof_path.read_text())
        if proof["exit_code"] != 0 or not proof["source_unchanged_during_batch"]:
            raise SystemExit(f"Failed source guard: {path}")
        if proof["raw_sha256"] != hashlib.sha256(path.read_bytes()).hexdigest():
            raise SystemExit(f"Raw report hash changed: {path}")
    temporary = directory / "003a1_all_observations_offline_summary.json"
    if temporary.exists():
        raise SystemExit("Refusing to overwrite final analysis")
    all_summary = analyse(required, temporary)
    paired_paths = before_natural + after_natural + extra_pairs
    paired_samples = [r for r in all_summary["samples"] if Path(r["raw_report"]) in paired_paths]
    pairs = [r for r in all_summary["pairs"] if Path(r["raw_report"]) in paired_paths]
    if not all(pair["identical_handoff_fingerprint"] for pair in pairs):
        raise SystemExit("Paired maturity fingerprint mismatch")
    for row in all_summary["samples"]:
        if abs(row["ledger_closure_error"]) > 1e-9:
            raise SystemExit("RPM ledger closure failure")
    curves = []
    for path in paired_paths:
        source = json.loads(path.read_text())
        for row in source["samples"]:
            handoff_time = row.get("handoff", {}).get("time", float("inf"))
            curves.append({"raw_report": str(path), **{k: row[k] for k in ("seed", "starter", "stage", "policy")},
                           "curve": [{k: trace[k] for k in ("time", "rpm", "radius", "wobble", "powers", "losses", "gains", "direction", "brake", "mode", "census", "tier", "draining", "update")}
                                     for trace in row["trace"] if trace["time"] >= handoff_time]})
    policy_note = "Primary minimal controls sample every 0.25 seconds: centre-only 0.24 correction, intermittent when centred, occasional 0.25-second Brake with a 6-second cooldown, public-state outside recharge when needed; no enemy target/lookahead/chase/Burst. The common 360-second warmup uses the older declared defensive controller equally for both rows."
    interpretation = [
        "Accepted main already has strictly negative true AFK economics after finite recovery: no mathematical infinite equilibrium was reproduced. The human report describes excessive comfort, and inherited/occasional controls can legitimately keep credited automatic elimination income enabled.",
        "Dead Centre's finite quota (Rank II/Bulwark 0.28) can temporarily mask gross loss, while automatic brace, wobble relief, Crash Guard and 81x Bulwark mass keep position/wobble comfortable. Inputs naturally change subsequent enemy clears/admission times; same seed/common handoff does not impose a fabricated identical later sequence.",
        "The candidate removes only duplicated Bastion spin efficiency: 0.90 -> 1.00. Direct passive cost rises from 0.0011574/s to 0.001286/s, a guaranteed extra 0.03858 full reserve per 300 combat seconds at the exact Guard/Low/Ball stamina 8.7. Further outcome differences include natural contact/director feedback and different warmup handoffs.",
        "The parts, heavy 1.35 mass, 1.35 bank, 1.30 recovery, all powers/AI and all other starters/custom handling are preserved. Starter-specific tuning cannot guarantee monotonic final reserve for every deterministic trajectory.",
        "The extreme_wind fixture contains a legacy-owned SecondWind family absent from current active offers; it is a disclosed seven-family finite-emergency-power diagnostic, not a currently earnable offer build.",
        "Zero-input handoffs intentionally preserve recent-control eligibility for its remaining production 3 seconds; early inherited payouts are counted, not erased. Synthetic mature openings have no inherited participation and are separately labelled.",
        "Natural observations use an invested opening then an actual 360-second combat warmup; they are not naturally earned power acquisition playthroughs. Synthetic 360-second pressure contexts begin with declared full reserve/fresh powers/centre placement and never edit reserve or clocks during observed ticks.",
        "Director history timestamps record choices before warning/safe-entry admission. Candidate heavy and Counterweight seed 421 naturally share the same 22 ordered threat keys/serials through the AFK lifetime, but decision times and late-tier feedback differ; this is not an imposed identical enemy timing/physics replay.",
    ]
    active = {"schema": "003a1-bastion-active-vs-afk-v1", "phase": "candidate-for-human-review", "policy": policy_note,
              "interpretation": interpretation, "samples": paired_samples, "pairs": pairs, "curves": curves,
              "source_guarded_raw_reports": [str(path) for path in paired_paths]}
    recharge_path = directory / "003a1_after_earned_recharge_421_v2.json"
    recharge_proof_path = recharge_path.with_suffix(".provenance.json")
    if not (recharge_path.exists() and recharge_proof_path.exists()):
        raise SystemExit("Validated natural recharge demonstration required")
    recharge_proof = json.loads(recharge_proof_path.read_text())
    if recharge_proof["exit_code"] or not recharge_proof["source_unchanged_during_batch"] or recharge_proof["raw_sha256"] != hashlib.sha256(recharge_path.read_bytes()).hexdigest():
        raise SystemExit("Natural recharge source/hash guard failed")
    recharge = json.loads(recharge_path.read_text())["samples"][0]
    active["natural_recharge_demonstration"] = {"raw_report": str(recharge_path), "provenance": str(recharge_proof_path),
        "scope": "Additional recharge-only public-state policy: no inputs while holding centre until finite quota naturally exhausts; real leave/outside rotation/re-establish; no reserve/quota/clock injection. Primary minimal-active controller is unchanged.",
        "summary": summarize(recharge, recharge_path), "state_trace": [{k: trace[k] for k in ("time", "rpm", "radius", "speed", "mode", "powers")}
                                                                      for trace in recharge["trace"] if trace["phase"] == "mature"]}
    opening_rows = [r for r in all_summary["samples"] if Path(r["raw_report"]) in before_opening + after_opening]
    invariance = []
    for before_path, after_path in zip(before_opening, after_opening):
        old = {(r["starter"], r["stage"]): r for r in json.loads(before_path.read_text())["samples"]}
        for row in json.loads(after_path.read_text())["samples"]:
            if row["starter"] == "bastion":
                continue
            a = old[(row["starter"], row["stage"])]
            invariance.append({"seed": row["seed"], "starter": row["starter"], "stage": row["stage"],
                               "identical_outcome_time_rpm_economy": all(row[k] == a[k] for k in ("run_seconds", "reason", "final_rpm", "whole_run_economy"))})
    starter_report = {"schema": "003a1-starter-passive-comparison-v1", "scope": "Separately disclosed synthetic mature opening at a 360-second Director context, fresh declared reserve/powers/centre, then every combat tick natural. Same seeds, investment budget 15 and opening contexts for all assemblies. Stock and extreme defensive cases; no-input throughout.",
                      "samples": opening_rows, "unchanged_non_bastion_outcome_checks": invariance,
                      "interpretation": "Bastion's passive superiority is evaluated across representative seeds, not promised for every single trajectory; ring-outs can terminate a stocked high-reserve top. Guard/Low/Ball without handling and Guard/Ballast/Tripod custom assembly separately identify starter, parts and power contributions."}
    audit_path = directory / "003a1_defensive_code_audit.json"
    audit = json.loads(audit_path.read_text()) if audit_path.exists() else {}
    ablations = []
    for path in sorted(directory.glob("003a1_before_ablation_*.summary.json")):
        ablations.extend(json.loads(path.read_text())["samples"])
    afk = [r for r in paired_samples if r["policy"] == "zero_input"]
    passive = {"schema": "003a1-bastion-passive-audit-v1", "starting_main": "c4228d446b5ed70a91c2e66c37dca0f8a32e56fc",
               "candidate": {"changed_coefficient": "Bastion handling.spin_drain", "before": .9, "after": 1.0,
                             "mass": 1.35, "bank": 1.35, "recovery": 1.30,
                             "guaranteed_direct_extra_passive_reserve_per_300_seconds": .03858},
               "identified_move_out_recharge_power": {"id": "dead_centre", "name": "Dead Centre", "user_memory": "hold center",
                   "natural_rearm_requirements": {"radius_at_least": 82, "deliberate_input_at_least": .35, "speed_at_least": 35, "continuous_seconds": 1.25, "brake": False}},
               "interpretation": interpretation, "read_only_code_audit": audit, "afk_samples": afk,
               "initial_handling_ablations": ablations,
               "ablation_causality_limit": "Handling overrides apply once at opening, so each naturally changes warmup outcomes/handoff quota and later admissions; whole final-reserve differences cannot be assigned solely to the changed coefficient. Direct fixed passive contribution is separately known from production source accounting.",
               "ledger_closure_maximum_absolute_error": max(abs(r["ledger_closure_error"]) for r in all_summary["samples"]),
               "paired_handoff_fingerprints_all_match": True,
               "raw_reports": [str(path) for path in required]}
    ablation_analysis_path = directory / "003a1_before_initial_handling_ablation_analysis_421.json"
    if ablation_analysis_path.exists():
        passive["initial_handling_ablation_source_analysis"] = json.loads(ablation_analysis_path.read_text())
    natural_order_audit_path = directory / "003a1_natural_matched_order_physical_entry_audit.json"
    if natural_order_audit_path.exists():
        passive["independent_natural_threat_order_and_physical_entry_audit"] = json.loads(natural_order_audit_path.read_text())
        active["independent_natural_order_physical_entry_proof"] = str(natural_order_audit_path)
    outputs = {"003a1_bastion_passive_audit.json": passive, "003a1_bastion_active_vs_afk.json": active,
               "003a1_starter_passive_comparison.json": starter_report}
    for name, report in outputs.items():
        target = directory / name
        if target.exists():
            raise SystemExit(f"Refusing to overwrite final report: {target}")
        target.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Final reports: {len(all_summary['samples'])} source-guarded observations, {len(pairs)} exact-handoff pairs; ledger closure passes")


def append_fixed_order_supplement(directory: Path) -> None:
    """Append new derived evidence while preserving the original primary reports."""
    summary_path = directory / "003a1_after_fixed_parameter_order_421.summary.json"
    summary = json.loads(summary_path.read_text())
    raw_path = Path(summary["raw_report"])
    proof_path = raw_path.with_suffix(".provenance.json")
    proof = json.loads(proof_path.read_text())
    digest = hashlib.sha256(raw_path.read_bytes()).hexdigest()
    if proof["exit_code"] or not proof["source_unchanged"] or not proof["reference_unchanged"] or proof["raw_sha256"] != digest or summary["raw_sha256"] != digest:
        raise SystemExit("Fixed-order supplement source/reference/hash guard failed")
    if not all(summary[key] for key in ("identical_full_handoff", "identical_all_shared_admitted_parameters", "all_original_caps_and_budgets_respected")):
        raise SystemExit("Fixed-order supplement pairing/specification/cap check failed")
    if any(abs(row["ledger_closure_error"]) > 1e-9 for row in summary["samples"]):
        raise SystemExit("Fixed-order supplement RPM ledger closure failed")
    names = ["003a1_bastion_passive_audit.json", "003a1_bastion_active_vs_afk.json"]
    originals = {name: json.loads((directory / name).read_text()) for name in names}
    if any("supplemental_fixed_parameter_order_pair" in report for report in originals.values()):
        raise SystemExit("Supplement already appended")
    archive = directory.parent / "archive" / "primary_reports_before_fixed_order_supplement"
    if archive.exists():
        raise SystemExit("Refusing to overwrite the pre-supplement report archive")
    archive.mkdir(parents=True)
    archived = {}
    for name in names:
        source, target = directory / name, archive / name
        shutil.copy2(source, target)
        archived[name] = hashlib.sha256(target.read_bytes()).hexdigest()
        originals[name]["supplemental_fixed_parameter_order_pair"] = {"summary_report": str(summary_path), "provenance": str(proof_path),
            "protocol": "Explicit synthetic Director-choice replay, separate from the primary natural multi-seed studies. The exact ordered event parameters/tiers/IDs come from the preserved real AFK reference; original caps, budgets, warning and safe-entry admission remain live. Admission timing still differs naturally. No RPM, damage, outcome or post-opening clock injection.",
            "summary": summary}
        (directory / name).write_text(json.dumps(originals[name], indent=2) + "\n", encoding="utf-8")
    (archive / "preservation.json").write_text(json.dumps({"scope": "Exact derived primary reports preserved before adding newly completed fixed-order supplemental evidence; raw observations are unchanged.", "hashes": archived}, indent=2) + "\n", encoding="utf-8")
    print("Appended verified fixed-order pair; original primary reports preserved externally")


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    snapshot = sub.add_parser("snapshot")
    snapshot.add_argument("--out", required=True, type=Path)
    final = sub.add_parser("finalize")
    final.add_argument("--directory", required=True, type=Path)
    supplement = sub.add_parser("append-supplement")
    supplement.add_argument("--directory", required=True, type=Path)
    analysis = sub.add_parser("analyse")
    analysis.add_argument("reports", nargs="+", type=Path)
    analysis.add_argument("--out", required=True, type=Path)
    run = sub.add_parser("run")
    run.add_argument("--godot", required=True, type=Path)
    run.add_argument("--root", type=Path, default=ROOT)
    run.add_argument("--out", required=True, type=Path)
    run.add_argument("--seed", type=int, default=421)
    run.add_argument("--stage", default="legacy_bulwark")
    run.add_argument("--starter", default="bastion")
    run.add_argument("--policy", default="zero_input,minimal_active")
    run.add_argument("--warmup", type=float, default=360)
    run.add_argument("--opening-time", type=float, default=0)
    run.add_argument("--horizon", type=float, default=300)
    run.add_argument("--handling", type=Path)
    run.add_argument("--label", default="")
    args = parser.parse_args()
    if args.command == "finalize":
        finalize(args.directory)
        return
    if args.command == "append-supplement":
        append_fixed_order_supplement(args.directory)
        return
    if args.command == "snapshot":
        if args.out.exists():
            raise SystemExit("Refusing to overwrite frozen source snapshot")
        args.out.mkdir(parents=True)
        archive = args.out.parent / (args.out.name + ".zip")
        if archive.exists():
            raise SystemExit("Refusing to overwrite archive")
        before = source_hashes()
        head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
        production_diff = subprocess.check_output(["git", "diff", "--", "scripts"], cwd=ROOT, text=True)
        subprocess.run(["git", "archive", "--format=zip", f"--output={archive}", "HEAD"], cwd=ROOT, check=True)
        with zipfile.ZipFile(archive) as zipped:
            zipped.extractall(args.out)
        # git archive emits committed LF blobs while this Windows checkout has
        # CRLF. Copy exact frozen study source bytes for byte-level provenance.
        for relative in before:
            shutil.copy2(ROOT / relative, args.out / relative)
        for relative in ["tests/observe_bastion_active_defence.gd", "tests/observe_bastion_active_defence.gd.uid", "tools/presentation/bastion_active_defence_study.py"]:
            target = args.out / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / relative, target)
        # Imported resources are cached outputs only; source paths remain res://.
        shutil.copytree(ROOT / ".godot", args.out / ".godot")
        frozen = source_hashes(args.out)
        after = source_hashes()
        manifest = {"head": head, "snapshot": str(args.out), "source_before": before, "frozen_source": frozen, "source_after": after,
                    "source_matches": before == frozen == after, "archive_sha256": hashlib.sha256(archive.read_bytes()).hexdigest(), "production_working_diff": production_diff}
        args.out.with_suffix(".provenance.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        if not manifest["source_matches"]:
            raise SystemExit("Frozen source does not match; preserve snapshot for audit")
        print(f"Frozen study source based on {head}: {args.out}")
        return
    if args.command == "analyse":
        report = analyse(args.reports, args.out)
        for row in report["samples"]:
            print(f"{row['seed']} {row['starter']} {row['stage']} {row['policy']}: mature={row['mature_seconds']:.2f}s rpm={row['final_rpm']:.4f} net/min={row['net_reserve_per_minute']} loss={row['mature_total_lost']:.4f} gain={row['mature_total_gained']:.4f} closure={row['ledger_closure_error']:.3g}")
        return
    before = source_hashes(args.root)
    if args.root.resolve() != ROOT.resolve():
        snapshot_proof = args.root.with_suffix(".provenance.json")
        if not snapshot_proof.exists():
            raise SystemExit("Frozen snapshot is not complete; wait for its provenance manifest")
        frozen_proof = json.loads(snapshot_proof.read_text())
        if not frozen_proof.get("source_matches") or frozen_proof.get("frozen_source") != before:
            raise SystemExit("Frozen snapshot source differs from its completed provenance")
    args.out.parent.mkdir(parents=True, exist_ok=True)
    log = args.out.parent.parent / "logs" / args.out.with_suffix(".log").name
    log.parent.mkdir(parents=True, exist_ok=True)
    related = [args.out, log, args.out.with_suffix(".provenance.json"), args.out.with_suffix(".summary.json")]
    if any(path.exists() for path in related):
        raise SystemExit("Refusing to overwrite preserved observation/provenance: " + ", ".join(str(p) for p in related if p.exists()))
    command = [str(args.godot), "--headless", "--path", str(args.root), "--script", "res://tests/observe_bastion_active_defence.gd", "--",
               f"--report={args.out}", f"--seed={args.seed}", f"--stage={args.stage}", f"--starter={args.starter}",
               f"--policy={args.policy}", f"--warmup={args.warmup}", f"--opening-time={args.opening_time}", f"--horizon={args.horizon}", f"--label={args.label}"]
    if args.handling:
        command.append(f"--handling={args.handling}")
    with log.open("w", encoding="utf-8") as stream:
        process = subprocess.run(command, cwd=args.root, stdout=stream, stderr=subprocess.STDOUT)
    after = source_hashes(args.root)
    provenance = {"command": command, "exit_code": process.returncode, "source_before": before, "source_after": after,
                  "source_unchanged_during_batch": before == after, "raw_sha256": hashlib.sha256(args.out.read_bytes()).hexdigest() if args.out.exists() else None, "log": str(log)}
    args.out.with_suffix(".provenance.json").write_text(json.dumps(provenance, indent=2) + "\n", encoding="utf-8")
    if process.returncode or before != after:
        raise SystemExit(f"Observation failed or source changed; preserve {log}")
    analyse([args.out], args.out.with_suffix(".summary.json"))


if __name__ == "__main__":
    main()
