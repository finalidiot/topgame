"""Fresh, source-guarded regression evidence; never replace historical reports."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "tools/build"), str(ROOT / "tools/presentation")]
import windows_checkpoint as pipeline
from upgrade_sustain_003a1 import source, player

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("headless", "python", "native"), required=True)
    parser.add_argument("--engine", default=r"E:\Desktop\Godot_v4.7.2-stable_win64_console.exe")
    parser.add_argument("--python", default=sys.executable)
    parser.add_argument("--only", nargs="*")
    args = parser.parse_args()
    qa = ROOT.parent / "GyroBrothers-QA/003A.1"
    stem = "003a1_enemy_foundation_" + args.mode + "_" + datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
    output = qa / "manifests" / (stem + ".json")
    baseline = json.loads((ROOT / "tests/results/003a1_combat_acceptance_validation.json").read_text())
    if args.mode == "headless":
        names = [r["name"] for r in baseline["headless"]["suites"]]
        names += ["pickup_positions_003a1", "shop_ux_003a1", "shop_focus_cost_003a1", "combat_audio_mix_003a1", "native_window_layout_003a1", "enemy_intelligence_003a1", "enemy_power_packages_003a1", "enemy_burst_sampling_003a1"]
    elif args.mode == "native":
        names = [r["name"] for r in baseline["native"]["suites"]] + ["native_window_layout_003a1"]
    else:
        names = sorted({r["category"] for r in json.loads((qa / "manifests/003a1_combat_python_regression.json").read_text())["suites"]} | {"audio","android"})
    if args.only:
        assert set(args.only) <= set(names)
        names = args.only
    assert len(names) == len(set(names))
    record = {"schema":1,"scope":"Selected current contracts, fresh logs and preserved initial failures", "status":"running",
              "source_before":source(ROOT),"player_before":player(),"mode":args.mode,"suites":[]}
    pipeline.write_json(output, record)
    for name in names:
        log = qa / "logs" / (stem + "_" + name + ".log")
        if args.mode == "python":
            command = [args.python,"-m","unittest","discover","-s",str(ROOT / "tools" / name),"-p","test_*.py","-v"]
        else:
            command = [args.engine]
            if args.mode == "headless": command += ["--headless"]
            if name in ("input_acceptance_003a1", "overdrive_lifecycle_003a1", "shop_ux_003a1"):
                command += ["--fixed-fps", "60", "--disable-vsync"]
            command += ["--path",str(ROOT),"--script","res://tests/test_" + name + ".gd"]
            report = qa / "manifests" / (stem + "_" + name + ".json")
            command += ["--","--report=" + str(report)]
            if name == "music_escalation": command += ["--qa-task=003A.1"]
            if name in ("input_acceptance_003a1","overdrive_lifecycle_003a1"): command += ["--profiles=" + str(qa / "temp" / (stem + "_" + name + "_profiles"))]
            if name == "mobile_shell_layout_003a1": command += ["--profile=" + str(qa / "temp" / (stem + "_mobile_profile.json"))]
            if name == "shop_ux_003a1": command += ["--mode=all","--diagnostic","--profile=" + str(qa / "temp" / (stem + "_shop_profile.json"))]
            if args.mode == "native" and name in ("combat_acceptance_hud_003a1","native_window_layout_003a1","mobile_shell_layout_003a1"):
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
    record.update(source_after=source(ROOT),player_after=player())
    record["source_unchanged"] = record["source_before"] == record["source_after"]
    record["player_unchanged"] = record["player_before"] == record["player_after"]
    record["failed_suites"] = [r["name"] for r in record["suites"] if not r["passed"]]
    record["checks"] = sum(r["checks"] for r in record["suites"] if r["passed"])
    record["status"] = "passed" if not record["failed_suites"] and record["source_unchanged"] and record["player_unchanged"] else "failed"
    pipeline.write_json(output,record)
    print(json.dumps({k:record[k] for k in ("status","failed_suites","checks","source_unchanged","player_unchanged")}|{"report":str(output)}),flush=True)
    raise SystemExit(0 if record["status"] == "passed" else 1)

if __name__ == "__main__": main()
