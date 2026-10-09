"""Freeze real card UI, audit the roster and film scoped Main choices."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "tools/workspace"), str(ROOT / "tools/build"), str(ROOT / "tools/capture")]
import workspace
import windows_checkpoint as pipeline
from presentation_showcase import movie_metadata
try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.path.insert(0, r"C:\Users\samdf\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\Lib\site-packages")
    from PIL import Image, ImageDraw, ImageFont

DRIVERS = ("test_ability_card_hierarchy_003a1.gd", "capture_card_hierarchy_003a1.gd")
OWNED = ("scripts/menus.gd", "scripts/run_powers.gd", "scripts/ability_card_style.gd", "scripts/ability_inspection.gd")

def source(project: Path) -> dict:
    paths = [project / "project.godot", project / "main.tscn"]
    paths += [p for family in ("scripts", "assets") for p in (project / family).rglob("*") if p.is_file()]
    paths += [project / "tests" / name for name in DRIVERS]
    return {p.relative_to(project).as_posix(): pipeline.sha256(p) for p in sorted(paths)}

def player(start: dict) -> dict:
    names = [name for name in start["player_profile"] if name in ("collection.json", "collection.json.bak", "prototype.cfg") or name.startswith("collection-backups/")]
    assert len(names) == 24, "Use the valid full-player baseline, never a zero-profile attempt"
    directory = Path(start["profile_root"])
    return {name: pipeline.sha256(directory / name) for name in names}

def matrix_image(runtime: dict, destination: Path) -> None:
    # Copy whole native UI card crops; captions never repaint illustration pixels.
    cell = (420, 530)
    canvas = Image.new("RGB", (1284, 1662), "#10151f")
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.truetype(r"C:\Windows\Fonts\consola.ttf", 22)
    small = ImageFont.truetype(r"C:\Windows\Fonts\consola.ttf", 16)
    draw.text((16, 12), "POWER  <  RANK II  <  MUTATION", fill="#e3e8dc", font=font)
    draw.text((16, 42), "ACTUAL UI CARDS / 2x NEAREST / ORIGINAL ART / FOCUS SHOWN", fill="#9aa9a8", font=small)
    families = ("redline", "dead_centre", "afterimage")
    colours = {1: "#bdcbd3", 2: "#64d8ef", 3: "#d49bf1"}
    for row in runtime["matrix"]:
        image_record = runtime["images"][row["image"]]
        raw = Image.open(image_record["path"]).convert("RGB")
        x, y, width, height = image_record["card_rect"]
        assert 0 <= x < raw.width and 0 <= y < raw.height and x + width <= raw.width and y + height <= raw.height
        card = raw.crop((x, y, x + width, y + height)).resize((width * 2, height * 2), Image.Resampling.NEAREST)
        column = row["rank"] - 1
        line = families.index(row["family"])
        px = 12 + column * cell[0] + (cell[0] - card.width) // 2
        py = 94 + line * cell[1]
        draw.text((16 + column * cell[0], py - 26), row["badge"], fill=colours[row["rank"]], font=font)
        canvas.paste(card, (px, py))
    canvas.save(destination)

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--engine")
    ap.add_argument("--ffmpeg")
    ap.add_argument("--baseline", type=Path, required=True)
    ap.add_argument("--preliminary", action="store_true", help="Preserve an initial native attempt without claiming final copy acceptance")
    args = ap.parse_args()
    qa = workspace.create_task_workspace("003A.1")
    stem = "003a1_card_hierarchy_" + datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
    stage = qa / "temp" / (stem + "_source")
    manifest = qa / "manifests" / (stem + ".json")
    unit_report = qa / "manifests" / (stem + "_roster.json")
    runtime_report = qa / "manifests" / (stem + "_runtime.json")
    profile = qa / "temp" / (stem + "_profile") / "collection.json"
    frames = qa / "frames" / stem
    raw = qa / "temp" / (stem + ".avi")
    movie = qa / "video" / (stem + "_preliminary.mp4" if args.preliminary else "003a1_card_hierarchy_video.mp4")
    matrix = qa / "images" / (stem + "_preliminary.png" if args.preliminary else "003a1_ability_card_hierarchy.png")
    assert all(not p.exists() for p in (stage, manifest, unit_report, runtime_report, profile, frames, raw, movie, matrix)), "Preserve previous review evidence"
    start = json.loads(args.baseline.read_text(encoding="utf-8"))
    before_player = player(start)
    baseline_player = {name: start["player_profile"][name]["sha256"] for name in before_player}
    assert before_player == baseline_player
    inputs = source(ROOT)
    record = {"status": "started", "preliminary": args.preliminary, "scope": "Actual native Main/card menus with disclosed legal initial draft fixtures and synthetic keyboard/controller input. No physics/natural draft/hardware acceptance claim.",
              "starting_sha": "68669556b253a67212e32c0cbf18d56f0df43f6f", "source_git_sha": pipeline.git(ROOT, "rev-parse", "HEAD"),
              "working_tree": pipeline.git(ROOT, "status", "--porcelain"), "source_sha256": inputs,
              "baseline": str(args.baseline), "baseline_sha256": pipeline.sha256(args.baseline), "real_player_before": before_player, "stage": str(stage)}
    pipeline.write_json(manifest, record)
    stage.mkdir()
    for name in ("scripts", "assets"): shutil.copytree(ROOT / name, stage / name)
    for name in ("project.godot", "main.tscn"): shutil.copy2(ROOT / name, stage / name)
    (stage / "tests").mkdir()
    for name in DRIVERS: shutil.copy2(ROOT / "tests" / name, stage / "tests" / name)
    assert source(stage) == inputs == source(ROOT)
    # MovieWriter locks its dimensions before the SceneTree driver can resize.
    # Declare only the initial QA window size; production project bytes stay exact.
    original_project = (stage / "project.godot").read_bytes()
    adjusted_project = original_project
    for key, value in (("window_width_override", 800), ("window_height_override", 480)):
        adjusted_project, count = re.subn(rb"(?m)^window/size/" + key.encode() + rb"=\d+", b"window/size/" + key.encode() + b"=" + str(value).encode(), adjusted_project)
        assert count == 1
    (stage / "project.godot").write_bytes(adjusted_project)
    capture_inputs = dict(inputs)
    capture_inputs["project.godot"] = pipeline.sha256(stage / "project.godot")
    record["qa_window_override"] = {"source_project_sha256": inputs["project.godot"], "capture_project_sha256": capture_inputs["project.godot"], "fields": {"window/size/window_width_override":800, "window/size/window_height_override":480}, "reason":"MovieWriter initializes before the QA SceneTree; an exact 800x480 startup prevents nonuniform rescaling. Production project is unmodified."}
    pipeline.write_json(manifest, record)
    engine = workspace.find_tool("godot", args.engine)
    imported = pipeline.import_source([engine, "--headless", "--path", str(stage), "--editor", "--import"], qa / "logs" / (stem + "_import"), 600)
    frozen = source(stage)
    assert all(frozen[name] == digest for name, digest in capture_inputs.items())
    added = {name: digest for name, digest in frozen.items() if name not in inputs}
    assert all(name.endswith((".uid", ".import")) for name in added)
    unit = pipeline.run_logged([engine, "--headless", "--path", str(stage), "--script", "res://tests/test_ability_card_hierarchy_003a1.gd", "--fixed-fps", "60", "--disable-vsync", "--audio-driver", "Dummy", "--", "--report=" + str(unit_report)], qa / "logs" / (stem + "_roster.log"), 180)
    roster = json.loads(unit_report.read_text())
    assert roster["card_count"] == 46 and not roster["failures"]
    captured = pipeline.run_logged([engine, "--path", str(stage), "--script", "res://tests/capture_card_hierarchy_003a1.gd", "--fixed-fps", "60", "--disable-vsync", "--quit-after", "3600", "--resolution", "800x480", "--write-movie", str(raw), "--audio-driver", "Dummy", "--", "--profile=" + str(profile), "--report=" + str(runtime_report), "--frames=" + str(frames)], qa / "logs" / (stem + "_capture.log"), 240)
    runtime = json.loads(runtime_report.read_text())
    assert not runtime["failures"] and len(runtime["matrix"]) == 9
    assert [(r["power"], r["rank"], r["mutation"]) for r in runtime["selections"]] == [("redline", 1, ""), ("redline", 2, ""), ("afterimage", 3, "ghost_circuit"), ("dead_centre", 1, "")]
    assert runtime["isolated_collection_before"] == runtime["isolated_collection_after"]
    assert source(stage) == frozen and player(start) == before_player
    current = source(ROOT)
    assert all(current[name] == inputs[name] for name in OWNED + tuple("tests/" + name for name in DRIVERS))
    for image in runtime["images"].values():
        assert pipeline.sha256(Path(image["path"])) == image["sha256"]
    matrix_candidate = qa / "temp" / (stem + "_matrix.png")
    matrix_image(runtime, matrix_candidate)
    ffmpeg = workspace.find_tool("ffmpeg", args.ffmpeg)
    movie_info = movie_metadata(ffmpeg, raw)
    assert re.search(r"Video:.*\b800x480\b", movie_info["metadata"]), "Actual MovieWriter canvas must equal the native viewport; never stretch pixel art"
    crop = next(iter(runtime["images"].values()))["menu_rect"]
    assert all(image["menu_rect"] == crop for image in runtime["images"].values()) and crop[2:] == [640, 360]
    first, last = runtime["movie_start_frame"], runtime["movie_end_frame"]
    filters = [f"trim=start_frame={first}:end_frame={last}", "setpts=PTS-STARTPTS", f"crop=640:360:{int(crop[0])}:{int(crop[1])}", "scale=1280:720:flags=neighbor", "pad=1280:776:0:0:color=0x10151f"]
    for phase in runtime["phases"]:
        if phase["name"] == "end": continue
        lo = (phase["from_frame"] - first) / 60
        hi = (phase["to_frame"] - first) / 60
        filters.append("drawtext=fontfile='C\\:/Windows/Fonts/consola.ttf':text='" + phase["name"] + f"':x=12:y=728:fontsize=19:fontcolor=0xe3e8dc:enable='between(t,{lo:.6f},{hi:.6f})'")
    filters.append("drawtext=fontfile='C\\:/Windows/Fonts/consola.ttf':text='LEGAL INITIAL DRAFT FIXTURES / REAL MAIN SELECTION / AUTOMATED INPUT':x=12:y=754:fontsize=12:fontcolor=0x9aa9a8")
    candidate = qa / "temp" / (stem + "_video.mp4")
    command = [ffmpeg, "-v", "error", "-i", str(raw)]
    if not movie_info["has_audio"]: command += ["-i", str(raw.with_suffix(".wav"))]
    command += ["-map", "0:v:0", "-map", "0:a:0" if movie_info["has_audio"] else "1:a:0", "-vf", ",".join(filters), "-af", f"atrim=start={first/60:.6f}:end={last/60:.6f},asetpts=PTS-STARTPTS", "-c:v", "libx264", "-crf", "18", "-preset", "fast", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart", str(candidate)]
    encoded = pipeline.run_logged(command, qa / "logs" / (stem + "_encode.log"), 300)
    decoded = pipeline.run_logged([ffmpeg, "-v", "error", "-i", str(candidate), "-f", "null", "-"], qa / "logs" / (stem + "_decode.log"), 180)
    metadata = movie_metadata(ffmpeg, candidate)
    assert metadata["has_audio"] and abs(metadata["duration_seconds"] - (last - first)/60) < .25
    assert player(start) == before_player and source(stage) == frozen
    assert not movie.exists() and not matrix.exists()
    shutil.copy2(candidate, movie); shutil.copy2(matrix_candidate, matrix)
    record.update(status="passed_preliminary" if args.preliminary else "passed", import_process=imported, added_import_metadata=added, roster_process=unit, roster_report=str(unit_report), roster_report_sha256=pipeline.sha256(unit_report),
                  roster_checks=roster["checks"], cards_audited=46, capture_process=captured, runtime_report=str(runtime_report), runtime_report_sha256=pipeline.sha256(runtime_report),
                  runtime=runtime, video=str(movie), video_sha256=pipeline.sha256(movie), video_metadata=metadata, image=str(matrix), image_sha256=pipeline.sha256(matrix),
                  encoded=encoded, decoded=decoded, frozen_source_unchanged=True, card_source_unchanged=True, companion_source_changes={name:{"before":digest,"after":current.get(name)} for name,digest in inputs.items() if current.get(name)!=digest},
                  real_player_after=player(start), real_player_unchanged=True, art_policy="Whole actual native card crops copied at 2x nearest; no art tint, generated illustrations or altered assets. Raw MovieWriter and actual viewport are both 800x480; final movie crops the native 640x360 menu, then scales at 2x nearest. Matrix preparation excluded from final normal-speed movie.")
    pipeline.write_json(manifest, record)
    print(json.dumps({"passed": True, "manifest": str(manifest), "cards": 46, "checks": roster["checks"], "video": str(movie), "image": str(matrix)}, indent=2))

if __name__ == "__main__": main()
