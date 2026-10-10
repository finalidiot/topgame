"""Guarded production mobile-surface QA on Windows; never claims phone acceptance."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import sys
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
for family in ("tools/build", "tools/workspace", "tools/presentation"):
    sys.path.insert(0, str(ROOT / family))
import windows_checkpoint as pipeline
import workspace
from upgrade_sustain_003a1 import source

DRIVER = ROOT / "tests/test_android_fullscreen_layout_003a2.gd"
REQUIRED_SCREENS = {
    "title", "hub", "battle", "ability_draft", "mutation_draft", "pause", "shop",
    "workshop", "packet_purchase", "packet_open", "packet_result", "settings", "result",
    "starter", "starter_confirmation", "starter_owned", "acquisition", "uninitialized_hub",
}
REQUIRED_CASES = {"1280x720", "2160x1080", "2340x1080", "2400x1080", "2340x1080_cutout"}


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def pointer(path):
    path = Path(path).resolve()
    return {"path": str(path), "bytes": path.stat().st_size, "sha256": pipeline.sha256(path)}


def player():
    inventory = pipeline.production_profile(ROOT)
    folder = Path(inventory["directory"])
    baseline = read(ROOT.parent / "GyroBrothers-QA/003A.2/manifests/003a2_scope_baseline.json")
    # Preserve the agreed player/backup scope; engine log rotation, shader
    # cache and newly created historical QA profiles are not player data.
    files = {Path(name) for name in baseline["player"]}
    files.update(folder / name for name in inventory["files"])
    files.update(p for p in (folder / "collection-backups/collection").rglob("*") if p.is_file())
    assert all(p.is_file() and p.resolve().is_relative_to(folder.resolve()) for p in files)
    return {
        "directory": str(folder),
        "files": {str(p.relative_to(folder)): {"bytes": p.stat().st_size, "sha256": pipeline.sha256(p)}
                  for p in sorted(files)},
        "scope": "Exact438 accepted player/backup/previous profile paths plus current default collection/preferences/collection backups; excludes transient engine logs/shader cache/new QA profiles.",
    }


def validate(data, mode):
    assert data["schema"] == "android-fullscreen-layout-003a2-v1"
    assert data["checks"] > 0 and data["failures"] == [], data["failures"]
    assert data["physical_android_acceptance"] is False and data["direct_touch_router_calls"] == 0
    cases = {row["name"] for row in data["cases"]}
    assert cases == ({"2340x1080"} if mode == "movie" else REQUIRED_CASES)
    for case in cases:
        rows = [row for row in data["observations"] if row["case"] == case]
        assert {row["screen"] for row in rows} == REQUIRED_SCREENS
        battle = next(row for row in rows if row["screen"] == "battle")
        assert battle["actual_unused_physical_area"] == 0
        assert {"steering_rect", "burst_rect", "brake_rect"} == set(battle["touch_physical_regions"])
        assert battle["hud_physical_regions"]
        replay = next(row for row in data["cross_aspect_replays"] if row["case"] == case)
        assert replay["ticks"] == 1200 and len(replay["tick_sha256"]) == 1200
        assert replay["physics_viewport"] == [640, 360] and replay["hits"] > 0
        assert replay["power_events"] and replay["exact_vs_first"]
    assert data["all_physics_exact"]
    if mode != "movie":
        replays = data["cross_aspect_replays"]
        assert len({row["input_sha256"] for row in replays}) == 1
        assert all(row["tick_sha256"] == replays[0]["tick_sha256"] for row in replays)
    if mode in {"native", "movie"}:
        assert data["renderer"] != "headless" and data["native"]
        assert {(row["case"], row["screen"]) for row in data["images"]} == {
            (case, screen) for case in cases for screen in REQUIRED_SCREENS}
        for row in data["images"]:
            path = Path(row["path"])
            assert pipeline.sha256(path) == row["sha256"]
            with Image.open(path) as image:
                assert list(image.size) == row["physical_size"]
    if mode == "movie":
        assert data["movie"] and data["movie_frames"] > 1000
        assert {row["screen"] for row in data["movie_phases"]} == REQUIRED_SCREENS


def matrix(data, target):
    # Actual complete display pixels remain intact in each tile. Labels are
    # outside the game, and physical aspect is preserved with nearest sampling.
    font = ImageFont.truetype(r"C:\Windows\Fonts\consola.ttf", 17)
    title = ImageFont.truetype(r"C:\Windows\Fonts\consolab.ttf", 25)
    cases = ["1280x720", "2160x1080", "2340x1080", "2400x1080", "2340x1080_cutout"]
    canvas = Image.new("RGB", (1328, 4628), "#101a20")
    draw = ImageDraw.Draw(canvas)
    draw.text((16, 12), "003A.2 / ANDROID FULLSCREEN LAYOUT", font=title, fill="#f0ece0")
    draw.text((16, 46), "Windows production-shell simulation. No physical phone acceptance.", font=font, fill="#adc6c7")
    draw.text((16, 70), "Complete physical display; same canonical640x360 Battle; declared cutout inset.", font=font, fill="#adc6c7")
    by = {(row["case"], row["screen"]): row for row in data["images"]}
    for index, case in enumerate(cases):
        top = 104 + index * 774
        draw.text((16, top), case + " / BATTLE", font=font, fill="#7acee1")
        image = Image.open(by[(case, "battle")]["path"]).convert("RGB")
        width = 1280
        height = round(image.height * width / image.width)
        image = image.resize((width, height), Image.Resampling.NEAREST)
        canvas.paste(image, (16, top + 26))
    top = 3974
    draw.text((16, top), "2340x1080 / ACTUAL FRONTEND AND PAUSED CHOICE SCREENS", font=font, fill="#dcabed")
    screens = ["title", "hub", "ability_draft", "mutation_draft", "pause", "shop", "workshop", "settings", "result",
               "starter", "packet_open", "packet_result"]
    for index, screen in enumerate(screens):
        left, y = 16 + (index % 4) * 328, top + 34 + (index // 4) * 194
        draw.text((left, y), screen.replace("_", " ").upper(), font=font, fill="#d6dfdd")
        image = Image.open(by[("2340x1080", screen)]["path"]).convert("RGB")
        image = image.resize((316, round(image.height * 316 / image.width)), Image.Resampling.NEAREST)
        canvas.paste(image, (left, y + 24))
    canvas.save(target, optimize=True)


def case_summary(case, observation):
    layout = observation["layout"]
    touch = observation["touch_provider_layout"]
    hud = observation["hud"]
    return {
        "name": case["name"], "physical_size": case["size"], "logical_canvas_size": layout["canvas_size"],
        "physical_safe_area": layout["physical_safe_area"], "logical_safe_area": touch["safe_rect"],
        "ui_scale": layout["ui_scale"], "arena_rect": touch["arena_rect"], "arena_scale": hud["arena_scale"],
        "arena_physical_rect": observation["arena_physical"], "arena_physical_scale": observation["arena_physical"][2] / 640.0,
        "burst_rect": touch["burst_rect"], "brake_rect": touch["brake_rect"], "steering_rect": touch["steering_rect"],
        "physical_touch_regions": observation["touch_physical_regions"], "hud_regions": hud["regions"],
        "physical_hud_regions": observation["hud_physical_regions"], "actual_interactive_controls": observation["controls"],
        "actual_surface_physical": observation["actual_surface_physical"], "physical_coverage": observation["actual_physical_coverage"],
        "unused_physical_area": observation["actual_unused_physical_area"], "clipped_overscan_pixels": layout["clipped_overscan_pixels"],
        "world_viewport": [640, 360], "scope": "Rectangles without physical prefix are actual logical gameplay/HUD coordinates. Physical counterparts use the actual mounted surface transform."}


def freeze(project, stage):
    stage.mkdir()
    for name in ("project.godot", "main.tscn"):
        shutil.copy2(project / name, stage / name)
    for name in ("scripts", "assets", ".godot"):
        shutil.copytree(project / name, stage / name)
    (stage / "tests").mkdir()
    shutil.copy2(DRIVER, stage / "tests" / DRIVER.name)
    if DRIVER.with_suffix(".gd.uid").exists():
        shutil.copy2(DRIVER.with_suffix(".gd.uid"), stage / "tests" / DRIVER.with_suffix(".gd.uid").name)
    assert source(stage) == source(project)


def movie_display_fixture(stage):
    # Movie Maker chooses its recording resolution before SceneTree setup.
    # Change only the frozen QA project's initial root display dimensions.
    project = stage / "project.godot"
    original = project.read_bytes()
    replacements = {
        b"window/size/viewport_width=800": b"window/size/viewport_width=2340",
        b"window/size/viewport_height=480": b"window/size/viewport_height=1080",
        b"window/size/window_width_override=960": b"window/size/window_width_override=2340",
        b"window/size/window_height_override=600": b"window/size/window_height_override=1080",
    }
    adjusted = original
    for old, new in replacements.items():
        assert adjusted.count(old) == 1, ("Exact initial display fixture", old)
        adjusted = adjusted.replace(old, new)
    project.write_bytes(adjusted)
    assert all(adjusted.count(value) == 1 for value in replacements.values())
    return {
        "scope": "QA-only frozen project initial display viewport/window overrides to2340x1080; canonical project and640x360 Battle viewport unchanged.",
        "original_sha256": __import__("hashlib").sha256(original).hexdigest(),
        "adjusted_sha256": pipeline.sha256(project),
        "exact_replacements": {old.decode(): new.decode() for old, new in replacements.items()},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", default=r"E:\Desktop\Godot_v4.7.2-stable_win64_console.exe")
    parser.add_argument("--ffmpeg")
    parser.add_argument("--mode", choices=("headless", "native", "movie"), required=True)
    parser.add_argument("--label", default="final")
    args = parser.parse_args()
    assert args.label.replace("_", "").replace("-", "").isalnum()
    qa = workspace.create_task_workspace("003A.2")
    # Frozen external source lives below QA/temp. Point both the driver and
    # Main's production isolation guards at the same explicit task boundary.
    os.environ["TOPGAME_QA_ROOT"] = str(qa.parent)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
    stem = "android_fullscreen_" + args.mode + "_" + args.label + "_" + stamp
    manifest = qa / "manifests" / (stem + ".json")
    runtime = qa / "manifests" / (stem + "_runtime.json")
    stage = qa / "temp" / (stem + "_source")
    raw = qa / "temp" / (stem + ".avi")
    before = source(ROOT)
    profiles = player()
    harness = {str(p): pipeline.sha256(p) for p in (DRIVER, Path(__file__))}
    record = {"status": "preparing", "created_utc": datetime.now(timezone.utc).isoformat(), "mode": args.mode,
              "git_sha": pipeline.git(ROOT, "rev-parse", "HEAD"), "runtime_source": before, "harness": harness,
              "player_before": profiles, "scope": "Windows/headless production mobile-shell simulation only; no phone or immersive OS-bar acceptance."}
    record["child_environment"] = {"TOPGAME_QA_ROOT": str(qa.parent)}
    pipeline.write_json(manifest, record)
    try:
        freeze(ROOT, stage)
    except Exception as exc:
        after = source(ROOT)
        record.update(status="rejected_before_engine_launch", rejection=str(exc),
                      root_source_changed={name: {"before": before.get(name), "after": after.get(name)}
                                           for name in sorted(set(before) | set(after)) if before.get(name) != after.get(name)},
                      partial_stage=str(stage), player_after=player(), player_unchanged=profiles == player(),
                      engine_launched=False)
        pipeline.write_json(manifest, record)
        raise
    if args.mode == "movie":
        record["movie_initial_display_fixture"] = movie_display_fixture(stage)
        adjusted = source(stage)
        assert {name for name in set(before) | set(adjusted) if before.get(name) != adjusted.get(name)} == {"project.godot"}
    frozen = source(stage)
    command = [args.engine, "--path", str(stage), "--script", "res://tests/" + DRIVER.name,
               "--fixed-fps", "60", "--disable-vsync", "--audio-driver", "Dummy",
               "--log-file", str(qa / "logs" / (stem + "_engine.log"))]
    if args.mode == "headless":
        command += ["--headless"]
    else:
        command += ["--resolution", "2340x1080"]
    if args.mode == "movie":
        command += ["--write-movie", str(raw)]
    command += ["--", "--report=" + str(runtime), "--profile-prefix=" + str(qa / "temp" / (stem + "_collection"))]
    if args.mode != "headless":
        command += ["--native", "--frames=" + str(qa / "frames" / stem)]
    if args.mode == "movie":
        command += ["--movie"]
    record["status"] = "running"
    record["frozen_source_root"] = str(stage)
    pipeline.write_json(manifest, record)
    try:
        process = pipeline.run_logged(command, qa / "logs" / (stem + ".log"), 900)
    except pipeline.ProcessValidationError as exc:
        record.update(status="failed_engine_diagnostic", process=exc.record,
                      source_unchanged=before == source(ROOT), frozen_source_unchanged=frozen == source(stage),
                      harness_unchanged=harness == {str(p): pipeline.sha256(p) for p in (DRIVER, Path(__file__))},
                      player_after=player(), player_unchanged=profiles == player())
        if runtime.exists():
            failed = read(runtime)
            record.update(runtime_report=pointer(runtime), checks=failed.get("checks"), failures=failed.get("failures"),
                          all_physics_exact=failed.get("all_physics_exact"))
        pipeline.write_json(manifest, record)
        raise
    data = read(runtime)
    validate(data, args.mode)
    record.update(process=process, runtime_report=pointer(runtime), checks=data["checks"],
                  source_unchanged=before == source(ROOT), frozen_source_unchanged=frozen == source(stage),
                  harness_unchanged=harness == {str(p): pipeline.sha256(p) for p in (DRIVER, Path(__file__))},
                  player_after=player(), player_unchanged=profiles == player())
    assert all(record[key] for key in ("source_unchanged", "frozen_source_unchanged", "harness_unchanged", "player_unchanged"))
    if args.mode == "native":
        target = qa / "images/android_fullscreen_layout_matrix.png"
        assert not target.exists(), "Preserve old primary evidence; choose a new reviewed version explicitly"
        matrix(data, target)
        record["matrix"] = pointer(target)
        summary = {"schema": "android-fullscreen-layout-matrix-003a2-v1", "status": "passed", "source_sha": record["git_sha"],
                   "provenance": pointer(manifest), "runtime": pointer(runtime), "matrix": pointer(target), "checks": data["checks"],
                   "cases": [case_summary(case, next(row for row in data["observations"]
                               if row["case"] == case["name"] and row["screen"] == "battle")) for case in data["cases"]],
                   "screens": sorted(REQUIRED_SCREENS), "all_physics_exact": data["all_physics_exact"],
                   "physics_ticks_per_shape": 1200, "canonical_battle": [640, 360], "physical_android_acceptance": False,
                   "scope": record["scope"]}
        # Final provenance pointer is filled after the manifest's final write.
        record["matrix_summary_pending"] = summary
    if args.mode == "movie":
        assert "2340×1080" in Path(command[command.index("--log-file") + 1]).read_text(encoding="utf-8"), "Movie Maker must use actual required physical recording size"
        target = qa / "video/android_fullscreen_navigation.mp4"
        assert not target.exists(), "Preserve previous final navigation footage"
        ffmpeg = workspace.find_tool("ffmpeg", args.ffmpeg)
        footer = qa / "temp" / (stem + "_caption.png")
        image = Image.new("RGB", (2340, 36), "#101a20")
        ImageDraw.Draw(image).text((18, 5), "003A.2 ANDROID FULLSCREEN / WINDOWS PRODUCTION-SHELL SIMULATION / NOT PHYSICAL PHONE ACCEPTANCE",
                                  font=ImageFont.truetype(r"C:\Windows\Fonts\consola.ttf", 21), fill="#dce5e0")
        image.save(footer)
        encode = [ffmpeg, "-v", "error", "-i", str(raw), "-i", str(footer), "-filter_complex",
                  "[0:v]pad=iw:ih+36:0:0:color=0x101a20[v];[v][1:v]overlay=0:main_h-overlay_h[out]", "-map", "[out]", "-an",
                  "-c:v", "libx264", "-crf", "18", "-preset", "fast", "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(target)]
        record["encoder"] = pipeline.run_logged(encode, qa / "logs" / (stem + "_encode.log"), 900)
        record["decoder"] = pipeline.run_logged([ffmpeg, "-v", "error", "-i", str(target), "-f", "null", "-"], qa / "logs" / (stem + "_decode.log"), 240)
        record.update(video=pointer(target), raw_movie=pointer(raw), caption=pointer(footer), movie_frames=data["movie_frames"],
                      movie_phases=data["movie_phases"], audio_scope="Silent UI/layout evidence; accepted audio/music assets unchanged.")
    record["status"] = "passed"
    summary = record.pop("matrix_summary_pending", None)
    pipeline.write_json(manifest, record)
    if summary:
        summary["provenance"] = pointer(manifest)
        target = qa / "manifests/android_fullscreen_layout_matrix.json"
        mirror = qa / "android_fullscreen_layout_matrix.json"
        assert not target.exists() and not mirror.exists()
        pipeline.write_json(target, summary)
        mirror.write_bytes(target.read_bytes())
    print(json.dumps({"status": "passed", "manifest": str(manifest), "sha256": pipeline.sha256(manifest), "checks": data["checks"],
                      "matrix": record.get("matrix"), "video": record.get("video"), "physics_exact": data["all_physics_exact"],
                      "player_files": len(profiles["files"]), "physical_android_acceptance": False}, indent=2), flush=True)


if __name__ == "__main__":
    main()
