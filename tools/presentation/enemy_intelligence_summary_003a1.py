"""Read immutable matched studies and write a separate, compact interpretation."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def aggregate(rows: list[dict]) -> dict:
    live = sum(row["survival_time"] for row in rows)
    def per_minute(key: str) -> float:
        return sum(row[key] for row in rows) * 60 / live
    def fraction(key: str) -> float:
        return sum(row[key] for row in rows) / live
    events: dict[str, int] = {}
    for row in rows:
        for kind, count in row["power_activation"].items():
            events[kind] = events.get(kind, 0) + count
    return {
        "cases": len(rows), "observed_live_seconds": live,
        "mean_observed_live_seconds": live / len(rows),
        "attacks_per_live_minute": per_minute("attack_attempts"),
        "physical_meaningful_hits_per_live_minute": per_minute("meaningful_hits"),
        "physical_contact_rpm_damage_per_live_minute": per_minute("rpm_damage_caused"),
        "bursts_per_live_minute": per_minute("burst_usage"),
        "brake_live_fraction": fraction("brake_seconds"),
        "edge_live_fraction": fraction("edge_exposure_seconds"),
        "common_useful_ground_fraction": fraction("common_useful_ground_seconds"),
        "self_ring_outs": sum(row["self_ring_outs"] for row in rows),
        "player_ring_outs": sum(row["player_ring_outs"] for row in rows),
        "survival_censored_cases": sum(row["survival_censored"] for row in rows),
        "maximum_individual_observed_speed": max(row["max_observed_speed"] for row in rows),
        "maximum_individual_contact_severity": max(row["contact_severity_peak"] for row in rows),
        "recorded_power_events_by_kind": events,
        "recorded_stuck_count": sum(row["stuck_state_count"] for row in rows),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--qa-root", required=True, type=Path)
    parser.add_argument("--revision", default="")
    args = parser.parse_args()
    assert not args.revision or all(c.isalnum() or c == "_" for c in args.revision)
    suffix = "_" + args.revision if args.revision else ""
    paths = [args.qa_root / ("003a1_enemy_intelligence_comparison" + suffix + ".json"),
             args.qa_root / ("003a1_enemy_build_behaviour" + suffix + ".json")]
    original = {str(path): digest(path) for path in paths}
    studies = [json.loads(path.read_text(encoding="utf-8")) for path in paths]
    for path in paths:
        assert path.read_bytes() == (args.qa_root / "manifests" / path.name).read_bytes()
    report: dict = {
        "task": "003A.1 enemy intelligence matched-study interpretation",
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "immutable_study_sha256": original,
        "same_driver_sha256": studies[0]["driver_sha256"],
        "notes": [
            "Same starting conditions and feedback steering POLICY; actual player steering samples may diverge naturally after different contacts.",
            "Two seeds are matched replay labels, not independent statistical samples; no confidence interval claim.",
            "Composite comparison includes modern NPC powers/packages, bounded recovery buckets and player-equivalent running costs, as declared in the source studies.",
            "Physical meaningful hits require accepted contact severity >= .28 and actual player RPM loss >= .004; Afterimage pressure is separately counted as recorded power events.",
            "Power events are runtime records by kind, not necessarily distinct activations. Afterimage means a real trace emission; afterimage_hit means a real pressure request.",
            "Survival is censored by player defeat or the 45-second horizon; observed live time cannot prove total enemy survival beyond that boundary.",
            "The source summary totals sum per-case values for every named metric, including peaks. Use this report's individual maxima for global speed/severity bounds.",
            "All build-control cases retain the Hunter role/package to isolate actual Blade/Ratchet/Bit differences; this is not the fully authored role/package roster.",
        ],
        "roles": {}, "builds": {},
        "unclosed_behavioural_gaps": [
            "Frozen common-Hunter build control does not show defence/stamina using Burst less frequently than attack; their greater reserve permits more uses.",
            "Roles still dominate goal/state selection; the control does not establish independent defence-build centre preference.",
            "Mature Flanker, Bulwark and Harasser physical contact frequency is lower in these fixtures than the accepted baseline. Recorded power pressure and survival do not prove stronger overall human challenge.",
            "Hunter and mature Harasser self-ring-outs occur naturally; attack risk is present, but these fixtures do not certify an appropriate mistake rate.",
            "Hands-on skill/identity acceptance, real multi-enemy composition and final packaged/device performance remain outside these single-threat fixtures.",
        ],
    }
    for study, field in zip(studies, ["role", "build_id"]):
        family = report["roles" if field == "role" else "builds"]
        identities = dict.fromkeys(row[field] for row in study["after"]["rows"])
        for identity in identities:
            family[identity] = {}
            for version in ["before", "after"]:
                rows = [row for row in study[version]["rows"] if row[field] == identity]
                family[identity][version] = {
                    "all": aggregate(rows),
                    "early": aggregate([row for row in rows if row["start_time"] == 0]),
                    "mature": aggregate([row for row in rows if row["start_time"] == 480]),
                }
    if args.revision:
        report["unclosed_behavioural_gaps"] = [
            "Hands-on skill/identity acceptance, real multi-enemy composition and final packaged/device performance remain outside these single-threat fixtures.",
            "Some role physical contact rates remain below the accepted baseline; actual holding ground, survival and real power pressure are distinct outcomes, not evidence that every role lands more physical hits.",
        ]
        builds = report["builds"]
        attack_bursts = builds["attack"]["after"]["all"]["bursts_per_live_minute"]
        for name in ["defence", "stamina"]:
            if builds[name]["after"]["all"]["bursts_per_live_minute"] >= attack_bursts:
                report["unclosed_behavioural_gaps"].append(name + " does not demonstrate lower Burst frequency than attack in this revision.")
        report["revision"] = args.revision
    identity = "003a1_enemy_intelligence_interpretation_" + datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
    output = args.qa_root / "manifests" / (identity + ".json")
    assert not output.exists()
    output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    assert original == {str(path): digest(path) for path in paths}
    print(json.dumps({"passed": True, "report": str(output), "sha256": digest(output),
                      "source_reports_unchanged": True}, indent=2))


if __name__ == "__main__":
    main()
