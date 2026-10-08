"""Measure or film actual Anchor Stress recovery through normal Main controls."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import difflib
import json
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/workspace"))
sys.path.insert(0, str(ROOT / "tools/build"))
sys.path.insert(0, str(ROOT / "tools/capture"))
import workspace
import windows_checkpoint as pipeline
from presentation_showcase import movie_metadata

DRIVER = "observe_anchor_rearm_003a1.gd"


def hashes(root: Path) -> dict[str, str]:
    files = list((root / "scripts").glob("*.gd"))
    files += [p for p in (root / "assets").rglob("*") if p.is_file()]
    files += [root / "project.godot", root / "main.tscn"]
    files += [root / "tests" / name for name in (DRIVER, "observe_dead_centre_stress.gd", "rpm_bot.gd")]
    return {p.relative_to(root).as_posix(): pipeline.sha256(p) for p in sorted(files)}


def timing_summary(data: dict) -> dict:
    timings = []
    for case in data["cases"]:
        for index, cycle in enumerate(case["replants"]):
            timings.append({"case_id": case["configuration"]["id"], "cycle": index + 1,
                            "seed": case["configuration"]["seed"],
                            "recovery_radius": case["configuration"].get("vent_radius", 100),
                            "stress_at_release": cycle["release"]["stress"],
                            "rpm_at_release": cycle["release"]["rpm"],
                            "release_to_safe_seconds": cycle["release_to_safe_seconds"],
                            "release_to_full_safe_central_replant_seconds": cycle["release_to_full_replant_seconds"],
                            "overload_to_safe_seconds": cycle["overload_to_safe_seconds"],
                            "overload_to_full_safe_central_replant_seconds": cycle["overload_to_full_replant_seconds"],
                            "rpm_at_replant": cycle["replant"]["rpm"],
                            "stress_at_replant": cycle["replant"]["stress"],
                            "replant_radius": cycle["replant"]["radius"]})
    assert timings, "Real overload/recovery/full replant cycles are required"
    assert all(row["release_to_safe_seconds"] >= data["tuning"]["minimum_meaningful_recovery_seconds"] for row in timings)
    return {"schema": "003a1-anchor-rearm-timing-v1", "tuning": data["tuning"],
            "before_tuning": {"overload_event_threshold": .80, "hysteresis_latch": False,
                              "positional_safe_stress": .35, "movement_vent_rate": .18,
                              "outside_vent_rate": .30, "quota_rearm_seconds": 1.25,
                              "minimum_meaningful_released_motion_seconds": 0},
            "minimum_time_from_real_overload_to_full_safe_central_replant_seconds": min(row["overload_to_full_safe_central_replant_seconds"] for row in timings),
            "minimum_time_from_real_overload_release_to_full_safe_central_replant_seconds": min(row["release_to_full_safe_central_replant_seconds"] for row in timings),
            "minimum_release_to_safe_state_seconds": min(row["release_to_safe_seconds"] for row in timings),
            "scope": "Measured real solver movement and natural accepted collisions through normal Main. Starting powers and level are declared legal invested QA openings; no live Stress, RPM, force, position, clock or outcome writes. Safe state and actual full central replant are distinct. Incoming interruptions legitimately extend recovery.",
            "movement_recovery_cases": timings,
            "run_contexts": [{"configuration": c["configuration"], "opening_ranks": c["opening_ranks"],
                              "opening_mutations": c["opening_mutations"], "opening_investments": c["opening_investments"],
                              "actual_full_top_contacts": len(c["impacts"]), "stress_peak": max(r["stress"] for r in c["trace"]),
                              "simulation_seconds": c["final"]["time"], "result": c["result"]} for c in data["cases"]],
            "quota_policy": "Default controls return as soon as Stress hysteresis permits, independently of the finite RPM quota. A declared wait_quota case may deliberately keep moving for that separate six-second refill; stress-safe anchoring does not itself mint more RPM.",
            "human_acceptance": "Pending; deterministic QA is not physical controller or phone acceptance."}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--base-snapshot", type=Path, required=True)
    parser.add_argument("--stem", required=True)
    parser.add_argument("--qa-root", type=Path)
    parser.add_argument("--engine")
    parser.add_argument("--ffmpeg")
    parser.add_argument("--film", action="store_true")
    parser.add_argument("--final-timing", action="store_true")
    args = parser.parse_args()
    task = workspace.create_task_workspace("003A.1", args.qa_root)
    identity = args.stem + "_" + datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
    manifest = task / "manifests" / (identity + ".json")
    assert args.plan.is_file() and args.base_snapshot.is_dir() and not manifest.exists()
    source = hashes(ROOT)
    player = pipeline.production_profile(ROOT)
    snapshot = task / "temp" / (identity + "_source")
    shutil.copytree(args.base_snapshot, snapshot)
    for directory in ("scripts", "assets", ".godot"):
        shutil.copytree(ROOT / directory, snapshot / directory, dirs_exist_ok=True)
    shutil.copy2(ROOT / "project.godot", snapshot / "project.godot")
    shutil.copy2(ROOT / "main.tscn", snapshot / "main.tscn")
    for name in (DRIVER, "observe_dead_centre_stress.gd", "rpm_bot.gd"):
        shutil.copy2(ROOT / "tests" / name, snapshot / "tests" / name)
    assert hashes(snapshot) == source and hashes(ROOT) == source, "Finish source edits before freezing observation"
    # MovieWriter fixes its output size before this SceneTree's initializer.
    # Native capture therefore requires only the display override in this QA
    # copy to match 640x360 before launch; gameplay and canonical files stay exact.
    original_project = (snapshot / "project.godot").read_bytes()
    capture_project = original_project
    if args.film:
        capture_project = original_project.replace(b"window/size/window_width_override=1280", b"window/size/window_width_override=640").replace(b"window/size/window_height_override=720", b"window/size/window_height_override=360")
        (snapshot / "project.godot").write_bytes(capture_project)
    frozen_source = hashes(snapshot)
    profiles = task / "temp" / (identity + "_profiles")
    raw = task / "temp" / (identity + ".avi")
    command = [workspace.find_tool("godot", args.engine), "--path", str(snapshot), "--script", "res://tests/" + DRIVER]
    command += (["--resolution", "640x360", "--fixed-fps", "60", "--disable-vsync", "--write-movie", str(raw), "--audio-driver", "Dummy"]
                if args.film else ["--headless"])
    command += ["--", "--report=" + str(manifest), "--profiles=" + str(profiles), "--plan=" + str(args.plan)]
    if args.film: command += ["--film", "--frames=" + str(task / "frames" / identity)]
    process = pipeline.run_logged(command, task / "logs" / (identity + ".log"), 2400)
    log = Path(process["log"]).read_text(encoding="utf-8", errors="replace")
    assert not any(text in log for text in ("SCRIPT ERROR:", "ERROR:", "ObjectDB instances were leaked")), log[-5000:]
    data = json.loads(manifest.read_text(encoding="utf-8"))
    assert data["main_created"] and not data["real_player_profile_accessed"]
    assert data["mapped_events"] >= sum(case["tick"] for case in data["cases"]) * 4
    assert hashes(snapshot) == frozen_source, "Frozen source changed during observation"
    assert pipeline.production_profile(ROOT) == player, "Real player profile changed during QA"
    summary = timing_summary(data)
    data.update(source_git_sha=pipeline.git(ROOT, "rev-parse", "HEAD"), snapshot=str(snapshot), source_sha256=source,
                capture_source_sha256=frozen_source,
                display_only_project_diff="".join(difflib.unified_diff(original_project.decode().splitlines(True), capture_project.decode().splitlines(True), fromfile="canonical/project.godot", tofile="QA-native/project.godot")),
                process=process, real_profile_before=player, real_profile_unchanged=True, timing_summary=summary)
    manifest.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    if args.film:
        video = task / "video" / (args.stem + ".mp4")
        assert not video.exists(), "Preserve previous final review movies"
        assert data["movie_frames"] > 60 and any(r["overloaded"] for r in data["movie_rows"])
        assert any(r["venting"] for r in data["movie_rows"])
        ffmpeg = workspace.find_tool("ffmpeg", args.ffmpeg)
        raw_info = movie_metadata(ffmpeg, raw)
        assert "640x360" in raw_info["metadata"]
        command = [ffmpeg, "-v", "error", "-i", str(raw)]
        if not raw_info["has_audio"]: command += ["-i", str(raw.with_suffix(".wav"))]
        font_path = "C\\:/Windows/Fonts/consola.ttf"
        presentation_filter = ("scale=1280:720:flags=neighbor,pad=1280:800:0:0:color=0x141920,"
                               f"drawtext=fontfile='{font_path}':text='DECLARED QA BASTION LOADOUT / NORMAL MAIN + MAPPED INPUT':x=16:y=731:fontsize=20:fontcolor=0xdde7dc,"
                               f"drawtext=fontfile='{font_path}':text='POSITION HELD, SPIN SPENT / OVERLOAD - MOVE, VENT, REPLANT':x=16:y=762:fontsize=20:fontcolor=0x8fbcaa")
        command += ["-map", "0:v:0", "-map", "0:a:0" if raw_info["has_audio"] else "1:a:0",
                    "-vf", presentation_filter, "-c:v", "libx264", "-crf", "18", "-preset", "fast",
                    "-c:a", "aac", "-b:a", "160k", "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(video)]
        encoder = pipeline.run_logged(command, task / "logs" / (identity + "_encode.log"), 600)
        decoder = pipeline.run_logged([ffmpeg, "-v", "error", "-i", str(video), "-f", "null", "-"], task / "logs" / (identity + "_decode.log"), 180)
        info = movie_metadata(ffmpeg, video)
        # Textual media metadata rounds duration to hundredths of a second.
        assert info["has_audio"] and abs(info["duration_seconds"] - data["movie_seconds"]) < .3
        data.update(video=str(video), video_sha256=pipeline.sha256(video), movie_metadata=info, encoder=encoder, decoder=decoder,
                    recorded_render_boot_and_screenshot_overhead_seconds=info["duration_seconds"] - data["movie_seconds"],
                    review_caption_scope="Static review captions sit in an additional 80px strip below the complete 1280x720 nearest-neighbour gameplay image; the product HUD and central arena are never covered.")
    manifest.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    if args.final_timing:
        summary.update(observation_manifest=str(manifest), observation_sha256=pipeline.sha256(manifest), source_sha256=source,
                       real_profile_unchanged=True)
        for target in (task / "manifests" / "003a1_anchor_rearm_timing.json", task / "003a1_anchor_rearm_timing.json"):
            assert not target.exists(), "Preserve existing evidence"
            target.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"passed": True, "manifest": str(manifest), "video": data.get("video"),
                      "timing_cases": len(summary["movement_recovery_cases"]),
                      "minimum_full_safe_central_replant_seconds": summary["minimum_time_from_real_overload_release_to_full_safe_central_replant_seconds"]}, indent=2))


if __name__ == "__main__": main()
