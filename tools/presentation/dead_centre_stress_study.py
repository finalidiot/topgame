"""Preserve and compare genuine input-driven Dead Centre trajectories."""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/presentation"))
from bastion_active_defence_study import summarize


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_hashes(root: Path) -> dict[str, str]:
    files = list((root / "scripts").glob("*.gd"))
    files += [root / "tests" / name for name in ("observe_dead_centre_stress.gd", "rpm_bot.gd")]
    return {p.relative_to(root).as_posix(): digest(p) for p in sorted(files)}


def freeze(base: Path, out: Path, baseline: bool, old_director: bool) -> None:
    if out.exists():
        raise SystemExit("Refusing to replace a preserved source snapshot")
    shutil.copytree(base, out)
    if not baseline:
        shutil.copytree(ROOT / "scripts", out / "scripts", dirs_exist_ok=True)
        shutil.copytree(ROOT / "assets", out / "assets", dirs_exist_ok=True)
    for name in ("observe_dead_centre_stress.gd", "rpm_bot.gd"):
        shutil.copyfile(ROOT / "tests" / name, out / "tests" / name)
    if old_director:
        shutil.copyfile(base / "scripts/threat_director.gd", out / "scripts/threat_director.gd")
    proof = {"schema": "003a1-dead-centre-frozen-source-v1", "source_git_sha": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
             "snapshot": str(out), "baseline": baseline, "old_director": old_director,
             "base": str(base), "source_hashes": source_hashes(out), "created_utc": datetime.now(timezone.utc).isoformat(),
             "fixture": "Legal declared rank investments at opening, centre launch, real production simulation and sampled controls; no runtime reserve, maturity, admission, damage or outcome edits."}
    out.with_suffix(".dead-centre-provenance.json").write_text(json.dumps(proof, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"frozen": str(out), "baseline": baseline, "old_director": old_director}))


def run(root: Path, engine: Path, out: Path, label: str, horizon: float, seeds: list[int], builds: list[str]) -> None:
    proof_path = root.with_suffix(".dead-centre-provenance.json")
    if not proof_path.exists(): raise SystemExit("Wait for the completed frozen source provenance before running its matrix")
    proof = json.loads(proof_path.read_text(encoding="utf-8"))
    if source_hashes(root) != proof["source_hashes"]: raise SystemExit("Frozen source differs from its completed provenance")
    if out.exists(): raise SystemExit("Refusing to overwrite an earlier matrix")
    out.mkdir(parents=True)
    before = source_hashes(root)
    jobs = [(seed, build) for seed in seeds for build in builds]
    def one(job: tuple[int, str]) -> dict:
        seed, build = job
        starter = "custom_defence" if build == "extreme" else "bastion"
        ranks = {"without_dc":12, "legacy_bulwark":15, "dc_redline":15, "extreme":18}[build]
        report = out / f"{label}_{seed}_{build}.json"
        log = report.with_suffix(".log")
        command = [str(engine), "--headless", "--path", str(root), "--script", "res://tests/observe_dead_centre_stress.gd", "--",
                   f"--report={report}", f"--seed={seed}", f"--stage={build}", f"--starter={starter}", f"--investments={ranks}",
                   "--warmup=504", f"--horizon={horizon}", "--policy=zero_input,minimal_active", f"--label={label}"]
        with log.open("w", encoding="utf-8") as stream:
            completed = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, timeout=2400)
        logs = log.read_text(encoding="utf-8", errors="replace")
        if completed.returncode or any(s in logs for s in ("SCRIPT ERROR:", "ERROR:", "ObjectDB instances were leaked")):
            raise RuntimeError(f"Failed real trajectory: {log}\n{logs[-3000:]}")
        data = json.loads(report.read_text(encoding="utf-8"))
        if source_hashes(root) != before: raise RuntimeError("Frozen production/policy dependencies changed")
        data.update(source_hashes=before, source_root=str(root), source_unchanged=True, main_created=False, collection_accessed=False)
        report.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        print(logs.strip(), flush=True)
        return {"seed": seed, "build": build, "report": str(report), "log": str(log)}
    with ThreadPoolExecutor(max_workers=3) as pool:
        results = list(pool.map(one, jobs))
    (out / "matrix.json").write_text(json.dumps({"label": label, "source_root": str(root), "source_hashes": before, "jobs": results, "literal_warmup_seconds":504, "observed_seconds":horizon}, indent=2) + "\n", encoding="utf-8")


def analyse(before: Path, after: Path, afk_out: Path, active_out: Path) -> None:
    for out in (afk_out, active_out):
        if out.exists(): raise SystemExit(f"Preserve earlier acceptance output: {out}")
    rows: list[dict] = []
    for label, directory in (("before", before), ("after", after)):
        matrix_path = directory / "matrix.json"
        paths = [Path(job["report"]) for job in json.loads(matrix_path.read_text(encoding="utf-8"))["jobs"]] if matrix_path.exists() else sorted(directory.glob("*.json"))
        for path in paths:
            data = json.loads(path.read_text(encoding="utf-8"))
            for row in data.get("samples", []):
                if len(row["power_ranks"]) > 7:
                    raise RuntimeError(f"Over-cap diagnostic cannot enter acceptance: {path}")
                result = summarize(row, path)
                result.update(revision=label, final_power_diagnostics=row.get("final_power_diagnostics", {}),
                              final_power_state=row.get("final_power_state", {}), opening_mode=data.get("opening_mode"),
                              stress_curve=[{"time":t["time"], "rpm":t["rpm"], "stress":t["powers"].get("anchor_stress", 0.0), "radius":t["radius"], "wobble":t["wobble"], "strength":t["powers"].get("anchor_strength", t["powers"].get("anchor_charge",0.0))} for t in row["trace"] if t["phase"] == "mature"])
                rows.append(result)
    pairs: list[dict] = []
    for a in (r for r in rows if r["policy"] == "zero_input"):
        b = next((r for r in rows if r["revision"] == a["revision"] and r["seed"] == a["seed"] and r["starter"] == a["starter"] and r["stage"] == a["stage"] and r["policy"] == "minimal_active"), None)
        if b:
            pairs.append({"revision":a["revision"], "seed":a["seed"], "starter":a["starter"], "stage":a["stage"],
                          "identical_common_handoff":a["handoff_fingerprint"] == b["handoff_fingerprint"],
                          "afk_survival":a["mature_seconds"], "active_survival":b["mature_seconds"],
                          "active_minus_afk_seconds":b["mature_seconds"] - a["mature_seconds"],
                          "afk_final_rpm":a["final_rpm"], "active_final_rpm":b["final_rpm"],
                          "active_minus_afk_rpm":b["final_rpm"] - a["final_rpm"],
                          "afk_ended_naturally":a["ended_naturally"], "active_ended_naturally":b["ended_naturally"]})
    scope = {"schema":"003a1-dead-centre-human-fixture-v1", "human_fixture":{"stopped":504,"ended":833,"afk":329,"exact_build_unknown":True},
             "scope":"Several deterministic seeds, four disclosed legal invested builds, real504-second common input warmup then literal zero input or sampled public-state defence. No runtime force, reserve, maturity, clock, admission or outcome injection. Source changes may produce different warmup handoffs before versus after; each within-revision active/AFK pair must share its exact handoff.",
             "limits":["Horizon survivors are right-censored, not immortal.","Power grants and investment are declared QA opening fixtures, not a recovered human inventory.","Different player inputs legitimately alter later adaptive threat admissions and physical contact timing."],
             "source_matrices":{"before":str(before / "matrix.json"),"after":str(after / "matrix.json")}}
    afk_out.write_text(json.dumps({**scope, "samples":[r for r in rows if r["policy"] == "zero_input"]}, indent=2) + "\n", encoding="utf-8")
    active_out.write_text(json.dumps({**scope, "pairs":pairs, "samples":rows}, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"samples":len(rows), "pairs":len(pairs), "all_paired_handoffs_equal":all(p["identical_common_handoff"] for p in pairs), "max_ledger_error":max(abs(r["ledger_closure_error"]) for r in rows)}, indent=2))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="mode", required=True)
    f = sub.add_parser("freeze"); f.add_argument("--base",type=Path,required=True); f.add_argument("--out",type=Path,required=True); f.add_argument("--baseline",action="store_true"); f.add_argument("--old-director",action="store_true")
    r = sub.add_parser("run"); r.add_argument("--root",type=Path,required=True); r.add_argument("--engine",type=Path,required=True); r.add_argument("--out",type=Path,required=True); r.add_argument("--label",required=True); r.add_argument("--horizon",type=float,default=329); r.add_argument("--seeds",default="421,7341,2026"); r.add_argument("--builds",default="without_dc,legacy_bulwark,dc_redline,extreme")
    a = sub.add_parser("analyse"); a.add_argument("--before",type=Path,required=True); a.add_argument("--after",type=Path,required=True); a.add_argument("--afk-out",type=Path,required=True); a.add_argument("--active-out",type=Path,required=True)
    args=parser.parse_args()
    if args.mode == "freeze": freeze(args.base,args.out,args.baseline,args.old_director)
    if args.mode == "run": run(args.root,args.engine,args.out,args.label,args.horizon,[int(s) for s in args.seeds.split(",")],args.builds.split(","))
    if args.mode == "analyse": analyse(args.before,args.after,args.afk_out,args.active_out)


if __name__ == "__main__": main()
