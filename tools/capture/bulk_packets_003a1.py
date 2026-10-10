"""Freeze exact production source and film crash-safe bulk packets through GUI."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
import os
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

DRIVERS = ["capture_bulk_packets_003a1.gd", "test_collection_ui.gd"]

def hashes(root: Path) -> dict:
    files = list((root / "scripts").glob("*.gd")) + [p for p in (root / "assets").rglob("*") if p.is_file()]
    files += [root / "tests" / name for name in DRIVERS]
    return {p.relative_to(root).as_posix(): pipeline.sha256(p) for p in sorted(files)}

def player() -> dict:
    data = pipeline.production_profile(ROOT)
    directory = Path(data["directory"]) if data.get("directory") else None
    data["recovery_backups"] = ({str(p.relative_to(directory)): pipeline.sha256(p) for p in sorted((directory / "collection-backups").rglob("*")) if p.is_file()} if directory else {})
    return data

def validate(data: dict) -> dict:
    assert data["failures"] == 0 and data["checks"] > 100
    assert data["native_root"] == [800, 480] and data["native_menu"] == [640, 360]
    assert [t["quantity"] for t in data["transactions"]] == [1, 3, 5, 5]
    assert data["final_wallet"]["credits"] == 1200 - 48 * 14
    before, after = data["mid_batch_close_reload"]["before_close"], data["mid_batch_close_reload"]["after_reload"]
    assert before == after and 0 < before["cursor"] < 5
    mixed = []
    for transaction in data["transactions"]:
        rows = transaction["fixed_receipt"]["rows"]
        assert len(rows) == transaction["quantity"] * 3
        mixed.append({"quantity": transaction["quantity"], "new": sum(row["new"] for row in rows), "duplicates": sum(not row["new"] for row in rows), "salvage": sum(row["salvage"] for row in rows)})
    assert any(t["new"] > 0 and t["duplicates"] > 0 for t in mixed)
    assert all(e["type"] == "actual_gui_mouse_click" for e in data["input_events"])
    return {"mixed_results": mixed, "total_packets": 14, "total_parts": 42, "one_debit_per_batch": True, "mid_batch_exact_disk_resume": True, "fast_open_all": True}

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-snapshot", required=True, type=Path)
    parser.add_argument("--engine")
    parser.add_argument("--ffmpeg")
    parser.add_argument("--qa-root", type=Path)
    parser.add_argument("--diagnostic", action="store_true")
    args = parser.parse_args()
    qa = workspace.create_task_workspace("003A.1", args.qa_root)
    identity = "003a1_bulk_packet_opening_" + datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
    manifest = qa / "manifests" / (identity + ".json")
    snapshot = qa / "temp" / (identity + "_source")
    profile = qa / "temp" / (identity + "_profile") / "collection.json"
    raw = qa / "temp" / (identity + ".avi")
    frames = qa / "frames" / identity
    video = qa / "video" / "003a1_bulk_packet_opening.mp4"
    assert not snapshot.exists() and not profile.exists() and not manifest.exists()
    if not args.diagnostic: assert not video.exists(), "Keep all previous review evidence"
    profile.parent.mkdir()
    original_player = player()
    source = hashes(ROOT)
    shutil.copytree(args.base_snapshot, snapshot)
    for family in ("scripts", "assets", ".godot"):
        shutil.copytree(ROOT / family, snapshot / family, dirs_exist_ok=True)
    for name in DRIVERS: shutil.copy2(ROOT / "tests" / name, snapshot / "tests" / name)
    project = (ROOT / "project.godot").read_bytes()
    adjusted = project.replace(b"window/size/window_width_override=1600", b"window/size/window_width_override=800").replace(b"window/size/window_height_override=960", b"window/size/window_height_override=480")
    (snapshot / "project.godot").write_bytes(adjusted)
    assert hashes(snapshot) == source, "Frozen source must exactly match current production inputs"
    engine = workspace.find_tool("godot", args.engine)
    pipeline.run_logged([engine, "--headless", "--path", str(snapshot), "--editor", "--quit"], qa / "logs" / (identity + "_import.log"), 600)
    command = [engine, "--path", str(snapshot), "--script", "res://tests/capture_bulk_packets_003a1.gd", "--fixed-fps", "60", "--disable-vsync"]
    command += ["--headless"] if args.diagnostic else ["--resolution", "800x480", "--write-movie", str(raw), "--audio-driver", "Dummy"]
    command += ["--", "--manifest=" + str(manifest), "--profile=" + str(profile), "--frames=" + str(frames)]
    if args.diagnostic: command += ["--diagnostic"]
    old_qa = os.environ.get("TOPGAME_QA_ROOT")
    os.environ["TOPGAME_QA_ROOT"] = str(qa.parent)
    try:
        process = pipeline.run_logged(command, qa / "logs" / (identity + ".log"), 900)
    finally:
        if old_qa is None: os.environ.pop("TOPGAME_QA_ROOT", None)
        else: os.environ["TOPGAME_QA_ROOT"] = old_qa
    data = json.loads(manifest.read_text(encoding="utf-8"))
    proof = validate(data)
    assert hashes(snapshot) == source and player() == original_player
    data.update(content_proof=proof, capture_process=process, frozen_source=str(snapshot), source_sha256=source,
                source_git_sha=pipeline.git(ROOT, "rev-parse", "HEAD"), captured_working_tree=pipeline.git(ROOT, "status", "--porcelain"),
                exact_frozen_source_unchanged=True, real_player_before=original_player, real_player_unchanged=True,
                human_acceptance="Pending; GUI automation and isolated economic fixtures are not human/phone acceptance")
    if not args.diagnostic:
        ffmpeg = workspace.find_tool("ffmpeg", args.ffmpeg)
        raw_metadata = movie_metadata(ffmpeg, raw)
        command = [ffmpeg, "-v", "error", "-i", str(raw)]
        if not raw_metadata["has_audio"]: command += ["-i", str(raw.with_suffix(".wav"))]
        filters = ["crop=640:360:80:60", "scale=1280:720:flags=neighbor", "pad=1280:760:0:0:color=0x10151f"]
        captions = {"x1_original_physical_packet":"x1 / ORIGINAL PHYSICAL PACKET", "x3_fast_staggered_tears":"x3 / FAN + QUICK STAGGERED TEARS / ACTUAL PART SPRITES", "x5_fan_and_mid_batch_close":"x5 / EXACT PAID BATCH / CLOSE DURING THIRD PACKET", "x5_resume_exact_remaining_packets":"RELOAD / SAME RESULTS + SAVED CURSOR / NO EXTRA CHARGE OR GRANTS", "x5_fast_open_all_actual_mixed_results":"FAST OPEN ALL / ACTUAL NEW + DUPLICATES + SALVAGE SUMMARY"}
        for phase in data["phases"]:
            start, end = phase["from_frame"] / 60, phase["to_frame"] / 60
            filters.append("drawtext=fontfile='C\\:/Windows/Fonts/consola.ttf':text='" + captions[phase["name"]] + "':x=12:y=732:fontsize=16:fontcolor=0xd8e3dc:enable='between(t," + f"{start:.6f},{end:.6f}" + ")'")
        command += ["-map", "0:v:0", "-map", "0:a:0" if raw_metadata["has_audio"] else "1:a:0", "-vf", ",".join(filters), "-c:v", "libx264", "-crf", "18", "-preset", "fast", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart", str(video)]
        encoded = pipeline.run_logged(command, qa / "logs" / (identity + "_encode.log"), 600)
        decoded = pipeline.run_logged([ffmpeg, "-v", "error", "-i", str(video), "-f", "null", "-"], qa / "logs" / (identity + "_decode.log"), 180)
        metadata = movie_metadata(ffmpeg, video)
        assert metadata["has_audio"] and abs(metadata["duration_seconds"] - data["nominal_seconds"]) < 0.4
        assert data["sound_counts"].get("packet_tear", 0) and data["sound_counts"].get("packet_clink", 0)
        for image in data["images"].values():
            proof_image = pipeline.png_record(Path(image["path"]))
            assert proof_image["width"] == 640 and proof_image["height"] == 360
        data.update(video=str(video), video_sha256=pipeline.sha256(video), encoded=encoded, decoded=decoded, movie_metadata=metadata)
    manifest.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"passed":True,"manifest":str(manifest),"video":data.get("video"),"content":proof}, indent=2))

if __name__ == "__main__": main()
