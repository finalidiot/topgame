"""Capture four real beast manifestations with the production HUD.

Legal initial assemblies/powers precede a real omitted countdown. Only ordinary
steering/Burst/brake drive shown gameplay. Fresh external QA outputs retain
actual contacts, owner provenance, lifetime bounds and profile fingerprints.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/workspace"))
import workspace
sys.path.insert(0, str(ROOT / "tools/build"))
import windows_checkpoint as pipeline

IDENTITIES = ("black_arrow", "iron_bull", "stone_tortoise", "coil_dragon")
FEATURE_PHASES = ("travel", "strike", "guard", "travel")


def power_counts(run: dict) -> dict:
    result = {}
    for event in run["power_events"]:
        if event["owner"] == 1:
            result[event["kind"]] = result.get(event["kind"], 0) + 1
    return result


def validate(result: dict, visible: bool) -> None:
    runs = result["runs"]
    assert len(runs) == 4
    assert sum(run["capture_frames"] for run in runs) == 2280
    for identity, phase, run in zip(IDENTITIES, FEATURE_PHASES, runs):
        assert run["scenario"]["identity"] == identity
        assert run["actual_battle_frames"] == run["capture_frames"], "A real battle segment ended early"
        assert run["beast_visible_frames"] >= 8, f"No sustained actual {identity} manifestation"
        assert run["presentation_end"]["peak_live"] <= 3
        assert run["min_rpm"] >= 0 and run["max_rpm"] <= 1.24 + 1e-6
        assert run["phase_frames"].get(f"{identity}/{phase}", 0) > 0
        for row in run["rows"]:
            assert len(row["beasts"]) <= 3
            for instance in row["beasts"]:
                assert instance["owner_entity_id"] > 0
                assert instance["age"] < 4.0
        spawned = [event for event in run["presentation_end"]["events"] if event["kind"] == "spawned"]
        assert spawned and all(event["owner_entity_id"] > 0 for event in spawned)
        if visible:
            assert phase in run["feature_frames"], f"No clear full-bodied {identity} review frame"
            feature = run["feature_frames"][phase]
            assert feature["instance"]["beast"] == identity
            assert feature["instance"]["phase_age"] >= 0.04
            assert pipeline.png_record(Path(feature["path"]))["width"] == 640
    comet, wake, guard, breakneck = runs
    assert power_counts(comet).get("comet_charge", 0) > 0
    assert power_counts(comet).get("comet_release", 0) > 0 and comet["actual_contacts"] > 0
    assert power_counts(wake).get("impact_wake", 0) > 0 and wake["actual_contacts"] > 0
    assert guard["max_hold_seconds"] >= 6.0 - 1e-6
    assert any(event.get("trigger") == "anchor_mature" for event in guard["presentation_end"]["events"])
    assert power_counts(breakneck).get("breakneck_commit", 0) > 0
    assert breakneck["power_diagnostics"]["rpm_spent"] > 0.0
    if power_counts(breakneck).get("breakneck_miss", 0):
        assert not any(event.get("phase") == "strike" and event.get("trigger") == "breakneck_charge"
                       for event in breakneck["presentation_end"]["events"]), "Miss cannot invent a strike"


def fresh_name(task: Path, base: str) -> str:
    if not (task / "manifests" / (base + ".json")).exists():
        return base
    return base + "_" + datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--qa-root", type=Path)
    parser.add_argument("--engine")
    parser.add_argument("--ffmpeg")
    parser.add_argument("--diagnostic", action="store_true")
    args = parser.parse_args()
    task = workspace.create_task_workspace("002C.5.2", args.qa_root)
    base = "002c5_2_beasts_review" + ("_diagnostic" if args.diagnostic else "")
    name = fresh_name(task, base)
    manifest = task / "manifests" / (name + ".json")
    movie = task / "temp" / (name + ".avi")
    output = task / "video" / (name + ".mp4")
    frame_dir = task / "frames" / name
    profile_before = pipeline.production_profile(ROOT)
    command = [workspace.find_tool("godot", args.engine), "--path", str(ROOT),
               "--script", "res://tests/capture_beast_manifestations.gd"]
    if args.diagnostic:
        command += ["--headless"]
    else:
        command += ["--write-movie", str(movie), "--fixed-fps", "60", "--disable-vsync"]
    command += ["--", "--manifest=" + str(manifest)]
    command += ["--diagnostic"] if args.diagnostic else ["--frames=" + str(frame_dir)]
    print("RECORD_REAL_BEAST_GAMEPLAY " + name, flush=True)
    capture = pipeline.run_logged(command, task / "logs" / (name + ".log"), 600)
    result = json.loads(manifest.read_text(encoding="utf-8"))
    validate(result, visible=not args.diagnostic)
    assert "BEAST_CAPTURE_PASS runs=4" in Path(capture["log"]).read_text(encoding="utf-8", errors="replace")
    result["capture_process"] = capture
    result["source_git_sha"] = pipeline.git(ROOT, "rev-parse", "HEAD")
    result["tracked_changes_at_capture"] = pipeline.git(ROOT, "status", "--porcelain", "--untracked-files=no")
    paths = ["tests/capture_beast_manifestations.gd", "scripts/battle.gd", "scripts/power_runtime.gd",
             "scripts/beast_manifestations.gd", "scripts/menus.gd", "assets/data/parts_catalogue.json",
             "assets/powers/beasts_002c5_2/manifest.json"]
    paths += [str(path.relative_to(ROOT)).replace("\\", "/")
              for path in sorted((ROOT / "assets/powers/beasts_002c5_2").glob("*.png"))]
    result["source_sha256"] = {path: pipeline.sha256(ROOT / path) for path in paths}
    result["profile_before"] = profile_before
    result["profile_after"] = pipeline.production_profile(ROOT)
    result["profile_unchanged"] = result["profile_before"] == result["profile_after"]
    assert result["profile_unchanged"], "Review changed the production collection/preferences"
    result["automated_visible_mechanics_gate_passed"] = True
    if not args.diagnostic:
        ffmpeg = workspace.find_tool("ffmpeg", args.ffmpeg)
        encoded = pipeline.run_logged([ffmpeg, "-v", "error", "-i", str(movie), "-an", "-c:v", "libx264",
                                       "-preset", "fast", "-crf", "18", "-pix_fmt", "yuv420p", "-movflags",
                                       "+faststart", str(output)], task / "logs" / (name + "_encode.log"), 300)
        assert output.stat().st_size > 100_000
        decoded = pipeline.run_logged([ffmpeg, "-v", "error", "-i", str(output), "-f", "null", "-"],
                                       task / "logs" / (name + "_decode.log"), 300)
        metadata = subprocess.run([ffmpeg, "-hide_banner", "-i", str(output)], capture_output=True, text=True)
        match = re.search(r"Duration: (\d+):(\d+):(\d+(?:\.\d+)?)", metadata.stderr)
        assert match, "Finished movie duration unavailable"
        duration = int(match[1]) * 3600 + int(match[2]) * 60 + float(match[3])
        assert abs(duration - 38) < 0.20
        result.update(video=str(output), video_sha256=pipeline.sha256(output), actual_duration_seconds=duration,
                      nominal_seconds=38, encoder=encoded, decoder=decoded, raw_movie=str(movie),
                      raw_movie_sha256=pipeline.sha256(movie), editorial="Four labelled real-physics avatars with production HUD. Native640x360 nearest2x; real Comet charge/contact, heavy Wake hit, six-second settled guard and paid Run Breakneck commitment/miss. No injected state/contact/effect or saved profile writes.")
        featured = {}
        for identity, phase, run in zip(IDENTITIES, FEATURE_PHASES, result["runs"]):
            source = Path(run["feature_frames"][phase]["path"])
            destination = task / "images" / f"{name}_{identity}_native.png"
            assert not destination.exists(), "Fresh beast review images cannot overwrite prior QA"
            shutil.copy2(source, destination)
            featured[identity] = {"path": str(destination), "sha256": pipeline.sha256(destination),
                                  "source_instance": run["feature_frames"][phase]["instance"]}
        strike = result["runs"][0]["feature_frames"].get("strike")
        assert strike, "Black Arrow needs an additional real-contact strike review frame"
        destination = task / "images" / f"{name}_black_arrow_strike_native.png"
        assert not destination.exists()
        shutil.copy2(Path(strike["path"]), destination)
        featured["black_arrow_strike"] = {"path": str(destination), "sha256": pipeline.sha256(destination),
                                           "source_instance": strike["instance"]}
        result["featured_native_images"] = featured
    manifest.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"passed": True, "manifest": str(manifest), "video": result.get("video"),
                      "contacts": [run["actual_contacts"] for run in result["runs"]],
                      "profile_unchanged": result["profile_unchanged"]}, indent=2))


if __name__ == "__main__":
    main()
