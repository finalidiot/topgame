"""Film five native-speed excerpts of honest Bastion defence and attrition.

Recorded controls use the study policy and execute every skipped physics tick.
This tool refuses old output, checks frozen production dependencies, and verifies
the real profile plus exact replay of the previously measured paired context.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import difflib
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/workspace"))
sys.path.insert(0, str(ROOT / "tools/build"))
sys.path.insert(0, str(ROOT / "tools/capture"))
import workspace
import windows_checkpoint as pipeline
from presentation_showcase import movie_metadata


def source_hashes() -> dict[str, str]:
    files = list((ROOT / "scripts").glob("*.gd"))
    files += [ROOT / "tests" / name for name in ("capture_bastion_active_defence.gd", "observe_bastion_active_defence.gd", "rpm_bot.gd")]
    files += [p for p in (ROOT / "assets").rglob("*") if p.is_file()]
    files += [ROOT / "project.godot", Path(__file__).resolve()]
    return {p.relative_to(ROOT).as_posix(): pipeline.sha256(p) for p in sorted(set(files))}


def rows(path: Path) -> list[dict]:
    data = json.loads(path.read_text(encoding="utf-8"))
    return data.get("samples", data.get("measurements", {}).get("paired", []))


def make_plan(pair_path: Path, recharge_path: Path) -> tuple[dict, dict]:
    pair = {r["policy"]: r for r in rows(pair_path) if r["seed"] == 421 and r["stage"] == "legacy_bulwark"}
    afk, active = pair["zero_input"], pair["minimal_active"]
    assert afk["handoff"] == active["handoff"], "Paired context must have identical real common warmup"
    assert afk["mature_handoff_reached"] and afk["final_rpm"] < afk["handoff"]["rpm"] - .3
    recharge = next(r for r in rows(recharge_path) if r["policy"] == "recharge_only" and r["stage"] == "legacy_bulwark" and r["seed"] == 421)
    assert recharge["handoff"] == afk["handoff"], "The recharge replay uses the same unmodified common start"
    assert recharge["power_procs"].get("anchor_rearm", 0) >= 1, "A genuine recharge must already be observed"
    first_leave = next(t for t in recharge["trace"] if t["phase"] == "mature" and t["mode"] == "leave_centre")
    returned = next(t for t in recharge["trace"] if t["time"] > first_leave["time"] and t["mode"] == "rest" and t["radius"] <= 58 and t["powers"]["anchor_recovery_remaining"] >= .19)
    # Pick an actually received heavy impact near a real earned recovery, not an
    # injected visual pose. Selection affects only which replay interval is cut.
    heavy = None
    for event in active["full_impacts"]:
        if event["time"] < 378 or event["severity"] < 1.0:
            continue
        before = next((t for t in reversed(active["trace"]) if t["time"] <= event["time"]), None)
        after = next((t for t in active["trace"] if event["time"] < t["time"] <= event["time"] + 8 and sum(t["gains"].values()) > sum(before["gains"].values()) + .01), None)
        if after is not None:
            heavy = event
            break
    assert heavy, "A real heavy contact and ensuing named recovery must exist"
    start = float(afk["handoff"]["time"])
    end = float(afk["run_seconds"])
    plan = {
        "schema": "003a1-native-excerpt-plan-v1",
        "pair_report": str(pair_path), "recharge_report": str(recharge_path),
        "cases": [
            {"id": "afk", "seed": 421, "stage": "legacy_bulwark", "policy": "zero_input"},
            {"id": "active", "seed": 421, "stage": "legacy_bulwark", "policy": "minimal_active"},
            {"id": "recharge", "seed": 421, "stage": "legacy_bulwark", "policy": "recharge_only"},
        ],
        "sections": [
            {"id": "01_mature_zero_input", "case_id": "afk", "title": "ZERO INPUT / MATURE PRESSURE", "from": start, "to": start + 12},
            {"id": "02_modest_centre_control", "case_id": "active", "title": "SMALL CORRECTIONS / THE FORTRESS HOLDS", "from": start, "to": start + 12},
            {"id": "03_earned_centre_reload", "case_id": "recharge", "title": "DEAD CENTRE / LEAVE, RELOAD, RE-ESTABLISH", "from": first_leave["time"] - 6, "to": returned["time"] + 3},
            {"id": "04_heavy_reception", "case_id": "active", "title": "HEAVY RECEPTION / EARNED RECOVERY", "from": heavy["time"] - 4, "to": heavy["time"] + 8},
            {"id": "05_natural_reserve_decline", "case_id": "afk", "title": "FIVE MINUTES HANDS OFF / RESERVE DECLINES", "from": end - 12, "to": end},
        ],
    }
    return plan, {"afk": afk, "active": active, "recharge": recharge}


def validate(data: dict, reference: dict) -> None:
    assert data["native_view"] == [640, 360] and len(data["sections"]) == 5
    assert not data["main_created"] and not data["collection_accessed"]
    assert data["handling"]["spin_drain"] == 1.0 and data["handling"]["mass"] == 1.35
    cases = {r["configuration"]["id"]: r for r in data["cases"]}
    assert cases["afk"]["handoff"] == cases["active"]["handoff"]
    assert cases["afk"]["handoff"]["battle"] == reference["afk"]["handoff"]["battle"], "Video warmup must reproduce the measured production context"
    assert abs(cases["afk"]["end"]["rpm"] - reference["afk"]["final_rpm"]) < .000001, "AFK video must exactly replay the measured trajectory"
    assert abs(cases["afk"]["end"]["time"] - reference["afk"]["run_seconds"]) < .0001
    assert all(not r["burst"] for r in data["rows"])
    assert all(r["input"] == [0, 0] and not r["brake"] for r in data["rows"] if r["case_id"] == "afk")
    assert data["sections"][4]["end"]["rpm"] < data["sections"][0]["start"]["rpm"] - .3
    recharge = data["sections"][2]
    assert recharge["end"]["power_procs"].get("anchor_rearm", 0) > recharge["start"]["power_procs"].get("anchor_rearm", 0)
    assert recharge["end"]["radius"] <= 58 and recharge["end"]["powers"]["anchor_recovery_remaining"] >= .19
    assert any(r["case_id"] == "recharge" and r["radius"] >= 82 and r["speed"] >= 35 and (r["input"][0] ** 2 + r["input"][1] ** 2) ** .5 >= .35 for r in data["rows"])
    heavy = data["sections"][3]
    assert any(r["section"] == "04_heavy_reception" and r["severity"] >= 1 and r["player"]["mass"] > 900 for r in data["filmed_impacts"])
    assert sum(heavy["end"]["gains"].values()) > sum(heavy["start"]["gains"].values()) + .01


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--qa-root", type=Path)
    parser.add_argument("--engine")
    parser.add_argument("--ffmpeg")
    parser.add_argument("--diagnostic", action="store_true")
    parser.add_argument("--pair-report", required=True, type=Path)
    parser.add_argument("--recharge-report", required=True, type=Path)
    parser.add_argument("--freeze-manifest", required=True, type=Path)
    args = parser.parse_args()
    task = workspace.create_task_workspace("003A.1", args.qa_root)
    freeze = json.loads(args.freeze_manifest.read_text(encoding="utf-8"))
    assert freeze["source_matches"]
    assert all(pipeline.sha256(ROOT / name.replace("\\", "/")) == digest for name, digest in freeze["source_before"].items()), "Study production/policy source must remain frozen"
    plan, reference = make_plan(args.pair_report, args.recharge_report)
    identity = "003a1_bastion_active_defence_" + datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
    manifest = task / "manifests" / (identity + ".json")
    plan_path = task / "manifests" / (identity + "_plan.json")
    raw = task / "temp" / (identity + ".avi")
    frames = task / "frames" / identity
    video = task / "video" / "003a1_bastion_active_defence.mp4"
    assert not any(p.exists() for p in [manifest, plan_path, raw, frames]), "Preserve earlier capture artifacts"
    if not args.diagnostic: assert not video.exists(), "Preserve the human-review movie"
    plan_path.write_text(json.dumps(plan, indent=2) + "\n", encoding="utf-8")
    before, profile = source_hashes(), pipeline.production_profile(ROOT)
    capture_root = ROOT
    native_snapshot = None
    if not args.diagnostic:
        # Movie Maker fixes its writer size before the script runs, and its
        # writer resizes mismatched viewport pixels with bilinear interpolation.
        # Change only this fresh QA copy's display overrides, never production.
        capture_root = task / "temp" / (identity + "_source")
        assert not capture_root.exists()
        shutil.copytree(Path(freeze["snapshot"]), capture_root)
        # Retain the completed snapshot's imported cache, while restoring exact
        # current bytes (Git archive/config newline policies can otherwise differ).
        for directory in ["scripts", "assets"]:
            shutil.copytree(ROOT / directory, capture_root / directory, dirs_exist_ok=True)
        for name in ["capture_bastion_active_defence.gd", "capture_bastion_active_defence.gd.uid", "observe_bastion_active_defence.gd", "rpm_bot.gd"]:
            shutil.copyfile(ROOT / "tests" / name, capture_root / "tests" / name)
        project = capture_root / "project.godot"
        original = (ROOT / "project.godot").read_bytes()
        assert original.count(b"window/size/window_width_override=1280") == 1
        assert original.count(b"window/size/window_height_override=720") == 1
        adjusted = original.replace(b"window/size/window_width_override=1280", b"window/size/window_width_override=640")
        adjusted = adjusted.replace(b"window/size/window_height_override=720", b"window/size/window_height_override=360")
        project.write_bytes(adjusted)
        runtime_files = {name: digest for name, digest in before.items() if name.startswith(("scripts/", "assets/", "tests/"))}
        assert all(pipeline.sha256(capture_root / name) == digest for name, digest in runtime_files.items()), "Physical source, assets and capture driver must match canonical byte-for-byte"
        native_snapshot = {"root": str(capture_root), "physical_source_sha256": runtime_files,
                           "physical_source_matches_canonical": True,
                           "canonical_project_sha256": pipeline.sha256(ROOT / "project.godot"),
                           "capture_project_sha256": pipeline.sha256(project),
                           "display_only_project_diff": "".join(difflib.unified_diff(original.decode().splitlines(True), adjusted.decode().splitlines(True), fromfile="canonical/project.godot", tofile="QA-native/project.godot"))}
        (task / "manifests" / (identity + "_snapshot.json")).write_text(json.dumps(native_snapshot, indent=2) + "\n", encoding="utf-8")
    command = [workspace.find_tool("godot", args.engine), "--path", str(capture_root), "--script", "res://tests/capture_bastion_active_defence.gd"]
    command += ["--headless"] if args.diagnostic else ["--resolution", "640x360", "--fixed-fps", "60", "--disable-vsync", "--write-movie", str(raw), "--audio-driver", "Dummy"]
    command += ["--", "--manifest=" + str(manifest), "--plan=" + str(plan_path)]
    command += ["--diagnostic"] if args.diagnostic else ["--frames=" + str(frames)]
    print("BASTION_REVIEW_CAPTURE " + str(manifest), flush=True)
    process = pipeline.run_logged(command, task / "logs" / (identity + ".log"), 1800)
    log = Path(process["log"]).read_text(encoding="utf-8", errors="replace")
    assert not any(marker in log for marker in ["SCRIPT ERROR:", "ERROR:", "ObjectDB instances were leaked"]), log
    data = json.loads(manifest.read_text(encoding="utf-8"))
    validate(data, reference)
    assert before == source_hashes(), "Actual capture dependencies changed"
    assert profile == pipeline.production_profile(ROOT), "The real player profile changed"
    if native_snapshot:
        assert all(pipeline.sha256(capture_root / name) == digest for name, digest in native_snapshot["physical_source_sha256"].items())
        assert pipeline.sha256(capture_root / "project.godot") == native_snapshot["capture_project_sha256"]
    data.update(source_sha256=before, source_unchanged=True, real_profile_before=profile, real_profile_unchanged=True,
                capture_process=process, source_git_sha=pipeline.git(ROOT, "rev-parse", "HEAD"),
                working_tree=pipeline.git(ROOT, "status", "--porcelain"), freeze_manifest=str(args.freeze_manifest),
                pair_report=str(args.pair_report), recharge_report=str(args.recharge_report),
                native_snapshot=native_snapshot,
                human_feel="Pending human review; native-speed automated controls do not establish human feel or hardware acceptance.")
    manifest.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    if not args.diagnostic:
        ffmpeg = workspace.find_tool("ffmpeg", args.ffmpeg)
        raw_info = movie_metadata(ffmpeg, raw)
        assert "640x360" in raw_info["metadata"], "Movie Maker must capture native640x360 before explicit nearest2x encoding"
        sidecar = raw.with_suffix(".wav")
        encode = [ffmpeg, "-v", "error", "-i", str(raw)]
        if not raw_info["has_audio"]:
            assert sidecar.exists(), "The actual captured audio stream is required"
            encode += ["-i", str(sidecar)]
        encode += ["-map", "0:v:0", "-map", "0:a:0" if raw_info["has_audio"] else "1:a:0",
                   "-vf", "scale=1280:720:flags=neighbor", "-c:v", "libx264", "-crf", "18", "-preset", "fast",
                   "-c:a", "aac", "-b:a", "160k", "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(video)]
        encoder = pipeline.run_logged(encode, task / "logs" / (identity + "_encode.log"), 600)
        decoder = pipeline.run_logged([ffmpeg, "-v", "error", "-i", str(video), "-f", "null", "-"], task / "logs" / (identity + "_decode.log"), 180)
        info = movie_metadata(ffmpeg, video)
        assert info["has_audio"] and abs(info["duration_seconds"] - data["nominal_seconds"]) < .3
        data.update(video=str(video), video_sha256=pipeline.sha256(video), movie_metadata=info, encoder=encoder, decoder=decoder,
                    raw_movie=str(raw), soundtrack="Unchanged actual Run music and ordinary combat SFX; skipped solver intervals emit no out-of-time sound.")
        manifest.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"passed": True, "manifest": str(manifest), "video": data.get("video"), "seconds": data["nominal_seconds"], "profile_unchanged": True}, indent=2))


if __name__ == "__main__":
    main()
