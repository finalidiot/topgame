"""Capture decorated Windows resize/Maximise/Restore evidence without changing gameplay."""
from __future__ import annotations
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/workspace"))
sys.path.insert(0, str(ROOT / "tools/build"))
sys.path.insert(0, str(ROOT / "tools/capture"))
import workspace
import windows_checkpoint as pipeline
from presentation_showcase import movie_metadata

DRIVERS = ("capture_native_window_layout_003a1.gd", "test_native_window_layout_003a1.gd", "test_combat_acceptance_hud_003a1.gd")
PHASES = ("normal_960x600", "normal_800x480", "larger_1280x800", "os_api_maximise", "os_api_restore", "normal_800x480_final")

def hashes(project: Path) -> dict:
    paths = [project / "project.godot", project / "main.tscn"]
    paths += [p for family in ("scripts", "assets") for p in (project / family).rglob("*") if p.is_file()]
    paths += [project / "tests" / name for name in DRIVERS]
    return {p.relative_to(project).as_posix(): pipeline.sha256(p) for p in sorted(paths)}

def player() -> dict:
    record = pipeline.production_profile(ROOT)
    directory = Path(record["directory"])
    record["recovery_backups"] = {str(p.relative_to(directory)): pipeline.sha256(p) for p in sorted((directory / "collection-backups").rglob("*")) if p.is_file()}
    return record

def display_frame(path: Path, label: str, sublabel: str, target: Path, crop: list | None = None) -> None:
    # Screenshot pixels and real OS decorations are copied unchanged, never redrawn.
    image = Image.open(path).convert("RGB")
    if crop is not None: image = image.crop(tuple(crop))
    assert image.width <= 1920 and image.height <= 1080
    canvas = Image.new("RGB", (1920, 1152), (16, 21, 31))
    canvas.paste(image, ((1920-image.width)//2, (1080-image.height)//2))
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.truetype("C:/Windows/Fonts/consola.ttf", 24)
    small = ImageFont.truetype("C:/Windows/Fonts/consola.ttf", 18)
    draw.text((24, 1090), label, fill=(221, 235, 225), font=font)
    draw.text((24, 1125), sublabel, fill=(159, 177, 189), font=small)
    canvas.save(target)

def main() -> None:
    qa = workspace.create_task_workspace("003A.1")
    identity = "003a1_window_review_" + datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
    snapshot = qa / "temp" / (identity + "_source")
    manifest = qa / "manifests" / (identity + ".json")
    report = qa / "manifests" / (identity + "_runtime.json")
    frames = qa / "frames" / identity
    stop = qa / "temp" / (identity + ".stop")
    video = qa / "video" / "003a1_window_maximise_layout.mp4"
    matrix = qa / "images" / "003a1_window_layout_matrix.png"
    if video.exists() or matrix.exists():
        video = qa / "video" / (identity + "_maximise_layout.mp4")
        matrix = qa / "images" / (identity + "_layout_matrix.png")
    assert not snapshot.exists() and not manifest.exists() and not video.exists() and not matrix.exists()
    before = player()
    source = hashes(ROOT)
    record = {"validation": "started", "source_git_sha": pipeline.git(ROOT, "rev-parse", "HEAD"), "working_tree_at_freeze": pipeline.git(ROOT, "status", "--porcelain"), "source_sha256": source, "snapshot": str(snapshot), "real_player_before": before,
              "scope": "Real native decorated Windows screenshots of paused production gameplay with a declared legal rank-II four-power fixture. Maximise by a human is retained separately from earlier footage; this follow-up sequence uses OS APIs. No balance or Android acceptance claim."}
    pipeline.write_json(manifest, record)
    snapshot.mkdir()
    for family in ("scripts", "assets", ".godot"):
        shutil.copytree(ROOT / family, snapshot / family)
    for name in ("project.godot", "main.tscn"):
        shutil.copy2(ROOT / name, snapshot / name)
    (snapshot / "tests").mkdir()
    for name in DRIVERS:
        shutil.copy2(ROOT / "tests" / name, snapshot / "tests" / name)
    assert hashes(snapshot) == source == hashes(ROOT), "Freeze must be byte-exact"
    engine = workspace.find_tool("godot")
    record["import"] = pipeline.import_source([engine, "--headless", "--path", str(snapshot), "--editor", "--quit"], qa / "logs" / (identity + "_import"), 600)
    imported = hashes(snapshot)
    assert all(imported.get(k) == v for k, v in source.items())
    assert all(k.endswith((".uid", ".import")) for k in imported if k not in source)
    prior = os.environ.get("TOPGAME_QA_ROOT")
    os.environ["TOPGAME_QA_ROOT"] = str(qa.parent)
    try:
        contracts = []
        for driver in DRIVERS[1:]:
            test_report = qa / "manifests" / (identity + "_" + Path(driver).stem + ".json")
            command = [engine, "--path", str(snapshot), "--script", "res://tests/" + driver, "--audio-driver", "Dummy", "--", "--native", "--report=" + str(test_report)]
            process = pipeline.run_logged(command, qa / "logs" / (identity + "_" + Path(driver).stem + ".log"), 180)
            data = json.loads(test_report.read_text(encoding="utf-8"))
            assert data["failures"] == [] and data["checks"] > 80
            contracts.append({"report": str(test_report), "sha256": pipeline.sha256(test_report), "checks": data["checks"], "process": process})
        command = [engine, "--path", str(snapshot), "--script", "res://tests/" + DRIVERS[0], "--audio-driver", "Dummy", "--", "--auto-sequence", "--report=" + str(report), "--stop-file=" + str(stop), "--frames=" + str(frames)]
        record["capture_process"] = pipeline.run_logged(command, qa / "logs" / (identity + "_capture.log"), 90)
    finally:
        if prior is None: os.environ.pop("TOPGAME_QA_ROOT", None)
        else: os.environ["TOPGAME_QA_ROOT"] = prior
    data = json.loads(report.read_text(encoding="utf-8"))
    assert data["world_unchanged"] and data["restore_verified"]
    assert len(data["sequence_events"]) == 6
    groups = {phase: [f for f in data["captured_frames"] if f["phase"] == phase] for phase in PHASES}
    assert all(len(group) >= 5 for group in groups.values()), "Every stage needs genuine foreground screenshots"
    assert all(f["mode"] == (2 if phase == "os_api_maximise" else 0) for phase, group in groups.items() for f in group if f["phase_elapsed_msec"] >= 250)
    assert hashes(snapshot) == imported
    assert player() == before, "Human collection, backups and preferences must remain unchanged"
    old_report = qa / "manifests" / "003a1_window_native_buttons_20261009_110812.json"
    old_provenance = qa / "manifests" / "003a1_window_native_buttons_20261009_110812_provenance.json"
    old = json.loads(old_report.read_text(encoding="utf-8"))
    old_proof = json.loads(old_provenance.read_text(encoding="utf-8"))
    # The retained original report includes Windows' invisible bottom frame.
    # Crop only its known eight-pixel taskbar strip in derived review images;
    # original captures/report remain untouched and hashed.
    human_frames = [dict(f, review_crop=[0,0,1920,1040]) for f in old["captured_frames"] if f["mode"] == 2]
    assert len(human_frames) >= 5 and old["world_unchanged"] and old["current"]["borderless"] is False
    changed_sources = {k: {"human_capture": v, "follow_up": source.get(k)} for k, v in old_proof["source"].items() if source.get(k) != v}
    record["real_human_maximise"] = {"authorization_evidence": "User stated 'I just maximised the window'; parent observed matching native report mode=MAXIMIZED, client=1920x1017, decorated borders retained.", "report": str(old_report), "report_sha256": pipeline.sha256(old_report), "provenance": str(old_provenance), "provenance_sha256": pipeline.sha256(old_provenance), "snapshot": old["snapshots"][-1], "world_unchanged": old["world_unchanged"], "source_differences_from_follow_up": changed_sources,
        "limitation": "Earlier synthetic button input timed out twice, click geometry was unavailable, and Alt+Space/X did not maximise. Actual human Maximise is confirmed by the saved native state and screenshot; automated follow-up Restore does not establish human Restore-button acceptance."}
    # Edited review: retained human segment followed by a separately labelled API sequence.
    # Idle gaps are omitted explicitly. Every visible screenshot is original native capture.
    timeline = [(f, "HUMAN MAXIMISE: REAL WINDOWS CAPTION AND ENLARGED ARENA", "Earlier human capture; then a separate OS API resize/Restore check") for f in human_frames]
    timeline += [(f, f["phase"].replace("_", " ").upper(), "OS API actuation / paused fixture / native screen pixels; human Restore button pending") for f in data["captured_frames"]]
    edited = qa / "temp" / (identity + "_edited_frames")
    edited.mkdir()
    concat = edited / "timeline.ffconcat"
    lines = ["ffconcat version 1.0"]
    selected = []
    for index, (frame, label, sublabel) in enumerate(timeline):
        output = edited / ("review_%05d.png" % index)
        display_frame(Path(frame["path"]), label, sublabel, output, frame.get("review_crop"))
        if index+1 < len(timeline) and timeline[index+1][0].get("phase") == frame.get("phase"):
            duration = max(.04, min(.25, (timeline[index+1][0]["time_msec"]-frame["time_msec"])/1000))
        else: duration = .12
        lines += ["file '" + output.as_posix() + "'", "duration %.6f" % duration]
        selected.append({"source": frame["path"], "source_sha256": pipeline.sha256(Path(frame["path"])), "review_crop": frame.get("review_crop"), "time_msec": frame["time_msec"], "review_duration_seconds": duration, "label": label})
    lines.append("file '" + output.as_posix() + "'")
    concat.write_text("\n".join(lines)+"\n", encoding="utf-8")
    ffmpeg = workspace.find_tool("ffmpeg")
    record["encode"] = pipeline.run_logged([ffmpeg, "-v", "error", "-f", "concat", "-safe", "0", "-i", str(concat), "-r", "30", "-c:v", "libx264", "-crf", "17", "-preset", "fast", "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(video)], qa / "logs" / (identity + "_encode.log"), 600)
    record["decode"] = pipeline.run_logged([ffmpeg, "-v", "error", "-i", str(video), "-f", "null", "-"], qa / "logs" / (identity + "_decode.log"), 180)
    representatives = [(groups["normal_800x480"][-1], "NORMAL SMALL 800x480 / OS API"), (groups["larger_1280x800"][-1], "LARGER NORMAL 1280x800 / OS API"), (human_frames[-1], "MAXIMISED 1920x1017 / REAL HUMAN ACTION"), (groups["os_api_restore"][-1], "RESTORED 1280x800 / OS API / HUMAN BUTTON PENDING")]
    sheet = Image.new("RGB", (3840, 2304), (16, 21, 31))
    for index, (frame, label) in enumerate(representatives):
        tile = edited / ("matrix_%d.png" % index)
        display_frame(Path(frame["path"]), label, "Real OS decorations; frozen 640x360 solver/camera; HUD outside arena", tile, frame.get("review_crop"))
        sheet.paste(Image.open(tile), (1920*(index%2), 1152*(index//2)))
    sheet.save(matrix)
    record.update(validation="passed", contracts=contracts, runtime_report=str(report), runtime_report_sha256=pipeline.sha256(report), runtime=data, raw_capture_count=len(data["captured_frames"]), raw_frames_sha256={f["path"]: pipeline.sha256(Path(f["path"])) for f in data["captured_frames"]}, edited_review_timeline=selected, timing_policy="Original native capture intervals up to 250ms are retained; foreground-loss/idle gaps are omitted and review segment origins are labelled. No continuous physical button sequence is claimed.", review_crop_policy="Old human maximised frames trim only the eight-pixel taskbar strip outside the visible window (1920x1048 to1920x1040). Follow-up captures use actual client width plus native OS caption height, excluding invisible DWM side/bottom margins; no background window/taskbar pixels are included. Real caption/buttons and all game pixels remain unchanged.", video=str(video), video_sha256=pipeline.sha256(video), movie_metadata=movie_metadata(ffmpeg, video), image=str(matrix), image_sha256=pipeline.sha256(matrix), real_player_after=player(), real_player_unchanged=player()==before, frozen_source_unchanged=hashes(snapshot)==imported, canonical_source_unchanged_since_freeze=hashes(ROOT)==source)
    assert record["real_player_unchanged"] and record["frozen_source_unchanged"]
    pipeline.write_json(manifest, record)
    print(json.dumps({"validation": "passed", "manifest": str(manifest), "video": str(video), "matrix": str(matrix), "checks": [c["checks"] for c in contracts], "actual_human_maximise": True, "human_restore_button_test": False}, indent=2))

if __name__ == "__main__": main()
