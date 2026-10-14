"""003A.2 responsive front-end guarded contracts; fresh isolated outputs only."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "tools/build"), str(ROOT / "tools/presentation")]
import windows_checkpoint as pipeline
from upgrade_sustain_003a1 import source, player

def harness(names, mode):
    """Freeze executed drivers and their transitive test resources.

    Unrelated new capture/performance observers can be authored in parallel;
    any source, executed test or referenced fixture change invalidates the run.
    """
    if mode == "python":
        paths = {p for category in names for p in (ROOT / "tools" / category).rglob("*.py")}
    else:
        paths = {ROOT / "tests" / ("test_" + name + ".gd") for name in names}
        pending = list(paths)
        while pending:
            path = pending.pop()
            for reference in re.findall(r'res://(tests/[^"\s]+)', path.read_text(encoding="utf-8")):
                resource = ROOT / reference
                if resource.is_file() and resource not in paths:
                    paths.add(resource)
                    if resource.suffix == ".gd": pending.append(resource)
        paths.update(p.with_suffix(p.suffix + ".uid") for p in tuple(paths)
                     if p.suffix == ".gd" and p.with_suffix(p.suffix + ".uid").is_file())
    paths.update(p for p in (ROOT / "tests/fixtures").rglob("*") if p.is_file())
    paths.update([Path(__file__), ROOT / "tools/build/windows_checkpoint.py", ROOT / "tools/presentation/upgrade_sustain_003a1.py"])
    return {p.relative_to(ROOT).as_posix():pipeline.sha256(p) for p in sorted(paths)}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("headless", "python", "native"), required=True)
    parser.add_argument("--engine", default=r"E:\Desktop\Godot_v4.7.2-stable_win64_console.exe")
    parser.add_argument("--python", default=sys.executable)
    parser.add_argument("--only", nargs="*")
    args = parser.parse_args()
    qa = ROOT.parent / "GyroBrothers-QA/003A.2"
    os.environ["TOPGAME_QA_ROOT"] = str(qa.parent)
    stem = "003a2_frontend_validation_" + args.mode + "_" + datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
    output = qa / "manifests" / (stem + ".json")
    if args.mode == "python":
        names = ["build", "presentation", "android", "audio"]
    else:
        names = ["frontend_layout_003a2", "frontend_pages_003a2", "frontend_packet_touch_003a2", "frontend_interactions_003a2", "frontend_classes_003a2", "collection_ui", "controller", "frontend", "menus", "bulk_packet_transactions_003a1", "bulk_packet_touch_003a1", "shop_ux_003a1", "shop_focus_cost_003a1", "controller_bindings_003a1", "native_window_layout_003a1", "window_client_fill_003a1", "mobile_shell_layout_003a1", "mobile_menu_hud_safe_003a2", "touch_fullscreen_projection_003a2", "touch_fullscreen_003a2", "android_fullscreen_layout_003a2", "level_up_back_003a1", "ability_card_hierarchy_003a1", "mutation_acquisition_003a2", "mutation_physics_003a2", "mutation_solver_contract_003a2", "ecology_neutral_hosts_003a2", "enemy_intelligence_003a1", "enemy_power_packages_003a1", "deep_run_density_003a1", "ghost_circuit_hijack_003a1", "ghost_physics_003a1", "orbit_full_carve_003a1", "chain_hard_hits_003a1", "rpm_acceptance_003a1", "bastion_active_defence"]
    if args.only:
        assert set(args.only) <= set(names)
        names = args.only
    assert len(names) == len(set(names))
    record = {"schema":1,"scope":"Selected actual front-end GUI/window/mobile and unchanged gameplay contracts; fresh isolated logs/profiles, preserved failures. Synthetic input is not hardware acceptance.", "status":"running",
              "source_before":source(ROOT),"harness_before":harness(names,args.mode),"player_before":player(),"mode":args.mode,"suites":[]}
    pipeline.write_json(output, record)
    for name in names:
        log = qa / "logs" / (stem + "_" + name + ".log")
        if args.mode == "python":
            command = [args.python,"-m","unittest","discover","-s",str(ROOT / "tools" / name),"-p","test_*.py","-v"]
        else:
            command = [args.engine]
            if args.mode == "headless": command += ["--headless"]
            if name in ("input_acceptance_003a1", "overdrive_lifecycle_003a1", "shop_ux_003a1", "level_up_back_003a1"):
                command += ["--fixed-fps", "60", "--disable-vsync"]
            command += ["--path",str(ROOT),"--script","res://tests/test_" + name + ".gd"]
            report = qa / "manifests" / (stem + "_" + name + ".json")
            command += ["--","--report=" + str(report)]
            # These legacy fixtures intentionally exercise their own original
            # task-specific positive/negative catalogue gates in Main._ready.
            if name not in ("parts_package", "packet_package", "parts_collection"):
                command += ["--qa-task=003A.2"]
            if name in ("input_acceptance_003a1","overdrive_lifecycle_003a1","level_up_back_003a1"): command += ["--profiles=" + str(qa / "temp" / (stem + "_" + name + "_profiles"))]
            if name == "level_up_back_003a1": command += ["--kind=flow"]
            if name == "mobile_shell_layout_003a1": command += ["--profile=" + str(qa / "temp" / (stem + "_mobile_profile.json"))]
            if name == "frontend_interactions_003a2": command += ["--profile-prefix=" + str(qa / "temp" / (stem + "_interactions"))]
            if name == "android_fullscreen_layout_003a2": command += ["--profile-prefix=" + str(qa / "temp" / (stem + "_android"))]
            if name == "touch_fullscreen_projection_003a2": command += ["--profile=" + str(qa / "temp" / (stem + "_touch_projection.json"))]
            if args.mode == "native" and name == "android_fullscreen_layout_003a2": command += ["--native", "--frames=" + str(qa / "frames" / (stem + "_android"))]
            if name == "frontend_classes_003a2": command += ["--profile=" + str(qa / "temp" / (stem + "_classes.json"))]
            if args.mode == "native" and name in ("frontend_classes_003a2", "frontend_interactions_003a2"): command += ["--native"]
            if name == "shop_ux_003a1": command += ["--mode=all","--diagnostic","--profile=" + str(qa / "temp" / (stem + "_shop_profile.json"))]
            if args.mode == "native" and name in ("combat_acceptance_hud_003a1","native_window_layout_003a1","mobile_shell_layout_003a1","window_client_fill_003a1"):
                command += ["--native"]
            if args.mode == "native" and name == "music_native":
                command += ["--allow-native-audio","--recording=" + str(qa / "temp" / (stem + "_music_native.wav"))]
        start = time.monotonic()
        timed_out = False
        with log.open("wb") as stream:
            try:
                result = subprocess.run(command,cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT,timeout=900)
                code = result.returncode
            except subprocess.TimeoutExpired:
                code = None; timed_out = True
        text = log.read_text(encoding="utf-8",errors="replace")
        if args.mode == "python":
            count_match = re.search(r"Ran (\d+) tests?",text)
            summary = count_match.group(0) if count_match else "missing summary"
        else:
            numbers = re.findall(r"checks[=: ]+(\d+)",text,re.I) or re.findall(r"(\d+)\s+(?:checks|assertions|field comparisons)",text,re.I)
            summaries = [line for line in text.splitlines() if re.search(r"PASS|checks|assertions|field comparisons",line,re.I)]
            summary = summaries[-1] if summaries else "missing completion summary"
        checks = int(count_match.group(1)) if args.mode == "python" and count_match else (max(map(int,numbers),default=0) if args.mode != "python" else 0)
        failure = bool(re.search(r"(?:failed|failures)\s*[:=]\s*[1-9]\d*|\b[1-9]\d*\s+failures\b(?!\s*[:=])|FAIL:",text,re.I))
        runtime_evidence = None
        if args.mode != "python" and report.is_file():
            runtime = json.loads(report.read_text(encoding="utf-8"))
            if isinstance(runtime.get("checks"), int) and "failures" in runtime:
                checks = max(checks, runtime["checks"])
                failure = failure or bool(runtime["failures"])
                runtime_evidence = {"path": str(report), "sha256": pipeline.sha256(report),
                                    "checks": runtime["checks"], "failures": runtime["failures"]}
                if summary == "missing completion summary":
                    summary = "Runtime report: checks=%d failures=%s" % (runtime["checks"], runtime["failures"])
        completion = checks > 0 or (args.mode != "python" and bool(re.search(r"\b[A-Z0-9_]+_PASS\b",text)))
        passed = code == 0 and not pipeline.ERRORS.search(text) and not failure and completion
        row = {"name":name,"passed":passed,"checks":checks,"exit_code":code,"timed_out":timed_out,
               "seconds":round(time.monotonic()-start,3),"command":command,"summary":summary,"log":str(log),"log_sha256":pipeline.sha256(log)}
        if runtime_evidence is not None: row["runtime_report"] = runtime_evidence
        record["suites"].append(row)
        pipeline.write_json(output,record)
        print(json.dumps({k:row[k] for k in ("name","passed","checks","seconds")}),flush=True)
    record.update(source_after=source(ROOT),harness_after=harness(names,args.mode),player_after=player())
    record["source_unchanged"] = record["source_before"] == record["source_after"]
    record["harness_unchanged"] = record["harness_before"] == record["harness_after"]
    record["player_unchanged"] = record["player_before"] == record["player_after"]
    record["failed_suites"] = [r["name"] for r in record["suites"] if not r["passed"]]
    record["checks"] = sum(r["checks"] for r in record["suites"] if r["passed"])
    record["status"] = "passed" if not record["failed_suites"] and record["source_unchanged"] and record["harness_unchanged"] and record["player_unchanged"] else "failed"
    pipeline.write_json(output,record)
    print(json.dumps({k:record[k] for k in ("status","failed_suites","checks","source_unchanged","harness_unchanged","player_unchanged")}|{"report":str(output)}),flush=True)
    raise SystemExit(0 if record["status"] == "passed" else 1)

if __name__ == "__main__": main()
