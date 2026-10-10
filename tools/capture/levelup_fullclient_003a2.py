"""Guarded actual Main/Menus full-client Run choice proof and review media."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import importlib.util
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

spec = importlib.util.spec_from_file_location("levelup_profile_guard", ROOT / "tools/capture/android_fullscreen_003a2.py")
profile_guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(profile_guard)
DRIVER = ROOT / "tests/test_levelup_fullclient_003a2.gd"
SCREENS = {"level_up", "reward", "mutation", "acquisition"}
DESKTOP = {"800x480", "1280x720", "1920x1080", "2560x1440"}


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def pointer(path):
    path = Path(path).resolve()
    return {"path": str(path), "bytes": path.stat().st_size, "sha256": pipeline.sha256(path)}


def harness():
    paths = [DRIVER, Path(__file__), ROOT / "tools/capture/android_fullscreen_003a2.py",
             ROOT / "tools/build/windows_checkpoint.py", ROOT / "tools/workspace/workspace.py",
             ROOT / "tools/presentation/upgrade_sustain_003a1.py"]
    if DRIVER.with_suffix(".gd.uid").exists():
        paths.append(DRIVER.with_suffix(".gd.uid"))
    return {str(path): pipeline.sha256(path) for path in paths}


def freeze(stage):
    stage.mkdir()
    for name in ("project.godot", "main.tscn"):
        shutil.copy2(ROOT / name, stage / name)
    for name in ("scripts", "assets", ".godot"):
        shutil.copytree(ROOT / name, stage / name)
    (stage / "tests").mkdir()
    shutil.copy2(DRIVER, stage / "tests" / DRIVER.name)
    if DRIVER.with_suffix(".gd.uid").exists():
        shutil.copy2(DRIVER.with_suffix(".gd.uid"), stage / "tests" / DRIVER.with_suffix(".gd.uid").name)
    assert source(stage) == source(ROOT), "Frozen production bytes must equal current source"


def validate(data, mode):
    assert data["schema"] == "levelup-fullclient-003a2-v1"
    assert data["checks"] > 0 and data["failures"] == [], data["failures"]
    assert data["physical_phone_acceptance"] is False and data["physical_controller_acceptance"] is False
    cases = {row["case"] for row in data["observations"]}
    expected = {"1920x1080"} if mode == "movie" else DESKTOP | {"android_2340x1080_cutout"}
    if mode == "native":
        expected.add("native_maximized")
    assert cases == expected, (cases, expected)
    for case in cases:
        rows = [row for row in data["observations"] if row["case"] == case]
        assert {row["screen"] for row in rows} == SCREENS
        assert all(not row["font_fit_failures"] for row in rows)
        assert next(row for row in rows if row["screen"] == "reward")["cards"].__len__() == 3
        assert next(row for row in rows if row["screen"] == "mutation")["cards"].__len__() == 2
        traces = [row for row in data["inputs"] if row["case"] == case]
        pointer_rows = [row for row in traces if row["type"] == "physical_client_pointer"]
        assert {"reroll_power", "choose_power", "choose_mutation"} <= {row["intent"] for row in pointer_rows}
        assert all(row["push_input_in_local_coords"] is False for row in pointer_rows)
        assert any(row["type"] == "logical_reconnect_callback" and row["controls_before"] == row["controls_after"] for row in traces)
        assert any(row["type"] == "pause_regression" for row in traces)
        if not case.startswith("android"):
            assert any(row["type"] in {"actual_client_resize", "native_OS_API_mode"}
                       and row["simulation_before"] == row["simulation_after"]
                       and row["control_identity_before"] == row["control_identity_after"] for row in traces)
    if mode != "headless":
        assert data["native"]
        for row in data["images"] + data["film"]:
            assert pipeline.sha256(Path(row["path"])) == row["sha256"]
            with Image.open(row["path"]) as image:
                assert list(image.size) == row["pixels"]
    if mode == "movie":
        assert len(data["film"]) >= 150 and len(data["phases"]) == 4
        assert SCREENS <= {row["screen"] for row in data["film"]}
        assert len({frame for row in data["film"] for frame in row["art_frames"]}) >= 3, "Actual authored animation must advance"


def compose_matrix(data, target):
    cases = ["800x480", "1280x720", "1920x1080", "native_maximized", "2560x1440", "android_2340x1080_cutout"]
    screens = ["level_up", "reward", "mutation", "acquisition"]
    lookup = {(row["case"], row["screen"]): row for row in data["images"]}
    canvas = Image.new("RGB", (2616, 2848), "#101a20")
    draw = ImageDraw.Draw(canvas)
    title = ImageFont.truetype(r"C:\Windows\Fonts\consolab.ttf", 27)
    font = ImageFont.truetype(r"C:\Windows\Fonts\consola.ttf", 18)
    draw.text((16, 10), "003A.2 / FULL-CLIENT IN-RUN CHOICES", font=title, fill="#e3e8dc")
    draw.text((16, 45), "Actual Windows pixels; synthetic UI. Android safe-area simulation retains accepted mobile modal.", font=font, fill="#a7c5cc")
    for row_index, case in enumerate(cases):
        for column, screen in enumerate(screens):
            row = lookup[(case, screen)]
            x, y = 16 + column * 650, 86 + row_index * 456
            draw.text((x, y), f"{case} / {screen.upper()}", font=font, fill="#7fc8d9")
            image = Image.open(row["path"]).convert("RGB")
            scalar = min(640 / image.width, 392 / image.height)
            image = image.resize((round(image.width * scalar), round(image.height * scalar)), Image.Resampling.NEAREST)
            canvas.paste(image, (x, y + 28))
            draw.text((x, y + 427), f"Whole client {row['pixels'][0]}x{row['pixels'][1]}", font=font, fill="#a7c5cc")
    canvas.save(target, optimize=True)


def encode_movie(data, qa, stem, ffmpeg):
    composition = qa / "temp" / (stem + "_composition")
    composition.mkdir()
    font = ImageFont.truetype(r"C:\Windows\Fonts\consola.ttf", 21)
    for index, row in enumerate(data["film"]):
        image = Image.open(row["path"]).convert("RGB")
        scalar = min(1920 / image.width, 1080 / image.height)
        image = image.resize((round(image.width * scalar), round(image.height * scalar)), Image.Resampling.NEAREST)
        canvas = Image.new("RGB", (1920, 1128), "#101a20")
        canvas.paste(image, ((1920 - image.width) // 2, (1080 - image.height) // 2))
        ImageDraw.Draw(canvas).text((12, 1092), f"{row['screen'].upper()} / CLIENT {row['client'][0]}x{row['client'][1]} / {row['phase']} / SYNTHETIC UI", font=font, fill="#e3e8dc")
        canvas.save(composition / f"{index:05d}.png", compress_level=1)
    target = qa / "temp" / (stem + "_validated.mp4")
    encode = pipeline.run_logged([ffmpeg, "-v", "error", "-framerate", "30", "-i", str(composition / "%05d.png"),
                                 "-an", "-c:v", "libx264", "-crf", "18", "-preset", "fast", "-pix_fmt", "yuv420p",
                                 "-movflags", "+faststart", str(target)], qa / "logs" / (stem + "_encode.log"), 600)
    decode = pipeline.run_logged([ffmpeg, "-v", "error", "-i", str(target), "-f", "null", "-"], qa / "logs" / (stem + "_decode.log"), 180)
    return {"video": pointer(target), "encoder": encode, "decoder": decode, "composition": str(composition),
            "capture_cadence": "Actual animated root image per two fixed60 GUI frames; full variable client uniformly fitted to1920x1080 plus48px caption. UI timers deliberately held; cosmetic authored animation advances. No FPS/hardware claim."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("headless", "native", "movie"), required=True)
    parser.add_argument("--label", default="final")
    parser.add_argument("--engine", default=r"E:\Desktop\Godot_v4.7.2-stable_win64_console.exe")
    parser.add_argument("--ffmpeg")
    args = parser.parse_args()
    assert args.label.replace("_", "").replace("-", "").isalnum()
    qa = workspace.create_task_workspace("003A.2")
    os.environ["TOPGAME_QA_ROOT"] = str(qa.parent)
    stem = "003a2_levelup_fullclient_" + args.mode + "_" + args.label + "_" + datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
    stage = qa / "temp" / (stem + "_source")
    runtime = qa / "manifests" / (stem + "_runtime.json")
    manifest = qa / "manifests" / (stem + ".json")
    reserved = [qa / "images/003a2_levelup_fullclient.png", qa / "manifests/003a2_levelup_fullclient.json", qa / "003a2_levelup_fullclient.json"] if args.mode == "native" else ([qa / "video/003a2_levelup_fullclient.mp4"] if args.mode == "movie" else [])
    assert not any(path.exists() for path in reserved), "All selected primary paths must be absent before capture"
    original, profiles, drivers = source(ROOT), profile_guard.player(), harness()
    record = {"status": "preparing", "created_utc": datetime.now(timezone.utc).isoformat(), "mode": args.mode,
              "git_sha": pipeline.git(ROOT, "rev-parse", "HEAD"), "source_before": original,
              "player_before": profiles, "harness": drivers,
              "scope": "Actual Main/Menus Run overlay with declared legal initial invested ownership and pending Level5. Isolated collection; synthetic physical-client pointer and logical reconnect. Android case is Windows safe-area simulation only."}
    pipeline.write_json(manifest, record)
    try:
        freeze(stage)
        frozen = source(stage)
        command = [args.engine, "--path", str(stage), "--script", "res://tests/" + DRIVER.name,
                   "--fixed-fps", "60", "--disable-vsync", "--audio-driver", "Dummy",
                   "--log-file", str(qa / "logs" / (stem + "_engine.log"))]
        if args.mode == "headless":
            command += ["--headless"]
        command += ["--", "--report=" + str(runtime), "--profile-prefix=" + str(qa / "temp" / (stem + "_collection"))]
        if args.mode != "headless":
            command += ["--native", "--frames=" + str(qa / "frames" / stem)]
        if args.mode == "movie":
            command += ["--movie"]
        record.update(status="running", source_root=str(stage))
        pipeline.write_json(manifest, record)
        record["process"] = pipeline.run_logged(command, qa / "logs" / (stem + ".log"), 600)
        data = read(runtime)
        validate(data, args.mode)
        record.update(runtime=pointer(runtime), checks=data["checks"])
        if args.mode == "native":
            target = qa / "temp" / (stem + "_validated.png")
            compose_matrix(data, target)
            record["matrix_candidate"] = pointer(target)
        if args.mode == "movie":
            record.update(encode_movie(data, qa, stem, workspace.find_tool("ffmpeg", args.ffmpeg)))
        current_player = profile_guard.player()
        record.update(source_unchanged=original == source(ROOT), frozen_source_unchanged=frozen == source(stage),
                      harness_unchanged=drivers == harness(), player_after=current_player, player_unchanged=profiles == current_player)
        assert all(record[key] for key in ("source_unchanged", "frozen_source_unchanged", "harness_unchanged", "player_unchanged"))
        assert not any(path.exists() for path in reserved), "Selected paths still must be unused immediately before publication"
        if args.mode == "native":
            target = qa / "images/003a2_levelup_fullclient.png"
            shutil.copy2(Path(record["matrix_candidate"]["path"]), target)
            record["image"] = pointer(target)
        if args.mode == "movie":
            target = qa / "video/003a2_levelup_fullclient.mp4"
            shutil.copy2(Path(record["video"]["path"]), target)
            record["video"] = pointer(target)
        record["status"] = "passed"
        pipeline.write_json(manifest, record)
        if args.mode == "native":
            selected = qa / "manifests/003a2_levelup_fullclient.json"
            pipeline.write_json(selected, {"schema": "003a2-levelup-fullclient-v1", "status": "passed", "checks": data["checks"],
                                          "provenance": pointer(manifest), "runtime": pointer(runtime), "image": record["image"],
                                          "cases": data["observations"], "input_traces": data["inputs"],
                                          "physical_phone_acceptance": False, "physical_controller_acceptance": False,
                                          "scope": data["scope"]})
            (qa / "003a2_levelup_fullclient.json").write_bytes(selected.read_bytes())
        print(json.dumps({"status": "passed", "manifest": pointer(manifest), "checks": data["checks"],
                          "image": record.get("image"), "video": record.get("video"), "protected_player_files": len(profiles["files"])}, indent=2), flush=True)
    except Exception as exc:
        record.update(status="rejected_attempt", error=str(exc), source_unchanged=original == source(ROOT),
                      harness_unchanged=drivers == harness(), player_after=profile_guard.player(), player_unchanged=profiles == profile_guard.player())
        if isinstance(exc, pipeline.ProcessValidationError):
            record["failed_process"] = exc.record
        if runtime.exists():
            record["runtime"] = pointer(runtime)
        if stage.exists():
            record["partial_stage"] = str(stage)
        pipeline.write_json(manifest, record)
        raise


if __name__ == "__main__":
    main()
